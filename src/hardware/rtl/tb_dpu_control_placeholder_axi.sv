`timescale 1ns/1ps

module tb_dpu_control_placeholder_axi;
    logic         aclk = 1'b0;
    logic         aresetn = 1'b0;
    logic [31:0]  awaddr = '0;
    logic [2:0]   awprot = '0;
    logic         awvalid = 1'b0;
    wire          awready;
    logic [31:0]  wdata = '0;
    logic [3:0]   wstrb = '0;
    logic         wvalid = 1'b0;
    wire          wready;
    wire [1:0]    bresp;
    wire          bvalid;
    logic         bready = 1'b0;
    logic [31:0]  araddr = '0;
    logic [2:0]   arprot = '0;
    logic         arvalid = 1'b0;
    wire          arready;
    wire [31:0]   rdata;
    wire [1:0]    rresp;
    wire          rvalid;
    logic         rready = 1'b0;

    always #5 aclk = ~aclk;

    dpu_control_placeholder_axi dut (
        .s_axi_aclk(aclk),
        .s_axi_aresetn(aresetn),
        .s_axi_awaddr(awaddr),
        .s_axi_awprot(awprot),
        .s_axi_awvalid(awvalid),
        .s_axi_awready(awready),
        .s_axi_wdata(wdata),
        .s_axi_wstrb(wstrb),
        .s_axi_wvalid(wvalid),
        .s_axi_wready(wready),
        .s_axi_bresp(bresp),
        .s_axi_bvalid(bvalid),
        .s_axi_bready(bready),
        .s_axi_araddr(araddr),
        .s_axi_arprot(arprot),
        .s_axi_arvalid(arvalid),
        .s_axi_arready(arready),
        .s_axi_rdata(rdata),
        .s_axi_rresp(rresp),
        .s_axi_rvalid(rvalid),
        .s_axi_rready(rready)
    );

    task automatic axi_write(
        input logic [31:0] address,
        input logic [31:0] data,
        input logic [3:0] strobes,
        input integer response_stall_cycles
    );
        begin
            @(negedge aclk);
            awaddr  <= address;
            wdata   <= data;
            wstrb   <= strobes;
            awvalid <= 1'b1;
            wvalid  <= 1'b1;
            wait (awready && wready);
            @(negedge aclk);
            awvalid <= 1'b0;
            wvalid  <= 1'b0;
            repeat (response_stall_cycles) @(negedge aclk);
            if (!bvalid || bresp != 2'b00) begin
                $fatal(1, "AXI write response missing or not OKAY");
            end
            bready <= 1'b1;
            @(negedge aclk);
            bready <= 1'b0;
        end
    endtask

    task automatic axi_read(
        input logic [31:0] address,
        input logic [31:0] expected,
        input integer response_stall_cycles
    );
        begin
            @(negedge aclk);
            araddr  <= address;
            arvalid <= 1'b1;
            wait (arready);
            @(negedge aclk);
            arvalid <= 1'b0;
            repeat (response_stall_cycles) @(negedge aclk);
            if (!rvalid || rresp != 2'b00) begin
                $fatal(1, "AXI read response missing or not OKAY");
            end
            if (rdata !== expected) begin
                $fatal(1, "Read mismatch: expected %08x, got %08x", expected, rdata);
            end
            rready <= 1'b1;
            @(negedge aclk);
            rready <= 1'b0;
        end
    endtask

    initial begin
        repeat (4) @(posedge aclk);
        if (bvalid || rvalid || rdata !== 32'h0000_0000) begin
            $fatal(1, "Reset state is incorrect");
        end
        aresetn <= 1'b1;

        axi_write(32'h8204_0000, 32'hA5C3_5A3C, 4'b1111, 2);
        axi_read (32'h8204_0000, 32'hA5C3_5A3C, 3);

        axi_write(32'hFFFF_FFFC, 32'h1122_3344, 4'b0101, 1);
        axi_read (32'h0000_0000, 32'hA522_5A44, 1);

        @(negedge aclk);
        awvalid <= 1'b1;
        wvalid  <= 1'b0;
        if (awready) $fatal(1, "AWREADY asserted before WVALID");
        @(negedge aclk);
        wvalid <= 1'b1;
        wait (awready && wready);
        @(negedge aclk);
        awvalid <= 1'b0;
        wvalid  <= 1'b0;
        bready  <= 1'b1;
        @(negedge aclk);
        bready  <= 1'b0;

        $display("TB_PASS: reset, full write/read, byte strobes, and backpressure verified");
        $finish;
    end

    initial begin
        #5000;
        $fatal(1, "Simulation timeout");
    end
endmodule
