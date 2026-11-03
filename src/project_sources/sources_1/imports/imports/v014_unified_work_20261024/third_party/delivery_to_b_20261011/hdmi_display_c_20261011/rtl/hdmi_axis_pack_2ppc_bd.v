module hdmi_axis_pack_2ppc_bd (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF s_axis:m_axis, ASSOCIATED_RESET aresetn" *)
    input wire aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input wire aresetn,
    input wire [23:0] s_axis_tdata,
    input wire s_axis_tvalid, s_axis_tuser, s_axis_tlast,
    output wire s_axis_tready,
    output wire [47:0] m_axis_tdata,
    output wire m_axis_tvalid, m_axis_tuser, m_axis_tlast,
    input wire m_axis_tready
);
    hdmi_axis_pack_2ppc core (
        .aclk(aclk), .aresetn(aresetn),
        .s_axis_tdata(s_axis_tdata), .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tuser(s_axis_tuser), .s_axis_tlast(s_axis_tlast), .s_axis_tready(s_axis_tready),
        .m_axis_tdata(m_axis_tdata), .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tuser(m_axis_tuser), .m_axis_tlast(m_axis_tlast), .m_axis_tready(m_axis_tready)
    );
endmodule
