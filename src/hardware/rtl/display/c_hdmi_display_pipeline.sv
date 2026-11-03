// C-owned logic runs on V0.13's 100 MHz domain. Use a 2-PPC packer and
// an official asynchronous AXIS FIFO before the HDMI TX subsystem.
module c_hdmi_display_pipeline #(
    parameter integer INPUT_WIDTH = 640, INPUT_HEIGHT = 480,
    parameter integer OUTPUT_WIDTH = 1280, OUTPUT_HEIGHT = 720,
    parameter integer X_OFFSET = 320, Y_OFFSET = 120,
    parameter MEMORY_STYLE = "ultra"
) (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF s_axis_video:m_axis_video, ASSOCIATED_RESET aresetn" *)
    input logic aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *) input logic aresetn,
    input logic [7:0] s_axis_video_tdata,
    input logic s_axis_video_tvalid, s_axis_video_tuser, s_axis_video_tlast,
    output logic s_axis_video_tready,
    input logic [31:0] s_frame_id,
    output logic [23:0] m_axis_video_tdata,
    output logic m_axis_video_tvalid, m_axis_video_tuser, m_axis_video_tlast,
    input logic m_axis_video_tready,
    // Whole box packet is held stable until accepted, in the aclk domain.
    input logic box_update_valid,
    output logic box_update_ready,
    input logic [31:0] box_frame_id,
    input logic [3:0] box_count,
    input logic [95:0] box_x_flat, box_y_flat, box_w_flat, box_h_flat,
    input logic [191:0] box_color_flat,
    output logic [31:0] display_frame_id,
    output logic display_frame_valid, frame_ready,
    output logic [31:0] protocol_error_count, stale_box_count, display_drop_count
);
    logic [11:0] fetch_x, fetch_y, pixel_x, pixel_y;
    logic fetch_valid, fetch_ready, fetch_sof, fetch_eol;
    logic [23:0] rgb;
    logic [31:0] active_box_frame_id;
    logic [3:0] active_count, pending_count;
    logic [95:0] ax, ay, aw, ah, px, py, pw, ph;
    logic [191:0] ac, pc;
    logic [31:0] pending_id;
    logic box_pending;
    integer box_index;
    wire frame_fetch = fetch_valid && fetch_ready && fetch_sof;
    assign box_update_ready = aresetn && !box_pending;

    video_timing_720p_axis #(.FRAME_WIDTH(OUTPUT_WIDTH), .FRAME_HEIGHT(OUTPUT_HEIGHT),
        .X_WIDTH(12), .Y_WIDTH(12)) timing_i (
        .aclk(aclk), .aresetn(aresetn), .m_axis_tready(fetch_ready),
        .m_axis_tvalid(fetch_valid), .pixel_x(fetch_x), .pixel_y(fetch_y),
        .pixel_active(), .frame_start(fetch_sof), .line_end(fetch_eol),
        .m_axis_tuser(), .m_axis_tlast()
    );
    display_framebuffer_640x480 #(.INPUT_WIDTH(INPUT_WIDTH), .INPUT_HEIGHT(INPUT_HEIGHT),
        .X_OFFSET(X_OFFSET), .Y_OFFSET(Y_OFFSET), .MEMORY_STYLE(MEMORY_STYLE)) framebuffer_i (
        .aclk(aclk), .aresetn(aresetn), .s_axis_tdata(s_axis_video_tdata),
        .s_axis_tvalid(s_axis_video_tvalid), .s_axis_tuser(s_axis_video_tuser),
        .s_axis_tlast(s_axis_video_tlast), .s_axis_tready(s_axis_video_tready),
        .s_frame_id(s_frame_id), .fetch_x(fetch_x), .fetch_y(fetch_y),
        .fetch_valid(fetch_valid), .fetch_ready(fetch_ready), .fetch_sof(fetch_sof),
        .fetch_eol(fetch_eol), .pixel_x(pixel_x), .pixel_y(pixel_y),
        .m_axis_tdata(rgb), .m_axis_tvalid(m_axis_video_tvalid),
        .m_axis_tuser(m_axis_video_tuser), .m_axis_tlast(m_axis_video_tlast),
        .m_axis_tready(m_axis_video_tready), .display_frame_id(display_frame_id),
        .display_frame_valid(display_frame_valid), .frame_ready(frame_ready),
        .protocol_error_count(protocol_error_count), .display_drop_count(display_drop_count)
    );

    // Shadow and active box banks; active updates occur at accepted frame SOF.
    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            box_pending <= 0; pending_id <= 0; pending_count <= 0;
            px <= 0; py <= 0; pw <= 0; ph <= 0; pc <= 0;
            active_count <= 0; active_box_frame_id <= 0;
            ax <= 0; ay <= 0; aw <= 0; ah <= 0; ac <= 0; stale_box_count <= 0;
        end else begin
            if (box_update_valid && box_update_ready) begin
                box_pending <= 1; pending_id <= box_frame_id;
                pending_count <= (box_count > 8) ? 8 : box_count;
                px <= box_x_flat; py <= box_y_flat; pc <= box_color_flat;
                for (box_index=0; box_index<8; box_index=box_index+1) begin
                    if (box_x_flat[box_index*12 +: 12] >= INPUT_WIDTH ||
                        box_y_flat[box_index*12 +: 12] >= INPUT_HEIGHT) begin
                        pw[box_index*12 +: 12] <= 0;
                        ph[box_index*12 +: 12] <= 0;
                    end else begin
                        pw[box_index*12 +: 12] <=
                            (box_w_flat[box_index*12 +: 12] > INPUT_WIDTH-box_x_flat[box_index*12 +: 12]) ?
                            INPUT_WIDTH-box_x_flat[box_index*12 +: 12] : box_w_flat[box_index*12 +: 12];
                        ph[box_index*12 +: 12] <=
                            (box_h_flat[box_index*12 +: 12] > INPUT_HEIGHT-box_y_flat[box_index*12 +: 12]) ?
                            INPUT_HEIGHT-box_y_flat[box_index*12 +: 12] : box_h_flat[box_index*12 +: 12];
                    end
                end
            end
            if (frame_fetch && box_pending) begin
                box_pending <= 0;
                active_count <= pending_count; active_box_frame_id <= pending_id;
                ax <= px; ay <= py; aw <= pw; ah <= ph; ac <= pc;
            end
            if (m_axis_video_tvalid && m_axis_video_tready && m_axis_video_tuser &&
                active_count != 0 && active_box_frame_id != display_frame_id)
                stale_box_count <= stale_box_count + 1;
        end
    end

    logic [95:0] shifted_x, shifted_y;
    integer i;
    always_comb begin
        for (i=0; i<8; i=i+1) begin
            shifted_x[i*12 +: 12] = ax[i*12 +: 12] + X_OFFSET;
            shifted_y[i*12 +: 12] = ay[i*12 +: 12] + Y_OFFSET;
        end
    end
    pl_osd_engine #(.COORD_WIDTH(12), .RGB_WIDTH(24), .LINE_WIDTH(2)) osd_i (
        .pixel_active(m_axis_video_tvalid && display_frame_valid),
        .pixel_x(pixel_x), .pixel_y(pixel_y), .pixel_rgb_in(rgb),
        .pixel_rgb_out(m_axis_video_tdata),
        .box_count((active_box_frame_id == display_frame_id) ? active_count : 4'd0),
        .box_x_flat(shifted_x), .box_y_flat(shifted_y), .box_w_flat(aw),
        .box_h_flat(ah), .box_color_flat(ac)
    );
endmodule
