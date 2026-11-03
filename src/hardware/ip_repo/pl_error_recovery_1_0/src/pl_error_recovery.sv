`timescale 1ns/1ps

module pl_error_recovery #(
    parameter integer DATAMOVER_RESET_CYCLES = 4
)(
    input  logic        aclk,
    input  logic        aresetn,
    input  logic        soft_reset,
    input  logic        clear_status,
    input  logic        software_trigger,

    input  logic        dpu_timeout_pulse,
    input  logic        dpu_owned_present,
    input  logic        dpu_owner_abort_ack,
    input  logic        datamover_fatal,
    input  logic        video_error_pulse,
    input  logic        frame_abort,
    input  logic [1:0]  frame_abort_reason,

    output logic        dpu_owner_abort,
    output logic        request_cancel,
    output logic        profiler_request_abort,
    output logic        adapter_recovery_reset,
    output logic        datamover_recovery_reset,
    output logic        recovery_event_pulse,

    output logic        recovery_active,
    output logic        fatal_sticky,
    output logic        protocol_sticky,
    output logic        software_sticky,
    output logic        recovery_done_sticky,
    output logic [7:0]  last_reason,
    output logic [31:0] recovery_count,
    output logic [31:0] dpu_timeout_recoveries,
    output logic [31:0] datamover_recoveries,
    output logic [31:0] protocol_recoveries
);

    localparam logic [7:0] REASON_NONE             = 8'h00;
    localparam logic [7:0] REASON_DPU_TIMEOUT      = 8'h01;
    localparam logic [7:0] REASON_DATAMOVER_FATAL  = 8'h02;
    localparam logic [7:0] REASON_VIDEO_PROTOCOL   = 8'h03;
    localparam logic [7:0] REASON_FRAME_PROTOCOL   = 8'h04;
    localparam logic [7:0] REASON_SOFTWARE         = 8'h05;
    localparam logic [7:0] REASON_DATAMOVER_STATUS = 8'h06;

    logic [15:0] reset_cycles_left;
    logic datamover_fatal_seen;
    logic waiting_owner_abort_ack;

    generate
        if (DATAMOVER_RESET_CYCLES < 3 || DATAMOVER_RESET_CYCLES > 65535) begin
            initial $error("DATAMOVER_RESET_CYCLES must be in the range 3..65535");
        end
    endgenerate

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn || soft_reset) begin
            dpu_owner_abort <= 1'b0;
            request_cancel <= 1'b0;
            profiler_request_abort <= 1'b0;
            adapter_recovery_reset <= 1'b0;
            datamover_recovery_reset <= 1'b0;
            recovery_event_pulse <= 1'b0;
            recovery_active <= 1'b0;
            fatal_sticky <= 1'b0;
            protocol_sticky <= 1'b0;
            software_sticky <= 1'b0;
            recovery_done_sticky <= 1'b0;
            last_reason <= REASON_NONE;
            recovery_count <= 32'd0;
            dpu_timeout_recoveries <= 32'd0;
            datamover_recoveries <= 32'd0;
            protocol_recoveries <= 32'd0;
            reset_cycles_left <= 16'd0;
            datamover_fatal_seen <= 1'b0;
            waiting_owner_abort_ack <= 1'b0;
        end else begin
            dpu_owner_abort <= 1'b0;
            request_cancel <= 1'b0;
            profiler_request_abort <= 1'b0;
            recovery_event_pulse <= 1'b0;
            recovery_active <= 1'b0;

            if (!datamover_fatal)
                datamover_fatal_seen <= 1'b0;

            if (clear_status) begin
                fatal_sticky <= 1'b0;
                protocol_sticky <= 1'b0;
                software_sticky <= 1'b0;
                recovery_done_sticky <= 1'b0;
                last_reason <= REASON_NONE;
            end

            if (waiting_owner_abort_ack) begin
                recovery_active <= 1'b1;
                if (dpu_owner_abort_ack) begin
                    waiting_owner_abort_ack <= 1'b0;
                    recovery_done_sticky <= 1'b1;
                end
            end else if (reset_cycles_left != 0) begin
                recovery_active <= 1'b1;
                adapter_recovery_reset <= 1'b1;
                datamover_recovery_reset <= 1'b1;
                reset_cycles_left <= reset_cycles_left - 16'd1;
                if (reset_cycles_left == 16'd1)
                    recovery_done_sticky <= 1'b1;
            end else begin
                adapter_recovery_reset <= 1'b0;
                datamover_recovery_reset <= 1'b0;

                // Fatal DataMover recovery has the highest priority and is
                // armed again only after the level returns low.
                if (datamover_fatal && !datamover_fatal_seen) begin
                    datamover_fatal_seen <= 1'b1;
                    adapter_recovery_reset <= 1'b1;
                    datamover_recovery_reset <= 1'b1;
                    reset_cycles_left <= DATAMOVER_RESET_CYCLES - 1;
                    recovery_active <= 1'b1;
                    recovery_event_pulse <= 1'b1;
                    fatal_sticky <= 1'b1;
                    last_reason <= REASON_DATAMOVER_FATAL;
                    recovery_count <= recovery_count + 32'd1;
                    datamover_recoveries <= datamover_recoveries + 32'd1;
                end else if (dpu_timeout_pulse) begin
                    dpu_owner_abort <= 1'b1;
                    request_cancel <= 1'b1;
                    profiler_request_abort <= 1'b1;
                    recovery_active <= 1'b1;
                    recovery_event_pulse <= 1'b1;
                    waiting_owner_abort_ack <= dpu_owned_present;
                    if (!dpu_owned_present)
                        recovery_done_sticky <= 1'b1;
                    last_reason <= REASON_DPU_TIMEOUT;
                    recovery_count <= recovery_count + 32'd1;
                    dpu_timeout_recoveries <= dpu_timeout_recoveries + 32'd1;
                end else if (software_trigger) begin
                    dpu_owner_abort <= 1'b1;
                    request_cancel <= 1'b1;
                    profiler_request_abort <= 1'b1;
                    recovery_active <= 1'b1;
                    recovery_event_pulse <= 1'b1;
                    software_sticky <= 1'b1;
                    waiting_owner_abort_ack <= dpu_owned_present;
                    if (!dpu_owned_present)
                        recovery_done_sticky <= 1'b1;
                    last_reason <= REASON_SOFTWARE;
                    recovery_count <= recovery_count + 32'd1;
                end else if (video_error_pulse) begin
                    recovery_active <= 1'b1;
                    recovery_event_pulse <= 1'b1;
                    protocol_sticky <= 1'b1;
                    recovery_done_sticky <= 1'b1;
                    last_reason <= REASON_VIDEO_PROTOCOL;
                    recovery_count <= recovery_count + 32'd1;
                    protocol_recoveries <= protocol_recoveries + 32'd1;
                end else if (frame_abort) begin
                    recovery_active <= 1'b1;
                    recovery_event_pulse <= 1'b1;
                    recovery_done_sticky <= 1'b1;
                    recovery_count <= recovery_count + 32'd1;
                    if (frame_abort_reason == 2'b01) begin
                        protocol_sticky <= 1'b1;
                        last_reason <= REASON_FRAME_PROTOCOL;
                        protocol_recoveries <= protocol_recoveries + 32'd1;
                    end else if (frame_abort_reason == 2'b10) begin
                        last_reason <= REASON_DATAMOVER_STATUS;
                        datamover_recoveries <= datamover_recoveries + 32'd1;
                    end
                end
            end
        end
    end

`ifndef SYNTHESIS
    property p_abort_pulses_one_cycle;
        @(posedge aclk) disable iff (!aresetn || soft_reset)
            dpu_owner_abort |=> !dpu_owner_abort;
    endproperty
    assert property (p_abort_pulses_one_cycle)
        else $error("dpu_owner_abort lasted more than one cycle");

    property p_cancel_pulses_together;
        @(posedge aclk) disable iff (!aresetn || soft_reset)
            dpu_owner_abort |-> (request_cancel && profiler_request_abort);
    endproperty
    assert property (p_cancel_pulses_together)
        else $error("DPU recovery cancellation pulses disagree");

    property p_resets_match;
        @(posedge aclk) disable iff (!aresetn || soft_reset)
            adapter_recovery_reset == datamover_recovery_reset;
    endproperty
    assert property (p_resets_match)
        else $error("adapter and DataMover recovery resets disagree");
`endif

endmodule
