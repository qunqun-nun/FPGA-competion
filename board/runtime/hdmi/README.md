# V0.16 HDMI Linux 初始化审查与支持交付

> 历史审查资料：V0.17当前运行入口为`pynq_integration.md`和`pynq_hdmi_init.py`，已包含用户态初始化代码及匹配原生库，仍待实板亮屏验收。以下DRM路线保留供参考，不与当前用户态驱动同时启用。

日期：2026-11-01。结论：**完成只读审查和可复核的 Linux 配置/构建/诊断支持；完整 TX+PHY 亮屏初始化尚未实现或验收。** 没有提供假初始化器，也没有把裸机 firmware 包装成 Linux 程序。全部新增内容位于本目录；未修改 V0.16、未运行 Vivado/Vitis 硬件构建、未访问板卡。主集成代理关心的 IRQ、clocks、endpoints、启动内存保留与采集工具说明见 `integration.md`。

## 已确认的硬件

依据是 V0.16 **最终 Vitis 链接**的 `build/link/_x/link/vivado/vpl/prj/prj.srcs/sources_1/bd/design_1/design_1.bd`，以及 `V0.16_给丙上板包/hardware/fengyan_v016_dpu.hwh`；不是早期平台 BD 或失败链接目录。`hardware-audit.json` 保存绝对路径、SHA-256、实际参数和连接。交付 HWH 与最终链接生成的 HWH 字节一致。

| 对象 | 最终配置 | 地址范围 | 中断 |
| --- | --- | --- | --- |
| v014_hdmi_tx_ss | v_hdmi_tx_ss 3.2；AXIS、2 PPC、8 BPC；无 HDCP、无有效音频输入 | 0x82000000–0x8201ffff | concat In2 → PL_PS_IRQ0[2]，GIC SPI 91，硬件 ID 123 |
| 内部 TX / VTC | v_hdmi_tx 3.0 / v_tc 6.2 | TX +0；VTC +0x10000 | 由 TXSS 管理 |
| v014_vid_phy | vid_phy_controller 2.2；GTHE4 X0Y16–18；TX HDMI、RX None；QPLL 选择值 6；refclk 选择值 0；LOL 输入反相 | 0x82020000–0x8202ffff | concat In3，SPI 92，硬件 ID 124 |
| v014_fmch_iic | AXI IIC 2.1；100 kHz；AXI 时钟报告 99999001 Hz | 0x82030000–0x8203ffff | concat In4，SPI 93，硬件 ID 125 |

Linux 分配的虚拟 IRQ 编号不应写死为上述硬件 ID。PS PL0 对应 `zynqmp_clk` 的 71；实际运行频率应通过板端 clk_summary 再核对。

视频链路是 `c_hdmi_display_0 → hdmi_axis_pack_0 → v014_hdmi_axis_fifo → TXSS → PHY`。源 RTL 默认输出 1280×720，640×480 是输入帧缓存尺寸。AXIS 源提供 active-video，电气消隐由 TXSS/VTC 产生。软件应限定 **1280×720p60、RGB、8 BPC、2 PPC**，不能照搬官方例程默认的 1080p。720p60 标准像素时钟为 74.25 MHz；最终 GT 参考时钟必须由 PHY 对模式计算的结果驱动 IDT，不能把 AXIS 的约 100 MHz 或 XDC 的 297 MHz 约束当作实际输出频率。

TX_EN_OUT 由常量 1 驱动；LOL 接 PHY tx_refclk_rdy 且配置反相；HPD、DDC、TX GT 参考时钟有连接。I²C 管脚为 D1/E1。未发现可供现有 Linux 驱动使用的显示 framebuffer-read DMA/CRTC。工程里的 AXI DMA 用于另一条输入数据路径，不能在 DTS 中冒充 HDMI framebuffer-read。缺少完整 Linux 设备树和板端状态，尚不能确认 IDT reset 的实际释放状态。

## 官方 2022.2 对照结果

1. [官方 2022.2 Yocto 配方](https://github.com/Xilinx/meta-xilinx/blob/2e60ee606a1a9a08db72b69e018b1ed1fd2d1047/meta-xilinx-core/recipes-kernel/hdmi/kernel-module-hdmi_git.bb)指定 `hdmi-modules` 提交 **25b6fe7a26a975be15c002b48cfd4c291486491e**。本目录 `official-2022.2/` 与源码压缩包均固定为该版本，许可证保留。可变分支 HEAD 比配方多一个提交，仅修改 TX 驱动；差异记录在 `release-vs-branch.json`。`hdmi-tree.json` 是发现阶段的 HEAD 快照，不是交付源码版本。
2. [2022.2 TXSS binding](https://github.com/Xilinx/hdmi-modules/blob/25b6fe7a26a975be15c002b48cfd4c291486491e/Documentation/devicetree/bindings/xlnx,v-hdmi-tx-ss.txt)与 [PHY binding](https://github.com/Xilinx/hdmi-modules/blob/25b6fe7a26a975be15c002b48cfd4c291486491e/Documentation/devicetree/bindings/xlnx,vphy.txt)已保存在源码目录。TX 驱动匹配 `xlnx,v-hdmi-tx-ss-3.1`，所以 3.2 节点需保留该兼容字符串。PHY 匹配 2.2；GTHE4 枚举值 5 已对照 xvphy.h。
3. 官方模块是 `xilinx-vphy.ko`、`xilinx-hdmi-tx.ko` 和 `dp159.ko`，源树还构建 RX 模块。TX 通过 component_add 接入 DRM；probe 成功不等于 modeset。它需要 `s_axis_video_aclk`、`s_axi_cpu_aclk`、`txref-clk`、三条 PHY lane，以及可完成绑定和模式设置的 DRM 显示管线。
4. **版本细节：**绑定文档说 retimer-clk 可选，但此提交 `hdmi/xilinx_drm_hdmi.c` 的 devm_clk_get 错误分支直接 return，缺失它会失败。ZCU104 DP159 为 **0x5c**，不是 ZCU102 文档示例中的 0x5e。
5. [官方 HDMI Linux 说明](https://xilinx-wiki.atlassian.net/wiki/spaces/A/pages/18842136)描述的程序化时序是：DRM modeset 配 TX/VTC/PHY，再由 CCF 设置外部参考时钟，等待 PHY 锁定并配置 retimer。Wiki 页面会更新，因此本交付以固定的 2022.2 源码为准。
6. 现有 `official_tx_bd_zcu104_2018_3.tcl` 和 firmware 是早期裸机参考。已联网另外下载 [embeddedsw xilinx_v2022.2 TxOnly](https://github.com/Xilinx/embeddedsw/tree/xilinx_v2022.2/XilinxProcessorIPLib/drivers/v_hdmitxss/examples/xhdmi_example/TxOnly)及 IDT/DP159 源码到 `baremetal-reference-2022.2/` 作对照。里面的 XScuGic、Xil_Exception、XIic、物理地址 BSP API 要依赖 standalone 环境，不能在 Linux 下直接 gcc 后运行。
7. [ZCU104 官方指南 UG1267](https://docs.amd.com/api/khub/documents/g76en4BfB6qIp2gHDRkQxg/content)确认外部时钟是 IDT 8T49N241，且 reset 必须释放。[官方 PYNQ v3.0.1 ZCU104 例程](https://github.com/Xilinx/PYNQ/blob/v3.0.1/boards/zcu104/base/base.py)使用 DP159 0x5c、IDT 0x6c，并显式执行 reset/PHY/HDMI 初始化。PYNQ 是已有真实 Linux 实现的参考，但它的 reset_control、层级、库 ABI、MMIO 所有权不适配本设计，不能直接执行其 BaseOverlay.download 或替换本工程 bitstream。

## 可直接使用的交付

- `audit_v016.py`：仅以 rb/只读解析方式读取 V0.16，向当前目录输出 `hardware-audit.json`。核对最终 BD、地址、IRQ 连接、交付 HWH 一致性，并比较读取前后哈希。运行：`python audit_v016.py`。
- `v016-hdmi-audited.dtsi`：基于最终硬件的配置修正片段；**TX、PHY、I²C 默认均 disabled**。需在由相同 XSA 生成的完整 DTS 中，按 DTG 标签合并已有节点，不能当独立 overlay 加载。TX 时钟、PHY lanes/phys 和显示 graph 应以实际生成树为基础，当前片段不宣称能启用 TX。
- `v016-iic-enable-after-pl.dtsi`：只启用真实存在的 AXI IIC、DP159 和 IDT 子节点。仅在匹配 PL 于内核 probe 前已配置的启动流程中使用。若依靠 XRT 在 Linux 启动后才加载 xclbin，保持前一片段 disabled，需在 PL 加载后采用经过验证的设备 DT overlay/probe 生命周期（内存保留必须在启动前完成）。禁止对未加载 PL 直接访问 AXI。
- `kernel-hdmi.cfg`：内核依赖配置。官方 HDMI/PHY/DP159 是树外模块，不存在通过一个虚构的 TXSS Kconfig 选项完成初始化的捷径。可在 PetaLinux 2022.2 使用官方配方，把 `CONFIG_kernel-module-hdmi` 加入项目 user-rootfsconfig 后选入 rootfs；保留现有内核配置并核对最终 `.config`。
- `build-linux-modules.sh`：使用匹配板端内核的源码、已构建输出、Module.symvers 和 AArch64 SDK，在本目录的新子目录构建官方模块；不安装、不加载、不改内核源。示例：设置 `KERNEL_SRC`、`KERNEL_OUT`、`CROSS_COMPILE` 后运行 `sh build-linux-modules.sh`。若 SDK 的 CROSS_COMPILE 含额外参数，应改为纯工具前缀再使用；脚本不处理带参数的工具前缀。
- `validate-dts.sh`：对已经合入片段的**完整** DTS 执行 cpp/dtc，保存输出和警告；用法 `sh validate-dts.sh /path/system-top.dts /path/dtg/output /path/linux/include`。它不会自动拼造 base DT，也不宣称通过了 binding schema 验证。
- `linux-preflight.sh`：板端只读观察 sysfs、FPGA manager 状态、设备绑定、HDMI connector、hdmi_info/vphy_info 和相关 dmesg；不发 I²C 事务、不读写 MMIO、不加载模块。`sh linux-preflight.sh`；缺设备或 connector 返回 2。即使返回 0，也只说明设备和 connector 存在，不能代替 PLL/stream/显示器验收。FPGA manager 的 operating 也不能证明加载的是 V0.16。

## 完整初始化的真实阻塞与落地方案

**依赖 A：已有 IDT 驱动的板级接入。** 补查确认官方 linux-xlnx 2022.2 已有 `CONFIG_COMMON_CLK_IDT8T49N24X`，实际 compatible 为 `idt,idt8t49n241`，与较新上游的 Renesas binding 不同。驱动/binding 快照见 `linux-reference-2022.2/`。已提供 0x6c provider、1 个 clock specifier cell、真实 40 MHz 晶振 input-xtal（fixed-clock 只描述晶振，不冒充 IDT 输出）。驱动支持 Q0–Q3 set_rate；官方裸机/PYNQ 同时配置 Q2/Q3。当前仍需核对输出路由、reset 和初始寄存器状态，再接入 TX txref-clk 并验证 LOL/实际参考频率。驱动 settings 表可选，未提供时读取当前硬件配置；不能假定板载默认值已合适，也不能照抄其他板的 settings。此项应接入现有驱动，不需要从零编写 IDT CCF 驱动。

**阻塞 B：模式设置触发与视频源适配。** 现有自定义 AXIS 源没有现成的官方 DRM CRTC 驱动。不能创建不存在的 `v_frmbuf_rd`、DMA phandle 或 endpoint 来骗过绑定。保持硬件不变可选：(1) 实现固定 720p60 的 Linux DRM CRTC/source 适配，处理 enable/disable、时钟、源持续出帧和模式约束，再与官方 TX component 绑定；或 (2) 参照官方 PYNQ 的 Linux MMIO/用户态库路径，专门适配当前硬件和中断，保证 kernel 与 userspace 不双重占用 TX/PHY/I²C。两种路线都需要真实软件适配和板端调试；不需要先重建硬件。

构建/验证还依赖：当前板端 `uname -a`、内核 `.config`、完整 DTS/DTB、对应 kernel 源码/构建目录与 Module.symvers、AArch64 SDK、PL 加载次序、实际 ZCU104 板及显示器。当前 Windows 工作区没有提供这些目标 Linux 构建产物或已连接板端会话，因而无法完成模块链接、完整 DT 合并和电气链路验收。此处是交付边界，不是已完成的初始化功能。

## 板端验收标准

先确认实际加载的 bit/xclbin 与 hardware-audit.json 哈希对应；记录加载次序和启动日志。完整软件补齐后，依次验证 I²C adapter 属于 0x82030000、DP159 绑定 0x5c、IDT 0x6c 正确识别且 reset 释放、PHY 三 lane 和 TX component 绑定、DRM 出现 HDMI connector、HPD/EDID 有效并可设置 720p60。核对参考时钟/LOL/GT PLL lock、VTC lock、hdmi_info 报告 1280×720p60 RGB 8 BPC；显示器实际稳定出图，并测试断插 HDMI、模式重设和重启。内核无 AXI abort、超时、中断风暴或持续 probe defer。仅出现 connector、LED 亮、模块已加载均不算通过。

本机验证结果见 `verification.json`；其中明确区分静态检查与未执行的 Linux/板端验证。
