`timescale 1 ns / 1 ps

module tb_dummy_video_in_source;

    localparam integer IMAGE_WIDTH  = 640;
    localparam integer IMAGE_HEIGHT = 480;
    localparam integer FRAME_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT;

    reg        video_aclk;
    reg        video_aresetn;
    reg        enable;
    reg        soft_reset;
    wire [7:0] m_axis_tdata;
    wire       m_axis_tvalid;
    reg        m_axis_tready;
    wire       m_axis_tuser;
    wire       m_axis_tlast;

    integer ready_mode;
    reg [15:0] lfsr;
    reg        stalled_previous;
    reg [7:0]  stalled_data;
    reg        stalled_user;
    reg        stalled_last;

    dummy_video_in_source #(
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .PIXEL_VALUE(8'h00)
    ) dut (
        .video_aclk(video_aclk),
        .video_aresetn(video_aresetn),
        .enable(enable),
        .soft_reset(soft_reset),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tuser(m_axis_tuser),
        .m_axis_tlast(m_axis_tlast)
    );

    initial video_aclk = 1'b0;
    always #5 video_aclk = ~video_aclk;

    always @(negedge video_aclk) begin
        if (!video_aresetn) begin
            m_axis_tready <= 1'b0;
            lfsr          <= 16'h1ace;
        end else begin
            lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
            case (ready_mode)
                0: m_axis_tready <= 1'b1;
                1: m_axis_tready <= lfsr[0] | lfsr[3];
                default: m_axis_tready <= 1'b0;
            endcase
        end
    end

    // Assertion: an unaccepted AXI4-Stream beat must remain unchanged.
    always @(posedge video_aclk) begin
        if (!video_aresetn || !enable || soft_reset) begin
            stalled_previous <= 1'b0;
        end else begin
            if (stalled_previous) begin
                assert (m_axis_tvalid)
                    else $fatal(1, "TVALID dropped during backpressure");
                assert (m_axis_tdata === stalled_data)
                    else $fatal(1, "TDATA changed during backpressure");
                assert (m_axis_tuser === stalled_user)
                    else $fatal(1, "TUSER changed during backpressure");
                assert (m_axis_tlast === stalled_last)
                    else $fatal(1, "TLAST changed during backpressure");
            end

            stalled_previous <= m_axis_tvalid && !m_axis_tready;
            stalled_data     <= m_axis_tdata;
            stalled_user     <= m_axis_tuser;
            stalled_last     <= m_axis_tlast;
        end
    end

    task automatic check_complete_frame;
        integer accepted;
        integer expected_x;
        integer expected_y;
        integer user_count;
        integer last_count;
        begin
            accepted   = 0;
            expected_x = 0;
            expected_y = 0;
            user_count = 0;
            last_count = 0;

            while (accepted < FRAME_PIXELS) begin
                @(posedge video_aclk);
                if (m_axis_tvalid && m_axis_tready) begin
                    assert (m_axis_tdata === 8'h00)
                        else $fatal(1, "Non-black pixel at transfer %0d", accepted);
                    assert (m_axis_tuser ===
                            (((expected_x == 0) && (expected_y == 0)) ? 1'b1 : 1'b0))
                        else $fatal(1, "Incorrect TUSER at x=%0d y=%0d",
                                    expected_x, expected_y);
                    assert (m_axis_tlast ===
                            ((expected_x == IMAGE_WIDTH - 1) ? 1'b1 : 1'b0))
                        else $fatal(1, "Incorrect TLAST at x=%0d y=%0d",
                                    expected_x, expected_y);

                    if (m_axis_tuser)
                        user_count = user_count + 1;
                    if (m_axis_tlast)
                        last_count = last_count + 1;

                    accepted = accepted + 1;
                    if (expected_x == IMAGE_WIDTH - 1) begin
                        expected_x = 0;
                        if (expected_y == IMAGE_HEIGHT - 1)
                            expected_y = 0;
                        else
                            expected_y = expected_y + 1;
                    end else begin
                        expected_x = expected_x + 1;
                    end
                end
            end

            assert (user_count == 1)
                else $fatal(1, "Expected one SOF, observed %0d", user_count);
            assert (last_count == IMAGE_HEIGHT)
                else $fatal(1, "Expected %0d EOL markers, observed %0d",
                            IMAGE_HEIGHT, last_count);
            assert (accepted == FRAME_PIXELS)
                else $fatal(1, "Expected %0d pixels, observed %0d",
                            FRAME_PIXELS, accepted);
        end
    endtask

    task automatic advance_transfers(input integer count);
        integer accepted;
        begin
            accepted = 0;
            while (accepted < count) begin
                @(posedge video_aclk);
                if (m_axis_tvalid && m_axis_tready)
                    accepted = accepted + 1;
            end
        end
    endtask

    task automatic check_next_transfer_is_sof;
        reg observed;
        begin
            observed = 1'b0;
            while (!observed) begin
                @(posedge video_aclk);
                if (m_axis_tvalid && m_axis_tready) begin
                    assert (m_axis_tdata === 8'h00)
                        else $fatal(1, "Restart pixel is not black");
                    assert (m_axis_tuser === 1'b1)
                        else $fatal(1, "Restart did not begin with SOF");
                    assert (m_axis_tlast === 1'b0)
                        else $fatal(1, "Unexpected TLAST on restart pixel");
                    observed = 1'b1;
                end
            end
        end
    endtask

    initial begin
        video_aresetn = 1'b0;
        enable        = 1'b0;
        soft_reset    = 1'b0;
        m_axis_tready = 1'b0;
        ready_mode    = 0;
        lfsr          = 16'h1ace;
        stalled_previous = 1'b0;

        repeat (5) @(posedge video_aclk);
        @(negedge video_aclk);
        video_aresetn = 1'b1;
        enable        = 1'b1;
        ready_mode    = 1;

        check_complete_frame();

        // Disable must discard a partial frame and restart at SOF.
        advance_transfers(37);
        @(negedge video_aclk);
        enable = 1'b0;
        repeat (3) begin
            @(posedge video_aclk);
            assert (!m_axis_tvalid)
                else $fatal(1, "TVALID asserted while disabled");
        end
        @(negedge video_aclk);
        enable = 1'b1;
        check_next_transfer_is_sof();

        // Soft reset must discard a partial frame and restart at SOF.
        advance_transfers(53);
        @(negedge video_aclk);
        soft_reset = 1'b1;
        repeat (2) begin
            @(posedge video_aclk);
            assert (!m_axis_tvalid)
                else $fatal(1, "TVALID asserted during soft reset");
        end
        @(negedge video_aclk);
        soft_reset = 1'b0;
        check_next_transfer_is_sof();

        // Hard reset must clear the stream position and restart at SOF.
        advance_transfers(29);
        @(negedge video_aclk);
        video_aresetn = 1'b0;
        repeat (2) begin
            @(posedge video_aclk);
            assert (!m_axis_tvalid)
                else $fatal(1, "TVALID asserted during hard reset");
        end
        @(negedge video_aclk);
        video_aresetn = 1'b1;
        check_next_transfer_is_sof();

        // Force a sustained stall; the assertion monitor checks stability.
        advance_transfers(11);
        @(negedge video_aclk);
        ready_mode = 2;
        repeat (8) @(posedge video_aclk);
        @(negedge video_aclk);
        ready_mode = 0;
        advance_transfers(2);

        $display("TB_DUMMY_VIDEO_IN_SOURCE_PASS");
        $finish;
    end

    initial begin
        #50000000;
        $fatal(1, "Unit simulation timeout");
    end

endmodule
