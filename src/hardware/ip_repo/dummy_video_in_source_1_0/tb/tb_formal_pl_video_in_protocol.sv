`timescale 1ns/1ps

// Protocol regression for the packaged pl_video_in RTL contract.
// Small dimensions keep error-recovery cases fast; the default IP values
// (640x480) are covered by the existing full-frame integration test.
module tb_formal_pl_video_in_protocol;
    localparam integer W = 4;
    localparam integer H = 3;
    localparam integer FRAME_PIXELS = W * H;

    reg        video_aclk;
    reg        video_aresetn;
    reg        enable;
    reg        soft_reset;
    reg        clear_error;
    reg [7:0]  s_axis_tdata;
    reg        s_axis_tvalid;
    wire       s_axis_tready;
    reg        s_axis_tuser;
    reg        s_axis_tlast;
    wire [7:0] m_axis_tdata;
    wire       m_axis_tvalid;
    reg        m_axis_tready;
    wire       m_axis_tuser;
    wire       m_axis_tlast;
    wire       lock;
    wire       busy;
    wire       frame_done_pulse;
    wire       err;
    wire [31:0] err_code;
    wire [31:0] frame_cnt;

    integer failures;
    integer output_count;
    integer done_count;
    integer sof_count;
    integer eol_count;
    integer expected_x;
    integer expected_y;
    reg     stalled;
    reg [7:0] stalled_data;
    reg       stalled_user;
    reg       stalled_last;
    reg       saw_error;
    reg       saw_done;
    reg       check_frame_data;

    localparam [31:0] ERR_NONE           = 32'h0000_0000;
    localparam [31:0] ERR_NO_SOF         = 32'h0000_0101;
    localparam [31:0] ERR_UNEXPECTED_SOF = 32'h0000_0102;
    localparam [31:0] ERR_EARLY_TLAST    = 32'h0000_0103;
    localparam [31:0] ERR_MISSING_TLAST  = 32'h0000_0104;
    localparam [31:0] ERR_TOO_MANY_LINES = 32'h0000_0105;

    pl_video_in #(
        .IMAGE_WIDTH(W),
        .IMAGE_HEIGHT(H)
    ) dut (
        .video_aclk(video_aclk),
        .video_aresetn(video_aresetn),
        .enable(enable),
        .soft_reset(soft_reset),
        .clear_error(clear_error),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tuser(s_axis_tuser),
        .s_axis_tlast(s_axis_tlast),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tuser(m_axis_tuser),
        .m_axis_tlast(m_axis_tlast),
        .lock(lock),
        .busy(busy),
        .frame_done_pulse(frame_done_pulse),
        .err(err),
        .err_code(err_code),
        .frame_cnt(frame_cnt)
    );

    initial video_aclk = 1'b0;
    always #5 video_aclk = ~video_aclk;

    task automatic fail(input [8*80-1:0] message);
        begin
            failures = failures + 1;
            $display("FAIL: %0s", message);
        end
    endtask

    task automatic hard_reset;
        begin
            @(negedge video_aclk);
            video_aresetn = 1'b0;
            enable = 1'b0;
            soft_reset = 1'b0;
            clear_error = 1'b0;
            s_axis_tvalid = 1'b0;
            s_axis_tuser = 1'b0;
            s_axis_tlast = 1'b0;
            repeat (3) @(posedge video_aclk);
            @(negedge video_aclk);
            video_aresetn = 1'b1;
            enable = 1'b1;
            m_axis_tready = 1'b1;
            output_count = 0;
            done_count = 0;
            sof_count = 0;
            eol_count = 0;
            expected_x = 0;
            expected_y = 0;
            saw_error = 1'b0;
            saw_done = 1'b0;
            check_frame_data = 1'b0;
        end
    endtask

    task automatic reset_scoreboard;
        begin
            output_count = 0;
            done_count = 0;
            sof_count = 0;
            eol_count = 0;
            expected_x = 0;
            expected_y = 0;
            saw_error = 1'b0;
            saw_done = 1'b0;
            check_frame_data = 1'b1;
        end
    endtask

    task automatic send_beat(input [7:0] data, input user, input last);
        begin
            @(negedge video_aclk);
            s_axis_tdata = data;
            s_axis_tuser = user;
            s_axis_tlast = last;
            s_axis_tvalid = 1'b1;
            while (!s_axis_tready)
                @(negedge video_aclk);
            @(posedge video_aclk);
            @(negedge video_aclk);
            s_axis_tvalid = 1'b0;
            s_axis_tuser = 1'b0;
            s_axis_tlast = 1'b0;
        end
    endtask

    task automatic send_frame;
        integer x;
        integer y;
        begin
            for (y = 0; y < H; y = y + 1) begin
                for (x = 0; x < W; x = x + 1)
                    send_beat((y * W + x) & 8'hff,
                              (x == 0) && (y == 0), x == W - 1);
            end
        end
    endtask

    task automatic wait_done(input integer expected_count);
        integer guard;
        begin
            guard = 0;
            while (!saw_done && guard < 100) begin
                @(posedge video_aclk);
                guard = guard + 1;
            end
            if (!saw_done)
                fail("frame_done timeout");
            if (frame_cnt != expected_count)
                fail("unexpected frame count");
        end
    endtask

    task automatic expect_error(input [31:0] expected_code);
        integer guard;
        begin
            guard = 0;
            while (!saw_error && guard < 20) begin
                @(posedge video_aclk);
                guard = guard + 1;
            end
            if (!saw_error)
                fail("expected error pulse was absent");
            if (err_code != expected_code)
                fail("unexpected error code");
            if (saw_done)
                fail("error frame unexpectedly completed");
        end
    endtask

    // Scoreboard and AXI4-Stream stability assertions.
    always @(posedge video_aclk) begin
        if (!video_aresetn || !enable || soft_reset) begin
            stalled <= 1'b0;
        end else begin
            if (stalled) begin
                if (!m_axis_tvalid) fail("TVALID dropped during backpressure");
                if (m_axis_tdata !== stalled_data) fail("TDATA changed during backpressure");
                if (m_axis_tuser !== stalled_user) fail("TUSER changed during backpressure");
                if (m_axis_tlast !== stalled_last) fail("TLAST changed during backpressure");
            end
            stalled <= m_axis_tvalid && !m_axis_tready;
            stalled_data <= m_axis_tdata;
            stalled_user <= m_axis_tuser;
            stalled_last <= m_axis_tlast;

            if (m_axis_tvalid && m_axis_tready) begin
                if (check_frame_data &&
                    m_axis_tdata !== ((expected_y * W + expected_x) & 8'hff))
                    fail("output data/order mismatch");
                if (m_axis_tuser) sof_count = sof_count + 1;
                if (m_axis_tlast) eol_count = eol_count + 1;
                output_count = output_count + 1;
                expected_x = (expected_x == W - 1) ? 0 : expected_x + 1;
                if (expected_x == 0)
                    expected_y = (expected_y == H - 1) ? 0 : expected_y + 1;
            end
            if (frame_done_pulse) begin
                done_count = done_count + 1;
                saw_done = 1'b1;
            end
            if (err)
                saw_error = 1'b1;
        end
    end

    task automatic clear_error_pulse;
        begin
            @(negedge video_aclk);
            clear_error = 1'b1;
            @(posedge video_aclk);
            @(negedge video_aclk);
            clear_error = 1'b0;
            if (err_code != ERR_NONE) fail("clear_error did not clear err_code");
        end
    endtask

    initial begin
        failures = 0;
        video_aresetn = 1'b0;
        enable = 1'b0;
        soft_reset = 1'b0;
        clear_error = 1'b0;
        s_axis_tdata = 0;
        s_axis_tvalid = 0;
        s_axis_tuser = 0;
        s_axis_tlast = 0;
        m_axis_tready = 1'b1;
        stalled = 1'b0;
        stalled_data = 0;
        stalled_user = 0;
        stalled_last = 0;
        output_count = 0;
        done_count = 0;
        sof_count = 0;
        eol_count = 0;
        expected_x = 0;
        expected_y = 0;
        saw_error = 1'b0;
        saw_done = 1'b0;
        check_frame_data = 1'b0;

        hard_reset();
        $display("TEST 1: normal frame with output backpressure");
        reset_scoreboard();
        fork
            begin
                repeat (8) begin
                    @(negedge video_aclk);
                    m_axis_tready = 1'b0;
                    @(negedge video_aclk);
                    m_axis_tready = 1'b1;
                end
            end
            send_frame();
        join
        wait_done(1);
        if (output_count != FRAME_PIXELS) fail("normal frame pixel count mismatch");
        if (sof_count != 1) fail("normal frame SOF count mismatch");
        if (eol_count != H) fail("normal frame EOL count mismatch");
        if (err_code != ERR_NONE) fail("normal frame retained an error");

        $display("TEST 2: missing SOF, then automatic DROP_FRAME recovery");
        hard_reset();
        send_beat(8'h11, 1'b0, 1'b0);
        expect_error(ERR_NO_SOF);
        clear_error_pulse();
        reset_scoreboard();
        send_frame();
        wait_done(1);

        $display("TEST 3: unexpected SOF in an active frame");
        hard_reset();
        send_beat(8'h00, 1'b1, 1'b0);
        send_beat(8'h02, 1'b1, 1'b0);
        expect_error(ERR_UNEXPECTED_SOF);
        clear_error_pulse();
        reset_scoreboard();
        send_frame();
        wait_done(1);

        $display("TEST 4: early TLAST");
        hard_reset();
        send_beat(8'h00, 1'b1, 1'b0);
        send_beat(8'h02, 1'b0, 1'b1);
        expect_error(ERR_EARLY_TLAST);
        clear_error_pulse();
        reset_scoreboard();
        send_frame();
        wait_done(1);

        $display("TEST 5: missing TLAST at line end");
        hard_reset();
        send_beat(8'h01, 1'b1, 1'b0);
        send_beat(8'h02, 1'b0, 1'b0);
        send_beat(8'h03, 1'b0, 1'b0);
        send_beat(8'h04, 1'b0, 1'b0);
        send_beat(8'h05, 1'b0, 1'b0);
        expect_error(ERR_MISSING_TLAST);
        clear_error_pulse();
        reset_scoreboard();
        send_frame();
        wait_done(1);

        $display("TEST 6: data after frame end without a new SOF");
        hard_reset();
        reset_scoreboard();
        send_frame();
        wait_done(1);
        saw_done = 1'b0;
        saw_error = 1'b0;
        check_frame_data = 1'b0;
        send_beat(8'h55, 1'b0, 1'b0);
        expect_error(ERR_TOO_MANY_LINES);

        $display("TEST 7: disable and soft reset abandon partial frames");
        hard_reset();
        send_beat(8'h00, 1'b1, 1'b0);
        @(negedge video_aclk);
        enable = 1'b0;
        repeat (2) begin
            @(posedge video_aclk);
            if (m_axis_tvalid) fail("TVALID asserted while disabled");
        end
        @(negedge video_aclk);
        enable = 1'b1;
        reset_scoreboard();
        send_frame();
        wait_done(1);
        send_beat(8'h00, 1'b1, 1'b0);
        @(negedge video_aclk);
        soft_reset = 1'b1;
        repeat (2) begin
            @(posedge video_aclk);
            if (m_axis_tvalid) fail("TVALID asserted during soft reset");
        end
        @(negedge video_aclk);
        soft_reset = 1'b0;
        reset_scoreboard();
        send_frame();
        wait_done(2);

        $display("TEST 8: hard reset clears frame count");
        @(negedge video_aclk);
        video_aresetn = 1'b0;
        repeat (2) @(posedge video_aclk);
        if (frame_cnt != 0) fail("hard reset did not clear frame count");
        $display("FORMAL_PL_VIDEO_IN_PROTOCOL_TEST %s", failures == 0 ? "PASS" : "FAIL");
        if (failures != 0) $fatal(1, "failures=%0d", failures);
        $finish;
    end

    initial begin
        #2000000;
        $fatal(1, "simulation timeout");
    end
endmodule
