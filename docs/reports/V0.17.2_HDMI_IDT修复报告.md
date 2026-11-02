# V0.17.2 HDMI IDT 软件兼容修复报告

## 判断

目前优先修软件。已确认旧软件存在与其依赖的 PYNQ 3.0.1 官方实现不一致的设备 ID 拦截；当前没有新增板端 IIC 寄存器、引脚波形或电源数据证明必须修改 Vivado。未修改 RTL、Block Design、XDC、HWH、XSA、FSBL、PMUFW，也未重建硬件。

官方 clocks.py 的 IDT check_device_id 接受 0x0606 和 65535；constants.py 的 IDT_Synth 前五个字节为 FF，而 _configure 会写入除 0x70 外的数组寄存器。因此，官方初始化本身可使拼接 ID 的 0x0002/3/4 变成 FF。这是可复现的软件事实；真实板上这次 0xffff 是否正由此前初始化造成，仍须日志确认。

## 修改及作用

| 文件 | 修改与目的 |
|---|---|
| runtime/hdmi/pynq_hdmi_init.py | 恢复官方支持的 ID 范围，先核对 DP159；IDT 配置后进行字段回读，继续保留 PLL/参考时钟/STREAM_UP 检查；阶段与逐笔事务留档 |
| runtime/hdmi/hdmi_iic.py | 检查精确发送/接收计数；记录地址、负载、返回值和 AXI IIC 状态；使用单次 IDT 事务替代官方静默重试，仍由现有进程看门狗限时 |
| runtime/collect_hdmi_iic.py | 只读探测、显式初始化与可选时钟/流启动验证；输出结构化结果，不依赖网页串口自动控制 |
| runtime/hdmi/test_hdmi_iic.py | 使用真实随包官方 IDT 算法配合模拟 IIC 传输，复现重复初始化并验证故障会被拒绝 |

16 个初始化字段采用官方方法使用的位掩码回读，覆盖模式、输入分频、反馈整数/小数和输出分频，不以全 FF 身份当作通信成功；额外检查 0x70 的使能/校准位。未增加任意试写、全总线扫描或复位翻转。寄存器状态读取不消费 RX FIFO，不按原始中断位单独判定 NACK 故障。

保留 V0.17.1 的 100 MHz FCLK0 运行时适配。硬件四件套与原包逐字节相同，因此仍是原同次构建配套文件，不用软件版本号冒充硬件重建。

## 必要验证

- 新增 IIC/IDT 测试 8 项通过：官方配置导致 ID=0xffff 与重复初始化；720p 时钟计算和回读；IDT 全 FF 卡死；共享总线全 FF 与未知 ID；短发送；短接收；异常无隐藏重试；配置损坏及输出未使能拒绝。
- 原 HDMI 检查 13 项通过：元数据、内核占用、库 ABI/校验、HPD/事件顺序、看门狗、失败状态等。
- 原运行时回归 61 项通过：FCLK0、摄像头、DMA、DDR/邮箱、超时和数据一致性等。
- 合计 82 项通过；修改 Python 源码语法检查通过；原 V0.17.1 的 1158 文件清单核验通过，原版本未改。
- 测试使用模拟传输和宿主机检查，不是 FPGA 电气仿真、真实 IIC 波形测量或 HDMI 实板验收。本次无需 RTL 变更，未新增 RTL Testbench 或运行硬件重建。

完整记录位于本目录 V0172_*.log。硬件哈希与验证状态见 V0.17.2_验证结果.json。

## 未完成与下一步

本机不能访问 ZCU104。用户提供的另一台电脑报告显示 FCLK0 在加载、Runner 创建和持续采样中约 99.999 MHz；这不代表 HDMI PHY 参考时钟已测量或锁定。

请按包根《先给另一台电脑Codex看.md》复测。必须分别证明配置回读、HDMI_INIT_OK、PLL 锁定、实际 PHY 参考时钟计数、STREAM_UP、屏幕画面和检测框；当前均未宣称通过。若新日志仍显示短事务、DP159 失败、IDT 配置回读失败，再据数据决定排查引脚/电源/复位还是 Vivado。

原有 HDMI TX hardware_evaluation 许可证限制仍存在。模型精度、实际检测框、摄像头完整链路和冷启动复现需要实板验收，软件兼容修复不替代这些任务。

## 回退与参考

原 V0.17 和 V0.17.1 目录未改；新软件独立在 V0.17.2 开发目录。停止新进程并重启到已验证启动方式，使用旧完整目录即可回退；/etc/vart.conf 按原包恢复脚本说明处理。

- https://github.com/Xilinx/PYNQ/blob/v3.0.1/pynq/lib/video/clocks.py
- https://github.com/Xilinx/PYNQ/blob/v3.0.1/pynq/lib/video/constants.py
- https://github.com/Xilinx/embeddedsw/blob/xilinx_v2022.2/XilinxProcessorIPLib/drivers/iic/src/xiic_l.h
- https://www.renesas.com/en/document/dst/8t49n241-datasheet
