// Active-video AXI4-Stream timing source for 1280x720 progressive video.
// The HDMI TX subsystem adds the electrical blanking and TMDS encoding.
module video_timing_720p_axis #(
    parameter integer FRAME_WIDTH  = 1280,
    parameter integer FRAME_HEIGHT = 720,
    parameter integer X_WIDTH = 12,
    parameter integer Y_WIDTH = 10
) (
    input  logic                 aclk,
    input  logic                 aresetn,
    input  logic                 m_axis_tready,
    output logic                 m_axis_tvalid,
    output logic [X_WIDTH-1:0]   pixel_x,
    output logic [Y_WIDTH-1:0]   pixel_y,
    output logic                 pixel_active,
    output logic                 frame_start,
    output logic                 line_end,
    output logic                 m_axis_tuser,
    output logic                 m_axis_tlast
);

    logic [X_WIDTH-1:0] x_count;
    logic [Y_WIDTH-1:0] y_count;
    wire transfer = m_axis_tvalid && m_axis_tready;

    always_comb begin
        m_axis_tvalid = aresetn;
        pixel_x       = x_count;
        pixel_y       = y_count;
        pixel_active  = aresetn;
        frame_start   = aresetn && (x_count == 0) && (y_count == 0);
        line_end      = aresetn && (x_count == FRAME_WIDTH-1);
        m_axis_tuser  = frame_start;
        m_axis_tlast  = line_end;
    end

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            x_count <= '0;
            y_count <= '0;
        end else if (transfer) begin
            if (x_count == FRAME_WIDTH-1) begin
                x_count <= '0;
                if (y_count == FRAME_HEIGHT-1)
                    y_count <= '0;
                else
                    y_count <= y_count + 1'b1;
            end else begin
                x_count <= x_count + 1'b1;
            end
        end
    end
endmodule
