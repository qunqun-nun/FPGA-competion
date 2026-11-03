`timescale 1 ns / 1 ps

module pl_sys_ctrl_v1_0_S00_AXI #
(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 8
)
(
    output wire enable,
    output wire soft_reset,
    output wire clear_error,
    output wire video_source_select,

    input wire lock,
    input wire busy,
    input wire fifo_ovf,
    input wire fifo_empty,
    input wire frame_done_pulse,
    input wire err,
    input wire [C_S_AXI_DATA_WIDTH-1:0] err_code_in,
    input wire [C_S_AXI_DATA_WIDTH-1:0] frame_cnt,
    input wire video_active_source,
    input wire video_pc_frame_active,
    input wire video_pc_error,
    input wire [31:0] video_pc_error_code,
    input wire [31:0] video_pc_frame_count,
    input wire [2:0] fusion_state,
    input wire tracker_active,
    input wire tracker_processing_busy,
    input wire [31:0] track_last_sad,

    input wire [31:0] scheduler_completed_frames,
    input wire [31:0] scheduler_stale_frames,
    input wire [31:0] scheduler_dropped_frames,
    input wire [31:0] scheduler_stale_results,
    input wire [31:0] scheduler_buffer_conflicts,
    input wire [31:0] adapter_frames_aborted,
    input wire [2:0] scheduler_dpu_owned_mask,
    input wire [2:0] scheduler_ready_mask,
    input wire scheduler_buffer_conflict,
    input wire adapter_protocol_error,
    input wire adapter_datamover_error,

    output wire profiler_clear_stats,
    output wire profiler_snapshot_stats,
    input wire [63:0] profiler_cycle_snapshot,
    input wire [31:0] profiler_last_frame_cycles,
    input wire [31:0] profiler_max_frame_cycles,
    input wire [31:0] profiler_last_dpu_latency,
    input wire [31:0] profiler_max_dpu_latency,
    input wire [31:0] profiler_last_result_frame_age,
    input wire [31:0] profiler_max_result_frame_age,
    input wire [31:0] profiler_dpu_timeout_count,
    input wire profiler_frame_active,
    input wire profiler_dpu_active,
    input wire profiler_dpu_timeout_sticky,
    input wire profiler_last_frame_aborted,
    input wire profiler_measurement_error,
    input wire profiler_snapshot_valid,
    input wire [31:0] profiler_profiled_frames,
    input wire [31:0] profiler_profiled_requests,
    input wire [31:0] profiler_profiled_results,

    output wire recovery_clear_status,
    output wire recovery_software_trigger,
    input wire request_cancel,
    input wire recovery_active,
    input wire recovery_fatal_sticky,
    input wire recovery_protocol_sticky,
    input wire recovery_software_sticky,
    input wire recovery_done_sticky,
    input wire [7:0] recovery_last_reason,
    input wire [31:0] recovery_count,
    input wire [31:0] recovery_dpu_timeout_count,
    input wire [31:0] recovery_datamover_count,
    input wire [31:0] recovery_protocol_count,

    input wire request_commit,
    input wire [31:0] request_frame_id_in,
    input wire [1:0] request_buffer_id_in,
    input wire [31:0] request_generation_in,
    input wire [7:0] request_reason_in,
    input wire [31:0] request_timestamp_in,

    input wire result_ack,

    output wire result_commit_pulse,
    output wire [31:0] result_frame_id,
    output wire [1:0] result_buffer_id,
    output wire [31:0] result_generation,
    output wire [15:0] result_bbox_x,
    output wire [15:0] result_bbox_y,
    output wire [15:0] result_bbox_w,
    output wire [15:0] result_bbox_h,
    output wire [15:0] result_confidence,
    output wire [7:0] result_status,
    output wire irq,

    input wire S_AXI_ACLK,
    input wire S_AXI_ARESETN,
    input wire [C_S_AXI_ADDR_WIDTH-1:0] S_AXI_AWADDR,
    input wire [2:0] S_AXI_AWPROT,
    input wire S_AXI_AWVALID,
    output wire S_AXI_AWREADY,
    input wire [C_S_AXI_DATA_WIDTH-1:0] S_AXI_WDATA,
    input wire [(C_S_AXI_DATA_WIDTH/8)-1:0] S_AXI_WSTRB,
    input wire S_AXI_WVALID,
    output wire S_AXI_WREADY,
    output wire [1:0] S_AXI_BRESP,
    output wire S_AXI_BVALID,
    input wire S_AXI_BREADY,
    input wire [C_S_AXI_ADDR_WIDTH-1:0] S_AXI_ARADDR,
    input wire [2:0] S_AXI_ARPROT,
    input wire S_AXI_ARVALID,
    output wire S_AXI_ARREADY,
    output wire [C_S_AXI_DATA_WIDTH-1:0] S_AXI_RDATA,
    output wire [1:0] S_AXI_RRESP,
    output wire S_AXI_RVALID,
    input wire S_AXI_RREADY
);

    localparam integer ADDR_LSB = (C_S_AXI_DATA_WIDTH/32) + 1;
    localparam integer OPT_MEM_ADDR_BITS = 5;
    localparam [7:0] ERR_REQUEST_OVERWRITE = 8'h01;
    localparam [7:0] ERR_STALE_RESULT = 8'h02;
    localparam [7:0] ERR_EXTERNAL = 8'h03;
    localparam [7:0] ERR_DATAMOVER = 8'h04;
    localparam [7:0] ERR_PROTOCOL = 8'h05;
    localparam [7:0] ERR_SCHEDULER = 8'h06;
    localparam [7:0] SOURCE_NONE = 8'h00;
    localparam [7:0] SOURCE_EXTERNAL = 8'h01;
    localparam [7:0] SOURCE_SCHEDULER = 8'h02;
    localparam [7:0] SOURCE_DATAMOVER = 8'h03;
    localparam [7:0] SOURCE_PROTOCOL = 8'h04;
    localparam [7:0] SOURCE_PC_VIDEO = 8'h05;

    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_awaddr;
    reg axi_aw_hold;
    reg axi_w_hold;
    reg [C_S_AXI_DATA_WIDTH-1:0] axi_wdata;
    reg [(C_S_AXI_DATA_WIDTH/8)-1:0] axi_wstrb;
    reg axi_bvalid;
    reg [1:0] axi_bresp;
    reg axi_rvalid;
    reg [1:0] axi_rresp;
    reg [C_S_AXI_DATA_WIDTH-1:0] axi_rdata;
    wire write_fire;
    wire read_fire;
    wire result_commit_write;

    reg [31:0] ctrl_reg;
    reg soft_reset_reg;
    reg clear_error_reg;
    reg profiler_clear_stats_reg;
    reg profiler_snapshot_stats_reg;
    reg recovery_clear_status_reg;
    reg recovery_software_trigger_reg;
    reg frame_done_seen_reg;
    reg err_sticky_reg;
    reg buffer_conflict_reg;
    reg stale_result_reg;
    reg [31:0] err_code_reg;
    reg [7:0] error_source_reg;
    reg video_source_select_reg;
    reg video_pc_error_sticky_reg;
    reg [31:0] video_switch_rejects_reg;

    reg [31:0] request_seq_reg;
    reg [31:0] request_frame_id_reg;
    reg [1:0] request_buffer_id_reg;
    reg [31:0] request_generation_reg;
    reg [7:0] request_reason_reg;
    reg [31:0] request_timestamp_reg;
    reg request_pending_reg;
    reg request_ps_seen_reg;
    reg request_active_reg;

    reg [31:0] result_shadow_frame_id_reg;
    reg [1:0] result_shadow_buffer_id_reg;
    reg [31:0] result_shadow_generation_reg;
    reg [15:0] result_shadow_bbox_x_reg;
    reg [15:0] result_shadow_bbox_y_reg;
    reg [15:0] result_shadow_bbox_w_reg;
    reg [15:0] result_shadow_bbox_h_reg;
    reg [15:0] result_shadow_confidence_reg;
    reg [7:0] result_shadow_status_reg;

    reg [31:0] result_frame_id_reg;
    reg [1:0] result_buffer_id_reg;
    reg [31:0] result_generation_reg;
    reg [15:0] result_bbox_x_reg;
    reg [15:0] result_bbox_y_reg;
    reg [15:0] result_bbox_w_reg;
    reg [15:0] result_bbox_h_reg;
    reg [15:0] result_confidence_reg;
    reg [7:0] result_status_reg;
    reg [31:0] result_seq_reg;
    reg result_pending_reg;
    reg result_commit_pulse_reg;

    reg [3:0] irq_status_reg;
    reg [31:0] irq_enable_reg;
    reg scheduler_buffer_conflict_d;
    reg adapter_protocol_error_d;
    reg adapter_datamover_error_d;

    wire scheduler_buffer_conflict_event =
        scheduler_buffer_conflict && !scheduler_buffer_conflict_d;
    wire adapter_protocol_error_event =
        adapter_protocol_error && !adapter_protocol_error_d;
    wire adapter_datamover_error_event =
        adapter_datamover_error && !adapter_datamover_error_d;

    assign enable = ctrl_reg[0];
    assign soft_reset = soft_reset_reg;
    assign clear_error = clear_error_reg;
    assign video_source_select = video_source_select_reg;
    assign profiler_clear_stats = profiler_clear_stats_reg;
    assign profiler_snapshot_stats = profiler_snapshot_stats_reg;
    assign recovery_clear_status = recovery_clear_status_reg;
    assign recovery_software_trigger = recovery_software_trigger_reg;
    assign result_commit_pulse = result_commit_pulse_reg;
    assign result_frame_id = result_frame_id_reg;
    assign result_buffer_id = result_buffer_id_reg;
    assign result_generation = result_generation_reg;
    assign result_bbox_x = result_bbox_x_reg;
    assign result_bbox_y = result_bbox_y_reg;
    assign result_bbox_w = result_bbox_w_reg;
    assign result_bbox_h = result_bbox_h_reg;
    assign result_confidence = result_confidence_reg;
    assign result_status = result_status_reg;
    assign irq = |(irq_status_reg & irq_enable_reg[3:0]);

    assign S_AXI_AWREADY = S_AXI_ARESETN && !axi_aw_hold && !axi_bvalid;
    assign S_AXI_WREADY = S_AXI_ARESETN && !axi_w_hold && !axi_bvalid;
    assign S_AXI_BVALID = axi_bvalid;
    assign S_AXI_BRESP = axi_bresp;
    assign write_fire = axi_aw_hold && axi_w_hold && !axi_bvalid;
    assign result_commit_write = write_fire &&
        (axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 6'h15) &&
        axi_wstrb[0] && axi_wdata[0];
    assign S_AXI_ARREADY = S_AXI_ARESETN && !axi_rvalid;
    assign S_AXI_RVALID = axi_rvalid;
    assign S_AXI_RRESP = axi_rresp;
    assign S_AXI_RDATA = axi_rdata;
    assign read_fire = S_AXI_ARVALID && S_AXI_ARREADY;

    function [31:0] apply_wstrb;
        input [31:0] prior_value;
        input [31:0] new_value;
        input [3:0] write_strobe;
        integer byte_index;
        begin
            apply_wstrb = prior_value;
            for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1) begin
                if (write_strobe[byte_index]) begin
                    apply_wstrb[byte_index*8 +: 8] =
                        new_value[byte_index*8 +: 8];
                end
            end
        end
    endfunction

    function [31:0] read_data;
        input [C_S_AXI_ADDR_WIDTH-1:0] address;
        reg [31:0] status_value;
        reg [31:0] request_status_value;
        begin
            status_value = 32'b0;
            status_value[0] = lock;
            status_value[1] = busy;
            status_value[2] = fifo_ovf;
            status_value[3] = fifo_empty;
            status_value[4] = frame_done_seen_reg;
            status_value[5] = err_sticky_reg;
            status_value[6] = request_pending_reg;
            status_value[7] = result_pending_reg;
            status_value[8] = |irq_status_reg;
            status_value[9] = buffer_conflict_reg;
            status_value[10] = stale_result_reg;

            request_status_value = 32'b0;
            request_status_value[0] = request_seq_reg != 0;
            request_status_value[1] = request_pending_reg;
            request_status_value[2] = request_ps_seen_reg;
            request_status_value[3] = request_pending_reg && !request_ps_seen_reg;
            request_status_value[4] = request_active_reg;

            read_data = 32'b0;
            case (address[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB])
                6'h00: read_data = ctrl_reg;
                6'h01: read_data = status_value;
                6'h02: read_data = frame_cnt;
                6'h03: read_data = err_code_reg;
                6'h04: read_data = request_seq_reg;
                6'h05: read_data = request_frame_id_reg;
                6'h06: read_data = {30'b0, request_buffer_id_reg};
                6'h07: read_data = request_generation_reg;
                6'h08: read_data = {24'b0, request_reason_reg};
                6'h09: read_data = request_status_value;
                6'h0A: read_data = request_timestamp_reg;
                6'h0C: read_data = result_shadow_frame_id_reg;
                6'h0D: read_data = {30'b0, result_shadow_buffer_id_reg};
                6'h0E: read_data = result_shadow_generation_reg;
                6'h0F: read_data = {16'b0, result_shadow_bbox_x_reg};
                6'h10: read_data = {16'b0, result_shadow_bbox_y_reg};
                6'h11: read_data = {16'b0, result_shadow_bbox_w_reg};
                6'h12: read_data = {16'b0, result_shadow_bbox_h_reg};
                6'h13: read_data = {16'b0, result_shadow_confidence_reg};
                6'h14: read_data = {24'b0, result_shadow_status_reg};
                6'h16: read_data = result_seq_reg;
                6'h17: read_data = {24'b0, result_status_reg};
                 6'h18: begin
                     read_data = 32'b0;
                     read_data[3:0] = irq_status_reg;
                 end
                 6'h1A: read_data = irq_enable_reg;
                 6'h1B: read_data = 32'h0004_0000;
                 6'h1C: read_data = scheduler_completed_frames;
                 6'h1D: read_data = scheduler_stale_frames;
                 6'h1E: read_data = scheduler_dropped_frames;
                 6'h1F: read_data = scheduler_stale_results;
                 6'h20: read_data = scheduler_buffer_conflicts;
                 6'h21: read_data = adapter_frames_aborted;
                 6'h22: read_data = {26'b0, scheduler_ready_mask,
                                      scheduler_dpu_owned_mask};
                 6'h23: read_data = {24'b0, error_source_reg};
                 6'h25: read_data = profiler_cycle_snapshot[31:0];
                 6'h26: read_data = profiler_cycle_snapshot[63:32];
                 6'h27: read_data = profiler_last_frame_cycles;
                 6'h28: read_data = profiler_max_frame_cycles;
                 6'h29: read_data = profiler_last_dpu_latency;
                 6'h2A: read_data = profiler_max_dpu_latency;
                 6'h2B: read_data = profiler_last_result_frame_age;
                 6'h2C: read_data = profiler_max_result_frame_age;
                 6'h2D: read_data = profiler_dpu_timeout_count;
                 6'h2E: begin
                     read_data = 32'b0;
                     read_data[0] = profiler_frame_active;
                     read_data[1] = profiler_dpu_active;
                     read_data[2] = profiler_dpu_timeout_sticky;
                     read_data[3] = profiler_last_frame_aborted;
                     read_data[4] = profiler_measurement_error;
                     read_data[5] = profiler_snapshot_valid;
                 end
                 6'h2F: read_data = profiler_profiled_frames;
                 6'h30: read_data = profiler_profiled_requests;
                 6'h31: read_data = profiler_profiled_results;
                 6'h33: begin
                     read_data = 32'b0;
                     read_data[0] = recovery_active;
                     read_data[1] = recovery_fatal_sticky;
                     read_data[2] = recovery_protocol_sticky;
                     read_data[3] = recovery_software_sticky;
                     read_data[4] = recovery_done_sticky;
                 end
                 6'h34: read_data = {24'b0, recovery_last_reason};
                 6'h35: read_data = recovery_count;
                 6'h36: read_data = recovery_dpu_timeout_count;
                 6'h37: read_data = recovery_datamover_count;
                 6'h38: read_data = recovery_protocol_count;
                 6'h39: read_data = {31'b0, video_source_select_reg};
                 6'h3A: begin
                     read_data = 32'b0;
                     read_data[0] = video_active_source;
                     read_data[1] = video_pc_frame_active;
                     read_data[2] = video_pc_error_sticky_reg;
                 end
                 6'h3B: read_data = video_pc_error_code;
                 6'h3C: read_data = video_pc_frame_count;
                 6'h3D: read_data = video_switch_rejects_reg;
                 6'h3E: begin
                     read_data = 32'b0;
                     read_data[2:0] = fusion_state;
                     read_data[8] = tracker_active;
                     read_data[9] = tracker_processing_busy;
                     read_data[10] = (fusion_state == 3'd4);
                 end
                 6'h3F: read_data = track_last_sad;
                 default: read_data = 32'b0;
            endcase
        end
    endfunction

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_awaddr <= {C_S_AXI_ADDR_WIDTH{1'b0}};
            axi_aw_hold <= 1'b0;
            axi_w_hold <= 1'b0;
            axi_wdata <= 32'b0;
            axi_wstrb <= 4'b0;
            axi_bvalid <= 1'b0;
            axi_bresp <= 2'b0;
            axi_rvalid <= 1'b0;
            axi_rresp <= 2'b0;
            axi_rdata <= 32'b0;

            ctrl_reg <= 32'b0;
            soft_reset_reg <= 1'b0;
            clear_error_reg <= 1'b0;
            profiler_clear_stats_reg <= 1'b0;
            profiler_snapshot_stats_reg <= 1'b0;
            recovery_clear_status_reg <= 1'b0;
            recovery_software_trigger_reg <= 1'b0;
            frame_done_seen_reg <= 1'b0;
            err_sticky_reg <= 1'b0;
             buffer_conflict_reg <= 1'b0;
             stale_result_reg <= 1'b0;
             err_code_reg <= 32'b0;
             error_source_reg <= SOURCE_NONE;
             video_source_select_reg <= 1'b0;
             video_pc_error_sticky_reg <= 1'b0;
             video_switch_rejects_reg <= 32'b0;

            request_seq_reg <= 32'b0;
            request_frame_id_reg <= 32'b0;
            request_buffer_id_reg <= 2'b0;
            request_generation_reg <= 32'b0;
            request_reason_reg <= 8'b0;
            request_timestamp_reg <= 32'b0;
            request_pending_reg <= 1'b0;
            request_ps_seen_reg <= 1'b0;
            request_active_reg <= 1'b0;

            result_shadow_frame_id_reg <= 32'b0;
            result_shadow_buffer_id_reg <= 2'b0;
            result_shadow_generation_reg <= 32'b0;
            result_shadow_bbox_x_reg <= 16'b0;
            result_shadow_bbox_y_reg <= 16'b0;
            result_shadow_bbox_w_reg <= 16'b0;
            result_shadow_bbox_h_reg <= 16'b0;
            result_shadow_confidence_reg <= 16'b0;
            result_shadow_status_reg <= 8'b0;

            result_frame_id_reg <= 32'b0;
            result_buffer_id_reg <= 2'b0;
            result_generation_reg <= 32'b0;
            result_bbox_x_reg <= 16'b0;
            result_bbox_y_reg <= 16'b0;
            result_bbox_w_reg <= 16'b0;
            result_bbox_h_reg <= 16'b0;
            result_confidence_reg <= 16'b0;
            result_status_reg <= 8'b0;
            result_seq_reg <= 32'b0;
            result_pending_reg <= 1'b0;
            result_commit_pulse_reg <= 1'b0;

            irq_status_reg <= 4'b0;
            irq_enable_reg <= 32'b0;
            scheduler_buffer_conflict_d <= 1'b0;
            adapter_protocol_error_d <= 1'b0;
            adapter_datamover_error_d <= 1'b0;
        end else begin
            soft_reset_reg <= 1'b0;
            clear_error_reg <= 1'b0;
            profiler_clear_stats_reg <= 1'b0;
            profiler_snapshot_stats_reg <= 1'b0;
            recovery_clear_status_reg <= 1'b0;
            recovery_software_trigger_reg <= 1'b0;
            result_commit_pulse_reg <= 1'b0;
            scheduler_buffer_conflict_d <= scheduler_buffer_conflict;
            adapter_protocol_error_d <= adapter_protocol_error;
            adapter_datamover_error_d <= adapter_datamover_error;

            if (S_AXI_AWVALID && S_AXI_AWREADY) begin
                axi_awaddr <= S_AXI_AWADDR;
                axi_aw_hold <= 1'b1;
            end
            if (S_AXI_WVALID && S_AXI_WREADY) begin
                axi_wdata <= S_AXI_WDATA;
                axi_wstrb <= S_AXI_WSTRB;
                axi_w_hold <= 1'b1;
            end
            if (write_fire) begin
                axi_aw_hold <= 1'b0;
                axi_w_hold <= 1'b0;
                axi_bvalid <= 1'b1;
                axi_bresp <= 2'b00;

                case (axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB])
                    6'h00: begin
                        if (axi_wstrb[0]) begin
                            ctrl_reg[0] <= axi_wdata[0];
                            if (axi_wdata[1]) soft_reset_reg <= 1'b1;
                            if (axi_wdata[2]) clear_error_reg <= 1'b1;
                        end
                        ctrl_reg[31:3] <= 29'b0;
                    end
                    6'h0C: begin
                        result_shadow_frame_id_reg <= apply_wstrb(
                            result_shadow_frame_id_reg, axi_wdata, axi_wstrb);
                    end
                    6'h0D: begin
                        if (axi_wstrb[0]) result_shadow_buffer_id_reg <= axi_wdata[1:0];
                    end
                    6'h0E: begin
                        result_shadow_generation_reg <= apply_wstrb(
                            result_shadow_generation_reg, axi_wdata, axi_wstrb);
                    end
                    6'h0F: begin
                        if (axi_wstrb[0]) result_shadow_bbox_x_reg[7:0] <= axi_wdata[7:0];
                        if (axi_wstrb[1]) result_shadow_bbox_x_reg[15:8] <= axi_wdata[15:8];
                    end
                    6'h10: begin
                        if (axi_wstrb[0]) result_shadow_bbox_y_reg[7:0] <= axi_wdata[7:0];
                        if (axi_wstrb[1]) result_shadow_bbox_y_reg[15:8] <= axi_wdata[15:8];
                    end
                    6'h11: begin
                        if (axi_wstrb[0]) result_shadow_bbox_w_reg[7:0] <= axi_wdata[7:0];
                        if (axi_wstrb[1]) result_shadow_bbox_w_reg[15:8] <= axi_wdata[15:8];
                    end
                    6'h12: begin
                        if (axi_wstrb[0]) result_shadow_bbox_h_reg[7:0] <= axi_wdata[7:0];
                        if (axi_wstrb[1]) result_shadow_bbox_h_reg[15:8] <= axi_wdata[15:8];
                    end
                    6'h13: begin
                        if (axi_wstrb[0]) result_shadow_confidence_reg[7:0] <= axi_wdata[7:0];
                        if (axi_wstrb[1]) result_shadow_confidence_reg[15:8] <= axi_wdata[15:8];
                    end
                    6'h14: begin
                        if (axi_wstrb[0]) result_shadow_status_reg <= axi_wdata[7:0];
                    end
                    6'h15: begin
                        if (axi_wstrb[0] && axi_wdata[0]) begin
                            if (request_active_reg && !request_cancel &&
                                (result_shadow_frame_id_reg == request_frame_id_reg) &&
                                (result_shadow_buffer_id_reg == request_buffer_id_reg) &&
                                (result_shadow_generation_reg == request_generation_reg)) begin
                                result_frame_id_reg <= result_shadow_frame_id_reg;
                                result_buffer_id_reg <= result_shadow_buffer_id_reg;
                                result_generation_reg <= result_shadow_generation_reg;
                                result_bbox_x_reg <= result_shadow_bbox_x_reg;
                                result_bbox_y_reg <= result_shadow_bbox_y_reg;
                                result_bbox_w_reg <= result_shadow_bbox_w_reg;
                                result_bbox_h_reg <= result_shadow_bbox_h_reg;
                                result_confidence_reg <= result_shadow_confidence_reg;
                                result_status_reg <= result_shadow_status_reg;
                                result_seq_reg <= result_seq_reg + 1'b1;
                                result_pending_reg <= 1'b1;
                                result_commit_pulse_reg <= 1'b1;
                                request_active_reg <= 1'b0;
                                irq_status_reg[3] <= 1'b1;
                            end else begin
                                 stale_result_reg <= 1'b1;
                                 err_sticky_reg <= 1'b1;
                                 err_code_reg <= {24'b0, ERR_STALE_RESULT};
                                 error_source_reg <= SOURCE_SCHEDULER;
                                 irq_status_reg[2] <= 1'b1;
                            end
                        end
                    end
                    6'h19: begin
                        if (axi_wstrb[0] && axi_wdata[0]) begin
                            request_pending_reg <= 1'b0;
                            request_ps_seen_reg <= 1'b1;
                        end
                        if (axi_wstrb[0]) irq_status_reg <= irq_status_reg & ~axi_wdata[3:0];
                    end
                    6'h1A: begin
                        irq_enable_reg <= apply_wstrb(
                            irq_enable_reg, axi_wdata, axi_wstrb);
                    end
                    6'h24: begin
                        if (axi_wstrb[0]) begin
                            if (axi_wdata[0])
                                profiler_clear_stats_reg <= 1'b1;
                            if (axi_wdata[1])
                                profiler_snapshot_stats_reg <= 1'b1;
                        end
                    end
                    6'h32: begin
                        if (axi_wstrb[0]) begin
                            if (axi_wdata[0])
                                recovery_clear_status_reg <= 1'b1;
                            if (axi_wdata[1])
                                recovery_software_trigger_reg <= 1'b1;
                        end
                    end
                    6'h39: begin
                        if (axi_wstrb[0]) begin
                            if (!ctrl_reg[0]) begin
                                video_source_select_reg <= axi_wdata[0];
                            end else if (axi_wdata[0] != video_source_select_reg) begin
                                video_switch_rejects_reg <= video_switch_rejects_reg + 1'b1;
                            end
                        end
                    end
                    default: begin
                    end
                endcase
            end
            if (axi_bvalid && S_AXI_BREADY) axi_bvalid <= 1'b0;

            if (read_fire) begin
                axi_rdata <= read_data(S_AXI_ARADDR);
                axi_rvalid <= 1'b1;
                axi_rresp <= 2'b00;
            end else if (axi_rvalid && S_AXI_RREADY) begin
                axi_rvalid <= 1'b0;
            end

            if (clear_error_reg) begin
                err_sticky_reg <= 1'b0;
                stale_result_reg <= 1'b0;
                buffer_conflict_reg <= 1'b0;
                err_code_reg <= 32'b0;
                error_source_reg <= SOURCE_NONE;
                video_pc_error_sticky_reg <= 1'b0;
                irq_status_reg[2] <= 1'b0;
                frame_done_seen_reg <= 1'b0;
            end

            if (frame_done_pulse) begin
                frame_done_seen_reg <= 1'b1;
                irq_status_reg[1] <= 1'b1;
            end

            // An acknowledgement applies to the previously active result.
            // A successful commit later in this cycle takes priority.
            if (result_ack && !result_commit_write) begin
                result_pending_reg <= 1'b0;
                irq_status_reg[3] <= 1'b0;
            end

            if (request_commit) begin
                if (request_pending_reg) begin
                    buffer_conflict_reg <= 1'b1;
                    err_sticky_reg <= 1'b1;
                    err_code_reg <= {24'b0, ERR_REQUEST_OVERWRITE};
                    error_source_reg <= SOURCE_SCHEDULER;
                    irq_status_reg[2] <= 1'b1;
                end
                request_frame_id_reg <= request_frame_id_in;
                request_buffer_id_reg <= request_buffer_id_in;
                request_generation_reg <= request_generation_in;
                request_reason_reg <= request_reason_in;
                request_timestamp_reg <= request_timestamp_in;
                request_seq_reg <= request_seq_reg + 1'b1;
                request_pending_reg <= 1'b1;
                request_ps_seen_reg <= 1'b0;
                request_active_reg <= 1'b1;
                irq_status_reg[0] <= 1'b1;
            end

            if (request_cancel) begin
                request_pending_reg <= 1'b0;
                request_ps_seen_reg <= 1'b1;
                request_active_reg <= 1'b0;
                irq_status_reg[0] <= 1'b0;
            end

            if (video_pc_error) begin
                video_pc_error_sticky_reg <= 1'b1;
                err_sticky_reg <= 1'b1;
                err_code_reg <= video_pc_error_code;
                error_source_reg <= SOURCE_PC_VIDEO;
                irq_status_reg[2] <= 1'b1;
            end else if (adapter_datamover_error_event) begin
                err_sticky_reg <= 1'b1;
                err_code_reg <= {24'b0, ERR_DATAMOVER};
                error_source_reg <= SOURCE_DATAMOVER;
                irq_status_reg[2] <= 1'b1;
            end else if (adapter_protocol_error_event) begin
                err_sticky_reg <= 1'b1;
                err_code_reg <= {24'b0, ERR_PROTOCOL};
                error_source_reg <= SOURCE_PROTOCOL;
                irq_status_reg[2] <= 1'b1;
            end else if (scheduler_buffer_conflict_event) begin
                err_sticky_reg <= 1'b1;
                err_code_reg <= {24'b0, ERR_SCHEDULER};
                error_source_reg <= SOURCE_SCHEDULER;
                irq_status_reg[2] <= 1'b1;
            end else if (err || fifo_ovf) begin
                err_sticky_reg <= 1'b1;
                err_code_reg <= (err_code_in != 0) ? err_code_in : {24'b0, ERR_EXTERNAL};
                error_source_reg <= SOURCE_EXTERNAL;
                irq_status_reg[2] <= 1'b1;
            end
        end
    end

endmodule
