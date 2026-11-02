`timescale 1ns/1ps

module pl_profiler #(
    parameter logic [63:0] DPU_TIMEOUT_CYCLES = 64'd100_000_000
)(
    input  logic        aclk,
    input  logic        aresetn,
    input  logic        soft_reset,
    input  logic        clear_stats,
    input  logic        snapshot_stats,

    input  logic        frame_start,
    input  logic        frame_end,
    input  logic        frame_abort,

    input  logic        request_commit,
    input  logic        request_abort,
    input  logic [31:0] request_frame_id,
    input  logic [1:0]  request_buffer_id,
    input  logic [31:0] request_generation,

    input  logic        result_release,
    input  logic [31:0] result_frame_id,
    input  logic [1:0]  result_buffer_id,
    input  logic [31:0] result_generation,
    input  logic [31:0] scheduler_completed_frames,

    output logic        dpu_timeout_pulse,
    output logic        frame_active,
    output logic        dpu_active,
    output logic        dpu_timeout_sticky,
    output logic        last_frame_aborted,
    output logic        measurement_error,
    output logic        snapshot_valid,

    output logic [63:0] cycle_snapshot,
    output logic [31:0] last_frame_cycles_snapshot,
    output logic [31:0] max_frame_cycles_snapshot,
    output logic [31:0] last_dpu_latency_snapshot,
    output logic [31:0] max_dpu_latency_snapshot,
    output logic [31:0] last_result_frame_age_snapshot,
    output logic [31:0] max_result_frame_age_snapshot,
    output logic [31:0] dpu_timeout_count_snapshot,
    output logic [31:0] profiled_frames_snapshot,
    output logic [31:0] profiled_requests_snapshot,
    output logic [31:0] profiled_results_snapshot
);

    logic [63:0] cycle_counter;
    logic [63:0] frame_start_cycle;
    logic [63:0] request_start_cycle;
    logic [31:0] active_request_frame_id;
    logic [1:0]  active_request_buffer_id;
    logic [31:0] active_request_generation;
    logic        dpu_timeout_seen;

    logic [31:0] last_frame_cycles;
    logic [31:0] max_frame_cycles;
    logic [31:0] last_dpu_latency;
    logic [31:0] max_dpu_latency;
    logic [31:0] last_result_frame_age;
    logic [31:0] max_result_frame_age;
    logic [31:0] dpu_timeout_count;
    logic [31:0] profiled_frames;
    logic [31:0] profiled_requests;
    logic [31:0] profiled_results;

    logic [63:0] frame_elapsed_wide;
    logic [63:0] dpu_elapsed_wide;
    logic [31:0] frame_elapsed;
    logic [31:0] dpu_elapsed;
    logic [31:0] result_frame_age;
    logic        result_identity_matches;

    always_comb begin
        frame_elapsed_wide = cycle_counter - frame_start_cycle;
        dpu_elapsed_wide = cycle_counter - request_start_cycle;
        frame_elapsed = frame_elapsed_wide[63:32] != 0 ?
                        32'hffff_ffff : frame_elapsed_wide[31:0];
        dpu_elapsed = dpu_elapsed_wide[63:32] != 0 ?
                      32'hffff_ffff : dpu_elapsed_wide[31:0];
        result_frame_age = scheduler_completed_frames - 32'd1 -
                           result_frame_id;
        result_identity_matches =
            result_frame_id == active_request_frame_id &&
            result_buffer_id == active_request_buffer_id &&
            result_generation == active_request_generation;
    end

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn || soft_reset) begin
            cycle_counter <= 64'd0;
            frame_start_cycle <= 64'd0;
            request_start_cycle <= 64'd0;
            active_request_frame_id <= 32'd0;
            active_request_buffer_id <= 2'd0;
            active_request_generation <= 32'd0;
            dpu_timeout_seen <= 1'b0;
            frame_active <= 1'b0;
            dpu_active <= 1'b0;
            dpu_timeout_pulse <= 1'b0;
            dpu_timeout_sticky <= 1'b0;
            last_frame_aborted <= 1'b0;
            measurement_error <= 1'b0;
            snapshot_valid <= 1'b0;
            last_frame_cycles <= 32'd0;
            max_frame_cycles <= 32'd0;
            last_dpu_latency <= 32'd0;
            max_dpu_latency <= 32'd0;
            last_result_frame_age <= 32'd0;
            max_result_frame_age <= 32'd0;
            dpu_timeout_count <= 32'd0;
            profiled_frames <= 32'd0;
            profiled_requests <= 32'd0;
            profiled_results <= 32'd0;
            cycle_snapshot <= 64'd0;
            last_frame_cycles_snapshot <= 32'd0;
            max_frame_cycles_snapshot <= 32'd0;
            last_dpu_latency_snapshot <= 32'd0;
            max_dpu_latency_snapshot <= 32'd0;
            last_result_frame_age_snapshot <= 32'd0;
            max_result_frame_age_snapshot <= 32'd0;
            dpu_timeout_count_snapshot <= 32'd0;
            profiled_frames_snapshot <= 32'd0;
            profiled_requests_snapshot <= 32'd0;
            profiled_results_snapshot <= 32'd0;
        end else begin
            cycle_counter <= cycle_counter + 64'd1;
            dpu_timeout_pulse <= 1'b0;

            if (clear_stats) begin
                dpu_timeout_sticky <= 1'b0;
                last_frame_aborted <= 1'b0;
                measurement_error <= 1'b0;
                snapshot_valid <= 1'b0;
                last_frame_cycles <= 32'd0;
                max_frame_cycles <= 32'd0;
                last_dpu_latency <= 32'd0;
                max_dpu_latency <= 32'd0;
                last_result_frame_age <= 32'd0;
                max_result_frame_age <= 32'd0;
                dpu_timeout_count <= 32'd0;
                profiled_frames <= 32'd0;
                profiled_requests <= 32'd0;
                profiled_results <= 32'd0;
                cycle_snapshot <= 64'd0;
                last_frame_cycles_snapshot <= 32'd0;
                max_frame_cycles_snapshot <= 32'd0;
                last_dpu_latency_snapshot <= 32'd0;
                max_dpu_latency_snapshot <= 32'd0;
                last_result_frame_age_snapshot <= 32'd0;
                max_result_frame_age_snapshot <= 32'd0;
                dpu_timeout_count_snapshot <= 32'd0;
                profiled_frames_snapshot <= 32'd0;
                profiled_requests_snapshot <= 32'd0;
                profiled_results_snapshot <= 32'd0;
            end

            if (frame_start) begin
                if (frame_active) begin
                    measurement_error <= 1'b1;
                end else begin
                    frame_start_cycle <= cycle_counter;
                    frame_active <= 1'b1;
                end
            end

            if (frame_end || frame_abort) begin
                if (frame_end && frame_abort)
                    measurement_error <= 1'b1;
                if (!frame_active) begin
                    measurement_error <= 1'b1;
                end else begin
                    last_frame_cycles <= frame_elapsed;
                    if (frame_elapsed > max_frame_cycles)
                        max_frame_cycles <= frame_elapsed;
                    last_frame_aborted <= frame_abort;
                    profiled_frames <= profiled_frames + 32'd1;
                    frame_active <= 1'b0;
                end
            end

            if (request_commit) begin
                if (dpu_active) begin
                    measurement_error <= 1'b1;
                end else begin
                    request_start_cycle <= cycle_counter;
                    active_request_frame_id <= request_frame_id;
                    active_request_buffer_id <= request_buffer_id;
                    active_request_generation <= request_generation;
                    dpu_timeout_seen <= 1'b0;
                    dpu_active <= 1'b1;
                    profiled_requests <= profiled_requests + 32'd1;
                end
            end

            if (dpu_active && !dpu_timeout_seen &&
                DPU_TIMEOUT_CYCLES != 0 &&
                dpu_elapsed_wide >= DPU_TIMEOUT_CYCLES) begin
                dpu_timeout_pulse <= 1'b1;
                dpu_timeout_sticky <= 1'b1;
                dpu_timeout_count <= dpu_timeout_count + 32'd1;
                dpu_timeout_seen <= 1'b1;
            end

            if (request_abort) begin
                if (dpu_active) begin
                    dpu_active <= 1'b0;
                    dpu_timeout_seen <= 1'b0;
                end else begin
                    measurement_error <= 1'b1;
                end
            end else if (result_release) begin
                if (!dpu_active || !result_identity_matches) begin
                    measurement_error <= 1'b1;
                end else begin
                    last_dpu_latency <= dpu_elapsed;
                    if (dpu_elapsed > max_dpu_latency)
                        max_dpu_latency <= dpu_elapsed;
                    if (scheduler_completed_frames == 0 ||
                        result_frame_id >= scheduler_completed_frames) begin
                        last_result_frame_age <= 32'd0;
                        measurement_error <= 1'b1;
                    end else begin
                        last_result_frame_age <= result_frame_age;
                        if (result_frame_age > max_result_frame_age)
                            max_result_frame_age <= result_frame_age;
                    end
                    profiled_results <= profiled_results + 32'd1;
                    dpu_active <= 1'b0;
                    dpu_timeout_seen <= 1'b0;
                end
            end

            if (snapshot_stats) begin
                cycle_snapshot <= cycle_counter;
                last_frame_cycles_snapshot <= last_frame_cycles;
                max_frame_cycles_snapshot <= max_frame_cycles;
                last_dpu_latency_snapshot <= last_dpu_latency;
                max_dpu_latency_snapshot <= max_dpu_latency;
                last_result_frame_age_snapshot <= last_result_frame_age;
                max_result_frame_age_snapshot <= max_result_frame_age;
                dpu_timeout_count_snapshot <= dpu_timeout_count;
                profiled_frames_snapshot <= profiled_frames;
                profiled_requests_snapshot <= profiled_requests;
                profiled_results_snapshot <= profiled_results;
                snapshot_valid <= 1'b1;
            end
        end
    end

`ifndef SYNTHESIS
    property p_timeout_pulse_one_cycle;
        @(posedge aclk) disable iff (!aresetn || soft_reset)
            dpu_timeout_pulse |=> !dpu_timeout_pulse;
    endproperty
    assert property (p_timeout_pulse_one_cycle)
        else $error("dpu_timeout_pulse lasted more than one cycle");

    property p_no_simultaneous_frame_end_abort;
        @(posedge aclk) disable iff (!aresetn || soft_reset)
            !(frame_end && frame_abort);
    endproperty
    assert property (p_no_simultaneous_frame_end_abort)
        else $error("frame_end and frame_abort asserted together");

    property p_result_does_not_increase_requests;
        @(posedge aclk) disable iff (!aresetn || soft_reset)
            result_release && !request_commit |=>
                $stable(profiled_requests);
    endproperty
    assert property (p_result_does_not_increase_requests)
        else $error("result_release changed profiled_requests");
`endif

endmodule
