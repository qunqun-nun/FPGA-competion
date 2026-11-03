`timescale 1ns/1ps

// Single-target short-term SAD tracker for a 640x480 GRAY8 AXI4-Stream.
//
// The tracker deliberately does not store a full video frame. It captures a
// 16x16 template after DPU initialization and, on following frames, captures
// only a 32x32 bounded search window around the previous target. The SAD search
// runs between frames while the upstream stream is backpressured. This keeps
// memory use small enough to coexist with the B4096 DPU and HDMI frame buffers.
module pl_sad_tracker #(
    parameter integer IMAGE_WIDTH        = 640,
    parameter integer IMAGE_HEIGHT       = 480,
    parameter integer TEMPLATE_SIZE      = 16,
    parameter integer SEARCH_RADIUS      = 8,
    parameter integer SAD_LOST_THRESHOLD = 12000
) (
    input  logic        aclk,
    input  logic        aresetn,
    input  logic        enable,
    input  logic        soft_reset,

    input  logic [7:0]  s_axis_tdata,
    input  logic        s_axis_tvalid,
    output logic        s_axis_tready,
    input  logic        s_axis_tuser,
    input  logic        s_axis_tlast,
    input  logic [31:0] s_frame_id,

    output logic [7:0]  m_axis_tdata,
    output logic        m_axis_tvalid,
    input  logic        m_axis_tready,
    output logic        m_axis_tuser,
    output logic        m_axis_tlast,

    input  logic        init_valid,
    output logic        init_ready,
    input  logic [15:0] init_x,
    input  logic [15:0] init_y,
    input  logic [15:0] init_w,
    input  logic [15:0] init_h,

    output logic        track_result_valid,
    output logic        track_active,
    output logic        track_lost_pulse,
    output logic [31:0] track_frame_id,
    output logic [15:0] track_x,
    output logic [15:0] track_y,
    output logic [15:0] track_w,
    output logic [15:0] track_h,
    output logic [31:0] track_sad,
    output logic [15:0] track_confidence,
    output logic [31:0] tracked_frames,
    output logic [31:0] lost_events,
    output logic        processing_busy
);
    localparam integer TEMPLATE_PIXELS = TEMPLATE_SIZE * TEMPLATE_SIZE;
    localparam integer WINDOW_SIZE = TEMPLATE_SIZE + (2 * SEARCH_RADIUS);
    localparam integer WINDOW_PIXELS = WINDOW_SIZE * WINDOW_SIZE;
    localparam integer TEMPLATE_INDEX_WIDTH = $clog2(TEMPLATE_PIXELS);

    typedef enum logic [1:0] {
        ST_CAPTURE,
        ST_SEARCH,
        ST_UPDATE_TEMPLATE,
        ST_REPORT
    } state_t;

    state_t state;

    (* ram_style = "distributed" *) logic [7:0] template_mem [0:TEMPLATE_PIXELS-1];
    (* ram_style = "distributed" *) logic [7:0] search_mem [0:WINDOW_PIXELS-1];

    logic [15:0] stream_x, stream_y;
    logic [31:0] captured_frame_id;
    logic capture_init_mode, capture_track_mode;
    logic [15:0] capture_template_x, capture_template_y;
    logic [15:0] capture_window_x, capture_window_y;

    logic init_pending;
    logic [15:0] init_x_q, init_y_q, init_w_q, init_h_q;
    logic [15:0] active_x, active_y, active_w, active_h;

    integer candidate_dx_index;
    integer candidate_dy_index;
    logic [TEMPLATE_INDEX_WIDTH-1:0] search_index;
    logic [31:0] sad_accum;
    logic [31:0] best_score;
    logic [15:0] best_x, best_y;
    integer best_dx_index, best_dy_index;
    logic [TEMPLATE_INDEX_WIDTH-1:0] update_index;
    integer update_dx_index, update_dy_index;

    logic [31:0] report_frame_id_q;
    logic [15:0] report_x_q, report_y_q, report_w_q, report_h_q;
    logic [31:0] report_sad_q;
    logic [15:0] report_conf_q;
    logic report_lost_q;

    wire stream_enabled = enable && !soft_reset && (state == ST_CAPTURE);
    wire stream_transfer = s_axis_tvalid && s_axis_tready;
    wire [15:0] pixel_x_now = s_axis_tuser ? 16'd0 : stream_x;
    wire [15:0] pixel_y_now = s_axis_tuser ? 16'd0 : stream_y;
    wire frame_last_transfer = stream_transfer &&
                               (pixel_x_now == IMAGE_WIDTH-1) &&
                               (pixel_y_now == IMAGE_HEIGHT-1);
    wire init_mode_now = s_axis_tuser ? init_pending : capture_init_mode;
    wire track_mode_now = s_axis_tuser ? (!init_pending && track_active) :
                                         capture_track_mode;

    function automatic [15:0] nonzero_width(input logic [15:0] value);
        nonzero_width = (value == 0) ? 16'd1 : value;
    endfunction

    function automatic [15:0] clip_box_x(
        input integer value,
        input logic [15:0] width
    );
        integer max_value;
        begin
            max_value = IMAGE_WIDTH - nonzero_width(width);
            if (max_value < 0) max_value = 0;
            if (value < 0) clip_box_x = 0;
            else if (value > max_value) clip_box_x = max_value[15:0];
            else clip_box_x = value[15:0];
        end
    endfunction

    function automatic [15:0] clip_box_y(
        input integer value,
        input logic [15:0] height
    );
        integer max_value;
        begin
            max_value = IMAGE_HEIGHT - nonzero_width(height);
            if (max_value < 0) max_value = 0;
            if (value < 0) clip_box_y = 0;
            else if (value > max_value) clip_box_y = max_value[15:0];
            else clip_box_y = value[15:0];
        end
    endfunction

    function automatic [15:0] template_x_from_box(
        input logic [15:0] box_x,
        input logic [15:0] box_w
    );
        integer value;
        begin
            value = box_x + (nonzero_width(box_w) / 2) - (TEMPLATE_SIZE / 2);
            if (value < 0) template_x_from_box = 0;
            else if (value > IMAGE_WIDTH-TEMPLATE_SIZE)
                template_x_from_box = IMAGE_WIDTH-TEMPLATE_SIZE;
            else template_x_from_box = value[15:0];
        end
    endfunction

    function automatic [15:0] template_y_from_box(
        input logic [15:0] box_y,
        input logic [15:0] box_h
    );
        integer value;
        begin
            value = box_y + (nonzero_width(box_h) / 2) - (TEMPLATE_SIZE / 2);
            if (value < 0) template_y_from_box = 0;
            else if (value > IMAGE_HEIGHT-TEMPLATE_SIZE)
                template_y_from_box = IMAGE_HEIGHT-TEMPLATE_SIZE;
            else template_y_from_box = value[15:0];
        end
    endfunction

    function automatic [15:0] window_x_from_box(
        input logic [15:0] box_x,
        input logic [15:0] box_w
    );
        integer value;
        integer max_value;
        begin
            value = template_x_from_box(box_x, box_w) - SEARCH_RADIUS;
            max_value = IMAGE_WIDTH - WINDOW_SIZE;
            if (max_value < 0) max_value = 0;
            if (value < 0) window_x_from_box = 0;
            else if (value > max_value) window_x_from_box = max_value[15:0];
            else window_x_from_box = value[15:0];
        end
    endfunction

    function automatic [15:0] window_y_from_box(
        input logic [15:0] box_y,
        input logic [15:0] box_h
    );
        integer value;
        integer max_value;
        begin
            value = template_y_from_box(box_y, box_h) - SEARCH_RADIUS;
            max_value = IMAGE_HEIGHT - WINDOW_SIZE;
            if (max_value < 0) max_value = 0;
            if (value < 0) window_y_from_box = 0;
            else if (value > max_value) window_y_from_box = max_value[15:0];
            else window_y_from_box = value[15:0];
        end
    endfunction

    function automatic [15:0] box_x_from_template(
        input integer template_x,
        input logic [15:0] box_w
    );
        integer value;
        begin
            value = template_x - (nonzero_width(box_w) / 2) +
                    (TEMPLATE_SIZE / 2);
            box_x_from_template = clip_box_x(value, box_w);
        end
    endfunction

    function automatic [15:0] box_y_from_template(
        input integer template_y,
        input logic [15:0] box_h
    );
        integer value;
        begin
            value = template_y - (nonzero_width(box_h) / 2) +
                    (TEMPLATE_SIZE / 2);
            box_y_from_template = clip_box_y(value, box_h);
        end
    endfunction

    assign processing_busy = state != ST_CAPTURE;
    assign init_ready = !init_pending;
    assign m_axis_tdata  = s_axis_tdata;
    assign m_axis_tvalid = s_axis_tvalid && stream_enabled;
    assign m_axis_tuser  = s_axis_tuser;
    assign m_axis_tlast  = s_axis_tlast;
    assign s_axis_tready = stream_enabled && m_axis_tready;

    always_ff @(posedge aclk) begin : tracker_control
        integer pixel_x_i;
        integer pixel_y_i;
        integer template_origin_x_i;
        integer template_origin_y_i;
        integer window_origin_x_i;
        integer window_origin_y_i;
        integer memory_index_i;
        integer template_col_i;
        integer template_row_i;
        integer search_col_i;
        integer search_row_i;
        integer search_address_i;
        integer candidate_template_x_i;
        integer candidate_template_y_i;
        logic [7:0] search_pixel_i;
        logic [7:0] template_pixel_i;
        logic [8:0] abs_diff_i;
        logic [31:0] candidate_total_i;
        logic [31:0] chosen_score_i;
        logic [15:0] chosen_x_i;
        logic [15:0] chosen_y_i;
        integer chosen_dx_i;
        integer chosen_dy_i;

        if (!aresetn || soft_reset) begin
            state                 <= ST_CAPTURE;
            stream_x              <= 16'd0;
            stream_y              <= 16'd0;
            captured_frame_id     <= 32'd0;
            capture_init_mode     <= 1'b0;
            capture_track_mode    <= 1'b0;
            capture_template_x    <= 16'd0;
            capture_template_y    <= 16'd0;
            capture_window_x      <= 16'd0;
            capture_window_y      <= 16'd0;
            init_pending          <= 1'b0;
            init_x_q              <= 16'd0;
            init_y_q              <= 16'd0;
            init_w_q              <= 16'd1;
            init_h_q              <= 16'd1;
            active_x              <= 16'd0;
            active_y              <= 16'd0;
            active_w              <= 16'd1;
            active_h              <= 16'd1;
            candidate_dx_index    <= 0;
            candidate_dy_index    <= 0;
            search_index          <= '0;
            sad_accum             <= 32'd0;
            best_score            <= 32'hffff_ffff;
            best_x                <= 16'd0;
            best_y                <= 16'd0;
            best_dx_index         <= 0;
            best_dy_index         <= 0;
            update_index          <= '0;
            update_dx_index       <= 0;
            update_dy_index       <= 0;
            report_frame_id_q     <= 32'd0;
            report_x_q            <= 16'd0;
            report_y_q            <= 16'd0;
            report_w_q            <= 16'd0;
            report_h_q            <= 16'd0;
            report_sad_q          <= 32'd0;
            report_conf_q         <= 16'd0;
            report_lost_q         <= 1'b0;
            track_result_valid    <= 1'b0;
            track_active          <= 1'b0;
            track_lost_pulse      <= 1'b0;
            track_frame_id        <= 32'd0;
            track_x               <= 16'd0;
            track_y               <= 16'd0;
            track_w               <= 16'd0;
            track_h               <= 16'd0;
            track_sad             <= 32'd0;
            track_confidence      <= 16'd0;
            tracked_frames        <= 32'd0;
            lost_events           <= 32'd0;
        end else begin
            track_result_valid <= 1'b0;
            track_lost_pulse <= 1'b0;

            if (init_valid && init_ready) begin
                init_pending <= 1'b1;
                init_x_q <= init_x;
                init_y_q <= init_y;
                init_w_q <= nonzero_width(init_w);
                init_h_q <= nonzero_width(init_h);
            end

            if (!enable) begin
                state <= ST_CAPTURE;
                stream_x <= 16'd0;
                stream_y <= 16'd0;
                capture_init_mode <= 1'b0;
                capture_track_mode <= 1'b0;
                track_active <= 1'b0;
            end else begin
                case (state)
                    ST_CAPTURE: begin
                        if (stream_transfer) begin
                            pixel_x_i = pixel_x_now;
                            pixel_y_i = pixel_y_now;

                            if (s_axis_tuser) begin
                                stream_x <= 16'd0;
                                stream_y <= 16'd0;
                                captured_frame_id <= s_frame_id;
                                capture_init_mode <= init_pending;
                                capture_track_mode <= !init_pending && track_active;
                                capture_template_x <= template_x_from_box(init_x_q, init_w_q);
                                capture_template_y <= template_y_from_box(init_y_q, init_h_q);
                                capture_window_x <= window_x_from_box(active_x, active_w);
                                capture_window_y <= window_y_from_box(active_y, active_h);
                            end

                            template_origin_x_i = s_axis_tuser ?
                                template_x_from_box(init_x_q, init_w_q) :
                                capture_template_x;
                            template_origin_y_i = s_axis_tuser ?
                                template_y_from_box(init_y_q, init_h_q) :
                                capture_template_y;
                            window_origin_x_i = s_axis_tuser ?
                                window_x_from_box(active_x, active_w) :
                                capture_window_x;
                            window_origin_y_i = s_axis_tuser ?
                                window_y_from_box(active_y, active_h) :
                                capture_window_y;

                            if (init_mode_now &&
                                pixel_x_i >= template_origin_x_i &&
                                pixel_x_i < template_origin_x_i + TEMPLATE_SIZE &&
                                pixel_y_i >= template_origin_y_i &&
                                pixel_y_i < template_origin_y_i + TEMPLATE_SIZE) begin
                                memory_index_i =
                                    (pixel_y_i-template_origin_y_i)*TEMPLATE_SIZE +
                                    (pixel_x_i-template_origin_x_i);
                                template_mem[memory_index_i] <= s_axis_tdata;
                            end

                            if (track_mode_now &&
                                pixel_x_i >= window_origin_x_i &&
                                pixel_x_i < window_origin_x_i + WINDOW_SIZE &&
                                pixel_y_i >= window_origin_y_i &&
                                pixel_y_i < window_origin_y_i + WINDOW_SIZE) begin
                                memory_index_i =
                                    (pixel_y_i-window_origin_y_i)*WINDOW_SIZE +
                                    (pixel_x_i-window_origin_x_i);
                                search_mem[memory_index_i] <= s_axis_tdata;
                            end

                            if (s_axis_tlast) begin
                                stream_x <= 16'd0;
                                if (pixel_y_i == IMAGE_HEIGHT-1)
                                    stream_y <= 16'd0;
                                else
                                    stream_y <= pixel_y_i + 1'b1;
                            end else begin
                                stream_x <= pixel_x_i + 1'b1;
                            end

                            if (frame_last_transfer) begin
                                stream_x <= 16'd0;
                                stream_y <= 16'd0;
                                if (init_mode_now) begin
                                    active_x <= clip_box_x(init_x_q, init_w_q);
                                    active_y <= clip_box_y(init_y_q, init_h_q);
                                    active_w <= (init_w_q > IMAGE_WIDTH) ? IMAGE_WIDTH : init_w_q;
                                    active_h <= (init_h_q > IMAGE_HEIGHT) ? IMAGE_HEIGHT : init_h_q;
                                    init_pending <= 1'b0;
                                    track_active <= 1'b1;
                                    report_frame_id_q <= captured_frame_id;
                                    report_x_q <= clip_box_x(init_x_q, init_w_q);
                                    report_y_q <= clip_box_y(init_y_q, init_h_q);
                                    report_w_q <= (init_w_q > IMAGE_WIDTH) ? IMAGE_WIDTH : init_w_q;
                                    report_h_q <= (init_h_q > IMAGE_HEIGHT) ? IMAGE_HEIGHT : init_h_q;
                                    report_sad_q <= 32'd0;
                                    report_conf_q <= 16'hffff;
                                    report_lost_q <= 1'b0;
                                    state <= ST_REPORT;
                                end else if (track_mode_now) begin
                                    candidate_dx_index <= 0;
                                    candidate_dy_index <= 0;
                                    search_index <= '0;
                                    sad_accum <= 32'd0;
                                    best_score <= 32'hffff_ffff;
                                    best_x <= active_x;
                                    best_y <= active_y;
                                    best_dx_index <= 0;
                                    best_dy_index <= 0;
                                    state <= ST_SEARCH;
                                end
                            end
                        end
                    end

                    ST_SEARCH: begin
                        template_col_i = search_index % TEMPLATE_SIZE;
                        template_row_i = search_index / TEMPLATE_SIZE;
                        search_col_i = candidate_dx_index + template_col_i;
                        search_row_i = candidate_dy_index + template_row_i;
                        search_address_i = search_row_i*WINDOW_SIZE + search_col_i;
                        search_pixel_i = search_mem[search_address_i];
                        template_pixel_i = template_mem[search_index];
                        abs_diff_i = (search_pixel_i >= template_pixel_i) ?
                                     (search_pixel_i-template_pixel_i) :
                                     (template_pixel_i-search_pixel_i);
                        candidate_total_i = sad_accum + abs_diff_i;

                        if (search_index == TEMPLATE_PIXELS-1) begin
                            candidate_template_x_i = capture_window_x + candidate_dx_index;
                            candidate_template_y_i = capture_window_y + candidate_dy_index;
                            chosen_x_i = box_x_from_template(candidate_template_x_i, active_w);
                            chosen_y_i = box_y_from_template(candidate_template_y_i, active_h);

                            if (candidate_total_i < best_score) begin
                                best_score <= candidate_total_i;
                                best_x <= chosen_x_i;
                                best_y <= chosen_y_i;
                                best_dx_index <= candidate_dx_index;
                                best_dy_index <= candidate_dy_index;
                            end

                            if ((candidate_dx_index == 2*SEARCH_RADIUS) &&
                                (candidate_dy_index == 2*SEARCH_RADIUS)) begin
                                chosen_score_i = (candidate_total_i < best_score) ?
                                                 candidate_total_i : best_score;
                                chosen_x_i = (candidate_total_i < best_score) ?
                                             chosen_x_i : best_x;
                                chosen_y_i = (candidate_total_i < best_score) ?
                                             chosen_y_i : best_y;
                                chosen_dx_i = (candidate_total_i < best_score) ?
                                              candidate_dx_index : best_dx_index;
                                chosen_dy_i = (candidate_total_i < best_score) ?
                                              candidate_dy_index : best_dy_index;

                                report_frame_id_q <= captured_frame_id;
                                report_x_q <= chosen_x_i;
                                report_y_q <= chosen_y_i;
                                report_w_q <= active_w;
                                report_h_q <= active_h;
                                report_sad_q <= chosen_score_i;
                                report_conf_q <= (chosen_score_i >= 16'hffff) ?
                                                 16'd0 : 16'hffff-chosen_score_i[15:0];
                                report_lost_q <= chosen_score_i > SAD_LOST_THRESHOLD;

                                if (chosen_score_i > SAD_LOST_THRESHOLD) begin
                                    track_active <= 1'b0;
                                    state <= ST_REPORT;
                                end else begin
                                    active_x <= chosen_x_i;
                                    active_y <= chosen_y_i;
                                    update_index <= '0;
                                    update_dx_index <= chosen_dx_i;
                                    update_dy_index <= chosen_dy_i;
                                    state <= ST_UPDATE_TEMPLATE;
                                end
                            end else begin
                                if (candidate_dx_index == 2*SEARCH_RADIUS) begin
                                    candidate_dx_index <= 0;
                                    candidate_dy_index <= candidate_dy_index + 1;
                                end else begin
                                    candidate_dx_index <= candidate_dx_index + 1;
                                end
                                search_index <= '0;
                                sad_accum <= 32'd0;
                            end
                        end else begin
                            search_index <= search_index + 1'b1;
                            sad_accum <= candidate_total_i;
                        end
                    end

                    ST_UPDATE_TEMPLATE: begin
                        template_col_i = update_index % TEMPLATE_SIZE;
                        template_row_i = update_index / TEMPLATE_SIZE;
                        search_address_i =
                            (update_dy_index+template_row_i)*WINDOW_SIZE +
                            update_dx_index+template_col_i;
                        template_mem[update_index] <= search_mem[search_address_i];
                        if (update_index == TEMPLATE_PIXELS-1)
                            state <= ST_REPORT;
                        else
                            update_index <= update_index + 1'b1;
                    end

                    ST_REPORT: begin
                        track_result_valid <= 1'b1;
                        track_lost_pulse <= report_lost_q;
                        track_frame_id <= report_frame_id_q;
                        track_x <= report_x_q;
                        track_y <= report_y_q;
                        track_w <= report_w_q;
                        track_h <= report_h_q;
                        track_sad <= report_sad_q;
                        track_confidence <= report_conf_q;
                        if (report_lost_q)
                            lost_events <= lost_events + 1'b1;
                        else
                            tracked_frames <= tracked_frames + 1'b1;
                        state <= ST_CAPTURE;
                    end

                    default: state <= ST_CAPTURE;
                endcase
            end
        end
    end

    initial begin
        if (TEMPLATE_SIZE < 2 || TEMPLATE_SIZE > IMAGE_WIDTH ||
            TEMPLATE_SIZE > IMAGE_HEIGHT)
            $error("Invalid TEMPLATE_SIZE");
        if (WINDOW_SIZE > IMAGE_WIDTH || WINDOW_SIZE > IMAGE_HEIGHT)
            $error("Search window exceeds image dimensions");
    end
endmodule
