`timescale 1ns/1ps

module pl_reset_ctrl #(
    parameter integer PIPELINE_RESET_CYCLES = 4,
    parameter integer DATAMOVER_RESET_CYCLES = 4,
    parameter integer DRAIN_TIMEOUT_CYCLES = 1048576
) (
    input  logic aclk,
    input  logic aresetn,
    input  logic soft_reset_req,
    input  logic recovery_reset_req,
    input  logic writer_busy,
    output logic writer_quiesce,
    output logic pipeline_soft_reset,
    output logic letterbox_aresetn,
    output logic datamover_aresetn,
    output logic adapter_recovery_reset,
    output logic reset_busy
);
    localparam integer RESET_CYCLES =
        (PIPELINE_RESET_CYCLES > DATAMOVER_RESET_CYCLES) ?
        PIPELINE_RESET_CYCLES : DATAMOVER_RESET_CYCLES;
    localparam integer RESET_W = (RESET_CYCLES < 2) ? 1 : $clog2(RESET_CYCLES + 1);
    localparam integer DRAIN_W = (DRAIN_TIMEOUT_CYCLES < 2) ?
        1 : $clog2(DRAIN_TIMEOUT_CYCLES + 1);
    localparam logic [RESET_W-1:0] RESET_COUNT = RESET_CYCLES;
    localparam logic [DRAIN_W-1:0] DRAIN_COUNT = DRAIN_TIMEOUT_CYCLES;

    typedef enum logic [1:0] {IDLE, DRAIN, ASSERT_RESET, RELEASE} state_t;
    state_t state;
    logic [RESET_W-1:0] reset_left;
    logic [DRAIN_W-1:0] drain_left;

    initial begin
        if (PIPELINE_RESET_CYCLES < 3)
            $error("PIPELINE_RESET_CYCLES must be >= 3");
        if (DATAMOVER_RESET_CYCLES < 3)
            $error("DATAMOVER_RESET_CYCLES must be >= 3");
        if (DRAIN_TIMEOUT_CYCLES < 1)
            $error("DRAIN_TIMEOUT_CYCLES must be >= 1");
    end

    // Reset outputs are registered to avoid LUT logic on asynchronous resets.
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            state                  <= IDLE;
            reset_left             <= '0;
            drain_left             <= '0;
            writer_quiesce         <= 1'b0;
            pipeline_soft_reset    <= 1'b0;
            letterbox_aresetn      <= 1'b0;
            datamover_aresetn      <= 1'b0;
            adapter_recovery_reset <= 1'b0;
            reset_busy             <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    writer_quiesce         <= 1'b0;
                    pipeline_soft_reset    <= 1'b0;
                    letterbox_aresetn      <= 1'b1;
                    datamover_aresetn      <= 1'b1;
                    adapter_recovery_reset <= 1'b0;
                    reset_busy             <= 1'b0;

                    if (recovery_reset_req) begin
                        writer_quiesce         <= 1'b1;
                        pipeline_soft_reset    <= 1'b1;
                        letterbox_aresetn      <= 1'b0;
                        datamover_aresetn      <= 1'b0;
                        adapter_recovery_reset <= 1'b1;
                        reset_busy             <= 1'b1;
                        reset_left             <= RESET_COUNT;
                        state                  <= ASSERT_RESET;
                    end else if (soft_reset_req) begin
                        writer_quiesce <= 1'b1;
                        reset_busy     <= 1'b1;
                        drain_left     <= DRAIN_COUNT;
                        state          <= DRAIN;
                    end
                end

                DRAIN: begin
                    writer_quiesce <= 1'b1;
                    reset_busy     <= 1'b1;

                    if (recovery_reset_req || !writer_busy || drain_left == 1) begin
                        pipeline_soft_reset    <= 1'b1;
                        letterbox_aresetn      <= 1'b0;
                        datamover_aresetn      <= 1'b0;
                        adapter_recovery_reset <= 1'b1;
                        reset_left             <= RESET_COUNT;
                        state                  <= ASSERT_RESET;
                    end else begin
                        drain_left <= drain_left - 1'b1;
                    end
                end

                ASSERT_RESET: begin
                    writer_quiesce         <= 1'b1;
                    pipeline_soft_reset    <= 1'b1;
                    letterbox_aresetn      <= 1'b0;
                    datamover_aresetn      <= 1'b0;
                    adapter_recovery_reset <= 1'b1;
                    reset_busy             <= 1'b1;

                    if (reset_left > 1) begin
                        reset_left <= reset_left - 1'b1;
                    end else begin
                        reset_left             <= '0;
                        pipeline_soft_reset    <= 1'b0;
                        letterbox_aresetn      <= 1'b1;
                        datamover_aresetn      <= 1'b1;
                        adapter_recovery_reset <= 1'b0;
                        state                  <= RELEASE;
                    end
                end

                RELEASE: begin
                    writer_quiesce         <= 1'b1;
                    pipeline_soft_reset    <= 1'b0;
                    letterbox_aresetn      <= 1'b1;
                    datamover_aresetn      <= 1'b1;
                    adapter_recovery_reset <= 1'b0;
                    reset_busy             <= 1'b1;
                    state                  <= IDLE;
                end

                default: begin
                    state                  <= ASSERT_RESET;
                    reset_left             <= RESET_COUNT;
                    writer_quiesce         <= 1'b1;
                    pipeline_soft_reset    <= 1'b1;
                    letterbox_aresetn      <= 1'b0;
                    datamover_aresetn      <= 1'b0;
                    adapter_recovery_reset <= 1'b1;
                    reset_busy             <= 1'b1;
                end
            endcase
        end
    end

`ifndef SYNTHESIS
    property p_datamover_reset_minimum;
        @(posedge aclk) disable iff (!aresetn)
            $fell(datamover_aresetn) |-> !datamover_aresetn[*3];
    endproperty
    assert property (p_datamover_reset_minimum)
        else $error("DataMover reset was shorter than three clocks");

    property p_pipeline_reset_minimum;
        @(posedge aclk) disable iff (!aresetn)
            $fell(letterbox_aresetn) |-> !letterbox_aresetn[*3];
    endproperty
    assert property (p_pipeline_reset_minimum)
        else $error("Pipeline reset was shorter than three clocks");

    property p_no_new_writer_work_while_busy;
        @(posedge aclk) disable iff (!aresetn) reset_busy |-> writer_quiesce;
    endproperty
    assert property (p_no_new_writer_work_while_busy)
        else $error("Writer was not quiesced during reset sequencing");
`endif
endmodule
