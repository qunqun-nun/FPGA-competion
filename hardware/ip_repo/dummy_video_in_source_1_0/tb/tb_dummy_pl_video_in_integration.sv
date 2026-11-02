`timescale 1 ns / 1 ps

module tb_dummy_pl_video_in_integration;

    localparam integer IMAGE_WIDTH  = 640;
    localparam integer IMAGE_HEIGHT = 480;
    localparam integer FRAME_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT;

    reg        video_aclk;
    reg        video_aresetn;
    reg        enable;
    reg        soft_reset;
    reg        clear_error;

    wire [7:0] source_tdata;
    wire       source_tvalid;
    wire       source_tready;
    wire       source_tuser;
    wire       source_tlast;

    wire [7:0] sink_tdata;
    wire       sink_tvalid;
    reg        sink_tready;
    wire       sink_tuser;
    wire       sink_tlast;

    wire        lock;
    wire        busy;
    wire        frame_done_pulse;
    wire        err;
    wire [31:0] err_code;
    wire [31:0] frame_cnt;

    reg [15:0] lfsr;
    integer output_pixels;
    integer output_lines;
    integer output_users;
    integer expected_x;
    integer expected_y;

    dummy_video_in_source #(
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .PIXEL_VALUE(8'h00)
    ) source (
        .video_aclk(video_aclk),
        .video_aresetn(video_aresetn),
        .enable(enable),
        .soft_reset(soft_reset),
        .m_axis_tdata(source_tdata),
        .m_axis_tvalid(source_tvalid),
        .m_axis_tready(source_tready),
        .m_axis_tuser(source_tuser),
        .m_axis_tlast(source_tlast)
    );

    pl_video_in #(
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT)
    ) video_in (
        .video_aclk(video_aclk),
        .video_aresetn(video_aresetn),
        .enable(enable),
        .soft_reset(soft_reset),
        .clear_error(clear_error),
        .s_axis_tdata(source_tdata),
        .s_axis_tvalid(source_tvalid),
        .s_axis_tready(source_tready),
        .s_axis_tuser(source_tuser),
        .s_axis_tlast(source_tlast),
        .m_axis_tdata(sink_tdata),
        .m_axis_tvalid(sink_tvalid),
        .m_axis_tready(sink_tready),
        .m_axis_tuser(sink_tuser),
        .m_axis_tlast(sink_tlast),
        .lock(lock),
        .busy(busy),
        .frame_done_pulse(frame_done_pulse),
        .err(err),
        .err_code(err_code),
        .frame_cnt(frame_cnt)
    );

    initial video_aclk = 1'b0;
    always #5 video_aclk = ~video_aclk;

    always @(negedge video_aclk) begin
        if (!video_aresetn) begin
            sink_tready <= 1'b0;
            lfsr        <= 16'h2bcd;
        end else begin
            lfsr        <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
            sink_tready <= lfsr[0] | lfsr[2];
        end
    end

    always @(posedge video_aclk) begin
        if (video_aresetn && enable) begin
            assert (!err)
                else $fatal(1, "pl_video_in reported err_code=0x%08x", err_code);
            assert (err_code == 32'h00000000)
                else $fatal(1, "Unexpected retained error code 0x%08x", err_code);

            if (frame_done_pulse) begin
                assert (output_pixels == FRAME_PIXELS)
                    else $fatal(1, "Expected %0d output pixels, observed %0d",
                                FRAME_PIXELS, output_pixels);
                assert (output_lines == IMAGE_HEIGHT)
                    else $fatal(1, "Expected %0d output EOL markers, observed %0d",
                                IMAGE_HEIGHT, output_lines);
                assert (output_users == 1)
                    else $fatal(1, "Expected one output SOF, observed %0d", output_users);
                assert (frame_cnt == 32'd1)
                    else $fatal(1, "FRAME_CNT expected 1, observed %0d", frame_cnt);
                assert (lock)
                    else $fatal(1, "LOCK was not asserted after a complete frame");
                $display("TB_DUMMY_PL_VIDEO_IN_INTEGRATION_PASS");
                $finish;
            end

            if (sink_tvalid && sink_tready) begin
                assert (sink_tdata === 8'h00)
                    else $fatal(1, "Non-black output pixel at index %0d", output_pixels);
                assert (sink_tuser ===
                        (((expected_x == 0) && (expected_y == 0)) ? 1'b1 : 1'b0))
                    else $fatal(1, "Incorrect output TUSER at x=%0d y=%0d",
                                expected_x, expected_y);
                assert (sink_tlast ===
                        ((expected_x == IMAGE_WIDTH - 1) ? 1'b1 : 1'b0))
                    else $fatal(1, "Incorrect output TLAST at x=%0d y=%0d",
                                expected_x, expected_y);

                output_pixels = output_pixels + 1;
                if (sink_tuser)
                    output_users = output_users + 1;
                if (sink_tlast)
                    output_lines = output_lines + 1;

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
    end

    initial begin
        video_aresetn = 1'b0;
        enable        = 1'b0;
        soft_reset    = 1'b0;
        clear_error   = 1'b0;
        sink_tready   = 1'b0;
        lfsr          = 16'h2bcd;
        output_pixels = 0;
        output_lines  = 0;
        output_users  = 0;
        expected_x    = 0;
        expected_y    = 0;

        repeat (5) @(posedge video_aclk);
        @(negedge video_aclk);
        video_aresetn = 1'b1;
        enable        = 1'b1;
    end

    initial begin
        #50000000;
        $fatal(1, "Integration simulation timeout");
    end

endmodule
