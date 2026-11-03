# PYNQ 用户态 Linux HDMI 初始化候选（新增路径）

此文件补充此前 Linux DRM 审查，不覆盖旧报告。用户现已授权主集成代理修复 V0.17 的 IDT reset 输出并重新链接；本候选不重编程硬件，也不自建 DRM CRTC。

## 已交付 API

```python
from hdmi.pynq_hdmi_init import HdmiSession

# overlay 必须来自已加载的 LocalDpuOverlay，例如 load_overlay.main() 返回值。
hdmi = HdmiSession(overlay)  # timeout_s=15；library_path/hwh_path 可显式给路径
try:
    init_status = hdmi.init()
    board.start()
    start_status = hdmi.start()
    # 主循环每帧执行；worker 也在空闲期间持续轮询官方事件处理器。
    status = hdmi.service()
finally:
    hdmi.close()
```

`init/start/service/close` 返回状态字典；错误抛出 HdmiError 或具体依赖/文件错误。`poll` 是 service 别名，`stop` 是 close 别名。便捷 `initialize(overlay, library_path=..., hwh_path=..., timeout_s=15)` 执行 init+start，返回 session。输出上限是实际 STREAM_UP 状态，**picture_verified 始终为 False**，显示器亮屏还需实板验收。

主代理 `--load --hdmi` 的顺序 init → board.start → start → 每帧 service → finally close 与此 API 一致。默认库相对当前模块定位为 `pynq_native/libfengyan_xhdmi.so`；receipt 同目录 `build-receipt.json`。默认 HWH 是 overlay.bitfile_name 同目录同名 .hwh。可重定位，无硬编码桌面路径。独立进程只能附着已经加载的正确硬件（例如 Overlay(bit_path, download=False)），不可重复加载 bit/xclbin；初始化器本身无 download 调用。

## Strict compatibility 默认行为

1. 要求真实 AArch64 Linux、root、overlay.is_loaded()，IP 类型/物理地址/窗口必须分别为 TXSS 3.2@0x82000000/0x20000、PHY 2.2@0x82020000/0x10000、AXI IIC 2.1@0x82030000/0x10000。
2. 从**实际最终 HWH**解析完整 TX/PHY 参数和 IDT_8T49N241_RST_OUT。必须是输出，且其线网连接单比特 xlconstant=1；缺失、值 0、无法证明连接时直接拒绝。HWH 可证明逻辑连接；M12/LVCMOS33 引脚约束及 routed/bit 一致性仍由主硬件交付签核。V0.16 baseline 会拒绝，绝不通过手工 flag 假设 reset 已释放。
3. 官方 PYNQ v3.0.1 Python bindto 确实支持 TXSS 3.2/PHY 2.2，但其 stock native 配置为 RX_PROTOCOL=1、NIDRU=1、NIDRU_REFCLK_SEL=3；本设计为 3/0/0。stock libxhdmi.so 不被接纳。匹配库用官方 PYNQ Linux wrapper/common 和 Vitis 2022.2 驱动源码构建；不是把 standalone 应用当 Linux 程序运行。
4. 验证 PYNQ 版本及 xilinx_hdmi.py/iic.py/clocks.py/constants.py 与包内 v3.0.1 官方快照相同，验证 ELF64/AArch64、库 SHA、receipt、实际导出的 ABI/profile。编译时同时修正原始及 canonical xparameters 宏，并用 C static assertions 检查。profile 比较覆盖 TX/PHY 所有驱动字段、时钟、模式；HWH SHA/reset 输出变更单独检查，因此**只新增 reset 常量输出、核心参数不变的 V0.17 可复用该库**，其他参数变化须重建。
5. 拒绝 sysfs 中仍绑定到这些 MMIO 窗口的内核驱动，包括任意命名但 resource 重叠的设备。不会自动 unbind。使用 /run/lock/fengyan-hdmi.lock 排斥合作的初始化进程；该锁不能约束不合作的 /dev/mem 程序，应停用其他 HDMI/PYNQ/I²C 控制任务。此前用于 DRM 的 I²C/IDT/DP159 节点不能与本路径同时占用资源。
6. 通过官方 Clocks API只读检查 PL0 实际频率与 HWH nominal 相差不超过 0.5%。不重设 PS 时钟。

## 实际调用和状态回读

worker 先通过 AxiIIC 读取 IDT 0x6c 的器件 ID，严格要求 0x0606，拒绝 PYNQ 原实现也接受的 0xffff；再读取 DP159 0x5c 寄存器 0..7，严格要求 TI DEVICE_ID 的 ASCII `DP159   `。不猜写 reset/expander 或未知寄存器。

随后使用官方 Vphy.initialize、HdmiTxSs.set_phy、DP159、IDT_8T49N24 对象。init 阶段 IDT 构造会按官方 IDT_Synth 编程。start 阶段通过官方 HdmiTx_set_format(1280,720,60) 计算参考频率和 line rate，再调用两个官方 clock 对象的 set_clock，然后原生 HdmiTx_start。沿用官方 stream-down → stream-up 事件顺序，但有超时。没有调用 Python 中无限等待的 HdmiTxSs.start。

外部时钟写入后，回读本次官方 set_clock 实际写入的稳定配置寄存器；跳过 DP159 0x0a 的 apply 动作寄存器精确比较，检查 IDT enable 位已释放。通过官方 XVphy_ClkDetGetRefClkFreqHz 与 XVphy_IsPllLocked API读取真实参考频率/PLL lock；频差超过 1% 或锁定失败即停止。service 继续检查 connected、ready、refclk 和 PLL。状态包含 requested/measured refclk、line_rate、PHY version、真实器件 ID 和寄存器回读结果，不把元数据当测量。

所有硬件寄存器写入都来自固定版本官方 PYNQ/embeddedsw 驱动，新增代码不猜测寄存器地址/位定义。IDT reset 是新硬件常 1 输出，不需要软件复位脉冲或新增 GPIO。

## 超时与停止语义

PYNQ C/I²C 函数可能自身阻塞，单靠 Python while 截止时间不足以限定它们。所有 C/I²C 操作都在独立 worker 中，父进程每个 init/start/service/close 最多等待 timeout_s，再 terminate/kill 各最多 0.5 秒。正常异常先尝试官方 HdmiTx_stop（关闭 TMDS 输出缓冲）并释放句柄；不承诺回滚 IDT 原始配置。C 崩溃或硬超时返回 **UNKNOWN_REBOOT_REQUIRED**，不能声称硬件已停止；若线程处于内核不可中断 I/O，kill 也可能等待内核返回，锁由存活 worker 持有。

Linux worker 当前使用 fork。应在创建 VART Runner/其他工作线程前执行 hdmi.init，避免从已有复杂线程状态 fork；主集成顺序需保证这一点。不启动独立 GUI，不加载新 bitstream，不创建虚假 DRM 节点。

## 二进制与重建

已在 Windows 用官方 Vitis 2022.2 GCC 11.2 交叉编译得到 AArch64 Linux .so，链接使用 `-Wl,-z,defs`。readelf 原始结果随库保存：NEEDED **仅 libc.so.6**，version-needs **仅 GLIBC_2.17**；无 GLIBCXX、CXXABI、libstdc++ 或 libgcc_s 运行依赖。纯 C 无需静态 libstdc++。因此该库的符号版本要求低于 GLIBC 2.31 基线；仍需板端动态加载与设备访问验证。不是在 Windows 上运行通过了 ARM 库。

重建输入全部包含在包中，系统编译器/sysroot 除外：

```sh
python3 pynq_prepare_library.py \
  --pynq-source ./pynq-reference-v3.0.1 \
  --embeddedsw ./pynq_native_sources/embeddedsw \
  --hwh /path/to/actual-final.hwh \
  --output-dir ./pynq-native-new-build \
  --cc aarch64-linux-gnu-gcc
```

新目录保留 PYNQ wrapper、改写的 xparameters、所有驱动/BSP 源码和头文件、compiler response file、编译日志、readelf 结果及哈希 receipt。不会覆盖已存在构建目录或已安装 PYNQ。源码 URL 和打包文件哈希见 pynq_sources.json。

测试：`python3 -m unittest discover -s . -p pynq_test_hdmi.py -v`。离线测试不访问 MMIO、不模拟板端成功。最终 V0.17 HWH 与真实 IDT/DP159/PLL/显示器尚未在本机会话验证，不能标为板端通过。

## 官方依据

- [PYNQ v3.0.1 HDMI Python ABI](https://github.com/Xilinx/PYNQ/blob/v3.0.1/pynq/lib/video/xilinx_hdmi.py)
- [PYNQ v3.0.1 原生 Linux wrapper](https://github.com/Xilinx/PYNQ/blob/v3.0.1/pynq/lib/_pynq/_xhdmi/hdmi_functions.c)
- [stock xparameters（含 RX/NIDRU 配置）](https://github.com/Xilinx/PYNQ/blob/v3.0.1/pynq/lib/_pynq/common/aarch64/xparameters.h)
- [ZCU104 base.py](https://github.com/Xilinx/PYNQ/blob/v3.0.1/boards/zcu104/base/base.py)、[M12/LVCMOS33 XDC](https://github.com/Xilinx/PYNQ/blob/v3.0.1/boards/zcu104/base/vivado/constraints/base.xdc)
- [UG1267：IDT reset 必须驱动高，U181 pin31 连接 FPGA M12](https://docs.amd.com/api/khub/documents/g76en4BfB6qIp2gHDRkQxg/content)
- [TI SN65DP159 datasheet，DEVICE_ID 0x00..0x07](https://www.ti.com/lit/gpn/sn65dp159)
