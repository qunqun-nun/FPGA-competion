# V0.17 接口变更与数据通路

本文件只记录本次集成的增量。`history/interface_v0.14.md` 为原文件原样副本，正文含历次累积章节，不把其早期页首版本号当作当前硬件版本。最终 HWH、同次构建报告与下列增量共同核对实际工程；不修改历史表中其他模块的正确端口。

## 新增及修复

1. 保留 V0.16 的复位极性修复：三个 Processor System Reset 的低有效辅助复位在不使用时接常量 1。
2. 新增顶层输出 `IDT_8T49N241_RST_OUT`，连接一位常量 1；FPGA 引脚 M12，LVCMOS33。用于释放 ZCU104 板上 HDMI 时钟芯片复位。不是新增 AXI 寄存器；无需软件猜写 GPIO。
3. 三缓冲调度器在无 FREE 槽时，可以回收非最新且未被占用的旧 READY 槽接收新帧。保留最新完整帧；绝不覆盖 WRITING/DPU_OWNED 槽。恢复 DPU 请求时仍选最新完整帧。同拍回收与分发不得将新写入槽再次标为 FREE；stale/dropped 对同一回收帧只计一次。
4. 调度器端口、寄存器地址、三缓冲基地址、模型输入尺寸不变。软件以请求的 frame_id 核对对应输入图像，允许请求引用当前写入帧之前的完整帧。

## 实际运行通路

```text
板上 USB UVC 摄像头
  → PS Linux V4L2/OpenCV 持续取最新帧
  → PS 转 640×480 GRAY8
  → 预留 DDR 输入区 0x21000000
  → AXI DMA MM2S
  → PC 输入格式化器
  → pl_video_in 视频规范化与帧编号
  → AXI4-Stream 分流
       ├─ SAD 逐帧跟踪 → 融合控制
       ├─ Letterbox：上下各补80行114 → 640×640三通道
       │    → 帧写入适配器 → AXI DataMover S2MM
       │    → PS DDR三缓冲 → Fresh-Frame检测请求
       │    → PS读取请求图像 → VART DPU-only Runner
       │    → 六路CPU末层 → DFL/sigmoid/NMS → 坐标还原
       │    → 结果影子寄存器 → 原子提交 → 融合/SAD模板更新
       └─ 原尺寸显示缓存 → OSD单目标框
            → 1280×720视频时序与打包 → HDMI TX/Video PHY
            → 显示器
```

USB 接在 PS/Linux，摄像头不直接连接 `pl_video_in` 引脚。图片模式与摄像头模式共用后半条真实 PL 通路。串口可用于传文件/执行命令，不是 PL 必须采用的像素接口。

## 部署固定地址

| 对象 | 地址/窗口 | 软件约定 |
|---|---|---|
| pl_sys_ctrl | 0x80000000 | CTRL 0x00；请求 0x10–0x24；结果影子 0x30–0x50；提交 0x54；结果序号 0x58；ACK 0x64 |
| AXI DMA | 0x80010000 | MM2S简单模式，输入按完整灰度帧传输 |
| DPU | 0x80020000 | 单核 B4096；目标指纹0x0101000016010407 |
| HDMI TX Subsystem | 0x82000000，0x20000窗口 | 用户态匹配驱动初始化 |
| Video PHY | 0x82020000，0x10000窗口 | 不与内核DRM驱动同时占用 |
| AXI IIC | 0x82030000，0x10000窗口 | 配置IDT/DP159板上时钟器件 |
| 三缓冲 | 0x20000000，总长0x004b0000 | 每帧640×640×4；内存字节R,G,B,0；必须启动时no-map预留 |
| 输入区 | 0x21000000，预留0x00200000 | 每输入帧640×480字节；必须启动时no-map预留 |

实际时钟频率以最终 HWH/时序报告为准，DPU约300/600 MHz。显示尺寸与摄像头/推理输入尺寸不同。当前结果邮箱回传一个最高置信度目标，不是多目标跟踪接口。

## 参考资料与采用内容

- [AMD PG020 三缓冲应用](https://docs.amd.com/r/en-US/pg020_axi_vdma/General-Use-Cases)、[读写帧同步原则](https://docs.amd.com/r/en-US/pg020_axi_vdma/Genlock-Synchronization)：参考生产者/消费者不能同时占用同一帧的原则；本工程继续使用已有 DataMover 与自研所有权调度器，没有替换成 VDMA。
- [Linux V4L2 视频采集接口](https://cdn.kernel.org/doc/html/latest/userspace-api/media/v4l/dev-capture.html)：摄像头由板端Linux采集，应用保留最新帧。
- [PYNQ v3.0.1 ZCU104约束](https://github.com/Xilinx/PYNQ/blob/v3.0.1/boards/zcu104/base/vivado/constraints/base.xdc)：核对IDT reset的M12/LVCMOS33连接；HDMI代码与编译来源见runtime/hdmi/pynq_integration.md。
- [AMD Vitis 2022.2链接选项](https://docs.amd.com/r/2022.2-English/ug1393-vitis-application-acceleration/v-General-Options)：使用真实v++链接，异常缓存检查时采用--no_ip_cache，不改名旧xclbin。

这些资料说明参考方法，不代替本工程的仿真、构建与实板验收记录。
