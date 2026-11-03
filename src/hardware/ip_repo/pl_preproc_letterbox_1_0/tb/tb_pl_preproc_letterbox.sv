`timescale 1ns/1ps

module tb_pl_preproc_letterbox;

    logic        aclk;
    logic        aresetn;

    logic [7:0]  s_axis_tdata;
    logic        s_axis_tvalid;
    logic        s_axis_tready;
    logic        s_axis_tlast;
    logic        s_axis_tuser;

    logic [23:0] m_axis_tdata;
    logic        m_axis_tvalid;
    logic        m_axis_tready;
    logic        m_axis_tlast;
    logic        m_axis_tuser;

    logic        error;

    integer input_row;
    integer input_col;
    integer output_row;
    integer output_col;
    integer error_count;
    integer output_count;
    integer timeout_count;
    integer rtl_fd;
    integer stability_error_count;
    logic        previous_output_stall;
    logic [23:0] held_output_data;
    logic        held_output_last;
    logic        held_output_user;

    localparam integer INPUT_WIDTH  = 640;
    localparam integer INPUT_HEIGHT = 480;
    localparam integer OUTPUT_WIDTH = 640;
    localparam integer OUTPUT_HEIGHT = 640;
    localparam integer PADDING_TOP  = 80;
    localparam integer PADDING_BOTTOM = 80;
    localparam integer PADDING_VALUE = 114;

    pl_preproc_letterbox dut (
        .aclk           (aclk),
        .aresetn        (aresetn),

        .s_axis_tdata   (s_axis_tdata),
        .s_axis_tvalid  (s_axis_tvalid),
        .s_axis_tready  (s_axis_tready),
        .s_axis_tlast   (s_axis_tlast),
        .s_axis_tuser   (s_axis_tuser),

        .m_axis_tdata   (m_axis_tdata),
        .m_axis_tvalid  (m_axis_tvalid),
        .m_axis_tready  (m_axis_tready),
        .m_axis_tlast   (m_axis_tlast),
        .m_axis_tuser   (m_axis_tuser),

        .error          (error)
    );

    // 100 MHz 时钟
    initial begin
        aclk = 1'b0;
        forever #5 aclk = ~aclk;
    end

    // 输出端始终准备好接收数据
    // assign m_axis_tready = 1'b1;

    // 换个测试，看看axi
    initial begin
    m_axis_tready = 1'b1;

    forever begin
        @(negedge aclk);

        // 随机制造输出端暂停
        if (($urandom % 5) == 0)
            m_axis_tready = 1'b0;
        else
            m_axis_tready = 1'b1;
    end
end

    // AXI4-Stream反压期间，VALID、数据和旁带信号必须保持稳定。
    always @(posedge aclk) begin
        if (!aresetn) begin
            previous_output_stall <= 1'b0;
            held_output_data      <= 24'd0;
            held_output_last      <= 1'b0;
            held_output_user      <= 1'b0;
        end else begin
            if (previous_output_stall) begin
                assert (m_axis_tvalid &&
                        m_axis_tdata === held_output_data &&
                        m_axis_tlast === held_output_last &&
                        m_axis_tuser === held_output_user)
                else begin
                    $display("ERROR: Letterbox输出在反压期间发生变化");
                    stability_error_count = stability_error_count + 1;
                end
            end

            previous_output_stall <= m_axis_tvalid && !m_axis_tready;
            if (m_axis_tvalid && !m_axis_tready) begin
                held_output_data <= m_axis_tdata;
                held_output_last <= m_axis_tlast;
                held_output_user <= m_axis_tuser;
            end
        end
    end

    // 输入图像像素模式：
    // 第 row 行、第 col 列的灰度值为 row + col
    function automatic [7:0] expected_input_pixel(
        input integer row,
        input integer col
    );
        expected_input_pixel = (row + col) & 8'hff;
    endfunction

    // 发送一帧 640x480 灰度图像
    task automatic send_one_frame;
        integer r;
        integer c;
        begin
            for (r = 0; r < INPUT_HEIGHT; r = r + 1) begin
                for (c = 0; c < INPUT_WIDTH; c = c + 1) begin

                    // 等待模块准备接收
                    while (!s_axis_tready) begin
                        @(negedge aclk);
                    end

                    @(negedge aclk);

                    s_axis_tvalid = 1'b1;
                    s_axis_tdata  = expected_input_pixel(r, c);
                    s_axis_tlast  = (c == INPUT_WIDTH - 1);
                    s_axis_tuser  = (r == 0 && c == 0);

                    // 在下一个上升沿完成握手
                    @(posedge aclk);

                    @(negedge aclk);

                    s_axis_tvalid = 1'b0;
                    s_axis_tlast  = 1'b0;
                    s_axis_tuser  = 1'b0;
                end
            end

            @(negedge aclk);

            s_axis_tvalid = 1'b0;
            s_axis_tdata  = 8'd0;
            s_axis_tlast  = 1'b0;
            s_axis_tuser  = 1'b0;
        end
    endtask

    // 输出数据检查
    always @(posedge aclk) begin
        if (aresetn && m_axis_tvalid && m_axis_tready) begin

            // 保存 RTL 输出的 RGB888 数据，供后续与软件金标准逐字节比较
            $fwrite(
                rtl_fd,
                "%c%c%c",
                m_axis_tdata[23:16],
                m_axis_tdata[15:8],
                m_axis_tdata[7:0]
            );

            // 检查 RGB 三个通道是否相同
            if (m_axis_tdata[23:16] != m_axis_tdata[15:8] ||
                m_axis_tdata[15:8]  != m_axis_tdata[7:0]) begin

                $display(
                    "ERROR: RGB不相同，row=%0d col=%0d data=%h",
                    output_row,
                    output_col,
                    m_axis_tdata
                );

                error_count = error_count + 1;
            end

            // 检查补边区域或图像区域的像素值
            if (output_row < PADDING_TOP ||
                output_row >= PADDING_TOP + INPUT_HEIGHT) begin

                // 上下补边必须为 114
                if (m_axis_tdata != {8'd114, 8'd114, 8'd114}) begin
                    $display(
                        "ERROR: 补边错误，row=%0d col=%0d data=%h",
                        output_row,
                        output_col,
                        m_axis_tdata
                    );

                    error_count = error_count + 1;
                end

            end else begin

                // 中间区域应该对应输入图像
                input_row = output_row - PADDING_TOP;
                input_col = output_col;

                if (m_axis_tdata != {
                    expected_input_pixel(input_row, input_col),
                    expected_input_pixel(input_row, input_col),
                    expected_input_pixel(input_row, input_col)
                }) begin

                    $display(
                        "ERROR: 图像区域错误，out_row=%0d out_col=%0d data=%h expected=%h",
                        output_row,
                        output_col,
                        m_axis_tdata,
                        {
                            expected_input_pixel(input_row, input_col),
                            expected_input_pixel(input_row, input_col),
                            expected_input_pixel(input_row, input_col)
                        }
                    );

                    error_count = error_count + 1;
                end
            end

            // 每行最后一个像素必须有 TLAST
            if (m_axis_tlast != (output_col == OUTPUT_WIDTH - 1)) begin
                $display(
                    "ERROR: TLAST错误，row=%0d col=%0d tlast=%b",
                    output_row,
                    output_col,
                    m_axis_tlast
                );

                error_count = error_count + 1;
            end

            // 只有第一帧第一个像素允许 TUSER 为 1
            if (m_axis_tuser !=
                (output_row == 0 && output_col == 0)) begin

                $display(
                    "ERROR: TUSER错误，row=%0d col=%0d tuser=%b",
                    output_row,
                    output_col,
                    m_axis_tuser
                );

                error_count = error_count + 1;
            end

            output_count = output_count + 1;

            // 更新输出坐标
            if (output_col == OUTPUT_WIDTH - 1) begin
                output_col = 0;
                output_row = output_row + 1;
            end else begin
                output_col = output_col + 1;
            end
        end
    end

    // 测试主流程
    initial begin
        rtl_fd = $fopen("fpga/preproc/golden/rtl_rgb.bin", "wb");

        if (rtl_fd == 0) begin
            $display("ERROR: 无法创建 RTL 输出文件");
            $fatal(1, "无法创建 RTL 输出文件");
        end

        s_axis_tdata  = 8'd0;
        s_axis_tvalid = 1'b0;
        s_axis_tlast  = 1'b0;
        s_axis_tuser  = 1'b0;

        output_row   = 0;
        output_col   = 0;
        output_count = 0;
        error_count  = 0;
        stability_error_count = 0;

        // 复位
        aresetn = 1'b0;

        repeat (10) begin
            @(posedge aclk);
        end

        aresetn = 1'b1;

        // 等待一个时钟
        @(posedge aclk);

        $display("开始发送 640x480 灰度测试图像...");
        send_one_frame;
        $display("输入图像发送完成，等待输出...");

        // 最多等待 2,000,000 个时钟周期
        timeout_count = 0;
        while (output_count < OUTPUT_WIDTH * OUTPUT_HEIGHT &&
               timeout_count < 2000000) begin
            @(posedge aclk);
            timeout_count = timeout_count + 1;
        end

        if (error) begin
            $display("ERROR: RTL模块报告 error=1");
            error_count = error_count + 1;
        end

        if (error_count == 0 &&
            stability_error_count == 0 &&
            output_count == OUTPUT_WIDTH * OUTPUT_HEIGHT) begin

            $display("========================================");
            $display("TEST PASS");
            $display("输出像素数: %0d", output_count);
            $display("错误数量:   %0d", error_count);
            $display("反压断言错误: %0d", stability_error_count);
            $display("========================================");

        end else begin

            $display("========================================");
            $display("TEST FAIL");
            $display("输出像素数: %0d / %0d",
                     output_count,
                     OUTPUT_WIDTH * OUTPUT_HEIGHT);
            $display("错误数量:   %0d", error_count);
            $display("反压断言错误: %0d", stability_error_count);
            $display("========================================");
            $fclose(rtl_fd);
            $fatal(1,
                "LETTERBOX TEST FAIL errors=%0d stability=%0d outputs=%0d",
                error_count, stability_error_count, output_count);
        end

        $fclose(rtl_fd);
        $finish;
    end

endmodule
