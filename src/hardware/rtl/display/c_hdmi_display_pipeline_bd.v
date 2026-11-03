// Verilog entry point: Vivado 2018.3 does not accept a SystemVerilog BD reference.
module c_hdmi_display_pipeline_bd (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF s_axis_video:m_axis_video, ASSOCIATED_RESET aresetn" *)
    input wire aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input wire aresetn,
    input wire [7:0] s_axis_video_tdata,
    input wire s_axis_video_tvalid, s_axis_video_tuser, s_axis_video_tlast,
    output wire s_axis_video_tready,
    input wire [31:0] s_frame_id,
    output wire [23:0] m_axis_video_tdata,
    output wire m_axis_video_tvalid, m_axis_video_tuser, m_axis_video_tlast,
    input wire m_axis_video_tready,
    input wire box_update_valid,
    output wire box_update_ready,
    input wire [31:0] box_frame_id,
    input wire [3:0] box_count,
    input wire [95:0] box_x_flat, box_y_flat, box_w_flat, box_h_flat,
    input wire [191:0] box_color_flat,
    output wire [31:0] display_frame_id,
    output wire display_frame_valid, frame_ready,
    output wire [31:0] protocol_error_count, stale_box_count, display_drop_count
);
    c_hdmi_display_pipeline core (
        .aclk(aclk), .aresetn(aresetn),
        .s_axis_video_tdata(s_axis_video_tdata), .s_axis_video_tvalid(s_axis_video_tvalid),
        .s_axis_video_tuser(s_axis_video_tuser), .s_axis_video_tlast(s_axis_video_tlast),
        .s_axis_video_tready(s_axis_video_tready), .s_frame_id(s_frame_id),
        .m_axis_video_tdata(m_axis_video_tdata), .m_axis_video_tvalid(m_axis_video_tvalid),
        .m_axis_video_tuser(m_axis_video_tuser), .m_axis_video_tlast(m_axis_video_tlast),
        .m_axis_video_tready(m_axis_video_tready),
        .box_update_valid(box_update_valid), .box_update_ready(box_update_ready),
        .box_frame_id(box_frame_id), .box_count(box_count),
        .box_x_flat(box_x_flat), .box_y_flat(box_y_flat),
        .box_w_flat(box_w_flat), .box_h_flat(box_h_flat), .box_color_flat(box_color_flat),
        .display_frame_id(display_frame_id), .display_frame_valid(display_frame_valid),
        .frame_ready(frame_ready), .protocol_error_count(protocol_error_count),
        .stale_box_count(stale_box_count), .display_drop_count(display_drop_count)
    );
endmodule
