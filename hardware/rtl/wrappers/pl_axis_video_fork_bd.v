module pl_axis_video_fork_bd #(
    parameter integer DATA_WIDTH = 8
) (
    input wire aclk,
    input wire aresetn,
    input wire [DATA_WIDTH-1:0] s_axis_tdata,
    input wire s_axis_tvalid,
    output wire s_axis_tready,
    input wire s_axis_tuser,
    input wire s_axis_tlast,
    output wire [DATA_WIDTH-1:0] m_axis_algo_tdata,
    output wire m_axis_algo_tvalid,
    input wire m_axis_algo_tready,
    output wire m_axis_algo_tuser,
    output wire m_axis_algo_tlast,
    output wire [DATA_WIDTH-1:0] m_axis_display_tdata,
    output wire m_axis_display_tvalid,
    input wire m_axis_display_tready,
    output wire m_axis_display_tuser,
    output wire m_axis_display_tlast
);
    pl_axis_video_fork #(.DATA_WIDTH(DATA_WIDTH)) impl (
        .aclk(aclk), .aresetn(aresetn),
        .s_axis_tdata(s_axis_tdata), .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready), .s_axis_tuser(s_axis_tuser),
        .s_axis_tlast(s_axis_tlast),
        .m_axis_algo_tdata(m_axis_algo_tdata),
        .m_axis_algo_tvalid(m_axis_algo_tvalid),
        .m_axis_algo_tready(m_axis_algo_tready),
        .m_axis_algo_tuser(m_axis_algo_tuser),
        .m_axis_algo_tlast(m_axis_algo_tlast),
        .m_axis_display_tdata(m_axis_display_tdata),
        .m_axis_display_tvalid(m_axis_display_tvalid),
        .m_axis_display_tready(m_axis_display_tready),
        .m_axis_display_tuser(m_axis_display_tuser),
        .m_axis_display_tlast(m_axis_display_tlast)
    );
endmodule
