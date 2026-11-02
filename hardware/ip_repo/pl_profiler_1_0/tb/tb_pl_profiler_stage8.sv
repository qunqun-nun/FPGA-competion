`timescale 1ns/1ps

module tb_pl_profiler_stage8;
    logic clk = 1'b0;
    logic aresetn = 1'b0;
    logic soft_reset = 1'b0;
    logic clear_stats = 1'b0;
    logic snapshot_stats = 1'b0;
    logic frame_start = 1'b0;
    logic frame_end = 1'b0;
    logic frame_abort = 1'b0;
    logic request_commit = 1'b0;
    logic [31:0] request_frame_id = 0;
    logic [1:0] request_buffer_id = 0;
    logic [31:0] request_generation = 0;
    logic result_release = 1'b0;
    logic [31:0] result_frame_id = 0;
    logic [1:0] result_buffer_id = 0;
    logic [31:0] result_generation = 0;
    logic [31:0] scheduler_completed_frames = 0;

    wire dpu_timeout_pulse;
    wire frame_active;
    wire dpu_active;
    wire dpu_timeout_sticky;
    wire last_frame_aborted;
    wire measurement_error;
    wire snapshot_valid;
    wire [63:0] cycle_snapshot;
    wire [31:0] last_frame_cycles_snapshot;
    wire [31:0] max_frame_cycles_snapshot;
    wire [31:0] last_dpu_latency_snapshot;
    wire [31:0] max_dpu_latency_snapshot;
    wire [31:0] last_result_frame_age_snapshot;
    wire [31:0] max_result_frame_age_snapshot;
    wire [31:0] dpu_timeout_count_snapshot;
    wire [31:0] profiled_frames_snapshot;
    wire [31:0] profiled_requests_snapshot;
    wire [31:0] profiled_results_snapshot;

    integer failures = 0;
    integer timeout_pulses = 0;

    always #5 clk = ~clk;
    always @(posedge clk) if (dpu_timeout_pulse) timeout_pulses <= timeout_pulses + 1;

    pl_profiler #(.DPU_TIMEOUT_CYCLES(64'd6)) dut (
        .aclk(clk),
        .aresetn(aresetn),
        .soft_reset(soft_reset),
        .clear_stats(clear_stats),
        .snapshot_stats(snapshot_stats),
        .frame_start(frame_start),
        .frame_end(frame_end),
        .frame_abort(frame_abort),
        .request_commit(request_commit),
        .request_frame_id(request_frame_id),
        .request_buffer_id(request_buffer_id),
        .request_generation(request_generation),
        .result_release(result_release),
        .result_frame_id(result_frame_id),
        .result_buffer_id(result_buffer_id),
        .result_generation(result_generation),
        .scheduler_completed_frames(scheduler_completed_frames),
        .dpu_timeout_pulse(dpu_timeout_pulse),
        .frame_active(frame_active),
        .dpu_active(dpu_active),
        .dpu_timeout_sticky(dpu_timeout_sticky),
        .last_frame_aborted(last_frame_aborted),
        .measurement_error(measurement_error),
        .snapshot_valid(snapshot_valid),
        .cycle_snapshot(cycle_snapshot),
        .last_frame_cycles_snapshot(last_frame_cycles_snapshot),
        .max_frame_cycles_snapshot(max_frame_cycles_snapshot),
        .last_dpu_latency_snapshot(last_dpu_latency_snapshot),
        .max_dpu_latency_snapshot(max_dpu_latency_snapshot),
        .last_result_frame_age_snapshot(last_result_frame_age_snapshot),
        .max_result_frame_age_snapshot(max_result_frame_age_snapshot),
        .dpu_timeout_count_snapshot(dpu_timeout_count_snapshot),
        .profiled_frames_snapshot(profiled_frames_snapshot),
        .profiled_requests_snapshot(profiled_requests_snapshot),
        .profiled_results_snapshot(profiled_results_snapshot)
    );

    task automatic check(input bit condition, input string message);
        if (!condition) begin
            $display("FAIL: %s", message);
            failures++;
        end else begin
            $display("PASS: %s", message);
        end
    endtask

    task automatic pulse(ref logic signal);
        @(negedge clk); signal = 1'b1;
        @(negedge clk); signal = 1'b0;
    endtask

    task automatic take_snapshot;
        pulse(snapshot_stats);
        @(posedge clk); #1;
    endtask

    task automatic start_request(
        input [31:0] frame_id, input [1:0] buffer_id,
        input [31:0] generation
    );
        @(negedge clk);
        request_frame_id = frame_id;
        request_buffer_id = buffer_id;
        request_generation = generation;
        request_commit = 1'b1;
        @(negedge clk); request_commit = 1'b0;
    endtask

    task automatic finish_result(
        input [31:0] frame_id, input [1:0] buffer_id,
        input [31:0] generation
    );
        @(negedge clk);
        result_frame_id = frame_id;
        result_buffer_id = buffer_id;
        result_generation = generation;
        result_release = 1'b1;
        @(negedge clk); result_release = 1'b0;
    endtask

    initial begin
        repeat (3) @(posedge clk);
        aresetn = 1'b1;
        repeat (2) @(posedge clk);

        // A successful four-cycle frame.
        pulse(frame_start);
        repeat (3) @(posedge clk);
        pulse(frame_end);
        take_snapshot();
        check(profiled_frames_snapshot == 1, "successful frame counted");
        check(last_frame_cycles_snapshot == 4, "successful frame latency is four cycles");
        check(max_frame_cycles_snapshot == 4, "frame maximum initialized");
        check(!last_frame_aborted, "successful frame marked non-aborted");

        // A shorter aborted frame updates last but not maximum.
        pulse(frame_start);
        @(posedge clk);
        pulse(frame_abort);
        take_snapshot();
        check(profiled_frames_snapshot == 2, "aborted frame counted");
        check(last_frame_cycles_snapshot == 2, "aborted frame latency measured");
        check(max_frame_cycles_snapshot == 4, "short abort does not reduce maximum");
        check(last_frame_aborted, "last frame records abort termination");

        // Request/result identity and frame-age calculation.
        scheduler_completed_frames = 32'd12;
        start_request(32'd8, 2'd1, 32'd3);
        repeat (2) @(posedge clk);
        finish_result(32'd8, 2'd1, 32'd3);
        take_snapshot();
        check(profiled_requests_snapshot == 1, "DPU request counted");
        check(profiled_results_snapshot == 1, "matching DPU result counted");
        check(last_dpu_latency_snapshot == 3, "DPU latency measured");
        check(last_result_frame_age_snapshot == 3, "result return frame age calculated");
        check(!dpu_active, "matching result closes active request");

        // Mismatching result does not end the active request.
        start_request(32'd12, 2'd2, 32'd9);
        finish_result(32'd12, 2'd1, 32'd9);
        check(dpu_active, "mismatching result cannot close request");
        check(measurement_error, "mismatching result raises measurement error");
        scheduler_completed_frames = 32'd14;
        finish_result(32'd12, 2'd2, 32'd9);
        check(!dpu_active, "later matching result closes request");

        // Timeout is emitted once per request and late matching result is accepted.
        start_request(32'd20, 2'd0, 32'd4);
        repeat (10) @(posedge clk);
        check(timeout_pulses == 1, "timeout produces exactly one pulse");
        check(dpu_timeout_sticky, "timeout sticky status set");
        pulse(clear_stats);
        repeat (8) @(posedge clk);
        check(timeout_pulses == 1, "clear statistics does not retrigger active request");
        scheduler_completed_frames = 32'd22;
        finish_result(32'd20, 2'd0, 32'd4);
        take_snapshot();
        check(profiled_requests_snapshot == 0, "clear statistics clears published request count");
        check(profiled_results_snapshot == 1, "late result after clear is newly counted");
        check(dpu_timeout_count_snapshot == 0, "clear statistics clears timeout count");

        // A result newer than the latest complete frame is rejected for age statistics.
        pulse(clear_stats);
        scheduler_completed_frames = 32'd5;
        start_request(32'd5, 2'd1, 32'd11);
        finish_result(32'd5, 2'd1, 32'd11);
        take_snapshot();
        check(last_result_frame_age_snapshot == 0, "invalid newer frame age clamps to zero");
        check(measurement_error, "invalid newer frame age raises measurement error");

        // Soft reset clears active measurements and snapshots.
        start_request(32'd1, 2'd0, 32'd1);
        pulse(soft_reset);
        check(!dpu_active && !frame_active, "soft reset clears active measurements");
        check(!snapshot_valid, "soft reset clears snapshot valid");

        if (failures == 0) begin
            $display("STAGE8 PL_PROFILER TEST PASS");
            $finish;
        end else begin
            $fatal(1, "STAGE8 PL_PROFILER TEST FAIL: %0d failures", failures);
        end
    end
endmodule
