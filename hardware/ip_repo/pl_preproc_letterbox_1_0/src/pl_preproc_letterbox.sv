`timescale 1ns/1ps

module pl_preproc_letterbox (
    input  logic        aclk,
    input  logic        aresetn,

    // 输入 AXI4-Stream
    // 每个像素为 8bit 灰度值
    input  logic [7:0]  s_axis_tdata,
    input  logic        s_axis_tvalid,
    output logic        s_axis_tready,
    input  logic        s_axis_tlast,
    input  logic        s_axis_tuser,

    // 输出 AXI4-Stream
    // 每个像素为 RGB888
    output logic [23:0] m_axis_tdata,
    output logic        m_axis_tvalid,
    input  logic        m_axis_tready,
    output logic        m_axis_tlast,
    output logic        m_axis_tuser,

    // 错误状态
    output logic        error,

    // 以 640x640 RGB888 输出流为准的帧级事件
    output logic        out_frame_start,
    output logic        out_frame_done
);

    // 输入图像尺寸
    localparam int INPUT_WIDTH  = 640;
    localparam int INPUT_HEIGHT = 480;

    // 输出图像尺寸
    localparam int OUTPUT_WIDTH  = 640;
    localparam int OUTPUT_HEIGHT = 640;

    // 上下补边尺寸
    localparam int PAD_TOP    = 80;
    localparam int PAD_BOTTOM = 80;

    // 补边灰度值
    localparam logic [7:0] PAD_VALUE = 8'd114;

    // 状态机
    typedef enum logic [2:0] {
        ST_IDLE,
        ST_TOP_PAD,
        ST_IMAGE,
        ST_BOTTOM_PAD,
        ST_ERROR
    } state_t;

    state_t state;

    // 输入缓存
    // 采用一个像素的缓存，避免输入数据在输出补边期间丢失
    logic [7:0] input_pixel_buf;
    logic        input_pixel_last;
    logic        input_buf_valid;

    // 补边阶段的行列计数
    logic [9:0] pad_row;
    logic [9:0] pad_col;

    // 有效图像阶段的行列计数
    logic [9:0] image_row;
    logic [9:0] image_col;

    // 灰度值复制为 RGB888
    logic [23:0] image_rgb;
    logic [23:0] pad_rgb;

    assign image_rgb = {
        input_pixel_buf,
        input_pixel_buf,
        input_pixel_buf
    };

    assign pad_rgb = {
        PAD_VALUE,
        PAD_VALUE,
        PAD_VALUE
    };

    // AXI4-Stream 输出组合逻辑
    always_comb begin
        // 默认输出
        m_axis_tdata  = 24'd0;
        m_axis_tvalid = 1'b0;
        m_axis_tlast  = 1'b0;
        m_axis_tuser  = 1'b0;

        // 默认不接收输入
        s_axis_tready = 1'b0;

        // 默认错误状态
        error = 1'b0;

        case (state)

            // 等待输入帧开始
            ST_IDLE: begin
                // 只允许接收一帧的第一个像素
                s_axis_tready = 1'b1;
            end

            // 输出顶部80行灰色补边
            ST_TOP_PAD: begin
                m_axis_tdata  = pad_rgb;
                m_axis_tvalid = 1'b1;

                // 每行最后一个像素
                m_axis_tlast = (
                    pad_col == OUTPUT_WIDTH - 1
                );

                // 输出帧第一个像素
                m_axis_tuser = (
                    pad_row == 0 &&
                    pad_col == 0
                );
            end

            // 输出中间的有效图像
            ST_IMAGE: begin
                // 当前缓存中有一个输入像素时才输出
                m_axis_tvalid = input_buf_valid;
                m_axis_tdata  = image_rgb;

                // 输出行结束信号
                m_axis_tlast = (
                    image_col == INPUT_WIDTH - 1
                );

                // IMAGE 阶段不会产生新的帧开始信号
                m_axis_tuser = 1'b0;

                // 缓存为空时允许接收一个新像素
                // 如果缓存有数据，必须先输出后再接收
                s_axis_tready = !input_buf_valid;
            end

            // 输出底部80行灰色补边
            ST_BOTTOM_PAD: begin
                m_axis_tdata  = pad_rgb;
                m_axis_tvalid = 1'b1;

                m_axis_tlast = (
                    pad_col == OUTPUT_WIDTH - 1
                );

                m_axis_tuser = 1'b0;
            end

            // 错误状态
            ST_ERROR: begin
                m_axis_tdata  = 24'd0;
                m_axis_tvalid = 1'b0;
                m_axis_tlast  = 1'b0;
                m_axis_tuser  = 1'b0;
                s_axis_tready = 1'b0;
                error         = 1'b1;
            end

            default: begin
                m_axis_tdata  = 24'd0;
                m_axis_tvalid = 1'b0;
                m_axis_tlast  = 1'b0;
                m_axis_tuser  = 1'b0;
                s_axis_tready = 1'b0;
            end

        endcase
    end


    // 状态机和计数器
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            state            <= ST_IDLE;

            input_pixel_buf  <= 8'd0;
            input_pixel_last <= 1'b0;
            input_buf_valid  <= 1'b0;

            pad_row          <= 10'd0;
            pad_col          <= 10'd0;

            image_row        <= 10'd0;
            image_col        <= 10'd0;

            out_frame_start  <= 1'b0;
            out_frame_done   <= 1'b0;
        end
        else begin

            // 默认无帧级事件；发生时仅保持一个时钟周期
            out_frame_start <= 1'b0;
            out_frame_done  <= 1'b0;

            case (state)

                // 等待输入帧的第一个像素
                ST_IDLE: begin
                    if (
                        s_axis_tvalid &&
                        s_axis_tready
                    ) begin
                        // 第一个输入像素必须带 TUSER
                        if (s_axis_tuser) begin
                            input_pixel_buf  <= s_axis_tdata;
                            input_pixel_last <= s_axis_tlast;
                            input_buf_valid  <= 1'b1;

                            pad_row <= 10'd0;
                            pad_col <= 10'd0;

                            image_row <= 10'd0;
                            image_col <= 10'd0;

                            // 先输出顶部补边
                            state <= ST_TOP_PAD;
                        end
                        else begin
                            // 没有 TUSER，说明不是一帧的开始
                            state <= ST_ERROR;
                        end
                    end
                end


                // 输出顶部80行补边
                ST_TOP_PAD: begin
                    if (
                        m_axis_tvalid &&
                        m_axis_tready
                    ) begin
                        if (pad_row == 0 && pad_col == 0) begin
                            out_frame_start <= 1'b1;
                        end

                        if (pad_col == OUTPUT_WIDTH - 1) begin
                            pad_col <= 10'd0;

                            if (pad_row == PAD_TOP - 1) begin
                                // 顶部补边完成
                                // 开始输出有效图像
                                state <= ST_IMAGE;

                                image_row <= 10'd0;
                                image_col <= 10'd0;
                            end
                            else begin
                                pad_row <= pad_row + 1'b1;
                            end
                        end
                        else begin
                            pad_col <= pad_col + 1'b1;
                        end
                    end
                end


                // 输出中间480行有效图像
                ST_IMAGE: begin

                    // 接收新的输入像素
                    if (
                        s_axis_tvalid &&
                        s_axis_tready
                    ) begin
                        input_pixel_buf  <= s_axis_tdata;
                        input_pixel_last <= s_axis_tlast;
                        input_buf_valid  <= 1'b1;
                    end

                    // 输出当前缓存中的像素
                    if (
                        m_axis_tvalid &&
                        m_axis_tready
                    ) begin

                        // 每行最后一个像素必须带 TLAST
                        if (
                            image_col == INPUT_WIDTH - 1 &&
                            !input_pixel_last
                        ) begin
                            state <= ST_ERROR;
                            input_buf_valid <= 1'b0;
                        end

                        // 非行尾像素不能带 TLAST
                        else if (
                            image_col != INPUT_WIDTH - 1 &&
                            input_pixel_last
                        ) begin
                            state <= ST_ERROR;
                            input_buf_valid <= 1'b0;
                        end

                        // 当前像素正常输出
                        else begin
                            input_buf_valid <= 1'b0;

                            if (image_col == INPUT_WIDTH - 1) begin
                                image_col <= 10'd0;

                                if (image_row == INPUT_HEIGHT - 1) begin
                                    // 最后一行输出完成
                                    state <= ST_BOTTOM_PAD;

                                    pad_row <= 10'd0;
                                    pad_col <= 10'd0;
                                end
                                else begin
                                    image_row <= image_row + 1'b1;
                                end
                            end
                            else begin
                                image_col <= image_col + 1'b1;
                            end
                        end
                    end
                end


                // 输出底部80行补边
                ST_BOTTOM_PAD: begin
                    if (
                        m_axis_tvalid &&
                        m_axis_tready
                    ) begin
                        if (pad_col == OUTPUT_WIDTH - 1) begin
                            pad_col <= 10'd0;

                            if (pad_row == PAD_BOTTOM - 1) begin
                                // 一帧完成
                                state <= ST_IDLE;
                                pad_row <= 10'd0;
                                out_frame_done <= 1'b1;
                            end
                            else begin
                                pad_row <= pad_row + 1'b1;
                            end
                        end
                        else begin
                            pad_col <= pad_col + 1'b1;
                        end
                    end
                end


                // 错误状态
                ST_ERROR: begin
                    // 只有复位后才能重新开始
                    state <= ST_ERROR;

                    input_buf_valid <= 1'b0;

                    pad_row <= 10'd0;
                    pad_col <= 10'd0;

                    image_row <= 10'd0;
                    image_col <= 10'd0;
                end


                default: begin
                    state <= ST_IDLE;
                    input_buf_valid <= 1'b0;
                end

            endcase
        end
    end

endmodule
