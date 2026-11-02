`timescale 1ns/1ps

module tb_pl_preproc_letterbox_protocol;

    localparam integer INPUT_WIDTH = 640;
    localparam integer INPUT_HEIGHT = 480;
    localparam integer OUTPUT_WIDTH = 640;
    localparam integer OUTPUT_HEIGHT = 640;
    localparam integer PAD_TOP = 80;
    localparam integer PAD_VALUE = 114;
    localparam integer OUTPUT_PIXELS = OUTPUT_WIDTH * OUTPUT_HEIGHT;

    logic aclk;
    logic aresetn;
    logic [7:0] s_axis_tdata;
    logic s_axis_tvalid;
    logic s_axis_tready;
    logic s_axis_tlast;
    logic s_axis_tuser;
    logic [23:0] m_axis_tdata;
    logic m_axis_tvalid;
    logic m_axis_tready;
    logic m_axis_tlast;
    logic m_axis_tuser;
    logic error;
    logic out_frame_start;
    logic out_frame_done;

    integer test_errors;
    integer output_count;
    integer output_row;
    integer output_col;
    integer sof_count;
    integer eol_count;
    integer frame_start_count;
    integer frame_done_count;
    integer ready_phase;
    integer timeout_count;
    integer pixel_index;
    logic check_output_data;
    logic expected_start_level;
    logic expected_done_level;

    pl_preproc_letterbox dut (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tuser(s_axis_tuser),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast),
        .m_axis_tuser(m_axis_tuser),
        .error(error),
        .out_frame_start(out_frame_start),
        .out_frame_done(out_frame_done)
    );

    initial begin
        aclk = 1'b0;
        forever #5 aclk = ~aclk;
    end

    // Deterministic backpressure makes every regression repeatable while
    // exercising single-cycle and consecutive stalls.
    always @(negedge aclk) begin
        if (!aresetn) begin
            m_axis_tready <= 1'b0;
            ready_phase = 0;
        end else begin
            m_axis_tready <= ((ready_phase % 11) != 3) &&
                             ((ready_phase % 11) != 4) &&
                             ((ready_phase % 17) != 9);
            ready_phase = ready_phase + 1;
        end
    end

    function automatic [7:0] input_pixel(
        input integer row,
        input integer col
    );
        input_pixel = (row + col) & 8'hff;
    endfunction

    task automatic apply_reset;
        begin
            @(negedge aclk);
            aresetn = 1'b0;
            s_axis_tvalid = 1'b0;
            s_axis_tdata = 8'd0;
            s_axis_tlast = 1'b0;
            s_axis_tuser = 1'b0;
            repeat (5) @(posedge aclk);
            @(negedge aclk);
            aresetn = 1'b1;
            repeat (2) @(posedge aclk);
        end
    endtask

    task automatic send_pixel(
        input [7:0] data,
        input logic user_value,
        input logic last_value
    );
        logic accepted;
        begin
            @(negedge aclk);
            s_axis_tdata = data;
            s_axis_tuser = user_value;
            s_axis_tlast = last_value;
            s_axis_tvalid = 1'b1;
            accepted = 1'b0;
            while (!accepted) begin
                @(posedge aclk);
                accepted = s_axis_tready;
            end
            @(negedge aclk);
            s_axis_tvalid = 1'b0;
            s_axis_tuser = 1'b0;
            s_axis_tlast = 1'b0;
        end
    endtask

    task automatic send_valid_frame;
        integer row;
        integer col;
        begin
            for (row = 0; row < INPUT_HEIGHT; row = row + 1) begin
                for (col = 0; col < INPUT_WIDTH; col = col + 1) begin
                    send_pixel(
                        input_pixel(row, col),
                        row == 0 && col == 0,
                        col == INPUT_WIDTH - 1
                    );
                end
            end
        end
    endtask

    task automatic wait_for_error(input integer limit);
        begin
            timeout_count = 0;
            while (!error && timeout_count < limit) begin
                @(posedge aclk);
                timeout_count = timeout_count + 1;
            end
            if (!error) begin
                $display("ERROR: 等待协议错误超时");
                test_errors = test_errors + 1;
            end
        end
    endtask

    always @(posedge aclk) begin
        if (!aresetn) begin
            output_count = 0;
            output_row = 0;
            output_col = 0;
            sof_count = 0;
            eol_count = 0;
            frame_start_count = 0;
            frame_done_count = 0;
            expected_start_level = 1'b0;
            expected_done_level = 1'b0;
        end else begin
            expected_start_level = 1'b0;
            expected_done_level = 1'b0;

            if (out_frame_start)
                frame_start_count = frame_start_count + 1;
            if (out_frame_done)
                frame_done_count = frame_done_count + 1;

            if (m_axis_tvalid && m_axis_tready) begin
                expected_start_level = (output_row == 0 && output_col == 0);
                expected_done_level =
                    (output_row == OUTPUT_HEIGHT - 1 &&
                     output_col == OUTPUT_WIDTH - 1);

                if (m_axis_tuser)
                    sof_count = sof_count + 1;
                if (m_axis_tlast)
                    eol_count = eol_count + 1;

                if (m_axis_tuser !==
                    (output_row == 0 && output_col == 0)) begin
                    $display("ERROR: 输出SOF位置错误 row=%0d col=%0d",
                        output_row, output_col);
                    test_errors = test_errors + 1;
                end

                if (m_axis_tlast !==
                    (output_col == OUTPUT_WIDTH - 1)) begin
                    $display("ERROR: 输出EOL位置错误 row=%0d col=%0d",
                        output_row, output_col);
                    test_errors = test_errors + 1;
                end

                if (check_output_data) begin
                    if (output_row < PAD_TOP ||
                        output_row >= PAD_TOP + INPUT_HEIGHT) begin
                        if (m_axis_tdata !==
                            {8'd114, 8'd114, 8'd114}) begin
                            $display("ERROR: 补边像素错误 row=%0d col=%0d data=%h",
                                output_row, output_col, m_axis_tdata);
                            test_errors = test_errors + 1;
                        end
                    end else begin
                        pixel_index = input_pixel(
                            output_row - PAD_TOP, output_col);
                        if (m_axis_tdata !==
                            {pixel_index[7:0], pixel_index[7:0],
                             pixel_index[7:0]}) begin
                            $display("ERROR: 图像像素错误 row=%0d col=%0d data=%h",
                                output_row, output_col, m_axis_tdata);
                            test_errors = test_errors + 1;
                        end
                    end
                end

                output_count = output_count + 1;
                if (output_col == OUTPUT_WIDTH - 1) begin
                    output_col = 0;
                    output_row = output_row + 1;
                end else begin
                    output_col = output_col + 1;
                end
            end
        end
    end

    // Registered frame-event outputs must correspond to the transfer sampled
    // on the immediately preceding rising edge.
    always @(negedge aclk) begin
        if (aresetn) begin
            assert (out_frame_start === expected_start_level)
            else begin
                $display("ERROR: out_frame_start与帧首握手不一致");
                test_errors = test_errors + 1;
            end
            assert (out_frame_done === expected_done_level)
            else begin
                $display("ERROR: out_frame_done与帧末握手不一致");
                test_errors = test_errors + 1;
            end
        end
    end

    initial begin
        aresetn = 1'b0;
        s_axis_tdata = 8'd0;
        s_axis_tvalid = 1'b0;
        s_axis_tlast = 1'b0;
        s_axis_tuser = 1'b0;
        m_axis_tready = 1'b0;
        check_output_data = 1'b0;
        test_errors = 0;
        ready_phase = 0;

        // 正常帧、随机式周期反压、像素和帧事件。
        apply_reset;
        check_output_data = 1'b1;
        $display("开始Letterbox正常帧和帧事件测试...");
        send_valid_frame;
        timeout_count = 0;
        while (output_count < OUTPUT_PIXELS && timeout_count < 2000000) begin
            @(posedge aclk);
            timeout_count = timeout_count + 1;
        end
        repeat (3) @(posedge aclk);
        #1;

        if (output_count != OUTPUT_PIXELS || sof_count != 1 ||
            eol_count != OUTPUT_HEIGHT || frame_start_count != 1 ||
            frame_done_count != 1 || error) begin
            $display("ERROR: 正常帧统计 pixels=%0d sof=%0d eol=%0d start=%0d done=%0d error=%b",
                output_count, sof_count, eol_count, frame_start_count,
                frame_done_count, error);
            test_errors = test_errors + 1;
        end

        // 输出过程中硬复位必须放弃未完成帧并回到空闲状态。
        apply_reset;
        check_output_data = 1'b0;
        send_pixel(8'h22, 1'b1, 1'b0);
        repeat (25) @(posedge aclk);
        apply_reset;
        if (error || !s_axis_tready || m_axis_tvalid ||
            out_frame_start || out_frame_done) begin
            $display("ERROR: 中途复位后状态不正确");
            test_errors = test_errors + 1;
        end

        // 首像素缺少SOF。
        apply_reset;
        send_pixel(8'h11, 1'b0, 1'b0);
        wait_for_error(20);
        repeat (4) @(posedge aclk);
        if (!error || s_axis_tready || m_axis_tvalid) begin
            $display("ERROR: 缺SOF没有进入保持型错误状态");
            test_errors = test_errors + 1;
        end
        apply_reset;
        if (error || !s_axis_tready) begin
            $display("ERROR: 硬复位未清除缺SOF错误");
            test_errors = test_errors + 1;
        end

        // 第一行首像素提前给出TLAST。
        apply_reset;
        send_pixel(8'h33, 1'b1, 1'b1);
        wait_for_error(100000);
        repeat (4) @(posedge aclk);
        if (!error || s_axis_tready || m_axis_tvalid) begin
            $display("ERROR: 提前TLAST没有进入保持型错误状态");
            test_errors = test_errors + 1;
        end
        apply_reset;

        // 第一行第640个像素缺少TLAST。
        for (pixel_index = 0; pixel_index < INPUT_WIDTH;
             pixel_index = pixel_index + 1) begin
            send_pixel(pixel_index[7:0], pixel_index == 0, 1'b0);
        end
        wait_for_error(100000);
        repeat (4) @(posedge aclk);
        if (!error || s_axis_tready || m_axis_tvalid) begin
            $display("ERROR: 缺失TLAST没有进入保持型错误状态");
            test_errors = test_errors + 1;
        end
        apply_reset;

        if (test_errors == 0) begin
            $display("========================================");
            $display("LETTERBOX PROTOCOL TEST PASS");
            $display("normal_pixels=%0d sof=1 eol=640 start=1 done=1",
                OUTPUT_PIXELS);
            $display("========================================");
        end else begin
            $display("LETTERBOX PROTOCOL TEST FAIL errors=%0d", test_errors);
            $fatal(1, "LETTERBOX PROTOCOL TEST FAIL errors=%0d", test_errors);
        end

        $finish;
    end

    initial begin
        #200000000;
        $fatal(1, "LETTERBOX PROTOCOL TEST TIMEOUT");
    end

endmodule
