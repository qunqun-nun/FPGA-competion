`timescale 1ns/1ps

module pl_pc_video_stream_formatter #(
    parameter integer IMAGE_WIDTH  = 640,
    parameter integer IMAGE_HEIGHT = 480
) (
    input  wire        aclk,
    input  wire        aresetn,
    input  wire        enable,
    input  wire        soft_reset,
    input  wire        clear_error,
    input  wire        source_select,

    input  wire [7:0]  s_dummy_tdata,
    input  wire        s_dummy_tvalid,
    output wire        s_dummy_tready,
    input  wire        s_dummy_tuser,
    input  wire        s_dummy_tlast,

    input  wire [7:0]  s_pc_tdata,
    input  wire        s_pc_tvalid,
    output wire        s_pc_tready,
    input  wire        s_pc_tlast,

    output wire [7:0]  m_axis_tdata,
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire        m_axis_tuser,
    output wire        m_axis_tlast,

    output reg         active_source,
    output reg         pc_frame_active,
    output reg         pc_frame_done_pulse,
    output reg         pc_error,
    output reg  [31:0] pc_error_code,
    output reg  [31:0] pc_frame_count
);

    localparam integer FRAME_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT;
    localparam integer X_WIDTH = (IMAGE_WIDTH <= 1) ? 1 : $clog2(IMAGE_WIDTH);
    localparam integer Y_WIDTH = (IMAGE_HEIGHT <= 1) ? 1 : $clog2(IMAGE_HEIGHT);

    localparam [31:0] ERR_SOURCE_CHANGE = 32'h0000_1301;
    localparam [31:0] ERR_TLAST_EARLY   = 32'h0000_1302;
    localparam [31:0] ERR_TLAST_MISSING = 32'h0000_1303;

    reg [X_WIDTH-1:0] x_count;
    reg [Y_WIDTH-1:0] y_count;
    reg               source_violation_seen;

    wire pc_selected = enable && active_source;
    wire dummy_selected = enable && !active_source;
    wire pc_transfer = pc_selected && s_pc_tvalid && m_axis_tready;
    wire pc_last_pixel = (x_count == IMAGE_WIDTH-1) &&
                         (y_count == IMAGE_HEIGHT-1);

    initial begin
        if (IMAGE_WIDTH <= 0 || IMAGE_HEIGHT <= 0 || FRAME_PIXELS <= 0)
            $error("IMAGE_WIDTH and IMAGE_HEIGHT must be positive");
    end

    assign m_axis_tdata  = active_source ? s_pc_tdata : s_dummy_tdata;
    assign m_axis_tvalid = active_source ? (enable && s_pc_tvalid) :
                                          (enable && s_dummy_tvalid);
    assign m_axis_tuser  = active_source ? ((x_count == 0) && (y_count == 0)) :
                                          s_dummy_tuser;
    assign m_axis_tlast  = active_source ? (x_count == IMAGE_WIDTH-1) :
                                          s_dummy_tlast;

    assign s_pc_tready    = pc_selected && m_axis_tready;
    assign s_dummy_tready = dummy_selected && m_axis_tready;

    always @(posedge aclk) begin
        if (!aresetn) begin
            active_source         <= 1'b0;
            x_count               <= {X_WIDTH{1'b0}};
            y_count               <= {Y_WIDTH{1'b0}};
            pc_frame_active       <= 1'b0;
            pc_frame_done_pulse   <= 1'b0;
            pc_error              <= 1'b0;
            pc_error_code         <= 32'b0;
            pc_frame_count        <= 32'b0;
            source_violation_seen <= 1'b0;
        end else begin
            pc_frame_done_pulse <= 1'b0;
            pc_error            <= 1'b0;

            if (soft_reset) begin
                x_count               <= {X_WIDTH{1'b0}};
                y_count               <= {Y_WIDTH{1'b0}};
                pc_frame_active       <= 1'b0;
                source_violation_seen <= 1'b0;
            end else begin
                if (!enable) begin
                    active_source         <= source_select;
                    x_count               <= {X_WIDTH{1'b0}};
                    y_count               <= {Y_WIDTH{1'b0}};
                    pc_frame_active       <= 1'b0;
                    source_violation_seen <= 1'b0;
                end else if (source_select != active_source) begin
                    if (!source_violation_seen) begin
                        pc_error              <= 1'b1;
                        pc_error_code         <= ERR_SOURCE_CHANGE;
                        source_violation_seen <= 1'b1;
                    end
                end else begin
                    source_violation_seen <= 1'b0;
                end

                if (pc_transfer) begin
                    if ((x_count == 0) && (y_count == 0))
                        pc_frame_active <= 1'b1;

                    if (s_pc_tlast && !pc_last_pixel) begin
                        pc_error        <= 1'b1;
                        pc_error_code   <= ERR_TLAST_EARLY;
                        x_count         <= {X_WIDTH{1'b0}};
                        y_count         <= {Y_WIDTH{1'b0}};
                        pc_frame_active <= 1'b0;
                    end else if (pc_last_pixel) begin
                        x_count         <= {X_WIDTH{1'b0}};
                        y_count         <= {Y_WIDTH{1'b0}};
                        pc_frame_active <= 1'b0;
                        if (!s_pc_tlast) begin
                            pc_error      <= 1'b1;
                            pc_error_code <= ERR_TLAST_MISSING;
                        end else begin
                            pc_frame_done_pulse <= 1'b1;
                            pc_frame_count      <= pc_frame_count + 1'b1;
                        end
                    end else if (x_count == IMAGE_WIDTH-1) begin
                        x_count <= {X_WIDTH{1'b0}};
                        y_count <= y_count + 1'b1;
                    end else begin
                        x_count <= x_count + 1'b1;
                    end
                end
            end

            if (clear_error)
                pc_error_code <= 32'b0;
        end
    end

endmodule
