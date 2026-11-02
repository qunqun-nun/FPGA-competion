# V0.17.3 修复说明与验证结果

软件修复，硬件仍沿用 V0.17 同次构建四件套。保留 FCLK0 运行时分频适配和检查。原 V0.17、V0.17.1、V0.17.2 未覆盖；V0.17.2 包根全部清单文件重新核验一致。未修改 RTL/IP 接口，不新增接口表，不重建硬件。

## 修改

1. runtime/hdmi/board_validation.py：统一本板 TX_ADDRESS=0x5e，验证 DP159；0x5c 是实板返回 TMDS181 的输入侧，不对其写输出配置。
2. runtime/hdmi/hdmi_iic.py：支持有长度上限的连续读取，仍要求精确发送/接收计数并留档。
3. IDT：两次完整 16 字节读取必须一致；校验地址寄存器和工厂 ID，或匹配固定官方驱动的已知配置前缀。已知时钟状态由真实官方类在纯内存中生成，包含 37.125/74.25/148.5/297 MHz，覆盖本版固定 720p60 相关 PHY 参考状态；不接受任意 0xffff、任意分频、全 FF 或不稳定读数。其他未知配置会拒绝并留证，不能保证任意其他模式/外部软件状态都可接管。配置后仍验证初始字段、实际 set_clock 写入字段和输出使能。
4. DP159：0x0A 使用 0xFB 掩码排除自清除动作位，保留模式检查；0x0B 使用 0xF9 排除保留位和 DDC 动态 bit1，动态原值仍记日志；0x09/0x0C/0x0D 使用已审阅掩码。配置不匹配不会被忽略，I2C_EN/PIN 导致写无效时明确报错。工作模式发生变化时按 TI 要求切换 PD_EN，所有写操作限定在 0x5e。
5. runtime/hdmi/pynq_hdmi_init.py：接入上述验证；HPD 后在有超时的 worker 内读 EDID，校验头、已读块校验和、CTA 数据块边界，并由 VIC4 或详细时序证明 720p60 支持。保存原始 EDID；无证据时不强行输出。
6. PIO：依据当前匹配 native 的 xparameters 和 xv_hdmitx_hw.h，只读采集核内 PIO control/output/input，记录 HPD/link/video/bridge 及溢出欠流、复位上下文。STREAM_UP 后要求 bridge lock，运行中继续检查；保存实际 PHY 参考频率与 PLL lock。PIO 不是外部电压测量。
7. runtime/collect_hdmi_iic.py：只读探测与显式初始化都使用同一地址和状态验证；完整流水线依旧用 runtime/start.sh。

## 验证

- 新增 12 项板级行为测试通过：模拟本板的输入/输出地址分配；禁止向输入器件写配置；IDT 真实观测块、损坏/全 FF/短读/变化拒绝；真实官方 set_clock 后重识别和重新初始化；DP159 真实驱动模式切换、动态位与稳定位；EDID CTA/Detailed Timing、损坏/缺失/边界/未读扩展；PIO 偏移和状态。
- IIC 原有 8 项通过，HDMI 原有 13 项通过，运行时回归 61 项通过，合计 94 项。新修改 Python 语法检查通过。
- 对 ZIP 内原始实板 JSONL 做验证器回放，通过 IDT 配置态和 TX 身份判断。这是使用既有单次读取的离线回放；不伪称完成两次实板读取或新硬件访问。
- 验证 PIO 常量与包内实际 native 头文件、core 偏移一致。原生库、硬件和 FCLK0 加载代码保持相同 SHA。
- 原生库源码/构建凭据检查由 HDMI 测试覆盖。源码变化和每文件 SHA 见包根清单与 analysis 构建记录。

## 实板尚待验证与边界

未连接板卡，不宣称 HPD/EDID 实读、配置回读、PLL、桥接、画面、检测框、摄像头或冷启动通过。操作顺序和应返回证据详见包根《先给另一台电脑Codex看.md》。

EDID 沿用原库 256 字节接口。声明扩展多于一块时，只验证读到的块并明确 all_declared_blocks_read=false；若已读块已证明支持 720p60 可以继续，但不宣称额外扩展有效。若支持信息仅在未读块中会拒绝输出并需继续适配。

默认 image.ub 的 no-map 问题没有被软件补丁消除。丙应沿用已验证的临时 image17.ub 并每次核验实际保留区，正式冷启动方案仍需后续闭环。包内没有新 BOOT.BIN/FSBL/PMUFW 或可烧 SD 启动镜像。

硬件仍受 HDMI hardware_evaluation 许可限制；原始实现告警、HDPR-5 降级原因、实体 PCB 修订与引脚签核仍需要单独审阅，本次不以修软件替代这些事项。

## 依据

- 用户实板原始读数、三份中文核查报告：本目录 source_evidence。
- https://www.ti.com/lit/ds/symlink/sn65dp159.pdf ：地址表、ID 字符串、动作位、RWU 和模式切换规定。
- https://www.renesas.com/en/document/dst/8t49n241-datasheet ：ID 可写、地址脚/保留位与配置字段。
- 包内 PYNQ v3.0.1 clocks.py/constants.py/xilinx_hdmi.py：复用官方配置、算法和 EDID API。
- 包内 Vitis 2022.2 xv_hdmitx_hw.h/xparameters.h：PIO 状态偏移和位定义。
