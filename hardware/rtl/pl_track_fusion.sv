`timescale 1ns/1ps

// Detection -> template initialization -> short-term tracking -> periodic or
// confidence-driven re-detection controller. Delayed DPU results are compared
// against a small Frame-ID history before bounded correction is applied to the
// current track; stale coordinates are never drawn directly on a new frame.
module pl_track_fusion #(
    parameter integer IMAGE_WIDTH = 640,
    parameter integer IMAGE_HEIGHT = 480,
    parameter integer HISTORY_DEPTH = 16,
    parameter integer REDETECT_PERIOD = 15,
    parameter integer MIN_TRACK_CONFIDENCE = 16'h6000,
    parameter integer MIN_DETECT_CONFIDENCE = 16'h4000,
    parameter integer MAX_CORRECTION = 32
) (
    input  logic        aclk,
    input  logic        aresetn,
    input  logic        enable,
    input  logic        soft_reset,
    input  logic [31:0] current_frame_id,

    input  logic        result_commit_pulse,
    input  logic [31:0] result_frame_id,
    input  logic [15:0] result_bbox_x,
    input  logic [15:0] result_bbox_y,
    input  logic [15:0] result_bbox_w,
    input  logic [15:0] result_bbox_h,
    input  logic [15:0] result_confidence,
    input  logic [7:0]  result_status,
    output logic        result_ack,

    input  logic        tracker_result_valid,
    input  logic        tracker_lost_pulse,
    input  logic [31:0] tracker_frame_id,
    input  logic [15:0] tracker_x,
    input  logic [15:0] tracker_y,
    input  logic [15:0] tracker_w,
    input  logic [15:0] tracker_h,
    input  logic [15:0] tracker_confidence,

    output logic        tracker_init_valid,
    input  logic        tracker_init_ready,
    output logic [15:0] tracker_init_x,
    output logic [15:0] tracker_init_y,
    output logic [15:0] tracker_init_w,
    output logic [15:0] tracker_init_h,

    output logic        dpu_request_enable,
    output logic [7:0]  dpu_request_reason,

    output logic        box_update_valid,
    input  logic        box_update_ready,
    output logic [31:0] box_frame_id,
    output logic [3:0]  box_count,
    output logic [95:0] box_x_flat,
    output logic [95:0] box_y_flat,
    output logic [95:0] box_w_flat,
    output logic [95:0] box_h_flat,
    output logic [191:0] box_color_flat,

    output logic [2:0]  fusion_state,
    output logic [31:0] redetect_requests,
    output logic [31:0] stale_history_results,
    output logic [31:0] lost_count
);
    localparam logic [2:0] WAIT_TARGET   = 3'd0;
    localparam logic [2:0] INIT_TEMPLATE = 3'd1;
    localparam logic [2:0] PL_TRACK      = 3'd2;
    localparam logic [2:0] REDETECT      = 3'd3;
    localparam logic [2:0] LOST          = 3'd4;
    localparam integer HISTORY_BITS = (HISTORY_DEPTH <= 1) ? 1 : $clog2(HISTORY_DEPTH);

    logic [31:0] hist_frame [0:HISTORY_DEPTH-1];
    logic [15:0] hist_x [0:HISTORY_DEPTH-1];
    logic [15:0] hist_y [0:HISTORY_DEPTH-1];
    logic hist_valid [0:HISTORY_DEPTH-1];

    logic [15:0] current_x, current_y, current_w, current_h;
    logic [31:0] frames_since_detect;
    integer i;

    function automatic [15:0] clip_x(
        input integer value,
        input logic [15:0] width
    );
        integer max_value;
        begin
            max_value = IMAGE_WIDTH - ((width == 0) ? 1 : width);
            if (max_value < 0) max_value = 0;
            if (value < 0) clip_x = 0;
            else if (value > max_value) clip_x = max_value[15:0];
            else clip_x = value[15:0];
        end
    endfunction

    function automatic [15:0] clip_y(
        input integer value,
        input logic [15:0] height
    );
        integer max_value;
        begin
            max_value = IMAGE_HEIGHT - ((height == 0) ? 1 : height);
            if (max_value < 0) max_value = 0;
            if (value < 0) clip_y = 0;
            else if (value > max_value) clip_y = max_value[15:0];
            else clip_y = value[15:0];
        end
    endfunction

    function automatic integer clamp_delta(input integer value);
        if (value > MAX_CORRECTION) clamp_delta = MAX_CORRECTION;
        else if (value < -MAX_CORRECTION) clamp_delta = -MAX_CORRECTION;
        else clamp_delta = value;
    endfunction

    always_comb begin
        dpu_request_enable = enable &&
            ((fusion_state == WAIT_TARGET) ||
             (fusion_state == REDETECT) ||
             (fusion_state == LOST));
        case (fusion_state)
            WAIT_TARGET: dpu_request_reason = 8'h01;
            REDETECT:    dpu_request_reason = 8'h02;
            LOST:        dpu_request_reason = 8'h04;
            default:     dpu_request_reason = 8'h00;
        endcase
    end

    always_ff @(posedge aclk) begin : fusion_control
        integer history_index;
        integer dx;
        integer dy;
        integer corrected_x;
        integer corrected_y;
        logic history_hit;
        logic [15:0] selected_w;
        logic [15:0] selected_h;
        logic [15:0] clipped_x;
        logic [15:0] clipped_y;

        if (!aresetn || soft_reset) begin
            fusion_state          <= WAIT_TARGET;
            result_ack            <= 1'b0;
            tracker_init_valid    <= 1'b0;
            tracker_init_x        <= 16'd0;
            tracker_init_y        <= 16'd0;
            tracker_init_w        <= 16'd1;
            tracker_init_h        <= 16'd1;
            box_update_valid      <= 1'b0;
            box_frame_id          <= 32'd0;
            box_count             <= 4'd0;
            box_x_flat            <= '0;
            box_y_flat            <= '0;
            box_w_flat            <= '0;
            box_h_flat            <= '0;
            box_color_flat        <= '0;
            current_x             <= 16'd0;
            current_y             <= 16'd0;
            current_w             <= 16'd1;
            current_h             <= 16'd1;
            frames_since_detect   <= 32'd0;
            redetect_requests     <= 32'd0;
            stale_history_results <= 32'd0;
            lost_count            <= 32'd0;
            for (i = 0; i < HISTORY_DEPTH; i = i + 1) begin
                hist_valid[i] <= 1'b0;
                hist_frame[i] <= 32'd0;
                hist_x[i] <= 16'd0;
                hist_y[i] <= 16'd0;
            end
        end else begin
            result_ack <= result_commit_pulse;

            if (tracker_init_valid && tracker_init_ready)
                tracker_init_valid <= 1'b0;
            if (box_update_valid && box_update_ready)
                box_update_valid <= 1'b0;

            if (!enable) begin
                fusion_state <= WAIT_TARGET;
                tracker_init_valid <= 1'b0;
                box_update_valid <= 1'b0;
                frames_since_detect <= 32'd0;
            end else begin
                if (tracker_result_valid) begin
                    if (tracker_lost_pulse) begin
                        fusion_state <= LOST;
                        lost_count <= lost_count + 1'b1;
                        box_update_valid <= 1'b1;
                        box_frame_id <= tracker_frame_id;
                        box_count <= 4'd0;
                    end else begin
                        current_x <= tracker_x;
                        current_y <= tracker_y;
                        current_w <= tracker_w;
                        current_h <= tracker_h;
                        history_index = tracker_frame_id[HISTORY_BITS-1:0];
                        hist_valid[history_index] <= 1'b1;
                        hist_frame[history_index] <= tracker_frame_id;
                        hist_x[history_index] <= tracker_x;
                        hist_y[history_index] <= tracker_y;

                        box_update_valid <= 1'b1;
                        box_frame_id <= tracker_frame_id;
                        box_count <= 4'd1;
                        box_x_flat <= '0;
                        box_y_flat <= '0;
                        box_w_flat <= '0;
                        box_h_flat <= '0;
                        box_color_flat <= '0;
                        box_x_flat[11:0] <= tracker_x[11:0];
                        box_y_flat[11:0] <= tracker_y[11:0];
                        box_w_flat[11:0] <= tracker_w[11:0];
                        box_h_flat[11:0] <= tracker_h[11:0];
                        box_color_flat[23:0] <= 24'h00ff00;

                        frames_since_detect <= frames_since_detect + 1'b1;
                        if (fusion_state == INIT_TEMPLATE)
                            fusion_state <= PL_TRACK;
                        if ((tracker_confidence < MIN_TRACK_CONFIDENCE) ||
                            (frames_since_detect + 1 >= REDETECT_PERIOD)) begin
                            if (fusion_state != REDETECT)
                                redetect_requests <= redetect_requests + 1'b1;
                            fusion_state <= REDETECT;
                        end
                    end
                end

                if (result_commit_pulse) begin
                    if ((result_status == 8'h01) &&
                        (result_confidence >= MIN_DETECT_CONFIDENCE)) begin
                        history_index = result_frame_id[HISTORY_BITS-1:0];
                        history_hit = hist_valid[history_index] &&
                                      (hist_frame[history_index] == result_frame_id);
                        selected_w = (result_bbox_w == 0) ? current_w : result_bbox_w;
                        selected_h = (result_bbox_h == 0) ? current_h : result_bbox_h;

                        // WAIT_TARGET and LOST have no active display target, so a
                        // valid detection may establish a new target directly.
                        if ((fusion_state == WAIT_TARGET) ||
                            (fusion_state == LOST)) begin
                            corrected_x = $signed({1'b0, result_bbox_x});
                            corrected_y = $signed({1'b0, result_bbox_y});

                            clipped_x = clip_x(corrected_x, selected_w);
                            clipped_y = clip_y(corrected_y, selected_h);
                            current_x <= clipped_x;
                            current_y <= clipped_y;
                            current_w <= selected_w;
                            current_h <= selected_h;
                            tracker_init_x <= clipped_x;
                            tracker_init_y <= clipped_y;
                            tracker_init_w <= selected_w;
                            tracker_init_h <= selected_h;
                            tracker_init_valid <= 1'b1;
                            frames_since_detect <= 32'd0;
                            fusion_state <= INIT_TEMPLATE;

                            box_update_valid <= 1'b1;
                            box_frame_id <= current_frame_id;
                            box_count <= 4'd1;
                            box_x_flat <= '0;
                            box_y_flat <= '0;
                            box_w_flat <= '0;
                            box_h_flat <= '0;
                            box_color_flat <= '0;
                            box_x_flat[11:0] <= clipped_x[11:0];
                            box_y_flat[11:0] <= clipped_y[11:0];
                            box_w_flat[11:0] <= selected_w[11:0];
                            box_h_flat[11:0] <= selected_h[11:0];
                            box_color_flat[23:0] <= 24'hff0000;
                        end else if (history_hit &&
                                     ((fusion_state == INIT_TEMPLATE) ||
                                      (fusion_state == PL_TRACK) ||
                                      (fusion_state == REDETECT))) begin
                            // Use signed arithmetic so a detection moving left or
                            // up produces a negative correction instead of wrapping.
                            dx = $signed({1'b0, result_bbox_x}) -
                                 $signed({1'b0, hist_x[history_index]});
                            dy = $signed({1'b0, result_bbox_y}) -
                                 $signed({1'b0, hist_y[history_index]});
                            corrected_x = $signed({1'b0, current_x}) + clamp_delta(dx);
                            corrected_y = $signed({1'b0, current_y}) + clamp_delta(dy);

                            clipped_x = clip_x(corrected_x, selected_w);
                            clipped_y = clip_y(corrected_y, selected_h);
                            current_x <= clipped_x;
                            current_y <= clipped_y;
                            current_w <= selected_w;
                            current_h <= selected_h;
                            tracker_init_x <= clipped_x;
                            tracker_init_y <= clipped_y;
                            tracker_init_w <= selected_w;
                            tracker_init_h <= selected_h;
                            tracker_init_valid <= 1'b1;
                            frames_since_detect <= 32'd0;
                            fusion_state <= INIT_TEMPLATE;

                            box_update_valid <= 1'b1;
                            box_frame_id <= current_frame_id;
                            box_count <= 4'd1;
                            box_x_flat <= '0;
                            box_y_flat <= '0;
                            box_w_flat <= '0;
                            box_h_flat <= '0;
                            box_color_flat <= '0;
                            box_x_flat[11:0] <= clipped_x[11:0];
                            box_y_flat[11:0] <= clipped_y[11:0];
                            box_w_flat[11:0] <= selected_w[11:0];
                            box_h_flat[11:0] <= selected_h[11:0];
                            box_color_flat[23:0] <= 24'hff0000;
                        end else begin
                            // An unmatched result must never replace an active
                            // track. It is acknowledged but counted as stale.
                            stale_history_results <= stale_history_results + 1'b1;
                        end
                    end else if ((fusion_state == WAIT_TARGET) ||
                                 (fusion_state == LOST)) begin
                        fusion_state <= WAIT_TARGET;
                    end
                end
            end
        end
    end

    initial begin
        if ((1 << HISTORY_BITS) != HISTORY_DEPTH)
            $error("HISTORY_DEPTH must be a power of two");
    end
endmodule
