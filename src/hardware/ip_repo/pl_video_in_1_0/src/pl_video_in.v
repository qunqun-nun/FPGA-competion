`timescale 1 ns / 1 ps

module pl_video_in #(
    parameter integer IMAGE_WIDTH  = 640,
    parameter integer IMAGE_HEIGHT = 480
)(
    input  wire        video_aclk,
    input  wire        video_aresetn,

    input  wire        enable,
    input  wire        soft_reset,
    input  wire        clear_error,

    input  wire [7:0]  s_axis_tdata,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire        s_axis_tuser,
    input  wire        s_axis_tlast,

    output wire [7:0]  m_axis_tdata,
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire        m_axis_tuser,
    output wire        m_axis_tlast,

    output wire        lock,
    output wire        busy,
    output wire        frame_done_pulse,
    output wire        err,
    output wire [31:0] err_code,
    output wire [31:0] frame_cnt
);

    localparam [1:0] WAIT_SOF      = 2'd0;
    localparam [1:0] RECEIVE_FRAME = 2'd1;
    localparam [1:0] DROP_FRAME    = 2'd2;

    localparam [31:0] VIDEO_ERR_NONE           = 32'h0000_0000;
    localparam [31:0] VIDEO_ERR_NO_SOF         = 32'h0000_0101;
    localparam [31:0] VIDEO_ERR_UNEXPECTED_SOF = 32'h0000_0102;
    localparam [31:0] VIDEO_ERR_EARLY_TLAST    = 32'h0000_0103;
    localparam [31:0] VIDEO_ERR_MISSING_TLAST  = 32'h0000_0104;
    localparam [31:0] VIDEO_ERR_TOO_MANY_LINES = 32'h0000_0105;

    reg [1:0] state;
    reg [15:0] pixel_count;
    reg [15:0] line_count;
    reg        wait_after_frame;

    // A one-beat elastic register decouples input and output backpressure.
    reg [7:0]  out_data;
    reg        out_valid;
    reg        out_user;
    reg        out_last;
    reg        out_frame_last;

    reg        lock_reg;
    reg        frame_done_reg;
    reg        err_reg;
    reg [31:0] err_code_reg;
    reg [31:0] frame_cnt_reg;

    wire output_slot_available;
    wire s_transfer;
    wire m_transfer;

    assign m_axis_tdata  = out_data;
    assign m_axis_tvalid = enable && out_valid;
    assign m_axis_tuser  = out_user;
    assign m_axis_tlast  = out_last;

    assign output_slot_available = !out_valid || m_axis_tready;
    assign s_axis_tready = video_aresetn && enable && !soft_reset &&
                           ((state == DROP_FRAME) || output_slot_available);

    assign s_transfer = s_axis_tvalid && s_axis_tready;
    assign m_transfer = m_axis_tvalid && m_axis_tready;

    assign lock             = lock_reg;
    assign busy             = enable && ((state != WAIT_SOF) || out_valid);
    assign frame_done_pulse = frame_done_reg;
    assign err              = err_reg;
    assign err_code         = err_code_reg;
    assign frame_cnt        = frame_cnt_reg;

    always @(posedge video_aclk or negedge video_aresetn) begin
        if (!video_aresetn) begin
            state             <= WAIT_SOF;
            pixel_count       <= 16'd0;
            line_count        <= 16'd0;
            wait_after_frame  <= 1'b0;
            out_data          <= 8'd0;
            out_valid         <= 1'b0;
            out_user          <= 1'b0;
            out_last          <= 1'b0;
            out_frame_last    <= 1'b0;
            lock_reg          <= 1'b0;
            frame_done_reg    <= 1'b0;
            err_reg           <= 1'b0;
            err_code_reg      <= VIDEO_ERR_NONE;
            frame_cnt_reg     <= 32'd0;
        end else begin
            frame_done_reg <= 1'b0;
            err_reg        <= 1'b0;

            if (clear_error)
                err_code_reg <= VIDEO_ERR_NONE;

            if (!enable) begin
                state            <= WAIT_SOF;
                pixel_count      <= 16'd0;
                line_count       <= 16'd0;
                wait_after_frame <= 1'b0;
                out_valid        <= 1'b0;
                out_frame_last   <= 1'b0;
                lock_reg         <= 1'b0;
            end else if (soft_reset) begin
                state            <= WAIT_SOF;
                pixel_count      <= 16'd0;
                line_count       <= 16'd0;
                wait_after_frame <= 1'b0;
                out_valid        <= 1'b0;
                out_frame_last   <= 1'b0;
                lock_reg         <= 1'b0;
            end else begin
                if (m_transfer) begin
                    out_valid <= 1'b0;
                    if (out_frame_last) begin
                        frame_done_reg <= 1'b1;
                        frame_cnt_reg  <= frame_cnt_reg + 1'b1;
                        lock_reg       <= 1'b1;
                    end
                end

                if (s_transfer) begin
                    case (state)
                        WAIT_SOF: begin
                            if (!s_axis_tuser) begin
                                err_reg           <= 1'b1;
                                err_code_reg      <= wait_after_frame ?
                                                     VIDEO_ERR_TOO_MANY_LINES :
                                                     VIDEO_ERR_NO_SOF;
                                state             <= DROP_FRAME;
                                pixel_count       <= 16'd0;
                                line_count        <= 16'd0;
                                wait_after_frame  <= 1'b0;
                                out_valid         <= 1'b0;
                                out_frame_last    <= 1'b0;
                                lock_reg          <= 1'b0;
                            end else if ((IMAGE_WIDTH == 1) != s_axis_tlast) begin
                                err_reg           <= 1'b1;
                                err_code_reg      <= s_axis_tlast ?
                                                     VIDEO_ERR_EARLY_TLAST :
                                                     VIDEO_ERR_MISSING_TLAST;
                                state             <= DROP_FRAME;
                                pixel_count       <= 16'd0;
                                line_count        <= 16'd0;
                                wait_after_frame  <= 1'b0;
                                out_valid         <= 1'b0;
                                out_frame_last    <= 1'b0;
                                lock_reg          <= 1'b0;
                            end else begin
                                out_data       <= s_axis_tdata;
                                out_valid      <= 1'b1;
                                out_user       <= 1'b1;
                                out_last       <= s_axis_tlast;
                                out_frame_last <= (IMAGE_WIDTH == 1) &&
                                                  (IMAGE_HEIGHT == 1);
                                wait_after_frame <= 1'b0;

                                if (IMAGE_WIDTH == 1) begin
                                    pixel_count <= 16'd0;
                                    if (IMAGE_HEIGHT == 1) begin
                                        line_count       <= 16'd0;
                                        state            <= WAIT_SOF;
                                        wait_after_frame <= 1'b1;
                                    end else begin
                                        line_count <= 16'd1;
                                        state      <= RECEIVE_FRAME;
                                    end
                                end else begin
                                    pixel_count <= 16'd1;
                                    line_count  <= 16'd0;
                                    state       <= RECEIVE_FRAME;
                                end
                            end
                        end

                        RECEIVE_FRAME: begin
                            if (s_axis_tuser) begin
                                err_reg          <= 1'b1;
                                err_code_reg     <= VIDEO_ERR_UNEXPECTED_SOF;
                                state            <= DROP_FRAME;
                                pixel_count      <= 16'd0;
                                line_count       <= 16'd0;
                                wait_after_frame <= 1'b0;
                                out_valid        <= 1'b0;
                                out_frame_last   <= 1'b0;
                                lock_reg         <= 1'b0;
                            end else if ((pixel_count == IMAGE_WIDTH - 1) !=
                                         s_axis_tlast) begin
                                err_reg       <= 1'b1;
                                err_code_reg  <= s_axis_tlast ?
                                                 VIDEO_ERR_EARLY_TLAST :
                                                 VIDEO_ERR_MISSING_TLAST;
                                state         <= DROP_FRAME;
                                pixel_count   <= 16'd0;
                                line_count    <= 16'd0;
                                wait_after_frame <= 1'b0;
                                out_valid     <= 1'b0;
                                out_frame_last <= 1'b0;
                                lock_reg      <= 1'b0;
                            end else begin
                                out_data       <= s_axis_tdata;
                                out_valid      <= 1'b1;
                                out_user       <= 1'b0;
                                out_last       <= s_axis_tlast;
                                out_frame_last <= (pixel_count == IMAGE_WIDTH - 1) &&
                                                  (line_count == IMAGE_HEIGHT - 1);

                                if (pixel_count == IMAGE_WIDTH - 1) begin
                                    pixel_count <= 16'd0;
                                    if (line_count == IMAGE_HEIGHT - 1) begin
                                        line_count       <= 16'd0;
                                        state            <= WAIT_SOF;
                                        wait_after_frame <= 1'b1;
                                    end else begin
                                        line_count <= line_count + 1'b1;
                                    end
                                end else begin
                                    pixel_count <= pixel_count + 1'b1;
                                end
                            end
                        end

                        DROP_FRAME: begin
                            // A new SOF is processed on this same beat, not discarded.
                            if (s_axis_tuser) begin
                                if ((IMAGE_WIDTH == 1) != s_axis_tlast) begin
                                    err_reg       <= 1'b1;
                                    err_code_reg  <= s_axis_tlast ?
                                                     VIDEO_ERR_EARLY_TLAST :
                                                     VIDEO_ERR_MISSING_TLAST;
                                    pixel_count   <= 16'd0;
                                    line_count    <= 16'd0;
                                    out_valid     <= 1'b0;
                                    out_frame_last <= 1'b0;
                                end else begin
                                    out_data       <= s_axis_tdata;
                                    out_valid      <= 1'b1;
                                    out_user       <= 1'b1;
                                    out_last       <= s_axis_tlast;
                                    out_frame_last <= (IMAGE_WIDTH == 1) &&
                                                      (IMAGE_HEIGHT == 1);
                                    wait_after_frame <= 1'b0;

                                    if (IMAGE_WIDTH == 1) begin
                                        pixel_count <= 16'd0;
                                        if (IMAGE_HEIGHT == 1) begin
                                            line_count       <= 16'd0;
                                            state            <= WAIT_SOF;
                                            wait_after_frame <= 1'b1;
                                        end else begin
                                            line_count <= 16'd1;
                                            state      <= RECEIVE_FRAME;
                                        end
                                    end else begin
                                        pixel_count <= 16'd1;
                                        line_count  <= 16'd0;
                                        state       <= RECEIVE_FRAME;
                                    end
                                end
                            end
                        end

                        default: begin
                            state            <= WAIT_SOF;
                            pixel_count      <= 16'd0;
                            line_count       <= 16'd0;
                            wait_after_frame <= 1'b0;
                            out_valid        <= 1'b0;
                            out_frame_last   <= 1'b0;
                            lock_reg         <= 1'b0;
                        end
                    endcase
                end
            end
        end
    end

endmodule
