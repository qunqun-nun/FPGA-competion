`timescale 1ns / 1ps

// Static endpoint used only to materialize the Vitis dynamic DPU control path.
// The 32-bit AXI address bus prevents upstream SmartConnect propagation from
// narrowing the physical address map to the local register width.
module dpu_control_placeholder_axi #(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 32
) (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 S_AXI_ACLK CLK" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S_AXI_ACLK, ASSOCIATED_BUSIF S_AXI, ASSOCIATED_RESET S_AXI_ARESETN" *)
    input  wire                              s_axi_aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 S_AXI_ARESETN RST" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S_AXI_ARESETN, POLARITY ACTIVE_LOW" *)
    input  wire                              s_axi_aresetn,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWADDR" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S_AXI, PROTOCOL AXI4LITE, DATA_WIDTH 32, ADDR_WIDTH 32, ID_WIDTH 0, HAS_BURST 0, HAS_LOCK 0, HAS_CACHE 0, HAS_PROT 1, HAS_QOS 0, HAS_REGION 0, SUPPORTS_NARROW_BURST 0, NUM_READ_OUTSTANDING 1, NUM_WRITE_OUTSTANDING 1, MAX_BURST_LENGTH 1" *)
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]     s_axi_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWPROT" *)
    input  wire [2:0]                        s_axi_awprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *)
    input  wire                              s_axi_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *)
    output wire                              s_axi_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WDATA" *)
    input  wire [C_S_AXI_DATA_WIDTH-1:0]     s_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *)
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WVALID" *)
    input  wire                              s_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WREADY" *)
    output wire                              s_axi_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BRESP" *)
    output wire [1:0]                        s_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BVALID" *)
    output wire                              s_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BREADY" *)
    input  wire                              s_axi_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *)
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]     s_axi_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARPROT" *)
    input  wire [2:0]                        s_axi_arprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *)
    input  wire                              s_axi_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *)
    output wire                              s_axi_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RDATA" *)
    output wire [C_S_AXI_DATA_WIDTH-1:0]     s_axi_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RRESP" *)
    output wire [1:0]                        s_axi_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RVALID" *)
    output wire                              s_axi_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RREADY" *)
    input  wire                              s_axi_rready
);

    reg bvalid_reg;
    reg rvalid_reg;
    reg [C_S_AXI_DATA_WIDTH-1:0] scratch_reg;
    integer byte_index;

    wire write_accept = s_axi_awvalid && s_axi_awready &&
                        s_axi_wvalid  && s_axi_wready;
    wire read_accept  = s_axi_arvalid && s_axi_arready;

    assign s_axi_awready = !bvalid_reg && s_axi_wvalid;
    assign s_axi_wready  = !bvalid_reg && s_axi_awvalid;
    assign s_axi_bresp   = 2'b00;
    assign s_axi_bvalid  = bvalid_reg;
    assign s_axi_arready = !rvalid_reg;
    assign s_axi_rdata   = scratch_reg;
    assign s_axi_rresp   = 2'b00;
    assign s_axi_rvalid  = rvalid_reg;

    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            bvalid_reg  <= 1'b0;
            rvalid_reg  <= 1'b0;
            scratch_reg <= {C_S_AXI_DATA_WIDTH{1'b0}};
        end else begin
            if (write_accept) begin
                for (byte_index = 0; byte_index < C_S_AXI_DATA_WIDTH/8; byte_index = byte_index + 1) begin
                    if (s_axi_wstrb[byte_index]) begin
                        scratch_reg[byte_index*8 +: 8] <= s_axi_wdata[byte_index*8 +: 8];
                    end
                end
                bvalid_reg <= 1'b1;
            end else if (bvalid_reg && s_axi_bready) begin
                bvalid_reg <= 1'b0;
            end

            if (read_accept) begin
                rvalid_reg <= 1'b1;
            end else if (rvalid_reg && s_axi_rready) begin
                rvalid_reg <= 1'b0;
            end
        end
    end

    wire unused = &{1'b0, s_axi_awaddr, s_axi_awprot, s_axi_araddr, s_axi_arprot};

endmodule
