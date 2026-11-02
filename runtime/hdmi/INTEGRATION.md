# 给主集成代理的核查回报

> 这是V0.16硬件的历史核查回报。V0.17实际使用PYNQ用户态HDMI初始化，见`pynq_INTEGRATION.md`；最终地址和连接以V0.17的HWH及reports为准，不把本文当作本版亮屏通过记录。

最终链接 BD 和最终交付 HWH **均确认 TX/PHY IRQ 已连接**：TX irq 的 SIGNAME 为 v014_hdmi_tx_ss_irq，与 concat/In2 相同；PHY irq 为 v014_vid_phy_irq，与 In3 相同；IIC 与 In4 相同。concat/dout 与 PS/pl_ps_irq0 同为 dpu_irq_concat_dout，向量宽度为 5。对应 DTS GIC SPI 为 TX 91、PHY 92、IIC 93（硬件 ID 分别 123/124/125，Linux virq 动态分配）。

这是最终 Vitis link 的 `prj/prj.srcs/sources_1/bd/design_1/design_1.bd`，不是平台 BD 或 failed_link。`hardware-audit.json` 的 hwh_ports 保存交付 HWH 原始端口属性；审计脚本对上述四处 HWH 线网相等均做断言，且交付 HWH 与最终 link HWH 哈希相同。若板端缺中断，应核对实际加载的 bit/xclbin 和启动 DT。

Clocks 线网：

| 接收端 | 实际源 |
| --- | --- |
| TX s_axi_cpu_aclk / s_axis_video_aclk / s_axis_audio_aclk | PS pl_clk0，HWH 99999001 Hz |
| PHY drpclk / vid_phy_axi4lite_aclk / vid_phy_sb_aclk | PS pl_clk0 |
| TX link_clk、PHY vid_phy_tx_axi4s_aclk | PHY txoutclk |
| TX video_clk | PHY tx_video_clk |
| PHY mgtrefclk0_pad_p/n_in | 外部 TX_REFCLK 差分输入 |
| PHY tx_refclk_rdy | IDT LOL，IP 内配置反相 |

HWH 的 link_clk=148500000、video_clk=297000000、外部 refclk=100000000 是生成时元数据，不能作为 720p60 的运行测量或 fixed-clock 输出配置。外部 IDT 已有官方 CCF 驱动；其真实绑定和 kernel config 已补入交付。

物理 AXIS 接口已连接：自定义显示源 → 2PPC pack → FIFO → TX VIDEO_IN；TX 三路 LINK_DATA → PHY 三 lane，PHY SB_STATUS → TX。详见 hardware-audit.json 的 interface_nets。**这些连接不能证明 Linux clocks/phys phandle 与 DRM remote-endpoint 已配置**：未提供当前系统完整 DTS/DTB，而且此设计的自定义 AXIS 视频源没有现成官方 DRM CRTC 驱动。没有伪造 framebuffer DMA 或 DRM endpoint。完整亮屏仍阻塞于软件源适配/modeset、现有 IDT 驱动的板级接入和实板验证。

## 启动内存保留与适配输入采集

主集成代理实现 pl_runtime.py 时，必须在 boot 前完整 DT 中保留下列物理内存，设置 no-map、不可 reusable。不能以 Linux 启动后的 DTBO 作为内存保留手段。

| 用途 | 基址 | 大小 | 末地址（含） |
| --- | --- | --- | --- |
| DDR 三帧 | 0x20000000 | 0x004b0000 | 0x204affff |
| MM2S 输入 | 0x21000000 | 0x00200000 | 0x211fffff |

`collect-linux-inputs.py` 是板端只读采集器，运行：

```sh
python3 collect-linux-inputs.py --output-dir ./board-inputs
```

输出 adaptation-inputs.json 及 /proc/iomem、interrupts、version、cmdline 快照。JSON 保存实时树 reg/interrupts/clocks/phys/remote-endpoint/phandle 等属性的原始大端十六进制，供生成真实适配 DTS。它分别检查实时 DT 和 `/sys/firmware/fdt` 初始 blob 的两段 exact reg/no-map/启用/非 reusable 声明；缺任一启动保留或读不到 boot blob 均返回 2。运行时树出现同名保留节点不会代替启动 blob 检查。工具不安装 overlay、不触碰 MMIO、不发 I²C 事务、不初始化驱动。

返回 0 只代表两份 DT 的保留声明符合要求，不能证明 Linux allocator、DMA、mailbox、推理或 HDMI 全链路通过；结合内核 iomem、启动日志和真实驱动所有权继续验收。若系统未导出 boot blob，须从实际启动 DTB/U-Boot 和启动日志另行取证，不能跳过检查后宣称通过。

当前没有板端会话，因此没有采集结果；不要把本机验证的空 sysfs 负例当作板端证据。

官方 IDT 来源：[2022.2 驱动](https://github.com/Xilinx/linux-xlnx/blob/xlnx_rebase_v5.15_LTS_2022.2/drivers/clk/idt/clk-idt8t49n24x.c)、[对应 binding](https://github.com/Xilinx/linux-xlnx/blob/xlnx_rebase_v5.15_LTS_2022.2/Documentation/devicetree/bindings/clock/idt,idt8t49n24x.txt)。节点使用 `idt,idt8t49n241`、input-xtal 40MHz、0x6c；不要混用较新 Renesas binding。provider 可在启动 PL/I²C 就绪后接入，TX/PHY 仍保持 disabled，直到补齐软件显示源和完整时钟/PHY/graph 配置。
