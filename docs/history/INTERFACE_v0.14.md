# FPGA System Interface Definition

> Project: Infrared Tank Target Detection and Tracking Acceleration System
> Board: ZCU104 Evaluation Kit
> Device: Zynq UltraScale+ MPSoC ZU7EV
> Stage: V3.2 PL system integration
> Version: v0.4
> Date: 2026-09-17
> Owner: 乙

---

## 1. Interface Overview

本版本在最小 FPGA 系统骨架基础上，冻结 V3.2 的视频输入、三缓冲、请求/结果邮箱、序号、原子提交和保持型中断接口。

乙负责 PL 系统架构、`pl_video_in`、AXI-Lite、三缓冲、Fresh-Frame、CDC、XDC 和 Vivado 集成。乙不重复实现甲负责的 Letterbox、SAD 或融合算法，也不实现丙负责的 DPU 推理、NMS 和 OSD 算法。

系统结构：

```text
                    PS / ARM
                       |
                       | AXI4-Lite
                       v
                +---------------+
                |  pl_sys_ctrl  |
                +---------------+
                       ^
                       |
              frame_done_pulse
                       |
                       |
                +---------------+
                |  pl_video_in  |
                +---------------+
                       |
                       | AXI4-Stream
                       v
              pl_preproc_letterbox
                        |
                        v
                三缓冲 / Fresh-Frame
                        |
              DPU 请求/结果邮箱
```

本版本主要接口：

```text
1. PS <-> pl_sys_ctrl
      AXI4-Lite

2. `pl_video_in` <-> `pl_preproc_letterbox`
      AXI4-Stream

3. PL 调度器 <-> `pl_sys_ctrl`
      请求/结果邮箱及序号

4. `pl_sys_ctrl` -> PS
      保持型 IRQ
```

---

# 2. AXI4-Lite Register Interface

## 2.1 Register Map

`pl_sys_ctrl` 使用 AXI4-Lite 接口与 PS/PYNQ 通信。

| Offset | Register | PS access | Description |
|---:|---|:---:|---|
| `0x00` | CTRL | RW | 基础控制 |
| `0x04` | STATUS | RO | 当前及保持型系统状态 |
| `0x08` | FRAME_CNT | RO | 完整有效帧计数 |
| `0x0C` | ERR_CODE | RO | 最近一次错误代码 |
| `0x10` | REQUEST_SEQ | RO | PL已提交请求序号 |
| `0x14` | REQUEST_FRAME_ID | RO | 请求帧号 |
| `0x18` | REQUEST_BUFFER_ID | RO | 请求缓冲区编号 |
| `0x1C` | REQUEST_GENERATION | RO | 缓冲区复用代次 |
| `0x20` | REQUEST_REASON | RO | DPU请求原因 |
| `0x24` | REQUEST_STATUS | RO | 请求邮箱状态 |
| `0x28` | REQUEST_TIMESTAMP | RO | 请求时间戳/周期计数，可暂为0 |
| `0x2C` | RESERVED | - | 保留 |
| `0x30` | RESULT_SHADOW_FRAME_ID | RW | 结果影子帧号 |
| `0x34` | RESULT_SHADOW_BUFFER_ID | RW | 结果影子缓冲区编号 |
| `0x38` | RESULT_SHADOW_GENERATION | RW | 结果影子代次 |
| `0x3C` | RESULT_SHADOW_BBOX_X | RW | 结果影子框X |
| `0x40` | RESULT_SHADOW_BBOX_Y | RW | 结果影子框Y |
| `0x44` | RESULT_SHADOW_BBOX_W | RW | 结果影子框宽度 |
| `0x48` | RESULT_SHADOW_BBOX_H | RW | 结果影子框高度 |
| `0x4C` | RESULT_SHADOW_CONFIDENCE | RW | 结果影子置信度 |
| `0x50` | RESULT_SHADOW_STATUS | RW | 结果影子状态 |
| `0x54` | RESULT_COMMIT | WO/W1P | 原子提交结果 |
| `0x58` | RESULT_SEQ | RO | PL已提交结果序号 |
| `0x5C` | RESULT_STATUS | RO | 当前有效结果状态 |
| `0x60` | IRQ_STATUS | RO | 保持型中断状态 |
| `0x64` | IRQ_ACK | WO/W1C | 写1确认并清除中断 |
| `0x68` | IRQ_ENABLE | RW | 中断源使能 |
| `0x6C` | VERSION | RO | 接口版本，建议为 `0x00020000` |
| `0x70-0x7C` | RESERVED | - | 预留 |

其中：

```text
RW = Read / Write
RO = Read Only
WO = Write Only
W1P = Write 1 Pulse，写1产生一次动作
W1C = Write 1 Clear，写1清除保持状态
```

寄存器偏移量相对于 Vivado Address Editor 分配的 AXI-Lite 基地址；本文不规定绝对物理地址。由于地址范围扩展，IP 的 `C_S_AXI_ADDR_WIDTH` 应至少为 8，RTL 地址译码不能继续只使用 `axi_awaddr[3:2]` 和 `axi_araddr[3:2]`。

---

# 3. CTRL Register

## 3.1 Basic Information

```text
Address : 0x00
Access  : RW
Name    : CTRL
```

## 3.2 Bit Definition

|  Bit | Name        | Access | Description        |
| ---: | ----------- | :----: | ------------------ |
|    0 | enable      |   RW   | 启动/停止当前PL视频处理路径 |
|    1 | soft_reset  |   RW   | 请求系统软复位            |
|    2 | clear_error |   RW   | 清除错误状态/错误计数        |
| 31:3 | Reserved    |    -   | 保留，写 0             |

寄存器结构：

```text
31                       3 2           1           0
+-------------------------+-------------+-----------+
|        Reserved         |clear_error  |soft_reset |enable
+-------------------------+-------------+-----------+
```

## 3.3 Control Values

```text
CTRL = 0x00
    enable = 0
    系统停止

CTRL = 0x01
    enable = 1
    启动 dummy stream

CTRL = 0x02
    soft_reset = 1
    请求一次软复位

CTRL = 0x04
    clear_error = 1
    请求清除错误状态/错误计数
```

## 3.4 Pulse-Type Control

`soft_reset` 和 `clear_error` 为写 1 触发型控制位。

期望行为：

```text
CPU/PYNQ 写入：

CTRL = 0x02

        |
        v

触发 soft_reset

        |
        v

soft_reset 自动恢复为 0
```

同理：

```text
CTRL = 0x04

        |
        v

触发 clear_error

        |
        v

clear_error 自动恢复为 0
```

`enable` 为持续状态控制位：

```text
CTRL = 0x01
        |
        v
enable = 1
        |
        v
dummy_stream_gen 工作

CTRL = 0x00
        |
        v
enable = 0
        |
        v
dummy_stream_gen 停止
```

推荐约定：`soft_reset` 清除当前未完成帧、回到 `WAIT_SOF`，但保持 `FRAME_CNT` 和已经提交的请求/结果序号，便于系统累计统计。

---

# 4. STATUS Register

## 4.1 Basic Information

```text
Address : 0x04
Access  : RO
Name    : STATUS
```

## 4.2 Bit Definition

|  Bit | Name       | Description |
| ---: | ---------- | ----------- |
|    0 | lock       | 已识别并锁定输入格式  |
|    1 | busy       | 正在处理数据      |
|    2 | fifo_ovf   | FIFO 溢出     |
|    3 | fifo_empty | FIFO 当前为空   |
|    4 | frame_done_seen | 至少完整处理过一帧，保持型 |
|    5 | err_sticky | 存在保持型错误 |
|    6 | request_pending | 请求尚未被PS确认 |
|    7 | result_pending | 已提交结果等待PL消费 |
|    8 | irq_pending | 至少一个中断源待确认 |
|    9 | buffer_conflict | 缓冲区所有权冲突 |
|   10 | stale_result | 结果帧/缓冲区/代次不匹配 |
| 31:11 | Reserved | 保留 |

寄存器结构：

```text
31                         6 5       4           3           2           1       0
+---------------------------+---------+-----------+-----------+-----------+-------+
|       Reserved           |err_sticky|frame_done_seen|fifo_empty| fifo_ovf | busy |lock
+---------------------------+---------+-----------+-----------+-----------+-------+
```

## 4.3 Status Description

### bit0: lock

表示系统已经识别并锁定输入格式。

当前 dummy stream 阶段可暂时定义为：

```text
0 = 未锁定
1 = 已锁定
```

### bit1: busy

表示系统当前是否正在处理数据。

```text
0 = 空闲
1 = 正在处理
```

### bit2: fifo_ovf

表示 FIFO 是否发生溢出。

```text
0 = 无溢出
1 = 发生溢出
```

本阶段如果没有实际 FIFO，可以暂时保持为 0。

### bit3: fifo_empty

表示 FIFO 当前是否为空。

```text
0 = 非空
1 = 空
```

本阶段如果没有实际 FIFO，可以暂时保持为 0 或根据后续设计确定。

### bit4: frame_done_seen

表示系统是否至少完整处理过一帧。该位为保持型状态，直到清错误或定义的确认动作才清零。

```text
0 = 尚未完成完整帧
1 = 至少完成过一帧
```

注意：

```text
STATUS.frame_done_seen
```

与内部的：

```text
frame_done_pulse
```

不是完全相同的概念。

内部 `frame_done_pulse` 是一个单周期通知脉冲。

`STATUS[4]` 则表示：

```text
已经发生过完整帧完成事件
```

因此它可以保持为 1。

### bit5: err_sticky

表示系统是否记录过错误。错误码见 `ERR_CODE`，该位保持为 1，直到 `CTRL.clear_error` 或复位。

```text
0 = 无错误
1 = 存在错误
```

---

# 5. FRAME_CNT Register

## 5.1 Basic Information

```text
Address : 0x08
Access  : RO
Name    : FRAME_CNT
```

## 5.2 Definition

`FRAME_CNT` 表示：

```text
PL 已经完整处理完成的帧数量。
```

只有完整的一帧结束后，计数器才增加 1。

```text
FRAME_CNT <= FRAME_CNT + 1
```

## 5.3 Frame Counting Rule

对于 640 × 640 视频流：

```text
SOF
 |
 +--> 640 行
       |
       +--> 每行 640 个像素
                    |
                    +--> 最后一行最后一个像素
                                      |
                                      v
                          frame_done_pulse
                                      |
                                      v
                               FRAME_CNT + 1
```

因此：

```text
完整帧：
FRAME_CNT + 1

半帧：
FRAME_CNT 不增加

未完成帧：
FRAME_CNT 不增加
```

## 5.4 FRAME_CNT Is Not FPS

`FRAME_CNT` 表示累计完成帧数，而不是 FPS。

例如：

```text
第 1 秒：
FRAME_CNT = 20

第 2 秒：
FRAME_CNT = 35
```

则这一秒完成：

```text
35 - 20 = 15 帧
```

约为：

```text
15 FPS
```

---

# 6. AXI4-Stream Interface

## 6.1 Video Stream Format

`pl_video_in` 输入和 `pl_preproc_letterbox` 输出约定：

```text
`pl_video_in` 输入：640 × 480，8-bit 灰度

`pl_preproc_letterbox` 输出：640 × 640，RGB888
```

Letterbox 输出每个像素：

```text
R[7:0]
G[7:0]
B[7:0]
```

总数据宽度：

```text
TDATA = 24 bit
```

---

## 6.2 AXI4-Stream Signals

| Signal | Direction | Description |
| ------ | --------- | ----------- |
| TDATA  | Output    | 当前像素数据      |
| TVALID | Output    | 数据有效        |
| TREADY | Input     | 接收端准备好接收    |
| TUSER  | Output    | 帧开始标志       |
| TLAST  | Output    | 行结束标志       |

---

# 7. AXI4-Stream Handshake

只有以下条件同时满足时，才认为一个像素真正完成传输：

```text
TVALID == 1
AND
TREADY == 1
```

即：

```text
transfer = TVALID && TREADY
```

---

## 7.1 No Backpressure

正常情况下：

```text
TVALID = 1
TREADY = 1
```

每个时钟周期传输一个像素。

---

## 7.2 Backpressure

当：

```text
TVALID = 1
TREADY = 0
```

表示发送端当前有数据，但接收端暂时不能接收。

此时：

```text
TDATA 不变
TUSER 不变
TLAST 不变
像素计数器不增加
行计数器不增加
```

直到：

```text
TREADY = 1
```

恢复正常传输。

---

# 8. TUSER Definition

本项目约定：

```text
TUSER = 1
```

表示：

```text
一帧图像的第一个像素
```

因此每一帧：

```text
TUSER = 1
```

只出现一次。

示意：

```text
Frame Start
    |
    v
TUSER = 1
TDATA  = first pixel
```

其他像素：

```text
TUSER = 0
```

---

# 9. TLAST Definition

本项目约定：

```text
TLAST = 1
```

表示：

```text
当前行的最后一个像素。
```

由于每帧有 640 行，因此正常情况下：

```text
每帧 TLAST = 640 次
```

示意：

```text
第 1 行：
pixel 0 ... pixel 639
                  |
                  +--> TLAST = 1

第 2 行：
pixel 0 ... pixel 639
                  |
                  +--> TLAST = 1

...

第 640 行：
pixel 0 ... pixel 639
                  |
                  +--> TLAST = 1
```

---

# 10. frame_done Definition

## 10.1 Definition

`frame_done_pulse` 是帧处理模块（兼容测试时可由 `dummy_stream_gen` 产生）输出给 `pl_sys_ctrl` 的内部控制信号。

作用：

```text
通知 pl_sys_ctrl：

“一整帧数据已经完整传输完成。”
```

接口：

```text
frame_source.frame_done_pulse
              |
              v
      pl_sys_ctrl.frame_done_pulse
```

---

## 10.2 Trigger Condition

只有以下条件同时满足时，才能产生 `frame_done_pulse`：

```text
当前位于第 640 行
AND
当前像素为第 640 个像素
AND
TVALID == 1
AND
TREADY == 1
```

即：

```text
最后一个像素完成 AXI-Stream 握手
        |
        v
frame_done_pulse = 1
```

---

## 10.3 Pulse Width

`frame_done_pulse` 定义为单周期脉冲：

```text
正常：
frame_done_pulse = 0

最后一个像素完成传输：
frame_done_pulse = 1

下一时钟：
frame_done_pulse = 0
```

示意：

```text
Clock       1   2   3   4   5   6
             ┌───┐
frame_done_pulse ──┘   └──────────
                 ↑
              单周期脉冲
```

---

# 11. Relationship Between TLAST and frame_done

两者不能混淆：

```text
TLAST
    |
    +--> 每一行结束时产生
    |
    +--> 每帧约 640 次


frame_done_pulse
    |
    +--> 整帧结束时产生
    |
    +--> 每帧 1 次
```

因此：

```text
640 × 640 frame

TUSER:
    1 次

TLAST:
    640 次

frame_done_pulse:
    1 次
```

在最后一行最后一个像素上：

```text
TVALID = 1
TREADY = 1
TUSER  = 0
TLAST  = 1
frame_done_pulse = 1
```

---

# 12. Soft Reset Behavior

收到：

```text
CTRL.soft_reset = 1
```

后，系统请求恢复到初始等待状态。

至少应完成：

```text
pixel_count 清零
line_count 清零
stream 状态恢复
等待下一帧开始
```

预期状态：

```text
IDLE / WAIT_SOF
```

关于：

```text
FRAME_CNT
```

软复位后是：

```text
清零
```

还是：

```text
保持
```

当前暂定为：

```text
已确定：保持
```

在甲、丙确认后更新本文件。

---

# 13. Enable Behavior

当：

```text
CTRL.enable = 0
```

系统停止产生有效视频流：

```text
TVALID = 0
```

并且：

```text
FRAME_CNT 停止增加
```

当：

```text
CTRL.enable = 1
```

系统允许当前PL视频处理路径工作。

---

# 14. Dummy Stream Compatibility Test Mode

dummy stream 不是 V3.2 的最终视频输入。为避免把 `pl_video_in` 输入格式和 Letterbox 输出格式混在一起，兼容测试明确分为两个互斥配置。

用于直接测试 `pl_video_in` 的 `dummy_video_in_source` 配置：

```text
Width  = 640 pixels
Height = 480 lines
Format = GRAY8
TDATA  = 8 bit
```

它连接到 `pl_video_in.s_axis_*`，用于验证输入边界检查、AXI4-Stream 反压、错误帧恢复和帧计数。集成模式下由 `pl_video_in` 产生唯一的 `frame_done_pulse`，dummy 源不得同时驱动该信号。

## 14.1 `dummy_video_in_source` Module Boundary

`dummy_video_in_source` 是仅用于系统联调和回归测试的独立自研 IP。它在 PL 内连续产生符合本项目约定的 640x480、GRAY8 纯黑 AXI4-Stream 视频流，用于替代尚未接入的真实摄像头或视频输入源。

该 IP 只负责产生像素数据及帧、行边界：

```text
dummy_video_in_source.m_axis
              |
              | 640x480, GRAY8
              v
       pl_video_in.s_axis
```

该 IP 不执行输入协议检查、Letterbox、灰度转 RGB、帧缓存或 DPU 调度，也不产生 `frame_done_pulse`、`frame_cnt`、`lock`、`busy`、`err` 或 `err_code`。这些状态仍由 `pl_video_in` 产生并连接到 `pl_sys_ctrl`。

## 14.2 Parameters

| Parameter | Type/width | Default | Definition |
|---|---:|---:|---|
| `IMAGE_WIDTH` | positive integer | `640` | 每行像素数；V3.2 集成测试固定为 640 |
| `IMAGE_HEIGHT` | positive integer | `480` | 每帧行数；V3.2 集成测试固定为 480 |
| `PIXEL_VALUE` | 8 bit | `8'h00` | 所有输出像素的灰度值；`8'h00` 表示纯黑 |

用于 `project_1` 集成时必须保持以上默认值。参数化仅用于缩小仿真规模，不改变接口位宽和 AXI4-Stream 语义。

## 14.3 Complete Port Table

以下端口名、方向和位宽作为 `dummy_video_in_source` 首版 RTL 的冻结接口。方向均以 `dummy_video_in_source` 为参照。

| Port | Direction | Width | Clock domain | Definition |
|---|---|---:|---|---|
| `video_aclk` | input | 1 | video | 视频时钟；所有状态和 AXI4-Stream 信号均属于该时钟域 |
| `video_aresetn` | input | 1 | video | 低有效硬复位；作为 `video_aclk` 的关联复位 |
| `enable` | input | 1 | video | 持续型使能；为 1 时允许产生视频流，为 0 时停止并回到帧首 |
| `soft_reset` | input | 1 | video | 高有效软复位；放弃当前未完成帧并回到帧首 |
| `m_axis_tdata` | output | 8 | video | GRAY8 像素；集成配置固定输出 `8'h00` |
| `m_axis_tvalid` | output | 1 | video | 当前 `TDATA/TUSER/TLAST` 有效 |
| `m_axis_tready` | input | 1 | video | 下游已准备接收当前输出拍 |
| `m_axis_tuser` | output | 1 | video | SOF；仅每帧第一个像素为 1 |
| `m_axis_tlast` | output | 1 | video | EOL；仅每行最后一个像素为 1 |

打包为 Vivado IP 时，`m_axis_tdata`、`m_axis_tvalid`、`m_axis_tready`、`m_axis_tuser` 和 `m_axis_tlast` 必须归组为名为 `m_axis` 的 AXI4-Stream master 接口；`video_aclk` 必须关联 `m_axis` 和 `video_aresetn`。

## 14.4 Exact Output Format

内部坐标定义为：

```text
pixel_x = 0 ... IMAGE_WIDTH-1
line_y  = 0 ... IMAGE_HEIGHT-1
```

当前坐标对应的输出必须满足：

```text
m_axis_tdata = PIXEL_VALUE
m_axis_tuser = (pixel_x == 0) && (line_y == 0)
m_axis_tlast = (pixel_x == IMAGE_WIDTH-1)
```

在 640x480 默认配置中，每个完整帧必须包含 307200 个已握手像素、一次 `TUSER=1` 和 480 次 `TLAST=1`。除首像素外 `TUSER` 必须为 0；除每行第 640 个像素外 `TLAST` 必须为 0。

## 14.5 AXI4-Stream Handshake and Backpressure

一个像素仅在以下条件同时成立时完成传输：

```text
transfer = m_axis_tvalid && m_axis_tready
```

只有 `transfer=1` 时，`pixel_x` 和 `line_y` 才能前进：

```text
普通像素握手：pixel_x = pixel_x + 1
行末像素握手：pixel_x = 0，line_y = line_y + 1
帧末像素握手：pixel_x = 0，line_y = 0
```

当 `m_axis_tvalid=1 && m_axis_tready=0` 时，`m_axis_tdata`、`m_axis_tuser`、`m_axis_tlast`、`pixel_x` 和 `line_y` 必须保持不变，直到该拍完成握手。不得因反压丢失、重复或跳过像素和边界标志。

`enable=1`、未复位且下游持续就绪时，`m_axis_tvalid` 应持续为 1。上一帧最后一个像素完成握手后，下一时钟拍直接给出下一帧第一个像素，不强制插入帧间空拍。

## 14.6 Reset and Enable Behavior

控制优先级为：

```text
video_aresetn=0 > soft_reset=1 > enable=0 > AXI4-Stream transfer
```

`video_aresetn=0` 时：

- `pixel_x` 和 `line_y` 清零。
- `m_axis_tvalid=0`。
- 不得发生 AXI4-Stream 传输。

在 `video_aresetn=1` 时检测到 `soft_reset=1`：

- 放弃当前未完成帧，将 `pixel_x` 和 `line_y` 置零。
- `soft_reset=1` 期间 `m_axis_tvalid=0`，不得接收该周期可能存在的 `m_axis_tready`。
- `soft_reset` 释放后，若 `enable=1`，下一有效输出拍必须是新帧首像素，并令 `m_axis_tuser=1`。

`enable=0` 时：

- `m_axis_tvalid=0`。
- 停止输出并将 `pixel_x` 和 `line_y` 保持在零。
- 当前未完成帧直接作废，不产生错误或完成事件。

`enable` 从 0 变为 1 后，第一有效输出拍必须对应坐标 `(0,0)`，输出 `PIXEL_VALUE`，并令 `m_axis_tuser=1`。`enable`、`soft_reset` 和 `video_aresetn` 必须在 `video_aclk` 时钟域内使用；若其来源跨时钟域，必须在模块外完成同步。

## 14.7 Integration Ownership

在 `project_1` 中采用以下唯一连接关系：

```text
pl_sys_ctrl.enable      -> dummy_video_in_source.enable
pl_sys_ctrl.enable      -> pl_video_in.enable
pl_sys_ctrl.soft_reset  -> dummy_video_in_source.soft_reset
pl_sys_ctrl.soft_reset  -> pl_video_in.soft_reset

dummy_video_in_source.m_axis -> pl_video_in.s_axis

pl_video_in.frame_done_pulse -> pl_sys_ctrl.frame_done_pulse
pl_video_in.frame_cnt        -> pl_sys_ctrl.frame_cnt
```

`dummy_video_in_source` 不得直接连接或驱动 `pl_sys_ctrl.frame_done_pulse` 和 `pl_sys_ctrl.frame_cnt`。只有 `pl_video_in` 的最后一个输出像素完成握手后，系统才认为一帧有效完成。

## 14.8 Minimum Verification Items

- [ ] 默认参数下每帧恰好传输 307200 个像素，且所有 `TDATA=8'h00`。
- [ ] 每帧恰好一次 `TUSER=1`，并且只出现在第一个像素。
- [ ] 每帧恰好 480 次 `TLAST=1`，并且只出现在每行第 640 个像素。
- [ ] 计数器只在 `TVALID && TREADY` 时更新。
- [ ] 随机反压期间 `TDATA`、`TUSER`、`TLAST` 和内部坐标保持稳定。
- [ ] `enable=0` 时 `TVALID=0`，重新使能后从新帧首像素开始。
- [ ] 帧中触发 `soft_reset` 时放弃半帧，释放后从新帧首像素开始。
- [ ] 硬复位时 `TVALID=0` 且内部坐标清零。
- [ ] 联合仿真中 `pl_video_in` 不报告协议错误，完整输出一帧后只产生一次 `frame_done_pulse`，且 `frame_cnt` 只增加 1。
- [ ] `frame_done_pulse` 和系统 `frame_cnt` 没有来自 dummy IP 的第二驱动源。

用于绕过 `pl_video_in`、单独测试 Letterbox 下游链路的配置：

```text
Width  = 640 pixels
Height = 640 lines
Format = RGB888
TDATA  = 24 bit
```

该配置只能接到 Letterbox 输出之后的 640x640 RGB888 链路，不能作为 `pl_video_in` 的输入。

`dummy_video_in_source` 的帧结构：

```text
Frame
 |
 +-- Line 0
 |    +-- Pixel 0
 |    +-- Pixel 1
 |    ...
 |    +-- Pixel 639 (TLAST=1)
 |
 +-- Line 1
 |
 ...
 |
 +-- Line 479
      +-- Pixel 0
      ...
      +-- Pixel 639
           |
           +-- TLAST=1
```

最后一个像素完成 `pl_video_in` 输出侧握手后，才由 `pl_video_in` 产生一次 `frame_done_pulse`。

---

# 15. Interface Verification Checklist

## Register

* [ ] CTRL 地址为 0x00
* [ ] STATUS 地址为 0x04
* [ ] FRAME_CNT 地址为 0x08
* [ ] CTRL 可以写入
* [ ] STATUS 可以读取
* [ ] FRAME_CNT 可以读取

## AXI-Stream

* [ ] TDATA 为 RGB888
* [ ] 分辨率为 640×640
* [ ] TUSER 正确标记帧开始
* [ ] TLAST 正确标记行结束
* [ ] TVALID/TREADY 握手正确
* [ ] TREADY=0 时数据保持不变
* [ ] TREADY=0 时计数器保持不变

## Frame

* [ ] 完整帧产生一次 frame_done_pulse
* [ ] 半帧不产生有效 frame_done_pulse
* [ ] 完整帧 FRAME_CNT +1
* [ ] CTRL=0 后 FRAME_CNT 停止
* [ ] 软复位后恢复等待状态

---

# 16. Interface Change Record

| Version | Date       | Change    | Author |
| ------- | ---------- | --------- | ------ |
| v0.1    | 2026-09-11 | 建立第一版接口定义 | 乙      |
| v0.2    | 2026-09-13 | 增加V3.2视频输入、三缓冲、邮箱、序号、原子提交和保持型中断 | 乙 |
| v0.3    | 2026-09-17 | 仅补充pl_video_in端口、格式边界、复位/使能、错误处理和验证约束；其他接口保持v0.2不变 | 乙 |

> 本文件是当前阶段 FPGA 模块之间的接口约定。后续如果甲、乙、丙之间的模块接口发生变化，应先修改本文件，再修改 RTL 和软件测试代码。

---

# 17. V3.2 Request Mailbox

请求邮箱是 PL 给 PS/DPU 的控制消息，不保存整张图像。图像本体位于 DDR 帧缓冲区，邮箱只描述帧号、缓冲区和请求原因。

## 17.1 Request Registers

| Offset | Register | PS access | Producer | Description |
|---:|---|:---:|---|---|
| `0x10` | `REQUEST_SEQ` | RO | PL hardware | 每次已提交请求后加1 |
| `0x14` | `REQUEST_FRAME_ID` | RO | PL scheduler | 要求DPU处理的帧号 |
| `0x18` | `REQUEST_BUFFER_ID` | RO | PL scheduler | `0`、`1`或`2` |
| `0x1C` | `REQUEST_GENERATION` | RO | PL buffer manager | 缓冲区复用代次 |
| `0x20` | `REQUEST_REASON` | RO | PL scheduler | DPU请求原因 |
| `0x24` | `REQUEST_STATUS` | RO | PL hardware | 请求状态 |
| `0x28` | `REQUEST_TIMESTAMP` | RO | PL/profiler | 时间戳或周期计数，初版可为0 |

推荐 `REQUEST_REASON`：

| Value | Meaning |
|---:|---|
| `0x00` | 周期重检测 |
| `0x01` | 跟踪置信度低 |
| `0x02` | 跟踪丢失 |
| `0x03` | 系统启动 |
| `0x04` | 跟踪恢复 |
| `0xFF` | 其他 |

推荐 `REQUEST_STATUS`：

```text
bit0 request_valid
bit1 request_pending
bit2 ps_seen
bit3 request_in_flight
bit31:4 reserved
```

## 17.2 Request Commit

PL调度器先准备全部请求字段，最后产生一个时钟周期的 `request_commit`。控制IP在该事件上发布请求并更新 `REQUEST_SEQ`：

```text
准备 frame_id、buffer_id、generation、reason
        ↓
request_commit = 1 一个时钟
        ↓
请求字段整体发布
        ↓
REQUEST_SEQ 加1，request_pending置1
```

PS读取 `REQUEST_SEQ` 后再读取其余字段。如果读取期间序号发生变化，PS必须重新读取整套请求。PS不得写 `REQUEST_SEQ`。

---

# 18. V3.2 Result Mailbox

结果邮箱是 PS/DPU 返回给 PL 的检测结果。PS只能写影子寄存器，PL只能读取提交后的活动结果。

## 18.1 Result Shadow Registers

| Offset | Register | PS access | Width | Description |
|---:|---|:---:|---:|---|
| `0x30` | `RESULT_SHADOW_FRAME_ID` | RW | 32 | 结果帧号 |
| `0x34` | `RESULT_SHADOW_BUFFER_ID` | RW | 2 | 结果缓冲区编号 |
| `0x38` | `RESULT_SHADOW_GENERATION` | RW | 32 | 结果缓冲区代次 |
| `0x3C` | `RESULT_SHADOW_BBOX_X` | RW | 16 | 框左上角X，低16位 |
| `0x40` | `RESULT_SHADOW_BBOX_Y` | RW | 16 | 框左上角Y，低16位 |
| `0x44` | `RESULT_SHADOW_BBOX_W` | RW | 16 | 框宽度，低16位 |
| `0x48` | `RESULT_SHADOW_BBOX_H` | RW | 16 | 框高度，低16位 |
| `0x4C` | `RESULT_SHADOW_CONFIDENCE` | RW | 16 | 无符号Q0.16置信度 |
| `0x50` | `RESULT_SHADOW_STATUS` | RW | 8 | 结果状态，低8位 |
| `0x54` | `RESULT_COMMIT` | WO/W1P | 1 | bit0写1，原子提交 |

推荐结果状态：

| Value | Meaning |
|---:|---|
| `0x00` | 无有效结果 |
| `0x01` | 找到目标 |
| `0x02` | 推理完成但无目标 |
| `0x03` | 超时 |
| `0x04` | 错误 |

## 18.2 Atomic Commit

PS先写 `0x30` 至 `0x50` 的全部影子字段，最后写 `RESULT_COMMIT = 1`。硬件随后一次性把影子字段复制到活动字段，并使 `RESULT_SEQ` 加1、`result_pending`置1。

在 `RESULT_COMMIT` 之前，PL不得使用任何影子字段。`RESULT_SEQ`由硬件更新，PS不得直接写入。

| Offset | Register | PS access | Description |
|---:|---|:---:|---|
| `0x58` | `RESULT_SEQ` | RO | 已提交结果序号 |
| `0x5C` | `RESULT_STATUS` | RO | 当前活动结果状态 |

PL接受结果的条件：

```text
result.frame_id   == expected.frame_id
result.buffer_id  == expected.buffer_id
result.generation == expected.generation
```

任一字段不匹配时不得覆盖当前跟踪框，应设置 `stale_result` 和 `ERR_STALE_RESULT`。
---

# 19. Sticky Interrupt

软件可见的中断必须是保持型，不能直接使用单周期的 `frame_done_pulse`。

| Offset | Register | PS access | Description |
|---:|---|:---:|---|
| `0x60` | `IRQ_STATUS` | RO | 保持型待处理中断 |
| `0x64` | `IRQ_ACK` | WO/W1C | 写1清除对应中断 |
| `0x68` | `IRQ_ENABLE` | RW | 中断源使能 |
| `0x6C` | `VERSION` | RO | 接口版本，建议 `0x00020000` |

推荐位定义：

| Bit | Name | Set by | Clear by |
|---:|---|---|---|
| 0 | `request_pending` | 请求提交 | PS写 `IRQ_ACK[0]=1` |
| 1 | `frame_done_pending` | 完整帧完成 | PS写 `IRQ_ACK[1]=1` |
| 2 | `error_pending` | 新错误产生 | PS写 `IRQ_ACK[2]=1`或`clear_error` |
| 3 | `result_pending` | 结果提交 | PL消费结果后确认 |
| 31:4 | Reserved | - | - |

行为约定：

```text
事件发生 → 对应IRQ_STATUS位置1
IRQ_STATUS保持为1
PS处理完事件后写IRQ_ACK对应位为1
对应IRQ_STATUS位清零
```

禁用某个中断源只禁止通知，不清除pending状态；重新使能后，尚未确认的事件仍然有效。

推荐外部中断输出：

```verilog
irq = |(IRQ_STATUS & IRQ_ENABLE);
```

---

# 20. Three-Buffer and Fresh-Frame Contract

DPU专用帧池包含三个缓冲区，显示通路不占用这三个缓冲区。

每个缓冲区至少保存：

```text
state
frame_id
timestamp
owner
generation
base_address
```

状态：

| State | Meaning |
|---|---|
| `FREE` | 可写入新帧 |
| `WRITING` | 正在写入当前帧 |
| `READY` | 完整帧等待DPU |
| `DPU_OWNED` | PS/DPU正在使用，PL禁止覆盖 |

正常状态流转：

```text
FREE → WRITING → READY → DPU_OWNED → FREE
```

Fresh-Frame规则：DPU空闲时选择所有 `READY` 缓冲区中 `frame_id` 最新的有效帧，将其原子切换为 `DPU_OWNED`，发布请求邮箱，并把更旧的READY帧记为跳过/过期。

禁止覆盖 `DPU_OWNED` 缓冲区。没有可用缓冲区时设置 `buffer_conflict` 并执行已记录的丢帧策略。缓冲区重新使用时 `generation` 必须递增，不能只依赖 `buffer_id`。

---

# 21. `pl_video_in` Contract

`pl_video_in` 是视频输入规范化模块，负责检查帧行边界、处理反压、丢弃错误帧并等待下一次SOF重新同步。

| Item | Definition |
|---|---|
| Input resolution | 640 x 480 |
| Input pixel | 8-bit grayscale |
| `TDATA` | `s_axis_tdata[7:0]` |
| `TUSER[0]` | SOF，仅帧首像素为1 |
| `TLAST` | EOL，仅行末像素为1 |
| Frame ID | 仅完整有效帧提交后递增 |
| Error policy | 当前错误帧整体丢弃，等待下一次SOF |

必须检查每行640个像素、每帧480行、TUSER帧首唯一、TLAST行末唯一，以及缺SOF、帧中SOF、提前TLAST、行溢出、FIFO溢出和复位中断等异常。

建议状态机：

```text
WAIT_SOF → RECEIVE_FRAME → WAIT_SOF
                 |
                 v
             DROP_FRAME → WAIT_SOF
```

所有计数器只在 `TVALID && TREADY` 时更新。反压期间必须保持 `TDATA`、`TUSER`、`TLAST` 和计数状态稳定。

## 21.1 Module Boundary

`pl_video_in` 只负责把输入源规范化为稳定的 640x480、8-bit 灰度 AXI4-Stream，同时报告帧完成和视频协议错误。它不执行 Letterbox，不把图像扩展为 640x640，也不把灰度像素转换成 RGB888。

```text
dummy_video_in_source / sensor_like_source
                 |
                 | 640x480, GRAY8
                 v
           +-------------+
           | pl_video_in |
           +-------------+
                 |
                 | 640x480, GRAY8
                 v
      pl_preproc_letterbox
                 |
                 | 640x640, RGB888
                 v
        three-buffer / downstream
```

因此，本文件前文中出现的 640x640、RGB888 和每帧 640 次 `TLAST`，均描述 Letterbox 输出侧或其下游测试链路；`pl_video_in` 自身每帧是 480 行、产生 480 次 `TLAST`。

## 21.2 Required Port Table

以下端口名和位宽作为 `pl_video_in` 首版 RTL 的冻结接口。方向均以 `pl_video_in` 模块为参照。

| Port | Direction | Width | Clock domain | Definition |
|---|:---:|---:|---|---|
| `video_aclk` | input | 1 | video | 模块和两侧 AXI4-Stream 的工作时钟 |
| `video_aresetn` | input | 1 | video | 低有效硬复位，同步释放 |
| `enable` | input | 1 | video | 来自 `pl_sys_ctrl` 的视频通路使能；跨时钟域时必须先同步 |
| `soft_reset` | input | 1 | video | 一拍软复位请求；跨时钟域时必须做脉冲同步或握手 |
| `clear_error` | input | 1 | video | 清除本地保存的 `err_code`；不修改 `frame_cnt`；跨时钟域时必须做脉冲同步或握手 |
| `s_axis_tdata` | input | 8 | video | 输入灰度像素，`[7:0]` 表示一个像素 |
| `s_axis_tvalid` | input | 1 | video | 输入像素及边界标志有效 |
| `s_axis_tready` | output | 1 | video | 模块可以接收当前输入拍 |
| `s_axis_tuser` | input | 1 | video | SOF；仅一帧第一个像素为 1 |
| `s_axis_tlast` | input | 1 | video | EOL；仅每行第 640 个像素为 1 |
| `m_axis_tdata` | output | 8 | video | 规范化后的灰度像素 |
| `m_axis_tvalid` | output | 1 | video | 输出像素及边界标志有效 |
| `m_axis_tready` | input | 1 | video | 下游可以接收当前输出拍 |
| `m_axis_tuser` | output | 1 | video | 输出 SOF；仅有效帧首像素为 1 |
| `m_axis_tlast` | output | 1 | video | 输出 EOL；仅有效行末像素为 1 |
| `lock` | output | 1 | video | 至少完整接收并输出一帧合法视频后置 1；协议错误、禁用或复位后清 0 |
| `busy` | output | 1 | video | 正在接收、输出或丢弃一帧时为 1 |
| `frame_done_pulse` | output | 1 | video | 一帧最后一个有效输出像素完成握手时产生的一拍脉冲 |
| `err` | output | 1 | video | 检测到一次视频协议错误时产生的一拍脉冲 |
| `err_code` | output | 32 | video | 最近一次完整 32-bit 视频错误码，编码见 21.7 |
| `frame_cnt` | output | 32 | video | 完整有效输出帧计数；仅随 `frame_done_pulse` 加 1 |

首版不强制在 `pl_video_in` 内加入像素 FIFO。连接现有 `pl_sys_ctrl` 时，状态输入按下表处理：

| `pl_sys_ctrl` input | Source |
|---|---|
| `lock` | `pl_video_in.lock` |
| `busy` | `pl_video_in.busy` |
| `frame_done_pulse` | `pl_video_in.frame_done_pulse` |
| `err` | `pl_video_in.err` |
| `err_code_in[31:0]` | `pl_video_in.err_code[31:0]` |
| `frame_cnt[31:0]` | `pl_video_in.frame_cnt[31:0]` |
| `fifo_ovf` | 首版无 FIFO 时接常量 0；加入真实 FIFO 后改接溢出状态 |
| `fifo_empty` | 首版无 FIFO 时接常量 1；加入真实 FIFO 后改接空状态 |

首版主工程优先让 `video_aclk` 与 `pl_sys_ctrl.s00_axi_aclk` 使用同一时钟，先消除不必要的 CDC 风险。若以后改为不同时钟域，`frame_done_pulse` 和 `err` 必须通过脉冲同步或事件握手传递；`err_code` 和 `frame_cnt` 必须通过握手快照、异步 FIFO 或其他能保证多比特一致性的 CDC 结构传递，禁止逐位直接同步。

## 21.3 Exact Video Format

| Boundary | Resolution | Pixel format | `TDATA` width | `TUSER` | `TLAST` |
|---|---|---|---:|---|---|
| `pl_video_in.s_axis_*` | 640x480 | GRAY8 | 8 | SOF | EOL |
| `pl_video_in.m_axis_*` | 640x480 | GRAY8 | 8 | SOF | EOL |
| `pl_preproc_letterbox.m_axis_*` | 640x640 | RGB888 | 24 | SOF | EOL |

对 `pl_video_in` 而言，合法帧必须同时满足：

```text
每行 640 个已握手像素
每帧 480 行
每帧第一个已握手像素：TUSER=1
其他像素：TUSER=0
每行第 640 个已握手像素：TLAST=1
其他像素：TLAST=0
```

## 21.4 Handshake and Backpressure

输入拍只在以下条件成立时被模块接收：

```text
s_transfer = s_axis_tvalid && s_axis_tready
```

输出拍只在以下条件成立时被下游接收：

```text
m_transfer = m_axis_tvalid && m_axis_tready
```

输入像素、行计数和输入协议检查只由 `s_transfer` 推进。输出完成状态只由 `m_transfer` 推进。

当 `m_axis_tvalid=1 && m_axis_tready=0` 时，`m_axis_tdata`、`m_axis_tuser` 和 `m_axis_tlast` 必须保持不变。若内部没有空间保存新的输入拍，必须拉低 `s_axis_tready`，不得覆盖尚未被下游接收的数据。

## 21.5 `frame_done_pulse` Ownership

正常集成模式下，`pl_video_in` 是 `pl_sys_ctrl.frame_done_pulse` 的唯一驱动源。dummy 源只能产生 AXI4-Stream 像素和边界标志，不能同时直接驱动 `pl_sys_ctrl.frame_done_pulse`。

`frame_done_pulse` 只能在以下事件发生时置 1，且只保持一个 `video_aclk` 周期：

```text
m_transfer
&& 当前输出是第 480 行的第 640 个像素
&& m_axis_tlast == 1
&& 当前帧从 SOF 到此处没有协议错误
```

同一拍使 `frame_cnt` 加 1。半帧、被复位打断的帧、被禁用打断的帧和协议错误帧均不得产生 `frame_done_pulse`，也不得增加 `frame_cnt`。

## 21.6 Error Frame Discard and Resynchronization

检测到协议错误后，模块进入 `DROP_FRAME`：

- 当前错误帧不产生 `frame_done_pulse`，不增加 `frame_cnt`。
- 停止向下游发送该帧的剩余像素，并继续接收、丢弃输入，直到发现下一次 SOF。
- 下一次 SOF 所在的像素就是新帧第一个像素，不应被一并丢弃；该拍用于重新进入 `RECEIVE_FRAME`。
- `err` 对每个新检测到的错误只脉冲一次，`err_code` 保存最近一次错误码，直到 `clear_error` 或硬复位。

纯流式模块在帧尾错误发生前，可能已经把该帧前半部分发送给下游，已经完成的握手无法撤回。因此“整帧丢弃”的系统级含义是：下游帧缓冲只有在收到 `frame_done_pulse` 后才能把缓冲区提交为 `READY`；没有 `frame_done_pulse` 的部分帧必须保持无效并允许后续覆盖。

## 21.7 Video Error Codes

视频错误码使用 `0x000001xx` 范围，避免与现有控制器内部错误码 `0x01` 至 `0x03` 混淆。

| Value | Name | Trigger condition |
|---:|---|---|
| `0x00000000` | `VIDEO_ERR_NONE` | 当前没有保存的视频错误 |
| `0x00000101` | `VIDEO_ERR_NO_SOF` | `WAIT_SOF` 中接收到未带 SOF 的有效输入拍 |
| `0x00000102` | `VIDEO_ERR_UNEXPECTED_SOF` | 当前帧尚未完成时再次接收到 SOF |
| `0x00000103` | `VIDEO_ERR_EARLY_TLAST` | 一行不足 640 个像素时收到 TLAST |
| `0x00000104` | `VIDEO_ERR_MISSING_TLAST` | 一行第 640 个像素未带 TLAST |
| `0x00000105` | `VIDEO_ERR_TOO_MANY_LINES` | 合法帧边界之外仍继续形成额外行 |
| `0x00000106` | `VIDEO_ERR_FIFO_OVERFLOW` | 后续版本加入输入 FIFO 后检测到溢出；首版不得产生 |

`soft_reset`、`enable=0` 和硬复位用于主动终止当前帧，不记为视频协议错误。

## 21.8 Reset and Enable Behavior

`video_aresetn=0` 时：

- 清空状态机、输入/输出暂存、像素计数和行计数。
- `m_axis_tvalid=0`、`s_axis_tready=0`、`frame_done_pulse=0`、`err=0`。
- `frame_cnt=0`、`err_code=VIDEO_ERR_NONE`、`lock=0`、`busy=0`。

`soft_reset=1` 的有效拍到来时：

- 放弃当前未完成帧并回到 `WAIT_SOF`。
- 清空像素计数、行计数和待输出拍，不产生 `frame_done_pulse` 或 `err`。
- 保持 `frame_cnt`，与第 12 节现有约定一致。
- `lock` 和 `busy` 清 0；`err_code` 保持到 `clear_error`。

`enable=0` 时：

- `s_axis_tready=0`、`m_axis_tvalid=0`，不接收也不发送像素。
- 当前未完成帧作废，所有帧内计数回到等待 SOF 状态。
- `frame_cnt` 和 `err_code` 保持，`lock=0`、`busy=0`。

`enable` 从 0 变为 1 后，模块必须从 `WAIT_SOF` 开始，只把下一次带 SOF 的已握手像素认作新帧起点。

## 21.9 Minimum Verification Items

- [ ] 正常 640x480 GRAY8 帧原样输出，像素顺序、SOF 和 EOL 不变。
- [ ] 每帧恰好 480 次 `m_axis_tlast`，每帧恰好一次 `m_axis_tuser`。
- [ ] 最后一个输出像素握手时只产生一次 `frame_done_pulse`，同时 `frame_cnt` 加 1。
- [ ] 随机拉低 `m_axis_tready` 时，输出数据和边界标志保持稳定且无像素丢失/重复。
- [ ] 缺 SOF、帧中 SOF、提前 TLAST、缺失 TLAST 均产生对应错误码。
- [ ] 错误帧、半帧、禁用打断帧和软复位打断帧不提交、不计数。
- [ ] `DROP_FRAME` 能在下一次 SOF 恢复，且新 SOF 像素不会被丢弃。
- [ ] 硬复位清除 `frame_cnt`；软复位和 `clear_error` 不清除 `frame_cnt`。
- [ ] normal integration 中 `frame_done_pulse` 只有一个驱动源。

---

# 22. Internal Ports Added for V3.2

这些信号不是AXI-Lite寄存器，而是 `pl_sys_ctrl` 与PL调度器/帧池之间的内部端口。若在Block Design中连接，必须出现在打包后的IP上。

| Port | Direction | Width | Meaning |
|---|---|---:|---|
| `frame_done_pulse` | input | 1 | 完整有效帧完成的一拍事件 |
| `irq` | output | 1 | 保持型、按IRQ_ENABLE屏蔽后的中断 |
| `request_commit` | input | 1 | PL请求提交事件 |
| `request_frame_id_in` | input | 32 | 请求帧号 |
| `request_buffer_id_in` | input | 2 | 请求缓冲区编号 |
| `request_generation_in` | input | 32 | 请求缓冲区代次 |
| `request_reason_in` | input | 8 | 请求原因 |
| `request_timestamp_in` | input | 32 | 请求时间戳 |
| `result_commit_pulse` | output | 1 | 结果原子提交事件 |
| `result_frame_id` | output | 32 | 活动结果帧号 |
| `result_buffer_id` | output | 2 | 活动结果缓冲区编号 |
| `result_generation` | output | 32 | 活动结果代次 |
| `result_bbox_x/y/w/h` | output | 16 each | 活动检测框 |
| `result_confidence` | output | 16 | Q0.16置信度 |
| `result_status` | output | 8 | 活动结果状态 |
| `result_ack` | input | 1 | PL消费结果确认 |

内部多比特信号如果跨时钟域，不能直接连线，必须使用异步FIFO或握手邮箱。

---

# 23. V3.2 Verification Checklist

## AXI-Lite and mailbox

- [ ] 地址译码覆盖 `0x00` 至 `0x6C`。
- [ ] `REQUEST_SEQ` 仅在请求提交后变化。
- [ ] 结果影子寄存器在提交前对PL不可见。
- [ ] `RESULT_COMMIT` 使整套结果一起生效。
- [ ] `RESULT_SEQ` 仅在结果提交后变化。
- [ ] 序号、帧号、缓冲区编号和代次能正确对应。
- [ ] IRQ pending保持到明确确认。
- [ ] 禁用IRQ不会清除pending。

## Video and frame path

- [ ] `pl_video_in` 正常传输640x480灰度帧。
- [ ] 每行640像素，每帧480行。
- [ ] `TUSER`每帧一次，`TLAST`每行一次。
- [ ] 随机反压时数据和标志稳定。
- [ ] 错误帧整体丢弃，下一次SOF可恢复。
- [ ] 仅完整帧增加 `FRAME_CNT`。
- [ ] 三缓冲不覆盖 `DPU_OWNED`。
- [ ] Fresh-Frame选择最新有效READY帧。
- [ ] 过期结果不能覆盖当前跟踪框。

## Integration

- [ ] 甲的Letterbox IP已接入总工程，乙未修改其内部算法。
- [ ] Block Design Validate通过。
- [ ] CDC、WNS、TNS、利用率和功耗报告已归档。
- [ ] `.bit`、`.hwh` 和构建Tcl可重复生成。

---

# 24. `pl_preproc_letterbox` Frozen Interface (V0.5 Addition)

本章是V0.5相对V0.4的唯一接口新增内容，用于冻结甲方交付的
`pl_preproc_letterbox` 首版RTL接口和精确行为。V0.4中其他模块、寄存器和接口
定义保持不变。

## 24.1 Module Responsibility

`pl_preproc_letterbox` 接收640x480、GRAY8（8位灰度）的AXI4-Stream视频帧，
保持图像宽度不变，在顶部和底部各补80行，将输出变为640x640，并将每个灰度
像素复制到R、G、B三个8位通道。

该模块不负责视频源生成、`pl_video_in`协议恢复、DDR写入、三缓冲调度、DPU
请求或AXI-Lite寄存器控制。

## 24.2 Required Port Table

以下端口名、方向和位宽作为 `pl_preproc_letterbox` 首版RTL的冻结接口。方向均以
本模块为参照。

| Port | Direction | Width | Clock domain | Definition |
|---|:---:|---:|---|---|
| `aclk` | input | 1 | video | 模块和两侧AXI4-Stream接口的唯一工作时钟 |
| `aresetn` | input | 1 | video | 低有效异步复位；系统集成时必须保证释放满足目标时钟域要求 |
| `s_axis_tdata` | input | 8 | video | 640x480 GRAY8输入像素 |
| `s_axis_tvalid` | input | 1 | video | 输入像素和旁带信号有效 |
| `s_axis_tready` | output | 1 | video | 模块能够接收当前输入拍 |
| `s_axis_tlast` | input | 1 | video | 输入EOL；仅每行第640个像素为1 |
| `s_axis_tuser` | input | 1 | video | 输入SOF；每帧第一个像素必须为1 |
| `m_axis_tdata` | output | 24 | video | 640x640 RGB888输出像素 |
| `m_axis_tvalid` | output | 1 | video | 输出像素和旁带信号有效 |
| `m_axis_tready` | input | 1 | video | 下游能够接收当前输出拍 |
| `m_axis_tlast` | output | 1 | video | 输出EOL；仅每行第640个像素为1 |
| `m_axis_tuser` | output | 1 | video | 输出SOF；仅输出帧第一个像素为1 |
| `error` | output | 1 | video | 协议错误保持状态；置1后保持到硬复位 |
| `out_frame_start` | output | 1 | video | 输出帧首像素完成握手时产生的一拍脉冲 |
| `out_frame_done` | output | 1 | video | 输出帧末像素完成握手时产生的一拍脉冲 |

## 24.3 Exact Pixel Format

输入格式：

```text
width  = 640
height = 480
format = GRAY8
s_axis_tdata[7:0] = gray
```

输出格式：

```text
width  = 640
height = 640
format = RGB888
m_axis_tdata[23:16] = R
m_axis_tdata[15:8]  = G
m_axis_tdata[7:0]   = B
```

输出第0至79行和第560至639行为补边区：

```text
R = 8'd114
G = 8'd114
B = 8'd114
```

输出第80至559行对应输入第0至479行。对每个有效图像像素：

```text
R = gray
G = gray
B = gray
```

一帧输出必须恰好包含409600个已握手像素、一次 `m_axis_tuser=1` 和640次
`m_axis_tlast=1`。

## 24.4 AXI4-Stream Handshake and Backpressure

输入和输出分别只在以下条件成立时推进：

```text
s_transfer = s_axis_tvalid && s_axis_tready
m_transfer = m_axis_tvalid && m_axis_tready
```

当 `m_axis_tvalid=1 && m_axis_tready=0` 时，`m_axis_tvalid`、
`m_axis_tdata`、`m_axis_tuser` 和 `m_axis_tlast` 必须保持不变，直到该拍完成
握手。模块内部输入缓存没有空间时必须拉低 `s_axis_tready`，不得覆盖尚未输出的
输入像素。

首个输入像素完成握手后，模块先输出顶部80行补边。在顶部补边期间，除已缓存的
首个输入像素外不再接收其他输入像素。顶部补边完成后，模块继续接收并输出有效
图像，最后输出底部80行补边。

## 24.5 SOF, EOL and Frame Events

- 输入帧第一个已握手像素必须携带 `s_axis_tuser=1`。
- 输出帧第一个已握手像素携带 `m_axis_tuser=1`，其他输出像素为0。
- 每个输入行第640个已握手像素必须携带 `s_axis_tlast=1`。
- 每个输出行第640个已握手像素携带 `m_axis_tlast=1`，其他输出像素为0。
- `out_frame_start`仅在输出第0行第0列像素完成握手的时钟沿置1，并保持一个
  `aclk`周期。
- `out_frame_done`仅在输出第639行第639列像素完成握手的时钟沿置1，并保持一个
  `aclk`周期。
- 帧事件只由真实输出握手产生；反压期间不得提前产生或重复产生。

## 24.6 Error and Reset Behavior

首版RTL必须检测以下错误：

1. 空闲状态收到的首个输入像素没有 `s_axis_tuser=1`。
2. 输入行不足640个像素时提前收到 `s_axis_tlast=1`。
3. 输入行第640个像素没有 `s_axis_tlast=1`。

检测到上述错误后，模块进入保持型错误状态：

```text
error         = 1
s_axis_tready = 0
m_axis_tvalid = 0
```

首版错误状态只能通过拉低 `aresetn` 清除，不定义自动等待下一帧恢复，也不定义
独立错误码。复位期间，两侧有效信号和帧事件必须为0；复位释放后回到等待输入
SOF的空闲状态。若系统要求同步释放复位，必须在模块外部使用复位同步器。

## 24.7 Vivado IP Packaging Rules

打包为Vivado IP时必须满足：

- `s_axis_tdata/tvalid/tready/tlast/tuser` 归组为名为 `s_axis` 的
  AXI4-Stream Slave接口。
- `m_axis_tdata/tvalid/tready/tlast/tuser` 归组为名为 `m_axis` 的
  AXI4-Stream Master接口。
- `aclk`归组为时钟接口，并关联 `s_axis`、`m_axis` 和 `aresetn`。
- `aresetn`归组为低有效复位接口，关联时钟为 `aclk`。
- `TDATA`宽度固定为输入8位、输出24位；每个时钟拍传输一个像素。
- `TUSER`宽度固定为1，只表示SOF；`TLAST`只表示EOL。
- `error`、`out_frame_start` 和 `out_frame_done` 保持为独立离散端口。

## 24.8 Acceptance Checklist

- [ ] 输入恰好为640x480 GRAY8，输出恰好为640x640 RGB888。
- [ ] 上下补边各80行且三个通道均为114。
- [ ] 中间区域的R、G、B均等于对应输入灰度值。
- [ ] 每帧409600个输出像素、一次SOF、640次EOL。
- [ ] 输入和输出计数只在READY/VALID握手时推进。
- [ ] 随机反压期间输出数据和旁带信号稳定。
- [ ] `out_frame_start`和`out_frame_done`各产生一次一拍脉冲。
- [ ] 缺SOF、提前TLAST和缺失TLAST均进入保持型错误状态。
- [ ] 硬复位能够清除错误状态并恢复到空闲状态。
- [ ] 软件金标准与RTL输出逐字节完全一致。
- [ ] OOC综合、`component.xml`检查和隔离Block Design验证通过。

---

# 25. `pl_frame_scheduler` Contract (V0.6 addition)

本节是 V0.6 相对 V0.5 的唯一新增内容。V0.5 的全部原文保持不变。
`pl_frame_scheduler` 负责三个帧缓冲区的状态、帧身份、复用代次、Fresh-Frame
选择和 DPU 所有权。它不负责 DDR 地址生成、DDR AXI 主机写入或 DPU 算法。

## 25.1 Module and Parameters

| Item | Definition |
|---|---|
| Module | `pl_frame_scheduler` |
| Clock | `aclk`, single clock domain in this stage |
| Reset | `aresetn`, asynchronous active-low; `soft_reset` is synchronous active-high |
| Buffer count | fixed at 3; `BUFFER_COUNT` parameter must remain 3 |
| ID width | `frame_id`, `generation` and timestamp are 32 bits |
| Buffer ID | 2 bits; only values 0, 1 and 2 are legal |
| Address | no physical DDR address port in this stage; later DDR adapter owns the mapping |

## 25.2 Exact Port Table

| Port | Direction | Width | Meaning |
|---|---|---:|---|
| `aclk` | input | 1 | scheduler clock |
| `aresetn` | input | 1 | asynchronous active-low reset |
| `enable` | input | 1 | system enable; low blocks new writes and dispatch |
| `soft_reset` | input | 1 | synchronous scheduler reset |
| `frame_start` | input | 1 | request to start a frame |
| `frame_start_ready` | output | 1 | high when `frame_start` may be accepted |
| `frame_end` | input | 1 | current frame is complete |
| `write_buffer` | output | 2 | buffer used by current/new frame |
| `write_frame_id` | output | 32 | provisional ID for current/new frame; formal at `frame_end` |
| `write_generation` | output | 32 | current generation; for a new frame it is old value plus one |
| `dpu_ready` | input | 1 | DPU/PS consumer can accept one request |
| `request_commit` | output | 1 | one-cycle atomic request commit pulse |
| `request_frame_id_in` | output | 32 | frame ID published to `pl_sys_ctrl` |
| `request_buffer_id_in` | output | 2 | buffer ID published to `pl_sys_ctrl` |
| `request_generation_in` | output | 32 | generation published to `pl_sys_ctrl` |
| `request_reason_in` | output | 8 | request reason; `8'h01` means Fresh-Frame |
| `request_timestamp_in` | output | 32 | timestamp captured with selected frame |
| `result_commit_pulse` | input | 1 | result mailbox atomic commit from `pl_sys_ctrl` |
| `result_frame_id` | input | 32 | returned result frame ID |
| `result_buffer_id` | input | 2 | returned result buffer ID |
| `result_generation` | input | 32 | returned result generation |
| `result_release` | output | 1 | one-cycle accepted-result release pulse |
| `result_stale_pulse` | output | 1 | one-cycle stale-result rejection pulse |
| `completed_frames` | output | 32 | count of complete accepted frames |
| `stale_frames` | output | 32 | READY frames skipped by Fresh-Frame selection |
| `dropped_frames` | output | 32 | stale frames plus rejected starts; saturating is not required in V0.6 |
| `stale_results` | output | 32 | result tuples that did not match the active DPU owner |
| `buffer_conflicts` | output | 32 | rejected `frame_start` events caused by no FREE buffer |
| `dpu_owned_mask` | output | 3 | one bit per buffer in `DPU_OWNED` state |
| `ready_mask` | output | 3 | one bit per buffer in `READY` state |
| `buffer_conflict` | output | 1 | sticky indicator that a buffer conflict has occurred |

The suffix `_in` on request outputs is retained because these signals connect
directly to the existing `pl_sys_ctrl` request-mailbox inputs.

## 25.3 State and Ownership Rules

Each buffer has exactly one state:

```text
FREE -> WRITING -> READY -> DPU_OWNED -> FREE
```

- `FREE` may be allocated by `frame_start`.
- `WRITING` is the only state that accepts `frame_end`.
- `READY` contains one complete frame and may be selected for dispatch.
- `DPU_OWNED` is protected from PL writes until a matching result is accepted.
- `DPU_OWNED` is never overwritten, even when no other buffer is free.
- With no `FREE` buffer, `frame_start_ready=0`; an attempted `frame_start` increments
  both `buffer_conflicts` and `dropped_frames`, and sets sticky `buffer_conflict`.

## 25.4 Frame ID and Generation Rules

- After reset, the next formal frame ID is 0 and every accepted complete frame
  increments it by one.
- A frame receives its formal `frame_id` only when `frame_end` is accepted.
- Each buffer starts with `generation=0` and increments when it is allocated for
  a new `WRITING` interval. The first use therefore has generation 1.
- A tuple is identified by `(frame_id, buffer_id, generation)`; `buffer_id` alone
  is never sufficient to identify a frame.
- `write_frame_id` is the provisional next ID while a frame is being written.

## 25.5 Fresh-Frame Request Behavior

When `enable=1`, `dpu_ready=1`, no buffer is currently `DPU_OWNED`, and at least
one `READY` buffer exists, the scheduler:

1. Selects the `READY` buffer with the greatest `frame_id`.
2. Publishes its frame ID, buffer ID, generation and timestamp together.
3. Raises `request_commit` for exactly one `aclk` cycle.
4. Atomically changes the selected buffer to `DPU_OWNED`.
5. Changes all other `READY` buffers to `FREE`, incrementing `stale_frames` and
   `dropped_frames` once per skipped buffer.

There is at most one active `DPU_OWNED` buffer in V0.6. A newly completed frame
is eligible for dispatch on the following clock cycle, not before its `frame_end`
state update has completed.

## 25.6 Result Matching

On `result_commit_pulse`, the tuple must satisfy:

```text
result_frame_id   == active.frame_id
result_buffer_id  == active.buffer_id
result_generation == active.generation
```

If all three fields match, the active buffer becomes `FREE` and
`result_release` is a one-cycle pulse. If any field differs, the buffer remains
`DPU_OWNED`, `stale_results` increments, and `result_stale_pulse` is a one-cycle
pulse. A result received without an active owner is also stale.

## 25.7 Reset and Verification Requirements

- Asynchronous reset clears all states to `FREE`, counters to zero and pulses to 0.
- `soft_reset` has the same effect on the next rising `aclk` edge.
- `request_commit`, `result_release` and `result_stale_pulse` are one-cycle pulses.
- Verification must cover three-frame allocation, monotonic IDs, generation reuse,
  Fresh-Frame selection, DPU ownership protection, no-FREE backpressure, all three
  result tuple mismatch cases, matching release, reset and soft reset.
- The V0.6 RTL must be checked by an editable standalone Vivado project, XSim
  (Vivado Simulator) simulation, assertions/immediate checks, OOC synthesis and
  an isolated Block Design validation. The formal `project_1` is not changed in
  this stage.

---

# 26. `pl_frame_write_adapter` Contract (V0.7 addition)

本节是 V0.7 相对 V0.6 的唯一新增内容。V0.6 的全部原文保持不变。
`pl_frame_write_adapter` 位于 RGB888 视频流、`pl_frame_scheduler` 与 AMD AXI
DataMover S2MM（Stream to Memory-Mapped，流到存储器映射）通道之间。它负责发出
每帧一次的 DataMover 命令、把 RGB888 扩展为 DDR 中的 32 位像素、检查视频行协议，
并且只在 DataMover 返回状态后向调度器提交成功或失败事件。它不实现 DDR 控制器，
也不直接实现 AXI4 Memory-Mapped Master。

## 26.1 Fixed Configuration and Address Map

| Item | Definition |
|---|---|
| Module | `pl_frame_write_adapter` |
| Clock domain | 单一 `aclk`；适配器、调度器和 DataMover S2MM 命令/状态/数据侧同域 |
| Input frame | 固定 640x640，RGB888，每个有效拍一个像素 |
| DDR pixel | 32 bits，低地址到高地址依次为 `R, G, B, 0` |
| Line stride | 2560 bytes = `40'h0000000A00` |
| Frame bytes / BTT | 1,638,400 bytes = `23'h190000` |
| Buffer count | 3；合法 `write_buffer` 为0、1、2 |
| Buffer 0 offset | `40'h0000000000` |
| Buffer 1 offset | `40'h0000190000` |
| Buffer 2 offset | `40'h0000320000` |
| Total reservation | `40'h00004B0000` bytes |
| Base address | 参数 `FRAME_BASE_ADDR[39:0]`；本阶段默认0，最终物理地址由 Linux 保留内存方案确定 |

三个帧地址均必须按8字节对齐，以满足关闭 DRE（Data Realignment Engine，数据重对齐引擎）
时的64位 AXI4 Memory-Mapped 写口要求。

## 26.2 Exact Port Table

| Port | Direction | Width | Meaning |
|---|---|---:|---|
| `aclk` | input | 1 | 模块时钟 |
| `aresetn` | input | 1 | 异步低有效复位 |
| `enable` | input | 1 | 允许启动新帧；不终止已经启动的帧 |
| `soft_reset` | input | 1 | 同步高有效复位 |
| `s_axis_tdata` | input | 24 | RGB888；`[23:16]=R, [15:8]=G, [7:0]=B` |
| `s_axis_tvalid` | input | 1 | 输入像素有效 |
| `s_axis_tready` | output | 1 | 输入像素可接收 |
| `s_axis_tuser` | input | 1 | SOF（Start of Frame，帧开始），只在首像素为1 |
| `s_axis_tlast` | input | 1 | EOL（End of Line，行结束），只在每行第640像素为1 |
| `scheduler_frame_start_ready` | input | 1 | 调度器允许分配写缓冲 |
| `write_buffer` | input | 2 | 调度器给出的目标缓冲编号 |
| `frame_start` | output | 1 | 接受一帧并锁存缓冲时产生一拍 |
| `frame_end` | output | 1 | DataMover 成功且本帧视频协议正确时产生一拍 |
| `frame_abort` | output | 1 | DataMover 或视频协议失败时产生一拍 |
| `dm_cmd_tdata` | output | 80 | DataMover S2MM 命令 |
| `dm_cmd_tvalid` | output | 1 | 命令有效 |
| `dm_cmd_tready` | input | 1 | DataMover 接受命令 |
| `dm_data_tdata` | output | 32 | 扩展后的像素数据 |
| `dm_data_tkeep` | output | 4 | 固定 `4'b1111` |
| `dm_data_tlast` | output | 1 | 仅整帧最后一个像素为1，不转发输入 EOL |
| `dm_data_tvalid` | output | 1 | DataMover 数据有效 |
| `dm_data_tready` | input | 1 | DataMover 数据可接收 |
| `dm_sts_tdata` | input | 8 | DataMover S2MM 状态字 |
| `dm_sts_tvalid` | input | 1 | 状态有效 |
| `dm_sts_tready` | output | 1 | 适配器可接受状态 |
| `dm_s2mm_err` | input | 1 | DataMover S2MM 严重错误指示 |
| `busy` | output | 1 | 已分配帧，正在等待命令、数据或状态 |
| `protocol_error` | output | 1 | 输入 SOF/EOL 或缓冲编号错误的保持型指示 |
| `datamover_error` | output | 1 | 状态失败或 `dm_s2mm_err` 的保持型指示 |
| `frames_written` | output | 32 | 成功写帧计数 |
| `frames_aborted` | output | 32 | 已分配但最终失败的帧计数 |

## 26.3 DataMover Configuration and Command Format

Vivado 2022.2 中使用 `xilinx.com:ip:axi_datamover:5.1`，配置如下：

```text
c_enable_mm2s                 = 0
c_enable_s2mm                 = 1
c_include_s2mm                = Full
c_addr_width                  = 40
c_m_axi_s2mm_addr_width       = 40
c_m_axi_s2mm_data_width       = 64
c_s_axis_s2mm_tdata_width     = 32
c_s2mm_btt_used               = 23
c_s2mm_burst_size             = 16
c_s2mm_support_indet_btt      = false
c_include_s2mm_stsfifo        = true
c_s2mm_stscmd_is_async        = false
c_include_s2mm_dre            = false
```

80位命令按照 PG022 与 Vivado 自带 S2MM example design 构造：

| Bits | Value | Meaning |
|---|---|---|
| `[79:76]` | `4'h0` | TAG |
| `[75:72]` | `4'h0` | Reserved |
| `[71:32]` | target address | SADDR（Start Address，起始地址） |
| `[31]` | `1'b0` | DRR（Discard on Realignment Request） |
| `[30]` | `1'b1` | EOF（End of Frame） |
| `[29:24]` | `6'b0` | DSA（Data Realignment，关闭 DRE 时为0） |
| `[23]` | `1'b1` | Type = INCR（递增地址传输） |
| `[22:0]` | `23'h190000` | BTT（Bytes To Transfer，传输字节数） |

命令在 `dm_cmd_tvalid && dm_cmd_tready` 前必须保持稳定；在命令握手前不得向
DataMover 发送任何数据。每帧只允许一个未完成命令。

## 26.4 Pixel, Backpressure and Frame Behavior

- 输入 RGB888 转换为 `dm_data_tdata={8'h00, B, G, R}`，因此 DDR 小端低地址到
  高地址为 `R, G, B, 0`。
- `dm_data_tkeep` 在所有有效数据拍固定为 `4'b1111`。
- 输入和输出计数只在 `s_axis_tvalid && s_axis_tready` 时推进。
- DataMover 反压时，`s_axis_tready=0`，数据、`tkeep` 和 `tlast` 必须保持稳定。
- `dm_data_tlast` 只在第409600个像素为1；输入 `s_axis_tlast` 仅用于检查 EOL。
- 帧首像素必须带 `s_axis_tuser=1`，其余像素若出现 `tuser=1` 记为协议错误。
- 每行第640个像素必须带 `s_axis_tlast=1`；其他位置出现 `tlast=1` 记为协议错误。
- 一旦命令已发出，即使检测到视频协议错误，也继续接收并写完固定409600像素，
  以便固定 BTT 命令正常收尾；收到状态后以 `frame_abort` 回收该缓冲。
- 空闲时无 SOF 的输入拍可以被丢弃并置 `protocol_error=1`，但不产生 `frame_start`。
- `write_buffer=3` 时拒绝启动命令并置 `protocol_error=1`，不产生 `frame_start`。

## 26.5 Completion, Failure and Scheduler Update

DataMover 的8位成功状态必须满足：

```text
dm_sts_tdata[7]   = 1  // OKAY
dm_sts_tdata[6:0] = 0  // 无错误位
```

只有在完整数据已经发送、收到上述成功状态、本帧没有协议错误且
`dm_s2mm_err=0` 时，适配器才产生 `frame_end` 并增加 `frames_written`。
否则产生 `frame_abort`、增加 `frames_aborted`，并置相应保持型错误指示。

`pl_frame_scheduler` 从 V0.7 起增加输入 `frame_abort`。对当前 `WRITING` 缓冲：

```text
frame_end   : WRITING -> READY，分配正式 frame_id，completed_frames 加1
frame_abort : WRITING -> FREE，不分配 frame_id，dropped_frames 加1
```

若 `frame_abort` 与 `frame_end` 同拍，`frame_abort` 优先。缓冲的 `generation`
不会回退；下一次复用时继续递增。失败帧绝不能进入 `READY` 或被发布给 DPU。

## 26.6 Reset and Verification Requirements

- `aresetn=0` 或 `soft_reset=1` 清除适配器状态、有效信号、脉冲、错误和计数。
- 复位期间不得产生命令、数据、状态握手或调度器事件。
- 必须验证三个缓冲地址、非法缓冲3、固定 BTT、命令先于数据、RGB字节顺序、
  `TKEEP`、输入 EOL、整帧输出 `TLAST`、三个 AXI4-Stream 通道反压、成功/失败状态、
  `dm_s2mm_err`、完整640x640像素数以及软/硬复位。
- 必须联合验证适配器与 `pl_frame_scheduler`：失败帧回到 `FREE`，不增加
  `completed_frames`，不进入 `READY`，不消耗 `frame_id`，不覆盖 `DPU_OWNED`。
- 必须进行 SystemVerilog Testbench、自检查断言、软件金标准、Vivado XSim 仿真、
  OOC（Out-of-Context，脱离上下文）综合、IP打包、`component.xml`检查和隔离
  Block Design 验证。正式 `project_1` 在本阶段仍不修改。

---

# 27. `pl_sys_ctrl` Stage 7 Integration Addendum (V0.8)

本节是 V0.8 相对 V0.7 的新增内容。V0.7 文件正文保持不变；本文件前面的全部
内容是从 `INTERFACE_v0.7.md` 原样复制而来。原文件名虽然为 V0.7，但文件头仍
保留了历史的 `Version: v0.4` 标记，本附录以文件名和本节为当前版本依据，不回写
旧文件。

## 27.1 Purpose

第七阶段只完成 `pl_sys_ctrl`（PL system control，PL系统控制器）与帧调度器、
DDR 写入适配器之间的控制和状态集成，不修改正式主工程 `project_1`。已有寄存器
偏移、请求邮箱、结果邮箱和保持型中断语义全部保持不变。

`FRAME_CNT` 继续表示视频链路已经完整处理的帧数量；它不改为调度器统计量。

## 27.2 Added Read-Only Registers

以下寄存器使用 V0.7 的保留地址，只读，写入不产生副作用：

| Offset | Register | Width | Source | Definition |
|---:|---|---:|---|---|
| `0x70` | `SCHED_COMPLETED_FRAMES` | 32 | `completed_frames` | 已完成并进入 READY 的帧数量 |
| `0x74` | `STALE_FRAMES` | 32 | `stale_frames` | Fresh-Frame 选择时释放的旧 READY 帧数量 |
| `0x78` | `DROPPED_FRAMES` | 32 | `dropped_frames` | 调度器累计丢弃帧数量 |
| `0x7C` | `STALE_RESULTS` | 32 | `stale_results` | 未匹配当前 DPU 所有权的结果数量 |
| `0x80` | `BUFFER_CONFLICTS` | 32 | `buffer_conflicts` | 无 FREE 缓冲区导致的冲突数量 |
| `0x84` | `FRAMES_ABORTED` | 32 | `frames_aborted` | DDR 写入或视频协议失败而放弃的帧数量 |
| `0x88` | `BUFFER_STATE` | 6 | `dpu_owned_mask`, `ready_mask` | bit[2:0] 为 DPU 所有权，bit[5:3] 为 READY 状态 |
| `0x8C` | `ERROR_SOURCE` | 8 | 控制器错误来源 | 最近一次保存错误的来源编码 |

`BUFFER_STATE` 位定义：

```text
bit[2:0] = dpu_owned_mask[2:0]
bit[5:3] = ready_mask[2:0]
bit[31:6] = 0
```

`ERROR_SOURCE` 编码：

| Value | Name | Meaning |
|---:|---|---|
| `0x00` | `ERROR_SOURCE_NONE` | 没有保持型错误 |
| `0x01` | `ERROR_SOURCE_EXTERNAL` | 外部 `err` 或视频错误 |
| `0x02` | `ERROR_SOURCE_SCHEDULER` | 调度器缓冲区冲突或过期结果 |
| `0x03` | `ERROR_SOURCE_DATAMOVER` | DDR DataMover 写入错误 |
| `0x04` | `ERROR_SOURCE_PROTOCOL` | 帧协议错误或帧放弃 |

## 27.3 Added Internal Ports

`pl_sys_ctrl` 增加以下输入端口。它们与 AXI-Lite 使用同一时钟域；若未来跨时钟域，
必须先经过事件同步或一致性快照，不得逐位直接同步多比特计数器。

| Port | Direction | Width | Meaning |
|---|---|---:|---|
| `scheduler_completed_frames` | input | 32 | 调度器完成帧计数 |
| `scheduler_stale_frames` | input | 32 | 调度器过期帧计数 |
| `scheduler_dropped_frames` | input | 32 | 调度器丢帧计数 |
| `scheduler_stale_results` | input | 32 | 调度器过期结果计数 |
| `scheduler_buffer_conflicts` | input | 32 | 调度器缓冲区冲突计数 |
| `adapter_frames_aborted` | input | 32 | DDR适配器放弃帧计数 |
| `scheduler_dpu_owned_mask` | input | 3 | 当前 DPU 所有权掩码 |
| `scheduler_ready_mask` | input | 3 | 当前 READY 缓冲区掩码 |
| `scheduler_buffer_conflict` | input | 1 | 调度器保持型冲突指示 |
| `adapter_protocol_error` | input | 1 | 适配器保持型视频协议错误 |
| `adapter_datamover_error` | input | 1 | 适配器保持型 DataMover 错误 |

新增端口不会替代已有 `err` 和 `err_code_in`。已有外部错误输入仍然有效；第七阶段
只负责把调度器和适配器错误纳入统一保持型错误状态，并在 `ERROR_SOURCE` 中记录
来源。统计寄存器直接反映上游计数器，不在 `pl_sys_ctrl` 内重复计数。

## 27.4 Error Priority

同一时钟周期多个错误同时到达时，错误来源按以下优先级选择，保证结果可重复：

```text
DataMover > protocol/frame_abort > scheduler > external
```

错误状态仍由 `CTRL.clear_error` 清除；清除错误不清除统计寄存器，不清除帧计数，
也不清除请求和结果序号。

## 27.5 Verification Additions

- 验证 `0x70` 至 `0x8C` 的只读映射和写入无副作用。
- 验证调度器和适配器计数器变化可以被软件读取。
- 验证统计输入不改变原有 `FRAME_CNT`、请求邮箱和结果邮箱。
- 验证四类错误来源及其优先级。
- 验证错误保持、`IRQ_STATUS` 保持、`IRQ_ACK` 清除和 `clear_error` 清除。
- 验证 `BUFFER_STATE` 与 `dpu_owned_mask`、`ready_mask` 一致。
- V0.8 阶段仍不修改正式 `project_1`。

---

# 28. `pl_profiler` Contract (V0.9 addition)

本节是 V0.9 相对 V0.8 的唯一新增内容。V0.8 的全部原文保持不变。
`pl_profiler` 是独立、可编辑的旁路观测 IP。它只监视帧写入、DPU 请求和合法结果
事件，不参与 AXI4-Stream 数据传输，不拥有帧缓冲区，也不直接执行故障恢复。

## 28.1 Clock, Counter and Command Semantics

- 全部端口位于同一个 `aclk` 时钟域。跨时钟事件必须在进入本模块前完成同步。
- 64 位 `cycle_counter` 每个有效时钟周期加1，硬复位或 `soft_reset` 清零。
- 周期差定义为终止事件被采样时的 `cycle_counter` 减去起始事件保存值。
- 超过32位的单次持续时间在输出统计中饱和为 `32'hFFFF_FFFF`。
- `clear_stats` 和 `snapshot_stats` 均为单周期脉冲。
- `clear_stats` 清除累计统计、快照和保持型统计状态，但不终止已经开始的帧或
  DPU请求，也不允许同一个活动请求再次产生超时事件。
- `snapshot_stats` 把全部实时统计和64位周期计数在同一拍复制到快照输出，保证软件
  读取多个寄存器时得到一致数据。同拍发生的新事件不包含在本次快照中。

## 28.2 Exact Port Table

| Port | Direction | Width | Meaning |
|---|---|---:|---|
| `aclk` | input | 1 | 统计时钟 |
| `aresetn` | input | 1 | 异步低有效复位 |
| `soft_reset` | input | 1 | 同步高有效复位 |
| `clear_stats` | input | 1 | 清统计命令脉冲 |
| `snapshot_stats` | input | 1 | 捕获一致性快照命令脉冲 |
| `frame_start` | input | 1 | DDR帧事务开始事件 |
| `frame_end` | input | 1 | DDR帧事务成功结束事件 |
| `frame_abort` | input | 1 | DDR帧事务失败结束事件，优先于成功 |
| `request_commit` | input | 1 | 调度器发布DPU请求事件 |
| `request_frame_id` | input | 32 | 请求来源帧编号 |
| `request_buffer_id` | input | 2 | 请求缓冲区编号 |
| `request_generation` | input | 32 | 请求缓冲区代际 |
| `result_release` | input | 1 | 调度器确认结果匹配并释放缓冲区事件 |
| `result_frame_id` | input | 32 | 合法结果来源帧编号 |
| `result_buffer_id` | input | 2 | 合法结果缓冲区编号 |
| `result_generation` | input | 32 | 合法结果缓冲区代际 |
| `scheduler_completed_frames` | input | 32 | 调度器累计完整帧数 |
| `dpu_timeout_pulse` | output | 1 | 每个活动请求最多一次的超时事件 |
| `frame_active` | output | 1 | 正在测量帧事务 |
| `dpu_active` | output | 1 | 正在等待匹配结果 |
| `dpu_timeout_sticky` | output | 1 | 至少发生过一次DPU超时 |
| `last_frame_aborted` | output | 1 | 最近测量的帧事务以abort结束 |
| `measurement_error` | output | 1 | 重叠起始、无起始终止或身份不匹配 |
| `snapshot_valid` | output | 1 | 至少捕获过一次有效快照 |
| `cycle_snapshot` | output | 64 | 一致性周期快照 |
| `last_frame_cycles_snapshot` | output | 32 | 最近帧事务周期 |
| `max_frame_cycles_snapshot` | output | 32 | 最大帧事务周期 |
| `last_dpu_latency_snapshot` | output | 32 | 最近请求到合法结果周期 |
| `max_dpu_latency_snapshot` | output | 32 | 最大请求到合法结果周期 |
| `last_result_frame_age_snapshot` | output | 32 | 最近结果返回帧龄 |
| `max_result_frame_age_snapshot` | output | 32 | 最大结果返回帧龄 |
| `dpu_timeout_count_snapshot` | output | 32 | DPU超时累计次数 |
| `profiled_frames_snapshot` | output | 32 | 已结束帧事务数量，含end和abort |
| `profiled_requests_snapshot` | output | 32 | 已接受DPU请求数量 |
| `profiled_results_snapshot` | output | 32 | 已接受匹配结果数量 |

参数 `DPU_TIMEOUT_CYCLES` 默认为 `100_000_000`；设置为0表示禁用超时检测。

## 28.3 Frame and DPU Measurement Behavior

- `frame_start` 在空闲时保存起始周期；活动期间再次出现只置
  `measurement_error`，不覆盖原起始值。
- `frame_end` 或 `frame_abort` 结束测量并更新最近值、最大值和
  `profiled_frames`。两者同拍属于协议错误，`frame_abort` 作为最近终止类型。
- `request_commit` 保存 Frame ID、Buffer ID、Generation 和起始周期。
- 活动请求期间新的 `request_commit` 只置错误，不覆盖当前请求。
- 只有 `result_release=1` 且三个身份字段全部匹配，才更新DPU延迟并结束活动请求。
- `ResultReturnFrameAge = scheduler_completed_frames - 1 - result_frame_id`，按32位无符号
  模运算解释；正常系统中结果帧不得新于最新完整帧。
- 该帧龄是“结果返回时相对最新完整帧的落后量”，不是最终显示帧龄。正式显示帧龄
  必须等显示模块提供 `DisplayFrameID` 后按
  `DisplayFrameID - ResultSourceFrameID` 计算。

## 28.4 `pl_sys_ctrl` Stage 8 Register Addition

`pl_sys_ctrl` 增加两个命令输出 `profiler_clear_stats`、
`profiler_snapshot_stats`，以及本节快照和状态对应的输入端口。所有新增寄存器不改变
V0.8 的 `0x00` 至 `0x8C` 映射。

| Offset | Register | Access | Definition |
|---:|---|---|---|
| `0x90` | `PROF_CTRL` | WO | bit0清统计，bit1捕获快照；写1产生一拍 |
| `0x94` | `PROF_CYCLE_LO` | RO | 64位周期快照低32位 |
| `0x98` | `PROF_CYCLE_HI` | RO | 64位周期快照高32位 |
| `0x9C` | `LAST_FRAME_CYCLES` | RO | 最近帧事务周期 |
| `0xA0` | `MAX_FRAME_CYCLES` | RO | 最大帧事务周期 |
| `0xA4` | `LAST_DPU_LATENCY` | RO | 最近请求到合法结果周期 |
| `0xA8` | `MAX_DPU_LATENCY` | RO | 最大请求到合法结果周期 |
| `0xAC` | `LAST_RESULT_FRAME_AGE` | RO | 最近结果返回帧龄 |
| `0xB0` | `MAX_RESULT_FRAME_AGE` | RO | 最大结果返回帧龄 |
| `0xB4` | `DPU_TIMEOUT_COUNT` | RO | DPU超时次数 |
| `0xB8` | `PROF_STATUS` | RO | bit0 frame_active，bit1 dpu_active，bit2 timeout sticky，bit3 last abort，bit4 measurement error，bit5 snapshot valid |
| `0xBC` | `PROFILED_FRAMES` | RO | 已测量结束帧事务数 |
| `0xC0` | `PROFILED_REQUESTS` | RO | 已接受DPU请求数 |
| `0xC4` | `PROFILED_RESULTS` | RO | 已接受匹配结果数 |

保留 `0xC8` 至 `0xFC`。V0.8 已有的丢帧、过期帧、冲突和放弃帧寄存器仍是
这些统计的唯一权威来源，`pl_profiler` 不重复累计它们。

## 28.5 Verification Requirements

- 验证帧成功、帧放弃、连续多帧、最近值和最大值。
- 验证请求身份锁存、合法结果、身份不匹配、重叠请求和结果帧龄。
- 验证超时阈值、每请求单次脉冲、迟到结果和清统计后不重复超时。
- 验证一致性快照、64位高低字、清统计、软复位和异步硬复位。
- 使用SystemVerilog Testbench、SVA断言、软件金标准、XSim、OOC综合、IP打包、
  `component.xml`检查和隔离Block Design验证。
- 第八阶段仍不修改正式 `project_1`。

---

# 29. `pl_error_recovery` Contract (V0.10 addition)

本节是 V0.10 相对 V0.9 的唯一新增内容。V0.9 的全部原文保持不变。
`pl_error_recovery` 是系统级故障恢复协调器。它不检查像素内容，也不代替
`pl_video_in`、`pl_frame_write_adapter` 和 `pl_frame_scheduler` 的本地状态机。
它负责把DPU超时、DataMover致命错误、视频协议错误和帧放弃转换为唯一、确定、
可统计的恢复动作。

## 29.1 Recovery Ownership and Priority

恢复职责固定如下：

| Fault | Local owner | Recovery action |
|---|---|---|
| 视频SOF/EOL错误 | `pl_video_in` | 丢弃错误帧，下一次SOF自动重新开始 |
| DDR帧协议错误 | `pl_frame_write_adapter` | 固定BTT收尾后产生`frame_abort`，调度器回收WRITING缓冲 |
| DataMover失败状态 | `pl_frame_write_adapter` | 当前帧`frame_abort`，记录失败，不执行致命复位 |
| DataMover S2MM fatal | `pl_error_recovery` | 适配器和DataMover同时保持复位至少3拍 |
| DPU请求超时 | `pl_error_recovery` | 取消请求邮箱、终止Profiler测量、释放当前DPU_OWNED缓冲 |

同拍优先级：

```text
DataMover fatal > DPU timeout > software trigger > video error > frame abort
```

恢复模块不得产生视频AXI4-Stream数据，不得直接产生`frame_abort`，也不得清除其他
READY缓冲区。DPU超时只回收当前唯一的DPU_OWNED缓冲区。

## 29.2 Exact Port Table

| Port | Direction | Width | Meaning |
|---|---|---:|---|
| `aclk` | input | 1 | 恢复协调时钟 |
| `aresetn` | input | 1 | 异步低有效复位 |
| `soft_reset` | input | 1 | 同步高有效全局软复位 |
| `clear_status` | input | 1 | 清保持状态和最近原因，不清累计次数 |
| `software_trigger` | input | 1 | 软件请求取消当前DPU所有权 |
| `dpu_timeout_pulse` | input | 1 | Profiler产生的一拍DPU超时事件 |
| `dpu_owned_present` | input | 1 | 调度器当前存在DPU_OWNED缓冲 |
| `dpu_owner_abort_ack` | input | 1 | 调度器确认已释放DPU所有权 |
| `datamover_fatal` | input | 1 | DataMover S2MM保持型致命错误 |
| `video_error_pulse` | input | 1 | 正式`pl_video_in.err`事件 |
| `frame_abort` | input | 1 | DDR写适配器放弃帧事件 |
| `frame_abort_reason` | input | 2 | 01协议，10状态失败，11致命错误 |
| `dpu_owner_abort` | output | 1 | 请求调度器释放当前DPU所有权的一拍脉冲 |
| `request_cancel` | output | 1 | 取消控制器活动请求的一拍脉冲 |
| `profiler_request_abort` | output | 1 | 结束Profiler活动请求的一拍脉冲 |
| `adapter_recovery_reset` | output | 1 | DDR写适配器本地高有效恢复复位 |
| `datamover_recovery_reset` | output | 1 | 送往DataMover复位控制的高有效请求 |
| `recovery_event_pulse` | output | 1 | 每次接受新恢复事件产生一拍 |
| `recovery_active` | output | 1 | 正在等待所有权确认或保持致命复位 |
| `fatal_sticky` | output | 1 | 至少发生过一次DataMover fatal |
| `protocol_sticky` | output | 1 | 至少发生过一次视频/帧协议恢复 |
| `software_sticky` | output | 1 | 至少执行过一次软件触发恢复 |
| `recovery_done_sticky` | output | 1 | 至少有一次恢复动作完成 |
| `last_reason` | output | 8 | 最近一次恢复原因编码 |
| `recovery_count` | output | 32 | 已接受恢复事件总数 |
| `dpu_timeout_recoveries` | output | 32 | DPU超时恢复次数 |
| `datamover_recoveries` | output | 32 | DataMover fatal或失败状态次数 |
| `protocol_recoveries` | output | 32 | 视频或帧协议恢复次数 |

参数 `DATAMOVER_RESET_CYCLES` 默认为4，合法范围3至65535。复位输出必须连续保持
准确的参数周期数。保持型 `datamover_fatal` 在返回低电平以前不得重复触发恢复。

## 29.3 Recovery Reason Encoding

| Value | Name | Meaning |
|---:|---|---|
| `0x00` | `NONE` | 没有已记录恢复 |
| `0x01` | `DPU_TIMEOUT` | DPU请求超过Profiler阈值 |
| `0x02` | `DATAMOVER_FATAL` | DataMover S2MM致命错误 |
| `0x03` | `VIDEO_PROTOCOL` | `pl_video_in`检测到SOF/EOL错误 |
| `0x04` | `FRAME_PROTOCOL` | DDR帧写适配器检测到帧协议错误 |
| `0x05` | `SOFTWARE` | 软件主动取消当前DPU请求 |
| `0x06` | `DATAMOVER_STATUS` | DataMover状态流返回非成功状态 |

## 29.4 Scheduler, Profiler, Adapter and Mailbox Additions

### `pl_frame_scheduler`

- 新增输入 `dpu_owner_abort` 和输出 `dpu_owner_abort_ack`。
- 有活动DPU所有权时，`dpu_owner_abort`使该槽从DPU_OWNED变为FREE，
  `dropped_frames`加1并输出一拍确认。
- 无活动所有权时不修改任何槽，也不输出确认。
- `dpu_owner_abort`与`result_commit_pulse`同拍时，恢复取消优先。

### `pl_profiler`

- 新增输入 `request_abort`。
- 活动请求被恢复取消时停止延迟测量并清除内部单次超时标记，不把取消计为合法结果。
- 无活动请求时收到`request_abort`置`measurement_error`。

### `pl_frame_write_adapter`

- 新增输入 `recovery_reset`和输出`frame_abort_reason[1:0]`。
- `recovery_reset`返回IDLE并清除本地保持错误，但保留`frames_written`和
  `frames_aborted`累计证据。
- `frame_abort_reason`只在`frame_abort`有效拍有意义：01协议、10失败状态、11 fatal。

### `pl_sys_ctrl`

- 新增内部`request_active`，独立于软件IRQ确认使用的`request_pending`。
- 发布请求时置活动；合法结果或`request_cancel`时清活动。
- 结果提交必须同时满足`request_active=1`和Frame ID、Buffer ID、Generation全匹配。
- `request_cancel`与软件结果提交同拍时，取消优先，结果按过期结果拒绝。

## 29.5 AXI4-Lite Register Addition

V0.9的`0x00`至`0xC4`保持不变。新增：

| Offset | Register | Access | Definition |
|---:|---|---|---|
| `0xC8` | `RECOVERY_CTRL` | WO | bit0清保持状态；bit1软件触发恢复，写1产生一拍 |
| `0xCC` | `RECOVERY_STATUS` | RO | bit0 active，bit1 fatal sticky，bit2 protocol sticky，bit3 software sticky，bit4 done sticky |
| `0xD0` | `RECOVERY_REASON` | RO | 最近恢复原因编码 |
| `0xD4` | `RECOVERY_COUNT` | RO | 已接受恢复事件总数 |
| `0xD8` | `DPU_TIMEOUT_RECOVERIES` | RO | DPU超时恢复次数 |
| `0xDC` | `DATAMOVER_RECOVERIES` | RO | DataMover恢复/失败次数 |
| `0xE0` | `PROTOCOL_RECOVERIES` | RO | 视频和帧协议恢复次数 |

保留`0xE4`至`0xFC`。`clear_status`不清累计计数，不清Profiler统计，也不清调度器
丢帧统计。

## 29.6 Verification Requirements

- 验证DPU超时取消邮箱、终止Profiler并只释放当前DPU_OWNED缓冲。
- 验证调度器确认以前`recovery_active`保持为1。
- 验证迟到结果和取消同拍结果均不能合法提交。
- 验证DataMover fatal复位长度、保持型错误防重复和重新拉低后的再次触发。
- 验证适配器从ST_FATAL返回IDLE且累计计数不被本地恢复复位清除。
- 验证视频错误后正式`pl_video_in`丢弃错误帧并在下一次SOF恢复。
- 验证协议、失败状态、软件触发、清状态和全部恢复计数。
- 执行SystemVerilog Testbench、SVA、软件金标准、XSim、OOC综合、重新打包、
  `component.xml`检查和隔离Block Design验证。
- 第九阶段仍不修改正式`project_1`。

---

# 30. 第十阶段正式主工程系统集成合同（V0.11 新增）

本节是 V0.11 相对 V0.10 的唯一新增内容。V0.10 的全部原文必须逐字节保持不变。
本节只规定正式 `project_1` 的模块连接、时钟、复位、DDR 地址、CDC 和时序验收，
不修改第1至第29节已经冻结的任何模块端口、寄存器偏移或单模块行为。

## 30.1 正式系统边界

第十阶段正式主工程必须包含以下可编辑或已封装模块：

```text
Zynq UltraScale+ MPSoC PS
AXI SmartConnect（PS控制通路）
Processor System Reset
dummy_video_in_source
pl_video_in
pl_preproc_letterbox
pl_frame_scheduler
pl_frame_write_adapter
pl_profiler
pl_error_recovery
AXI DataMover 5.1（只启用S2MM）
AXI SmartConnect（DDR写通路）
```

正式数据通路固定为：

```text
dummy_video_in_source
  -> pl_video_in
  -> pl_preproc_letterbox
  -> pl_frame_write_adapter
  -> AXI DataMover S2MM
  -> Zynq PS S_AXI_HP0_FPD
  -> PS DDR
```

第十阶段使用内部纯黑视频源完成结构验证，不连接真实摄像头、HDMI或DPU。DPU请求
仍通过 `pl_sys_ctrl` 请求邮箱交给PS软件；结果通过同一控制器的结果影子寄存器和原子
提交接口返回。

## 30.2 单时钟域合同

第十阶段全部PL模块使用同一个 `zynq_ultra_ps_e_0/pl_clk0`：

| 项目 | 固定值 |
|---|---|
| 目标频率 | 100 MHz |
| PS时钟源 | IOPLL |
| Vivado 2022.2计算实际频率 | 99.999001 MHz |
| AXI4-Lite控制域 | `pl_clk0` |
| 视频AXI4-Stream域 | `pl_clk0` |
| 调度、Profiler、恢复域 | `pl_clk0` |
| DataMover命令、数据、状态和AXI主端 | `pl_clk0` |

第十阶段不允许为了展示CDC而人为增加第二时钟域。现有
`cdc_async_fifo`、`cdc_axis_bridge`、`cdc_pulse_sync` 和
`cdc_handshake_sync` 保留给未来真实异步视频源使用，但不插入本阶段同步数据通路。

## 30.3 复位合同

`zynq_ultra_ps_e_0/pl_resetn0` 送入 `proc_sys_reset_0/ext_reset_in`，并把
`proc_sys_reset_0` 配置为外部复位低有效。`pl_clk0` 送入
`proc_sys_reset_0/slowest_sync_clk`。

| 复位输出 | 使用者 |
|---|---|
| `interconnect_aresetn` | 控制SmartConnect、DDR SmartConnect |
| `peripheral_aresetn` | 全部自研IP和DataMover正常复位路径 |
| `peripheral_reset` | 仅在需要高有效复位状态时使用 |

`pl_error_recovery.datamover_recovery_reset` 是同步高有效恢复请求，默认连续4拍。
DataMover实际低有效复位定义为：

```text
datamover_aresetn = peripheral_aresetn
                      AND NOT soft_reset
                      AND NOT datamover_recovery_reset
```

同一个 `datamover_recovery_reset` 必须同时送到
`pl_frame_write_adapter.recovery_reset`。禁止把一拍错误事件直接接到DataMover复位端，
禁止只复位DataMover而不复位适配器。

`pl_preproc_letterbox` 没有独立 `soft_reset` 端口，因此其低有效复位必须定义为：

```text
letterbox_aresetn = peripheral_aresetn AND NOT soft_reset
```

这样软件软复位可以把Letterbox从 `ST_ERROR` 返回初始状态，同时不改变第4阶段已经冻结的
Letterbox端口和算法行为。

## 30.4 AXI DataMover 固定配置

| Property | Value |
|---|---:|
| IP version | AXI DataMover 5.1 |
| `c_enable_mm2s` | 0 |
| `c_enable_s2mm` | 1 |
| `c_include_s2mm` | Full |
| `c_addr_width` | 40 |
| `c_m_axi_s2mm_addr_width` | 40 |
| `c_m_axi_s2mm_data_width` | 64 |
| `c_s_axis_s2mm_tdata_width` | 32 |
| `c_s2mm_btt_used` | 23 |
| `c_s2mm_burst_size` | 16 |
| `c_s2mm_support_indet_btt` | false |
| `c_include_s2mm_stsfifo` | true |
| command width | 80 bits |
| status width | 8 bits |

连接必须逐拍保持：

```text
pl_frame_write_adapter.dm_cmd_*  -> S_AXIS_S2MM_CMD
pl_frame_write_adapter.dm_data_* -> S_AXIS_S2MM
M_AXIS_S2MM_STS                  -> pl_frame_write_adapter.dm_sts_*
axi_datamover.s2mm_err           -> pl_frame_write_adapter.dm_s2mm_err
axi_datamover.s2mm_err           -> pl_error_recovery.datamover_fatal
```

`M_AXI_S2MM` 经独立DDR SmartConnect连接到PS的 `S_AXI_HP0_FPD`。PS必须启用
`PSU__USE__S_AXI_GP2=1`，HP0端口数据宽度保持128位，SmartConnect负责64位到128位
的数据宽度适配。

## 30.5 三缓冲DDR地址合同

第十阶段综合和结构验证使用以下地址：

| Buffer | Physical start address | Bytes |
|---:|---:|---:|
| 0 | `40'h0020000000` | `0x190000` |
| 1 | `40'h0020190000` | `0x190000` |
| 2 | `40'h0020320000` | `0x190000` |

地址总区间为：

```text
0x2000_0000 <= frame buffer address < 0x204B_0000
```

总长度为 `0x4B0000` 字节。该地址位于PS低DDR地址窗口内，但第十阶段只证明硬件结构、
综合、实现和时序正确。真正上板前，Linux设备树必须用 `reserved-memory` 保留完整区域，
软件必须确认它没有被内核、CMA、DPU或其他DMA设备占用。在完成该保留以前，软件不得把
`CTRL.enable` 置1，也不得启动DataMover写帧。

RGB888的DDR小端字节顺序继续使用第26节定义：低地址到高地址为 `R, G, B, 0`。

## 30.6 控制、邮箱与中断连接

| Source | Destination | Rule |
|---|---|---|
| `pl_sys_ctrl.enable` | dummy、video、scheduler、adapter | 持续型系统使能 |
| `pl_sys_ctrl.soft_reset` | 全部自研状态模块 | 同步软复位 |
| `pl_sys_ctrl.clear_error` | `pl_video_in.clear_error` | 清视频错误码 |
| scheduler request fields | `pl_sys_ctrl` request mailbox inputs | 同拍原子发布 |
| `pl_sys_ctrl` result identity | scheduler和Profiler | 只接正式提交值 |
| scheduler `result_release` | Profiler | 合法结果完成事件 |
| recovery `request_cancel` | `pl_sys_ctrl` | 取消活动请求 |
| `pl_sys_ctrl.irq` | PS `pl_ps_irq0[0]` | 单比特保持型中断 |

第十阶段没有独立PL结果消费者，因此 `pl_sys_ctrl.result_ack` 固定为0；结果保持到PS软件
按既有寄存器协议确认。`pl_frame_scheduler.dpu_ready` 固定为1，表示PS请求邮箱可以接受
一个请求；控制器内部 `request_active` 和调度器DPU_OWNED状态仍共同阻止第二个活动请求。

首版没有输入FIFO，因此 `fifo_ovf=0`、`fifo_empty=1`。这些常量不得与视频AXI4-Stream
握手信号混用。

## 30.7 错误与恢复连接

```text
pl_video_in.err
  -> pl_sys_ctrl.err
  -> pl_error_recovery.video_error_pulse

pl_frame_write_adapter.frame_abort/reason
  -> pl_frame_scheduler
  -> pl_profiler
  -> pl_error_recovery

pl_profiler.dpu_timeout_pulse
  -> pl_error_recovery.dpu_timeout_pulse

pl_error_recovery.dpu_owner_abort
  -> pl_frame_scheduler.dpu_owner_abort

pl_frame_scheduler.dpu_owner_abort_ack
  -> pl_error_recovery.dpu_owner_abort_ack
```

`dpu_owned_present` 必须由 `|scheduler_dpu_owned_mask` 生成，不允许使用软件推测值。
DataMover `s2mm_err` 是保持型fatal来源，既送适配器本地状态机，也送恢复协调器。

`pl_preproc_letterbox.error` 在当前实现中表示模块进入不可自动恢复的协议错误状态。
第十阶段先用可编辑的 `stage10_error_edge` 把该保持电平转换为每次断言只产生一次的
单拍事件，再与 `pl_video_in.err` 进行系统级或运算并送入
`pl_error_recovery.video_error_pulse`，因此该错误至少会进入协议恢复统计和保持状态，
不得静默删除。`stage10_error_edge` 与Letterbox使用相同的时钟和复位。
`pl_sys_ctrl.err` 和 `err_code_in` 仍只连接 `pl_video_in`，避免Letterbox错误被错误地
解释为某个视频错误码。若未来要求软件直接区分Letterbox错误，应在后续接口版本新增独立
状态位，不得复用已有视频错误码。

## 30.8 CDC 与 XDC 规则

- 本阶段所有功能逻辑同域，预期 `report_cdc` 不产生用户逻辑跨域违例。
- 禁止使用全局或宽泛 `set_false_path` 来消除时序告警。
- 禁止对PS导出的 `pl_clk0` 重复执行 `create_clock`。
- XPM CDC/FIFO未来引入时，优先使用XPM自带约束；只有报告证明无法自动识别时才添加
  精确点对点约束。
- 异步复位允许异步断言，但释放必须由 `proc_sys_reset` 或等价同步结构完成。
- `report_clock_interaction` 中除工具内部PS关系外，不应出现未解释的用户异步时钟组。

第十阶段XDC文件只记录约束策略和必要例外。如果没有需要额外约束的顶层PL引脚或真实
CDC路径，允许XDC不添加伪造时钟或false path。

## 30.9 第十阶段验收要求

必须完成：

1. V0.10是V0.11的精确字节前缀。
2. 八个自研IP的 `component.xml` 与本节连接端口一致。
3. 前九阶段Testbench和SVA回归全部通过。
4. 新增系统连接静态审计和DataMover属性探针。
5. `validate_bd_design` 通过。
6. 重新生成 `design_1_wrapper`。
7. 全部BD IP OOC综合通过。
8. 主工程综合通过。
9. 实现完成到 `route_design`。
10. `report_drc` 不存在阻止实现或比特流生成的错误。
11. `report_cdc` 不存在未解释的严重CDC问题。
12. `report_timing_summary` 满足 WNS大于等于0、TNS等于0。
13. 不存在未约束的用户关键路径。
14. 生成中文验收报告、重建Tcl和最终SHA-256快照。

第十阶段不下载ZCU104，不启动Linux，不运行Vitis AI，不执行DPU推理。最终 `.bit`、
`.hwh`、`.xsa` 和板端交付整理属于第十一阶段；但第十阶段实现结果必须达到可生成比特流
的质量门槛。

---

# 31. V0.12 复位协调与真实写事务合同

本节是 V0.12 相对 V0.11 的唯一新增内容。V0.11 的全部原文必须逐字节保持不变。
本节修复软件复位过短和组合 LUT 驱动官方 IP 异步复位的风险，并把官方
AXI DataMover（高级可扩展接口数据搬运器）的真实存储事务仿真列为发布门槛。

## 31.1 `pl_reset_ctrl` 端口

| 端口 | 方向 | 位宽 | 精确定义 |
|---|---:|---:|---|
| `aclk` | input | 1 | 与写适配器、调度器和 DataMover 命令/状态侧相同的时钟 |
| `aresetn` | input | 1 | 系统低有效复位；异步断言、同步释放来源必须是 `proc_sys_reset` |
| `soft_reset_req` | input | 1 | `pl_sys_ctrl` 发出的一拍软件复位请求 |
| `recovery_reset_req` | input | 1 | DataMover 致命错误恢复请求 |
| `writer_busy` | input | 1 | 写适配器存在已接受但尚未完成的帧事务 |
| `writer_quiesce` | output | 1 | 为1时禁止调度器向写适配器许可新帧 |
| `pipeline_soft_reset` | output | 1 | 送往自研流水线模块的同步高有效软复位 |
| `letterbox_aresetn` | output | 1 | 送往 Letterbox 及其错误边沿模块的寄存器化低有效复位 |
| `datamover_aresetn` | output | 1 | 同时送往 DataMover 两个低有效复位端的寄存器化复位 |
| `adapter_recovery_reset` | output | 1 | 与 DataMover 复位窗口一致的写适配器恢复复位 |
| `reset_busy` | output | 1 | 排空、复位断言或释放保护尚未完成 |

## 31.2 精确时序

1. 普通软件复位先进入 `DRAIN`：立即置 `writer_quiesce=1`，不得再接受新帧。
2. 若 `writer_busy=1`，等待当前 DataMover 写事务返回状态；不得截断正常 AXI 突发。
3. 当 writer 空闲或排空超时后，进入 `ASSERT_RESET`。
4. `pipeline_soft_reset`、`adapter_recovery_reset` 有效且
   `letterbox_aresetn`、`datamover_aresetn` 为低的时间均不得少于三个完整
   `aclk` 周期；正式参数为四拍。
5. `recovery_reset_req` 表示致命恢复，可跳过普通排空等待并立即进入复位窗口。
6. 所有受控复位输出必须由 `aclk` 触发的寄存器直接驱动。禁止使用
   `aresetn AND NOT request` 一类组合 LUT 输出直接驱动官方 IP 异步复位引脚。
7. 释放后保留一个 `RELEASE` 保护周期，然后撤销 `writer_quiesce`。
8. writer 永不空闲时，`DRAIN_TIMEOUT_CYCLES` 到期必须执行有界恢复，不能永久死锁。

Vivado 2022.2 中对本工程配置的 AXI DataMover 5.1 端口探针确认：S2MM 配置没有
`s2mm_halt` 或 `s2mm_halt_cmplt`。因此本合同使用“阻止新帧 + 等待
`pl_frame_write_adapter.busy` 清零”的排空方式，不允许连接不存在的 halt 端口。

## 31.3 Block Design 连接

```text
pl_sys_ctrl.soft_reset -> pl_reset_ctrl.soft_reset_req
pl_error_recovery.datamover_recovery_reset -> pl_reset_ctrl.recovery_reset_req
pl_frame_write_adapter.busy -> pl_reset_ctrl.writer_busy

pl_reset_ctrl.writer_quiesce
  -> NOT -> AND(pl_frame_scheduler.frame_start_ready)
  -> pl_frame_write_adapter.scheduler_frame_start_ready

pl_reset_ctrl.pipeline_soft_reset
  -> dummy_video_in_source / pl_video_in / pl_frame_scheduler
  -> pl_frame_write_adapter / pl_profiler / pl_error_recovery

pl_reset_ctrl.datamover_aresetn
  -> axi_datamover.m_axi_s2mm_aresetn
  -> axi_datamover.m_axis_s2mm_cmdsts_aresetn
```

写适配器新增两个编译期参数：`FRAME_WIDTH` 和 `FRAME_HEIGHT`，正式主工程默认值均为
640，因此正式命令的 BTT（待传输字节数）仍为 `640×640×4 = 0x190000`，缓冲跨度和
软件地址合同不变。参数合法范围为1到1024，且总字节数不得超过DataMover的23位BTT。
参数化仅用于在目标器件可用片上存储容量内运行官方DataMover闭环Testbench；不得在没有
同步修改三缓冲地址合同的情况下改变正式主工程默认值。

## 31.4 V0.12 新增验收门槛

- 复位单元 Testbench 覆盖普通排空、至少三拍、致命恢复和排空超时。
- 真实 AXI-Lite 写 `CTRL.soft_reset` 后，DataMover 实际复位窗口不少于三拍。
- `report_methodology` 不得出现 `LUTAR-*` 方法学违规。
- 使用官方 AXI DataMover、AXI BRAM Controller 和 Block Memory Generator 完成
  参数化完整帧的S2MM（流到存储器映射）写事务仿真，检查命令地址、突发、状态、
  字节使能、像素字节顺序和内存内容；抽象 ready/status 模型不能替代此项。正式
  640×640默认参数仍由既有全帧行为仿真、BTT断言和Package IP检查覆盖。
- 补充正式尺寸官方DataMover验证：使用固定版本开源AXI RAM模型，按640×640、
  每像素四字节完成三帧写入与全部像素回读，监测AW/W/B事务，并加入确定性地址/
  数据反压。此项补强完整BTT路径，不代表物理DDR或真实DPU缓存一致性验收。
- 重新执行全部 RTL 回归、IP 完整性检查、BD 验证、综合、实现、DRC、CDC 和时序检查。
- 只有上述门槛全部通过后，才可生成 V0.12 的 `.bit`、`.hwh` 和 `.xsa`。

本合同只证明 PL 硬件构建与仿真达到交付条件，不等同于 ZCU104 实机、DPU 推理、
NMS、OSD、HDMI 或整机闭环已经完成。

---

# 32. V0.13 PC实时视频输入合同

本节是V0.13相对V0.12的唯一新增合同。V0.12全部原文必须逐字节保持不变。本功能允许
PC视频文件或USB摄像头经千兆以太网持续发送视频帧，由ZCU104 Linux接收后写入独立DDR
双缓冲，再由官方AXI DMA MM2S读出并转换为现有`pl_video_in`要求的AXI4-Stream Video。

V0.13第一版固定为640×480、GRAY8、逐行从左到右、从上到下。未经新接口版本批准，
不得在PL中增加隐式缩放、裁剪或颜色变换。

## 32.1 系统链路

```text
PC OpenCV视频/摄像头
  -> TCP帧协议
  -> ZCU104 Linux接收程序
  -> DDR输入双缓冲
  -> 官方AXI DMA 7.1 MM2S简单模式
  -> pl_pc_video_stream_formatter
  -> pl_video_in
  -> 既有Letterbox/DataMover/三缓冲链
```

`dummy_video_in_source`必须保留。`video_source_select=0`选择dummy，值1选择PC/DMA。
软件只允许在`CTRL.enable=0`时修改输入源，随后再使能流水线。

## 32.2 PC到板端TCP帧协议

TCP端口默认`5000`。所有多字节整数采用网络字节序（大端）。帧头固定40字节：

| 偏移 | 字段 | 位宽 | V0.13定义 |
|---:|---|---:|---|
| 0x00 | magic | 4字节 | ASCII `FYV1` |
| 0x04 | version | 16 | 固定1 |
| 0x06 | header_size | 16 | 固定40 |
| 0x08 | frame_id | 32 | PC发送序号，自然回绕 |
| 0x0C | width | 16 | 固定640 |
| 0x0E | height | 16 | 固定480 |
| 0x10 | pixel_format | 16 | 1表示GRAY8 |
| 0x12 | flags | 16 | V0.13写0 |
| 0x14 | payload_size | 32 | 固定307200 |
| 0x18 | timestamp_ns | 64 | PC单调时钟时间戳，单位ns |
| 0x20 | crc32 | 32 | payload的IEEE CRC32 |
| 0x24 | reserved | 32 | 写0 |

帧头之后紧跟307200字节payload。接收端必须使用精确长度循环读取，禁止假设一次`recv`
返回完整帧。magic、版本、尺寸、格式、长度或CRC错误的帧必须丢弃，不得启动DMA。

网络线程允许在板端忙时淘汰尚未送入DMA的旧READY输入帧，但不得覆盖DMA正在读取的槽。
断网后监听程序继续运行并允许重连；重连不需要复位PL。

## 32.3 输入DDR双缓冲

| 槽 | 物理基地址 | 槽跨度 | 有效帧字节数 |
|---|---:|---:|---:|
| input 0 | `0x21000000` | `0x00100000` | `0x0004B000` |
| input 1 | `0x21100000` | `0x00100000` | `0x0004B000` |

输入区域必须由Linux设备树或等价机制完整保留为至少2MiB，并且与输出三缓冲
`0x20000000/0x20190000/0x20320000`、CMA和其他DMA不重叠。软件必须解决CPU缓存与DMA
一致性；`/dev/mem`加`O_SYNC`只作为第一版root联调方式，量产或受限内核应改用UIO、
udmabuf或正式驱动。

输入槽状态为`FREE/FILLING/READY/DMA_OWNED`。网络线程只写FREE或淘汰旧READY；DMA线程
只读取READY并在完成后释放。任意时刻最多一个DMA_OWNED槽。

## 32.4 AXI DMA固定配置与软件顺序

官方AXI DMA 7.1只启用MM2S简单模式：Scatter Gather关闭、S2MM关闭、地址宽度32、
M_AXI_MM2S数据宽度64、M_AXIS_MM2S数据宽度8、最大突发16。AXI-Lite控制基址为
`0x80010000`，窗口64KiB。

每帧软件顺序：

1. 确认目标输入槽不是DMA_OWNED。
2. 写入307200字节并完成缓存同步。
3. 确认AXI DMA处于Run状态且无错误。
4. 写MM2S源地址。
5. 最后写MM2S_LENGTH=`0x0004B000`启动一帧。
6. 等待Idle或IOC，检查全部DMA错误位，再释放输入槽。

启动系统时先`CTRL.enable=0`，写`VIDEO_INPUT_CTRL.source_select=1`，复位并启动DMA，
再写`CTRL.enable=1`。停止时先清`CTRL.enable`，等待或复位DMA后退出。V0.13使用轮询方式；
`mm2s_introut`可保留供后续正式驱动使用，但不能据此宣称Linux中断驱动已完成。

## 32.5 `pl_pc_video_stream_formatter`端口

| 端口 | 方向 | 位宽 | 定义 |
|---|---:|---:|---|
| `aclk` | input | 1 | 与AXI DMA MM2S及`pl_video_in`相同的时钟 |
| `aresetn` | input | 1 | `proc_sys_reset.peripheral_aresetn` |
| `enable` | input | 1 | 全局视频链使能 |
| `soft_reset` | input | 1 | V0.12受控同步复位 |
| `clear_error` | input | 1 | 清错误脉冲 |
| `source_select` | input | 1 | 0=dummy，1=PC/DMA；enable期间不得改变 |
| `s_dummy_tdata` | input | 8 | dummy像素 |
| `s_dummy_tvalid/tready` | in/out | 1 | dummy握手 |
| `s_dummy_tuser` | input | 1 | dummy SOF |
| `s_dummy_tlast` | input | 1 | dummy EOL |
| `s_pc_tdata` | input | 8 | AXI DMA MM2S像素 |
| `s_pc_tvalid/tready` | in/out | 1 | PC/DMA握手 |
| `s_pc_tlast` | input | 1 | AXI DMA整帧包末，只允许在第307200像素出现 |
| `m_axis_tdata` | output | 8 | 送`pl_video_in`的GRAY8像素 |
| `m_axis_tvalid/tready` | out/in | 1 | 输出握手 |
| `m_axis_tuser` | output | 1 | PC模式下仅第一像素为1；dummy模式透传 |
| `m_axis_tlast` | output | 1 | PC模式下每640像素为1；dummy模式透传 |
| `active_source` | output | 1 | enable前锁存的实际输入源 |
| `pc_frame_active` | output | 1 | PC帧传输进行中 |
| `pc_frame_done_pulse` | output | 1 | PC完整帧最后一个像素握手时单拍 |
| `pc_error` | output | 1 | 协议错误事件单拍 |
| `pc_error_code` | output | 32 | 最近一次错误码，clear_error清零 |
| `pc_frame_count` | output | 32 | 完成的PC输入帧数 |

PC模式只按`tvalid && tready`推进坐标。反压期间输出数据、TUSER和TLAST必须稳定。
第1像素生成TUSER，每行第640像素生成EOL。DMA `s_pc_tlast`提前为错误`0x00001302`，
最后像素缺失为错误`0x00001303`，enable期间源选择变化为错误`0x00001301`。

## 32.6 V0.13新增控制寄存器

在既有`pl_sys_ctrl` 64KiB窗口内追加：

| 偏移 | 名称 | 访问 | 定义 |
|---:|---|---|---|
| `0xE4` | VIDEO_INPUT_CTRL | RW | bit0 source_select；只在enable=0时接受变化 |
| `0xE8` | VIDEO_INPUT_STATUS | RO | bit0 active_source，bit1 pc_frame_active，bit2 pc_error_sticky |
| `0xEC` | VIDEO_INPUT_ERR_CODE | RO | 最近PC格式化错误码 |
| `0xF0` | VIDEO_INPUT_FRAME_CNT | RO | 完成PC输入帧数 |
| `0xF4` | VIDEO_INPUT_SWITCH_REJECTS | RO | enable期间被拒绝的切源写入次数 |

`VERSION`从`0x00020000`更新为`0x00030000`。`clear_error`清除输入错误状态，不清除帧计数
和切源拒绝计数。PC格式错误并入既有错误IRQ。AXI DMA状态由其独立AXI-Lite窗口读取。

## 32.7 Block Design连接

```text
PS M_AXI_HPM0_LPD
  -> control_smartconnect
     -> pl_sys_ctrl @ 0x80000000
     -> axi_dma/S_AXI_LITE @ 0x80010000

axi_dma/M_AXI_MM2S -> ddr_smartconnect -> PS S_AXI_HP0_FPD
axi_dma/M_AXIS_MM2S -> pl_pc_video_stream_formatter.s_pc
dummy_video_in_source.m_axis -> pl_pc_video_stream_formatter.s_dummy
pl_pc_video_stream_formatter.m_axis -> pl_video_in.s_axis
pl_sys_ctrl.video_source_select -> formatter.source_select
pl_reset_ctrl.pipeline_soft_reset -> formatter.soft_reset
pl_reset_ctrl.datamover_aresetn -> axi_dma.axi_resetn
```

V0.13仍使用PS `pl_clk0`约100MHz的单时钟测试架构。PC网络和Linux线程不属于PL时钟域；
DDR/AXI DMA由PS与官方互连处理。后续接入真实摄像头或HDMI像素时钟仍必须重新设计CDC/XDC。

## 32.8 PC发送端和Linux接收端行为

PC发送端使用OpenCV解码文件或摄像头，显式转换为GRAY8并缩放到640×480；为每帧生成
递增frame_id、单调timestamp和CRC32。视频文件可选择循环，发送速率可限制，断线后重连。

Linux接收端必须限制单客户端、设置socket超时、验证全部头字段和CRC，维护双缓冲所有权，
板端跟不上时保留最新完整READY帧并统计丢弃。程序必须打印接收帧、CRC错误、网络错误、
READY淘汰、DMA完成、DMA错误及最近frame_id，便于甲乙丙联合验收。

## 32.9 V0.13验收门槛

1. V0.12是V0.13的精确字节前缀。
2. Stream Formatter单元TB覆盖dummy透传、PC边界重建、随机反压、连续帧、提前/缺失包末、
   enable期间切源拒绝、soft reset和clear_error。
3. PC发送协议Python自测与Linux头解析/CRC测试通过。
4. 仿真连续输入至少三种非全黑图案，逐像素检查640×480输入与既有640×640输出。
5. AXI DMA官方IP的MM2S配置、地址和数据宽度由Vivado探针确认。
6. 新增/修改IP完成语法、展开、仿真、断言、OOC综合、Package和`component.xml`检查。
7. `validate_bd_design`、主工程综合、实现、DRC、CDC和时序通过，重新导出同版bit/hwh/xsa。
8. 无ZCU104实物时，交付状态必须写`PHYSICAL_PC_VIDEO_BOARD_ACCEPTANCE=NOT_TESTED`。
9. 实板验收还必须覆盖视频文件、USB摄像头、断网重连、错误帧、板端降速、缓存一致性、
   连续运行和实际FPS/帧龄；完成前不得宣称实时视频整机已通过。

---

# 33. V0.14：SAD逐帧跟踪、DPU重检测融合与正式视频链

本节只追加V0.14的新约定；第1至32节保持V0.13原文不变。V0.14的目标是把现有
“DPU实时检测”链扩展为“PL逐帧跟踪＋DPU周期/事件重检测”的异构协同系统，并形成
包含真实Vivado工程文件的统一主工程。

## 33.1 正式输入与dummy源处置

正式主工程不实例化`dummy_video_in_source`，因此它不占用最终PL资源。历史IP源码、
可编辑工程和Testbench继续保留，仅用于离线回归与故障定位。

V0.14正式输入固定为：

```text
PC视频文件或USB UVC摄像头
 -> ZCU104 Linux V4L2/网络接收程序
 -> DDR完整帧双缓冲
 -> AXI DMA MM2S
 -> pl_pc_video_stream_formatter
 -> pl_video_in
```

`pl_pc_video_stream_formatter.source_select`在正式构建中固定为PC/摄像头支路。软件仍可读取
V0.13兼容寄存器，但不允许切换到不存在的dummy硬件支路。

## 33.2 `pl_axis_video_fork`端口与行为

| 端口组 | 方向 | 宽度 | 定义 |
|---|---|---:|---|
| `s_axis_*` | 输入 | DATA=8 | 640×480 GRAY8 AXI4-Stream Video |
| `m_algo_axis_*` | 输出 | DATA=8 | 算法支路，送SAD/Letterbox/DDR写入 |
| `m_display_axis_*` | 输出 | DATA=8 | 显示支路，送OSD/HDMI |

每个输入Beat只有在两个输出消费者都能接受时才完成握手；SOF(`TUSER`)和EOL(`TLAST`)
必须在两条支路保持逐Beat一致。任何一条支路反压时，另一条支路不得重复或丢失像素。

## 33.3 `pl_sad_tracker`端口与精确行为

正式参数为640×480 GRAY8、16×16模板、水平/垂直±8像素搜索。模块不缓存完整帧；
它保存16×16模板，并在下一帧流经时只截取32×32搜索窗，随后在帧间对该窗口执行
SAD（Sum of Absolute Differences，绝对差和）搜索。该结构避免与DPU、显示双缓存争用大量URAM。

| 接口 | 方向 | 定义 |
|---|---|---|
| `s_axis_*` / `m_axis_*` | 输入/输出 | 视频原样透传；处理搜索期间允许标准AXI4-Stream反压 |
| `s_frame_id[31:0]` | 输入 | 当前输入帧编号 |
| `init_valid/ready` | 握手 | 接收DPU检测框并建立/更新模板 |
| `init_x/y/w/h` | 输入 | DPU检测框，单位为640×480输入像素 |
| `track_result_valid` | 输出 | 一帧一次的跟踪结果有效脉冲 |
| `track_x/y/w/h` | 输出 | 当前帧跟踪框 |
| `track_sad[31:0]` | 输出 | 最佳候选SAD，越小表示匹配越好 |
| `track_confidence[15:0]` | 输出 | 由SAD映射的跟踪置信度 |
| `track_lost_pulse` | 输出 | SAD超过阈值时的一拍丢失事件 |
| `processing_busy` | 输出 | 帧间模板装载或搜索正在进行 |

越界候选必须裁剪到图像范围内；宽高为0的初始化框按1像素处理。软复位必须清除模板有效、
活动目标和统计状态。该模块只负责单目标短时跟踪，不执行目标分类、NMS或多目标关联。

## 33.4 `pl_track_fusion`状态机

融合控制状态编码固定为：

| 编码 | 状态 | 行为 |
|---:|---|---|
| 0 | `WAIT_TARGET` | 无有效目标，持续允许Fresh-Frame DPU请求 |
| 1 | `INIT_TEMPLATE` | 已接收有效DPU框，等待SAD模板初始化和首个跟踪结果 |
| 2 | `PL_TRACK` | SAD逐帧跟踪，显示绿色跟踪框 |
| 3 | `REDETECT` | 周期到期或跟踪置信度过低，允许DPU重检测 |
| 4 | `LOST` | SAD判定目标丢失，停止显示旧框并允许DPU重新捕获 |

默认每15个有效跟踪结果触发一次周期重检测。低置信度或`track_lost_pulse`必须提前触发。
DPU请求原因码固定为：`0x01`首次检测，`0x02`周期/低置信度重检测，`0x04`丢失重捕获。

## 33.5 延迟DPU结果与历史帧修正

融合模块保存最近16项`Frame ID -> 跟踪框位置`。DPU结果返回时：

1. 若结果`Frame ID`命中历史项，计算检测框相对该历史跟踪框的偏差；
2. 把该偏差限制在每轴±32像素；
3. 将限幅偏差施加到当前跟踪框，更新模板；
4. 不得把旧帧检测坐标直接作为当前帧显示框；
5. 未命中历史项时计入`stale_history_results`，仅在无当前目标时允许把结果作为新目标初始化。

## 33.6 DPU请求/结果邮箱连接

```text
pl_frame_scheduler.request_* -> pl_sys_ctrl请求邮箱 -> Linux/DPU
Linux/DPU -> pl_sys_ctrl结果邮箱 -> pl_track_fusion
pl_track_fusion.result_ack -> pl_sys_ctrl.result_ack
pl_track_fusion.dpu_request_enable -> pl_frame_scheduler.dpu_ready
pl_track_fusion.dpu_request_reason -> pl_frame_scheduler请求原因输入
```

调度器只有在融合控制允许请求时才能把最新READY帧转为`DPU_OWNED`。结果邮箱仍遵守V0.11
影子寄存器与原子提交规则；融合模块确认消费后必须产生`result_ack`。

## 33.7 OSD与显示接口

`pl_track_fusion`输出最多8框的扁平框包：`box_frame_id`、`box_count`、每框12位
`x/y/w/h`和24位RGB颜色。当前单目标模式只使用第0项：DPU有效检测框为红色`0xFF0000`，
SAD跟踪框为绿色`0x00FF00`，LOST状态输出`box_count=0`。

显示链输入640×480 GRAY8，输出1280×720 RGB888；有效图像居中显示，左右各320像素、
上下各120行填黑。显示帧缓存采用双缓冲，写入中的帧不得被HDMI读取。

## 33.8 V0.14控制寄存器追加

在既有`pl_sys_ctrl` 64KiB窗口的末尾追加：

| 偏移 | 名称 | 访问 | 定义 |
|---:|---|---|---|
| `0xF8` | `TRACK_STATUS` | RO | bit[2:0]融合状态；bit8 tracker_active；bit9 processing_busy；bit10处于LOST状态 |
| `0xFC` | `TRACK_LAST_SAD` | RO | 最近一次SAD最佳值 |

`VERSION`从`0x0003_0000`更新为`0x0004_0000`。V0.13之前的寄存器地址和位定义不变。

## 33.9 单核DPU与硬件指纹

正式配置保持DPUCZDX8G v4.0、单核B4096、M-AXI 300MHz、计算时钟600MHz，控制地址
`0x81000000`，目标硬件指纹`0x101000016010407`。若重新配置DPU导致指纹变化，必须同步
重新编译模型，不能仅修改文档或软件常量。

## 33.10 USB工业摄像头边界

USB免驱摄像头接ZCU104 PS端USB Host，由Linux UVC/V4L2驱动生成`/dev/video0`。
板端软件负责MJPEG/YUYV解码、缩放和GRAY8转换，并写入DDR输入双缓冲；PL不自研USB协议核。
摄像头、视频文件和PC网络输入最终都必须汇聚为相同的640×480 GRAY8完整帧契约。

## 33.11 V0.14验收门槛

1. V0.13目录和回退快照保持字节不变；V0.14使用独立工程目录。
2. `pl_axis_video_fork`覆盖双支路随机反压、SOF/EOL一致性、无丢拍/重复拍。
3. `pl_sad_tracker`覆盖静止、水平/垂直移动、边界裁剪、丢失阈值、软复位和透传像素一致性。
4. `pl_track_fusion`覆盖首次检测、模板初始化、连续跟踪、周期重检测、低置信度重检测、
   丢失重捕获、历史Frame ID命中/未命中和坐标限幅修正。
5. `pl_sys_ctrl`重新Package并检查`component.xml`，`VERSION=0x00040000`，新寄存器可读。
6. 正式BD中不存在活动dummy源，AXI DMA/摄像头链是唯一视频输入。
7. DPU指纹保持匹配，DPU请求门控和原因码连接到Fresh-Frame调度器。
8. OSD/双缓存/HDMI链完成BD验证；640×480图像在1280×720输出中居中并补黑边。
9. 主工程完成综合、实现、DRC、CDC和时序检查，并从同一次构建导出`.bit/.hwh/.xsa`。
10. 交付目录必须包含真实可打开的`.xpr`，Tcl脚本仅作为可重复构建附件。
11. 实物验收覆盖USB摄像头、视频文件、DPU周期重检测、SAD逐帧跟踪、目标丢失/重新捕获、
    HDMI画框、连续运行FPS和帧龄；实测完成前状态标记为`PHYSICAL_V014_ACCEPTANCE=NOT_TESTED`。
