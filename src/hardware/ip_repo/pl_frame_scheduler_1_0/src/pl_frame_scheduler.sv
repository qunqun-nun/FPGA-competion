`timescale 1ns/1ps

// Three-buffer fresh-frame scheduler.
// The scheduler owns buffer state and request identity. DDR address mapping
// remains outside this module and is intentionally not part of this stage.
module pl_frame_scheduler #(
    parameter integer BUFFER_COUNT = 3
)(
    input  logic        aclk,
    input  logic        aresetn,
    input  logic        enable,
    input  logic        soft_reset,
    input  logic        dpu_owner_abort,
    output logic        dpu_owner_abort_ack,

    input  logic        frame_start,
    output logic        frame_start_ready,
    input  logic        frame_end,
    input  logic        frame_abort,
    output logic [1:0]  write_buffer,
    output logic [31:0] write_frame_id,
    output logic [31:0] write_generation,

    input  logic        dpu_ready,
    input  logic [7:0]  dpu_request_reason,
    output logic        request_commit,
    output logic [31:0] request_frame_id_in,
    output logic [1:0]  request_buffer_id_in,
    output logic [31:0] request_generation_in,
    output logic [7:0]  request_reason_in,
    output logic [31:0] request_timestamp_in,

    input  logic        result_commit_pulse,
    input  logic [31:0] result_frame_id,
    input  logic [1:0]  result_buffer_id,
    input  logic [31:0] result_generation,
    output logic        result_release,
    output logic        result_stale_pulse,

    output logic [31:0] completed_frames,
    output logic [31:0] stale_frames,
    output logic [31:0] dropped_frames,
    output logic [31:0] stale_results,
    output logic [31:0] buffer_conflicts,
    output logic [2:0]  dpu_owned_mask,
    output logic [2:0]  ready_mask,
    output logic        buffer_conflict
);

    localparam logic [1:0] SLOT_FREE     = 2'd0;
    localparam logic [1:0] SLOT_WRITING  = 2'd1;
    localparam logic [1:0] SLOT_READY    = 2'd2;
    localparam logic [1:0] SLOT_DPU_OWNED = 2'd3;

    logic [1:0]  slot_state [0:2];
    logic [31:0] slot_frame_id [0:2];
    logic [31:0] slot_generation [0:2];
    logic [31:0] slot_timestamp [0:2];

    logic        writing_active;
    logic [1:0]  current_write;
    logic [1:0]  current_owned;
    logic        dpu_owned_active;
    logic [31:0] next_frame_id;
    logic [31:0] timestamp_counter;

    logic        free_found;
    logic [1:0]  free_index;
    logic        dispatch_found;
    logic [1:0]  dispatch_index;
    logic [31:0] dispatch_frame_id;
    logic [31:0] dispatch_generation;
    logic [31:0] dispatch_timestamp;
    logic        reclaim_found;
    logic [1:0]  reclaim_index;
    logic [31:0] reclaim_frame_id;
    logic [1:0]  allocate_index;
    logic        start_accept;
    logic        dispatch_fire;
    logic        reclaim_start;
    logic [31:0] dropped_increment;
    integer stale_ready_count;
    integer comb_i;
    integer seq_i;

    generate
        if (BUFFER_COUNT != 3) begin : g_invalid_buffer_count
            initial $error("pl_frame_scheduler requires BUFFER_COUNT=3");
        end
    endgenerate

    always_comb begin
        free_found = 1'b0;
        free_index = 2'd0;
        dispatch_found = 1'b0;
        dispatch_index = 2'd0;
        dispatch_frame_id = 32'd0;
        dispatch_generation = 32'd0;
        dispatch_timestamp = 32'd0;
        reclaim_found = 1'b0;
        reclaim_index = 2'd0;
        reclaim_frame_id = 32'd0;
        stale_ready_count = 0;
        dropped_increment = 32'd0;

        for (comb_i = 0; comb_i < 3; comb_i = comb_i + 1) begin
            if (!free_found && slot_state[comb_i] == SLOT_FREE) begin
                free_found = 1'b1;
                free_index = comb_i[1:0];
            end
            if (slot_state[comb_i] == SLOT_READY) begin
                if (!dispatch_found ||
                    slot_frame_id[comb_i] > dispatch_frame_id) begin
                    dispatch_found = 1'b1;
                    dispatch_index = comb_i[1:0];
                    dispatch_frame_id = slot_frame_id[comb_i];
                    dispatch_generation = slot_generation[comb_i];
                    dispatch_timestamp = slot_timestamp[comb_i];
                end
            end
        end

        for (comb_i = 0; comb_i < 3; comb_i = comb_i + 1) begin
            if (slot_state[comb_i] == SLOT_READY &&
                (!dispatch_found || comb_i[1:0] != dispatch_index)) begin
                stale_ready_count = stale_ready_count + 1;
                // Keep the newest complete frame available for dispatch.
                // Only READY slots are eligible; never touch an owner/writer.
                if (!reclaim_found || slot_frame_id[comb_i] < reclaim_frame_id) begin
                    reclaim_found = 1'b1;
                    reclaim_index = comb_i[1:0];
                    reclaim_frame_id = slot_frame_id[comb_i];
                end
            end
        end

        allocate_index = free_found ? free_index : reclaim_index;
        frame_start_ready = enable && !soft_reset && (free_found || reclaim_found) &&
            (!writing_active || frame_end || frame_abort);
        start_accept = frame_start && frame_start_ready;
        dispatch_fire = enable && dpu_ready && !dpu_owned_active && dispatch_found;
        reclaim_start = start_accept && !free_found;

        if (frame_start && enable && !frame_start_ready)
            dropped_increment = dropped_increment + 32'd1;
        if (frame_abort && writing_active)
            dropped_increment = dropped_increment + 32'd1;
        if (dispatch_fire)
            dropped_increment = dropped_increment + stale_ready_count;
        else if (reclaim_start)
            dropped_increment = dropped_increment + 32'd1;
        if (dpu_owner_abort && dpu_owned_active)
            dropped_increment = dropped_increment + 32'd1;

        if (writing_active && !frame_end && !frame_abort) begin
            write_buffer = current_write;
            write_generation = slot_generation[current_write];
            write_frame_id = next_frame_id;
        end else begin
            write_buffer = allocate_index;
            write_generation = slot_generation[allocate_index] + 32'd1;
            write_frame_id = next_frame_id;
        end

        ready_mask = 3'b000;
        dpu_owned_mask = 3'b000;
        for (comb_i = 0; comb_i < 3; comb_i = comb_i + 1) begin
            if (slot_state[comb_i] == SLOT_READY)
                ready_mask[comb_i] = 1'b1;
            if (slot_state[comb_i] == SLOT_DPU_OWNED)
                dpu_owned_mask[comb_i] = 1'b1;
        end
    end

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn || soft_reset) begin
            writing_active       <= 1'b0;
            current_write        <= 2'd0;
            current_owned        <= 2'd0;
            dpu_owned_active     <= 1'b0;
            next_frame_id        <= 32'd0;
            timestamp_counter    <= 32'd0;
            request_commit       <= 1'b0;
            request_frame_id_in  <= 32'd0;
            request_buffer_id_in <= 2'd0;
            request_generation_in <= 32'd0;
            request_reason_in    <= 8'd0;
            request_timestamp_in <= 32'd0;
            result_release       <= 1'b0;
            result_stale_pulse   <= 1'b0;
            dpu_owner_abort_ack  <= 1'b0;
            completed_frames     <= 32'd0;
            stale_frames         <= 32'd0;
            dropped_frames       <= 32'd0;
            stale_results        <= 32'd0;
            buffer_conflicts     <= 32'd0;
            buffer_conflict      <= 1'b0;
            for (seq_i = 0; seq_i < 3; seq_i = seq_i + 1) begin
                slot_state[seq_i]      <= SLOT_FREE;
                slot_frame_id[seq_i]   <= 32'd0;
                slot_generation[seq_i] <= 32'd0;
                slot_timestamp[seq_i] <= 32'd0;
            end
        end else begin
            request_commit     <= 1'b0;
            result_release     <= 1'b0;
            result_stale_pulse <= 1'b0;
            dpu_owner_abort_ack <= 1'b0;
            timestamp_counter  <= timestamp_counter + 32'd1;

            if (frame_start && enable && !frame_start_ready) begin
                buffer_conflicts <= buffer_conflicts + 32'd1;
                buffer_conflict  <= 1'b1;
            end

            if (dropped_increment != 32'd0)
                dropped_frames <= dropped_frames + dropped_increment;

            // Abort has priority over completion. An aborted frame returns its
            // slot to FREE without consuming a formal frame ID.
            if (frame_abort && writing_active) begin
                slot_state[current_write] <= SLOT_FREE;
                writing_active <= 1'b0;
            end else if (frame_end && writing_active) begin
                slot_state[current_write] <= SLOT_READY;
                slot_frame_id[current_write] <= next_frame_id;
                slot_timestamp[current_write] <= timestamp_counter;
                next_frame_id <= next_frame_id + 32'd1;
                completed_frames <= completed_frames + 32'd1;
                writing_active <= 1'b0;
            end

            if (start_accept) begin
                current_write <= allocate_index;
                slot_state[allocate_index] <= SLOT_WRITING;
                slot_generation[allocate_index] <=
                    slot_generation[allocate_index] + 32'd1;
                writing_active <= 1'b1;
            end

            // A same-cycle dispatch already counts all older READY frames,
            // including the reclaimed one. Count that frame exactly once.
            if (reclaim_start && !dispatch_fire)
                stale_frames <= stale_frames + 32'd1;

            // Fresh-Frame dispatch is one request per DPU ownership interval.
            if (dispatch_fire) begin
                slot_state[dispatch_index] <= SLOT_DPU_OWNED;
                current_owned <= dispatch_index;
                dpu_owned_active <= 1'b1;
                request_frame_id_in <= dispatch_frame_id;
                request_buffer_id_in <= dispatch_index;
                request_generation_in <= dispatch_generation;
                request_reason_in <= dpu_request_reason;
                request_timestamp_in <= dispatch_timestamp;
                request_commit <= 1'b1;

                if (stale_ready_count > 0) begin
                    stale_frames <= stale_frames + stale_ready_count;
                end
                for (seq_i = 0; seq_i < 3; seq_i = seq_i + 1) begin
                    if (slot_state[seq_i] == SLOT_READY &&
                        seq_i[1:0] != dispatch_index &&
                        !(start_accept && seq_i[1:0] == allocate_index))
                        slot_state[seq_i] <= SLOT_FREE;
                end
            end

            // Recovery cancellation has priority over a result arriving in
            // the same cycle. The later result is rejected by the mailbox.
            if (dpu_owner_abort) begin
                if (dpu_owned_active) begin
                    slot_state[current_owned] <= SLOT_FREE;
                    dpu_owned_active <= 1'b0;
                    dpu_owner_abort_ack <= 1'b1;
                end
            end else if (result_commit_pulse) begin
                if (dpu_owned_active &&
                    result_buffer_id == current_owned &&
                    result_frame_id == slot_frame_id[current_owned] &&
                    result_generation == slot_generation[current_owned]) begin
                    slot_state[current_owned] <= SLOT_FREE;
                    dpu_owned_active <= 1'b0;
                    result_release <= 1'b1;
                end else begin
                    stale_results <= stale_results + 32'd1;
                    result_stale_pulse <= 1'b1;
                end
            end
        end
    end

`ifndef SYNTHESIS
    // These checks are simulation-only invariants for the ownership contract.
    always_ff @(posedge aclk) begin
        if (aresetn && !soft_reset) begin
            assert (slot_state[0] <= SLOT_DPU_OWNED)
                else $error("slot 0 has an illegal state");
            assert (slot_state[1] <= SLOT_DPU_OWNED)
                else $error("slot 1 has an illegal state");
            assert (slot_state[2] <= SLOT_DPU_OWNED)
                else $error("slot 2 has an illegal state");
            assert ($onehot0(dpu_owned_mask))
                else $error("more than one buffer is DPU_OWNED");
            assert (dpu_owned_active == (|dpu_owned_mask))
                else $error("DPU ownership flag and mask disagree");
            assert (!(writing_active && dpu_owned_active &&
                      current_write == current_owned))
                else $error("a buffer is both WRITING and DPU_OWNED");
            assert (!(start_accept && dispatch_fire &&
                      allocate_index == dispatch_index))
                else $error("write allocation conflicts with dispatch");
        end
    end
`endif

endmodule
