// Project RGB is RRGGBB; Xilinx RGB video samples are G,B,R low to high.
// Pixel 0 is in the low 24 bits; pixel 1 is in the high 24 bits. Even width only.
module hdmi_axis_pack_2ppc (
    input logic aclk, aresetn,
    input logic [23:0] s_axis_tdata,
    input logic s_axis_tvalid, s_axis_tuser, s_axis_tlast,
    output logic s_axis_tready,
    output logic [47:0] m_axis_tdata,
    output logic m_axis_tvalid, m_axis_tuser, m_axis_tlast,
    input logic m_axis_tready
);
    logic half_full;
    logic [23:0] half_data;
    logic half_user;
    wire [23:0] xilinx_rgb = {s_axis_tdata[23:16], s_axis_tdata[7:0], s_axis_tdata[15:8]};
    assign s_axis_tready = aresetn && (!m_axis_tvalid || m_axis_tready);
    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            half_full <= 0; half_data <= 0; half_user <= 0;
            m_axis_tvalid <= 0; m_axis_tdata <= 0; m_axis_tuser <= 0; m_axis_tlast <= 0;
        end else begin
            if (m_axis_tvalid && m_axis_tready) m_axis_tvalid <= 0;
            if (s_axis_tvalid && s_axis_tready) begin
                if (!half_full) begin
                    half_data <= xilinx_rgb; half_user <= s_axis_tuser; half_full <= 1;
                end else begin
                    m_axis_tdata <= {xilinx_rgb,half_data};
                    m_axis_tuser <= half_user; m_axis_tlast <= s_axis_tlast;
                    m_axis_tvalid <= 1; half_full <= 0;
                end
            end
        end
    end
endmodule
