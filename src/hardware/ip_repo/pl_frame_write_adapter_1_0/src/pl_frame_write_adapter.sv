`timescale 1ns/1ps

// RGB888 frame stream to AXI DataMover S2MM command/data/status adapter.
// The DataMover owns the AXI4 memory-mapped master; this block owns frame
// addressing, pixel packing, protocol checking, and scheduler completion.
module pl_frame_write_adapter #(
    parameter logic [39:0] FRAME_BASE_ADDR = 40'h0000000000,
    parameter integer FRAME_WIDTH = 640,
    parameter integer FRAME_HEIGHT = 640
)(
    input  logic        aclk,
    input  logic        aresetn,
    input  logic        enable,
    input  logic        soft_reset,
    input  logic        recovery_reset,

    input  logic [23:0] s_axis_tdata,
    input  logic        s_axis_tvalid,
    output logic        s_axis_tready,
    input  logic        s_axis_tuser,
    input  logic        s_axis_tlast,

    input  logic        scheduler_frame_start_ready,
    input  logic [1:0]  write_buffer,
    output logic        frame_start,
    output logic        frame_end,
    output logic        frame_abort,
    output logic [1:0]  frame_abort_reason,

    output logic [79:0] dm_cmd_tdata,
    output logic        dm_cmd_tvalid,
    input  logic        dm_cmd_tready,

    output logic [31:0] dm_data_tdata,
    output logic [3:0]  dm_data_tkeep,
    output logic        dm_data_tlast,
    output logic        dm_data_tvalid,
    input  logic        dm_data_tready,

    input  logic [7:0]  dm_sts_tdata,
    input  logic        dm_sts_tvalid,
    output logic        dm_sts_tready,
    input  logic        dm_s2mm_err,

    output logic        busy,
    output logic        protocol_error,
    output logic        datamover_error,
    output logic [31:0] frames_written,
    output logic [31:0] frames_aborted
);

    localparam logic [2:0] ST_IDLE   = 3'd0;
    localparam logic [2:0] ST_CMD    = 3'd1;
    localparam logic [2:0] ST_DATA   = 3'd2;
    localparam logic [2:0] ST_STATUS = 3'd3;
    localparam logic [2:0] ST_FATAL  = 3'd4;

    localparam logic [9:0] LAST_X = FRAME_WIDTH - 1;
    localparam logic [9:0] LAST_Y = FRAME_HEIGHT - 1;
    localparam logic [22:0] FRAME_BYTES =
        FRAME_WIDTH * FRAME_HEIGHT * 4;
    localparam logic [39:0] BUFFER_1_OFFSET = 40'h0000190000;
    localparam logic [39:0] BUFFER_2_OFFSET = 40'h0000320000;

    logic [2:0] state;
    logic [9:0] pixel_x;
    logic [9:0] pixel_y;
    logic       first_pixel_pending;
    logic [23:0] first_pixel_data;
    logic       first_pixel_user;
    logic       first_pixel_last;
    logic       frame_bad;
    logic       frame_dm_error;
    logic [39:0] target_address;
    logic [23:0] active_pixel_data;
    logic       active_pixel_user;
    logic       active_pixel_last;

    initial begin
        if (FRAME_WIDTH < 1 || FRAME_WIDTH > 1024)
            $error("FRAME_WIDTH must be in the range 1..1024");
        if (FRAME_HEIGHT < 1 || FRAME_HEIGHT > 1024)
            $error("FRAME_HEIGHT must be in the range 1..1024");
        if ((FRAME_WIDTH * FRAME_HEIGHT * 4) > 23'h7fffff)
            $error("Frame byte count exceeds DataMover BTT width");
    end

    function automatic logic [39:0] buffer_offset(input logic [1:0] buffer_id);
        case (buffer_id)
            2'd0: buffer_offset = 40'h0000000000;
            2'd1: buffer_offset = BUFFER_1_OFFSET;
            2'd2: buffer_offset = BUFFER_2_OFFSET;
            default: buffer_offset = 40'h0000000000;
        endcase
    endfunction

    always_comb begin
        busy = (state != ST_IDLE);

        dm_cmd_tvalid = (state == ST_CMD);
        dm_cmd_tdata = {
            4'h0,                 // TAG
            4'h0,                 // reserved
            target_address,       // SADDR
            1'b0,                 // DRR
            1'b1,                 // EOF
            6'b000000,            // DSA
            1'b1,                 // INCR transfer
            FRAME_BYTES           // BTT
        };

        active_pixel_data = first_pixel_pending ? first_pixel_data : s_axis_tdata;
        active_pixel_user = first_pixel_pending ? first_pixel_user : s_axis_tuser;
        active_pixel_last = first_pixel_pending ? first_pixel_last : s_axis_tlast;

        dm_data_tdata = {8'h00, active_pixel_data[7:0],
                         active_pixel_data[15:8], active_pixel_data[23:16]};
        dm_data_tkeep = 4'b1111;
        dm_data_tlast = (pixel_x == LAST_X) && (pixel_y == LAST_Y);
        dm_data_tvalid = (state == ST_DATA) &&
                         (first_pixel_pending || s_axis_tvalid);

        s_axis_tready = 1'b0;
        if (state == ST_IDLE)
            s_axis_tready = enable && scheduler_frame_start_ready;
        else if (state == ST_DATA && !first_pixel_pending)
            s_axis_tready = dm_data_tready;

        dm_sts_tready = (state == ST_STATUS);
    end

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn || soft_reset) begin
            state               <= ST_IDLE;
            pixel_x             <= 10'd0;
            pixel_y             <= 10'd0;
            first_pixel_pending <= 1'b0;
            first_pixel_data    <= 24'd0;
            first_pixel_user    <= 1'b0;
            first_pixel_last    <= 1'b0;
            frame_bad           <= 1'b0;
            frame_dm_error      <= 1'b0;
            target_address      <= 40'd0;
            frame_start         <= 1'b0;
            frame_end           <= 1'b0;
            frame_abort         <= 1'b0;
            frame_abort_reason  <= 2'b00;
            protocol_error      <= 1'b0;
            datamover_error     <= 1'b0;
            frames_written      <= 32'd0;
            frames_aborted      <= 32'd0;
        end else if (recovery_reset) begin
            // A local recovery reset returns the writer to IDLE without
            // erasing cumulative success/failure evidence.
            state               <= ST_IDLE;
            pixel_x             <= 10'd0;
            pixel_y             <= 10'd0;
            first_pixel_pending <= 1'b0;
            first_pixel_data    <= 24'd0;
            first_pixel_user    <= 1'b0;
            first_pixel_last    <= 1'b0;
            frame_bad           <= 1'b0;
            frame_dm_error      <= 1'b0;
            target_address      <= 40'd0;
            frame_start         <= 1'b0;
            frame_end           <= 1'b0;
            frame_abort         <= 1'b0;
            frame_abort_reason  <= 2'b00;
            protocol_error      <= 1'b0;
            datamover_error     <= 1'b0;
        end else begin
            frame_start <= 1'b0;
            frame_end   <= 1'b0;
            frame_abort <= 1'b0;
            frame_abort_reason <= 2'b00;

            if (busy && state != ST_FATAL && dm_s2mm_err) begin
                // DataMover halts after a serious S2MM error. Release the
                // scheduler slot once, then remain quiescent until reset.
                frame_dm_error  <= 1'b1;
                datamover_error <= 1'b1;
                frame_abort     <= 1'b1;
                frame_abort_reason <= 2'b11;
                frames_aborted  <= frames_aborted + 32'd1;
                state           <= ST_FATAL;
                first_pixel_pending <= 1'b0;
            end else begin
                case (state)
                    ST_IDLE: begin
                        pixel_x        <= 10'd0;
                        pixel_y        <= 10'd0;
                        frame_bad      <= 1'b0;
                        frame_dm_error <= 1'b0;

                        if (s_axis_tvalid && s_axis_tready) begin
                            if (!s_axis_tuser) begin
                                protocol_error <= 1'b1;
                            end else if (write_buffer == 2'd3) begin
                                protocol_error <= 1'b1;
                            end else begin
                                target_address <= FRAME_BASE_ADDR +
                                                  buffer_offset(write_buffer);
                                first_pixel_data <= s_axis_tdata;
                                first_pixel_user <= s_axis_tuser;
                                first_pixel_last <= s_axis_tlast;
                                first_pixel_pending <= 1'b1;
                                frame_start <= 1'b1;
                                state <= ST_CMD;
                            end
                        end
                    end

                    ST_CMD: begin
                        if (dm_cmd_tvalid && dm_cmd_tready)
                            state <= ST_DATA;
                    end

                    ST_DATA: begin
                        if (dm_data_tvalid && dm_data_tready) begin
                            if (((pixel_x == 10'd0) && (pixel_y == 10'd0)) !=
                                active_pixel_user) begin
                                frame_bad <= 1'b1;
                                protocol_error <= 1'b1;
                            end
                            if ((pixel_x == LAST_X) != active_pixel_last) begin
                                frame_bad <= 1'b1;
                                protocol_error <= 1'b1;
                            end

                            first_pixel_pending <= 1'b0;
                            if ((pixel_x == LAST_X) && (pixel_y == LAST_Y)) begin
                                state <= ST_STATUS;
                            end else if (pixel_x == LAST_X) begin
                                pixel_x <= 10'd0;
                                pixel_y <= pixel_y + 10'd1;
                            end else begin
                                pixel_x <= pixel_x + 10'd1;
                            end
                        end
                    end

                    ST_STATUS: begin
                        if (dm_sts_tvalid && dm_sts_tready) begin
                            if ((dm_sts_tdata == 8'h80) && !frame_bad &&
                                !frame_dm_error) begin
                                frame_end <= 1'b1;
                                frames_written <= frames_written + 32'd1;
                            end else begin
                                frame_abort <= 1'b1;
                                frames_aborted <= frames_aborted + 32'd1;
                                if (dm_sts_tdata != 8'h80) begin
                                    datamover_error <= 1'b1;
                                    frame_dm_error <= 1'b1;
                                    frame_abort_reason <= 2'b10;
                                end else begin
                                    frame_abort_reason <= 2'b01;
                                end
                            end
                            state <= ST_IDLE;
                        end
                    end

                    ST_FATAL: begin
                        state <= ST_FATAL;
                    end

                    default: state <= ST_IDLE;
                endcase
            end
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge aclk) begin
        if (aresetn && !soft_reset) begin
            assert (!(dm_data_tvalid && state != ST_DATA))
                else $error("Data was offered before/after the DATA state");
            assert (!(frame_end && frame_abort))
                else $error("frame_end and frame_abort asserted together");
            if (dm_data_tvalid) begin
                assert (dm_data_tkeep == 4'b1111)
                    else $error("DataMover TKEEP must be 1111");
                assert (dm_data_tlast == ((pixel_x == LAST_X) &&
                                          (pixel_y == LAST_Y)))
                    else $error("DataMover TLAST is not at end of frame");
            end
            if ($past(dm_cmd_tvalid) && !$past(dm_cmd_tready))
                assert ($stable(dm_cmd_tdata))
                    else $error("DataMover command changed while stalled");
            if ($past(dm_data_tvalid) && !$past(dm_data_tready))
                assert ($stable({dm_data_tdata, dm_data_tkeep, dm_data_tlast}))
                    else $error("DataMover data changed while stalled");
        end
    end
`endif

endmodule
