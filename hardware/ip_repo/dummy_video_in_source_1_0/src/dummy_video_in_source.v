`timescale 1 ns / 1 ps

module dummy_video_in_source #(
    parameter integer IMAGE_WIDTH  = 640,
    parameter integer IMAGE_HEIGHT = 480,
    parameter [7:0]   PIXEL_VALUE  = 8'h00
)(
    input  wire       video_aclk,
    input  wire       video_aresetn,
    input  wire       enable,
    input  wire       soft_reset,

    output wire [7:0] m_axis_tdata,
    output wire       m_axis_tvalid,
    input  wire       m_axis_tready,
    output wire       m_axis_tuser,
    output wire       m_axis_tlast
);

    reg [15:0] pixel_x;
    reg [15:0] line_y;

    wire transfer;
    wire first_pixel;
    wire last_pixel_in_line;
    wire last_line;

    assign m_axis_tvalid = video_aresetn && enable && !soft_reset;
    assign m_axis_tdata  = PIXEL_VALUE;

    assign first_pixel       = (pixel_x == 0) && (line_y == 0);
    assign last_pixel_in_line = (pixel_x == IMAGE_WIDTH - 1);
    assign last_line          = (line_y == IMAGE_HEIGHT - 1);

    assign m_axis_tuser = m_axis_tvalid && first_pixel;
    assign m_axis_tlast = m_axis_tvalid && last_pixel_in_line;
    assign transfer     = m_axis_tvalid && m_axis_tready;

    always @(posedge video_aclk or negedge video_aresetn) begin
        if (!video_aresetn) begin
            pixel_x <= 16'd0;
            line_y  <= 16'd0;
        end else if (soft_reset || !enable) begin
            pixel_x <= 16'd0;
            line_y  <= 16'd0;
        end else if (transfer) begin
            if (last_pixel_in_line) begin
                pixel_x <= 16'd0;
                if (last_line)
                    line_y <= 16'd0;
                else
                    line_y <= line_y + 1'b1;
            end else begin
                pixel_x <= pixel_x + 1'b1;
            end
        end
    end

endmodule
