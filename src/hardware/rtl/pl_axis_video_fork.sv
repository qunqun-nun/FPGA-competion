`timescale 1ns/1ps

// Lossless two-way AXI4-Stream Video fork. The input advances only after both
// consumers accept the same beat, so SOF/EOL and frame_id stay aligned.
module pl_axis_video_fork #(
    parameter integer DATA_WIDTH = 8
) (
    input  logic                  aclk,
    input  logic                  aresetn,
    input  logic [DATA_WIDTH-1:0] s_axis_tdata,
    input  logic                  s_axis_tvalid,
    output logic                  s_axis_tready,
    input  logic                  s_axis_tuser,
    input  logic                  s_axis_tlast,

    output logic [DATA_WIDTH-1:0] m_axis_algo_tdata,
    output logic                  m_axis_algo_tvalid,
    input  logic                  m_axis_algo_tready,
    output logic                  m_axis_algo_tuser,
    output logic                  m_axis_algo_tlast,

    output logic [DATA_WIDTH-1:0] m_axis_display_tdata,
    output logic                  m_axis_display_tvalid,
    input  logic                  m_axis_display_tready,
    output logic                  m_axis_display_tuser,
    output logic                  m_axis_display_tlast
);
    logic algo_pending;
    logic display_pending;
    logic [DATA_WIDTH-1:0] data_reg;
    logic user_reg;
    logic last_reg;

    assign s_axis_tready = aresetn && !algo_pending && !display_pending;

    assign m_axis_algo_tdata  = data_reg;
    assign m_axis_algo_tvalid = algo_pending;
    assign m_axis_algo_tuser  = user_reg;
    assign m_axis_algo_tlast  = last_reg;

    assign m_axis_display_tdata  = data_reg;
    assign m_axis_display_tvalid = display_pending;
    assign m_axis_display_tuser  = user_reg;
    assign m_axis_display_tlast  = last_reg;

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            algo_pending    <= 1'b0;
            display_pending <= 1'b0;
            data_reg        <= '0;
            user_reg        <= 1'b0;
            last_reg        <= 1'b0;
        end else begin
            if (algo_pending && m_axis_algo_tready)
                algo_pending <= 1'b0;
            if (display_pending && m_axis_display_tready)
                display_pending <= 1'b0;

            if (s_axis_tvalid && s_axis_tready) begin
                data_reg        <= s_axis_tdata;
                user_reg        <= s_axis_tuser;
                last_reg        <= s_axis_tlast;
                algo_pending    <= 1'b1;
                display_pending <= 1'b1;
            end
        end
    end
endmodule
