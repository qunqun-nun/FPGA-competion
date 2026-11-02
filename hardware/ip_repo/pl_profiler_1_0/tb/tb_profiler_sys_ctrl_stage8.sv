`timescale 1ns/1ps

module tb_profiler_sys_ctrl_stage8;
    logic clk = 0;
    logic aresetn = 0;
    logic [7:0] awaddr = 0, araddr = 0;
    logic [2:0] awprot = 0, arprot = 0;
    logic awvalid = 0, wvalid = 0, bready = 0, arvalid = 0, rready = 0;
    logic [31:0] wdata = 0;
    logic [3:0] wstrb = 0;
    wire awready, wready, bvalid, arready, rvalid;
    wire [1:0] bresp, rresp;
    wire [31:0] rdata;

    logic frame_start = 0, frame_end = 0, frame_abort = 0;
    logic request_commit = 0;
    logic [31:0] request_frame_id_in = 0;
    logic [1:0] request_buffer_id_in = 0;
    logic [31:0] request_generation_in = 0;
    logic [7:0] request_reason_in = 0;
    logic [31:0] request_timestamp_in = 0;
    logic result_release = 0;
    logic [31:0] scheduler_completed_frames = 0;

    wire enable, soft_reset, clear_error, irq;
    wire result_commit_pulse;
    wire [31:0] result_frame_id;
    wire [1:0] result_buffer_id;
    wire [31:0] result_generation;
    wire [15:0] result_bbox_x, result_bbox_y, result_bbox_w, result_bbox_h;
    wire [15:0] result_confidence;
    wire [7:0] result_status;
    wire profiler_clear_stats, profiler_snapshot_stats;
    wire dpu_timeout_pulse, frame_active, dpu_active, dpu_timeout_sticky;
    wire last_frame_aborted, measurement_error, snapshot_valid;
    wire [63:0] cycle_snapshot;
    wire [31:0] last_frame_cycles_snapshot, max_frame_cycles_snapshot;
    wire [31:0] last_dpu_latency_snapshot, max_dpu_latency_snapshot;
    wire [31:0] last_result_frame_age_snapshot, max_result_frame_age_snapshot;
    wire [31:0] dpu_timeout_count_snapshot, profiled_frames_snapshot;
    wire [31:0] profiled_requests_snapshot, profiled_results_snapshot;

    integer failures = 0;
    integer clear_pulses = 0;
    integer snapshot_pulses = 0;
    always #5 clk = ~clk;
    always @(posedge clk) begin
        if (profiler_clear_stats) clear_pulses++;
        if (profiler_snapshot_stats) snapshot_pulses++;
    end

    pl_profiler #(.DPU_TIMEOUT_CYCLES(64'd40)) profiler (
        .aclk(clk), .aresetn(aresetn), .soft_reset(soft_reset),
        .clear_stats(profiler_clear_stats), .snapshot_stats(profiler_snapshot_stats),
        .frame_start(frame_start), .frame_end(frame_end), .frame_abort(frame_abort),
        .request_commit(request_commit), .request_frame_id(request_frame_id_in),
        .request_buffer_id(request_buffer_id_in),
        .request_generation(request_generation_in),
        .result_release(result_release), .result_frame_id(result_frame_id),
        .result_buffer_id(result_buffer_id), .result_generation(result_generation),
        .scheduler_completed_frames(scheduler_completed_frames),
        .dpu_timeout_pulse(dpu_timeout_pulse), .frame_active(frame_active),
        .dpu_active(dpu_active), .dpu_timeout_sticky(dpu_timeout_sticky),
        .last_frame_aborted(last_frame_aborted),
        .measurement_error(measurement_error), .snapshot_valid(snapshot_valid),
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

    pl_sys_ctrl_v1_0 ctrl (
        .enable(enable), .soft_reset(soft_reset), .clear_error(clear_error),
        .video_source_select(), .video_active_source(1'b0),
        .video_pc_frame_active(1'b0), .video_pc_error(1'b0),
        .video_pc_error_code(32'd0), .video_pc_frame_count(32'd0),
        .lock(1'b1), .busy(1'b0), .fifo_ovf(1'b0), .fifo_empty(1'b1),
        .frame_done_pulse(1'b0), .err(1'b0), .err_code_in(32'd0),
        .frame_cnt(32'd0), .scheduler_completed_frames(scheduler_completed_frames),
        .scheduler_stale_frames(32'd0), .scheduler_dropped_frames(32'd0),
        .scheduler_stale_results(32'd0), .scheduler_buffer_conflicts(32'd0),
        .adapter_frames_aborted(32'd0), .scheduler_dpu_owned_mask(3'd0),
        .scheduler_ready_mask(3'd0), .scheduler_buffer_conflict(1'b0),
        .adapter_protocol_error(1'b0), .adapter_datamover_error(1'b0),
        .profiler_clear_stats(profiler_clear_stats),
        .profiler_snapshot_stats(profiler_snapshot_stats),
        .profiler_cycle_snapshot(cycle_snapshot),
        .profiler_last_frame_cycles(last_frame_cycles_snapshot),
        .profiler_max_frame_cycles(max_frame_cycles_snapshot),
        .profiler_last_dpu_latency(last_dpu_latency_snapshot),
        .profiler_max_dpu_latency(max_dpu_latency_snapshot),
        .profiler_last_result_frame_age(last_result_frame_age_snapshot),
        .profiler_max_result_frame_age(max_result_frame_age_snapshot),
        .profiler_dpu_timeout_count(dpu_timeout_count_snapshot),
        .profiler_frame_active(frame_active), .profiler_dpu_active(dpu_active),
        .profiler_dpu_timeout_sticky(dpu_timeout_sticky),
        .profiler_last_frame_aborted(last_frame_aborted),
        .profiler_measurement_error(measurement_error),
        .profiler_snapshot_valid(snapshot_valid),
        .profiler_profiled_frames(profiled_frames_snapshot),
        .profiler_profiled_requests(profiled_requests_snapshot),
        .profiler_profiled_results(profiled_results_snapshot),
        .request_commit(request_commit), .request_frame_id_in(request_frame_id_in),
        .request_buffer_id_in(request_buffer_id_in),
        .request_generation_in(request_generation_in),
        .request_reason_in(request_reason_in),
        .request_timestamp_in(request_timestamp_in), .result_ack(result_release),
        .result_commit_pulse(result_commit_pulse), .result_frame_id(result_frame_id),
        .result_buffer_id(result_buffer_id), .result_generation(result_generation),
        .result_bbox_x(result_bbox_x), .result_bbox_y(result_bbox_y),
        .result_bbox_w(result_bbox_w), .result_bbox_h(result_bbox_h),
        .result_confidence(result_confidence), .result_status(result_status), .irq(irq),
        .s00_axi_aclk(clk), .s00_axi_aresetn(aresetn),
        .s00_axi_awaddr(awaddr), .s00_axi_awprot(awprot),
        .s00_axi_awvalid(awvalid), .s00_axi_awready(awready),
        .s00_axi_wdata(wdata), .s00_axi_wstrb(wstrb),
        .s00_axi_wvalid(wvalid), .s00_axi_wready(wready),
        .s00_axi_bresp(bresp), .s00_axi_bvalid(bvalid), .s00_axi_bready(bready),
        .s00_axi_araddr(araddr), .s00_axi_arprot(arprot),
        .s00_axi_arvalid(arvalid), .s00_axi_arready(arready),
        .s00_axi_rdata(rdata), .s00_axi_rresp(rresp),
        .s00_axi_rvalid(rvalid), .s00_axi_rready(rready)
    );

    task automatic check(input bit condition, input string message);
        if (!condition) begin $display("FAIL: %s", message); failures++; end
        else $display("PASS: %s", message);
    endtask

    task automatic pulse(ref logic signal);
        @(negedge clk); signal = 1; @(negedge clk); signal = 0;
    endtask

    task automatic axi_write(input [7:0] address, input [31:0] data);
        @(negedge clk); awaddr=address; wdata=data; wstrb=4'hf; awvalid=1; wvalid=1;
        while (!(awready && wready)) @(negedge clk);
        @(negedge clk); awvalid=0; wvalid=0; bready=1;
        while (!bvalid) @(negedge clk);
        @(negedge clk); bready=0;
    endtask

    task automatic axi_read(input [7:0] address, output [31:0] data);
        @(negedge clk); araddr=address; arvalid=1;
        while (!arready) @(negedge clk);
        @(negedge clk); arvalid=0; rready=1;
        while (!rvalid) @(negedge clk);
        data=rdata;
        @(negedge clk); rready=0;
    endtask

    task automatic check_read(input [7:0] address, input [31:0] expected,
                              input string message);
        reg [31:0] actual;
        axi_read(address, actual);
        check(actual === expected, message);
        if (actual !== expected) $display(" expected=%08x actual=%08x", expected, actual);
    endtask

    initial begin
        repeat (4) @(posedge clk); aresetn=1; repeat (2) @(posedge clk);

        pulse(frame_start); repeat (3) @(posedge clk); pulse(frame_end);
        request_frame_id_in=32'd3; request_buffer_id_in=2'd1;
        request_generation_in=32'd7; request_reason_in=8'h1;
        pulse(request_commit); repeat (2) @(posedge clk);

        // Program a matching result through the real shadow/commit mailbox.
        scheduler_completed_frames=32'd6;
        axi_write(8'h30,32'd3); axi_write(8'h34,32'd1); axi_write(8'h38,32'd7);
        axi_write(8'h54,32'd1);
        pulse(result_release);

        axi_write(8'h90,32'd2);
        repeat (2) @(posedge clk);
        check(snapshot_pulses==1, "PROF_CTRL snapshot command is one pulse");
        check_read(8'h9c,32'd4,"frame latency reaches AXI register");
        check_read(8'ha0,32'd4,"frame maximum reaches AXI register");
        check_read(8'hac,32'd2,"result frame age reaches AXI register");
        check_read(8'hbc,32'd1,"profiled frame count reaches AXI register");
        check_read(8'hc0,32'd1,"profiled request count reaches AXI register");
        check_read(8'hc4,32'd1,"profiled result count reaches AXI register");
        check_read(8'hb8,32'h20,"snapshot-valid status is readable");

        // Read-only registers ignore writes.
        axi_write(8'h9c,32'hffff_ffff);
        check_read(8'h9c,32'd4,"profiler data registers are read-only");

        // Generate and snapshot one timeout.
        request_frame_id_in=32'd8; request_buffer_id_in=2'd2;
        request_generation_in=32'd9; pulse(request_commit);
        repeat (45) @(posedge clk);
        axi_write(8'h90,32'd2); repeat (2) @(posedge clk);
        check_read(8'hb4,32'd1,"timeout count reaches AXI register");
        check_read(8'hb8,32'h26,"DPU-active, timeout and snapshot status bits");

        axi_write(8'h90,32'd1); repeat (2) @(posedge clk);
        check(clear_pulses==1,"PROF_CTRL clear command is one pulse");
        axi_write(8'h90,32'd2); repeat (2) @(posedge clk);
        check_read(8'hb4,32'd0,"clear command clears timeout statistics");
        check_read(8'hbc,32'd0,"clear command clears frame statistics");
        check_read(8'hb8,32'h22,"clear preserves active request and new snapshot valid");

        if (failures==0) $display("STAGE8 PROFILER SYS_CTRL TEST PASS");
        else $fatal(1,"STAGE8 PROFILER SYS_CTRL TEST FAIL count=%0d",failures);
        $finish;
    end
endmodule
