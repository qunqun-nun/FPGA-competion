# ZCU104 板载 HDMI 全面核查报告

日期：2026-11-02。用途：模型目标图像识别展示。范围：ZCU104 板载 HDMI OUT；没有采用 ZCU102、PYNQ-Z2 或 FMC 子卡的接线说明替代本板资料。

## 结论和本轮边界

当前可以证实的直接软件问题仍是两项：IDT 已配置态被出厂 ID 单一判据拒绝；输出 DP159 地址使用了输入侧的 0x5c，而本板实际 DP159 在 0x5e。除此之外，本轮发现启动复现、板卡修订适配、实现签核、评估许可及状态验证方面的缺口，不能保证只改两处就一定亮屏。

本轮在电脑上重新检查原始工程、最终 HWH/XSA/bit/xclbin、驱动和既有实板采集，并从 AMD/Xilinx 官方重新取得板卡定义及 PYNQ 源码进行比对。没有新开串口、没有新的板端 MMIO、没有下载 Overlay、没有运行 HDMI 配置。实际 PCB 修订版尚未确认。下文“已核对”不等于新完成了板端测试。

机器复核：41 项均满足本报告定义的静态/历史证据条件；部署清单1160文件通过，原生库57份源码与构建凭据吻合。该结果不是整机验收 PASS。部署程序、候选程序和硬件文件未改。

## 1. 官方资料身份与适用范围

- AMD《ZCU104 Evaluation Board User Guide》，UG1267 v1.1，2018-10-09，92页。已确认封面确为 ZCU104；重点页11、57-62、87。官方来源与 SHA 保存于 results/official_zcu104_manual/source.json。
- UG1267 第11页明确：存在多个板卡修订版，差异不全部记录于本手册；应使用对应版本的原理图、布局和 XDC。因此不能把旧表直接当作所有 ZCU104 的最终引脚签核。
- AMD《ZCU104 Evaluation Kit Quick Start Guide》，XTP482 v2.1，2018-05-30。它是 BIST/工具入门，测试项目主要是时钟、存储器、EEPROM/IIC、开关和按键；不是给本项目直接亮 HDMI 的完整驱动流程。不能把 BIST 通过当成 HDMI 通过。
- Xilinx 官方 XilinxBoardStore，2022.2 标签，boards/Xilinx/zcu104/1.1：板名 ZCU104，器件 xczu7ev-ffvc1156-2-e，记录兼容 RevA/RevB/RevC。这里的文件版本1.1不是用户实体 PCB 版本；该 pin XML 未提供 HDMI 引脚，不能用它独立消除 G21/H9 差异。
- Xilinx 官方 PYNQ v3.0.1 的 boards/ZCU104/base/base.py、base.xdc 以及视频驱动/时钟常量共5文件，重新下载后与交付快照规范换行后一致。该参考只用于其明确支持的板卡/设计，地址不能脱离本板身份读回机械套用。
- Renesas 8T49N241 数据手册与 TI SN65DP159 数据手册用于解释本板实际器件的协议、寄存器与地址，属于器件资料，不是借用其他开发板接线。

官方网页：https://www.amd.com/en/products/adaptive-socs-and-fpgas/evaluation-boards/zcu104.html 。本次尝试的旧 schematic ZIP 地址已重定向到产品 HTML，未获得对应修订版完整原理图，未把该 HTML 保存成原理图。

## 2. 板级接线与引脚对照

| 检查项 | 官方依据与当前设计 | 结果 |
| --- | --- | --- |
| HDMI 接口 | UG1267 p57-60：P7上层OUT经U94 DP159，下层IN经U19 TMDS181；用户接上层 | 接口方向正确，无需子卡 |
| 控制 IIC | D1=SCL，E1=SDA；PL v014_fmch_iic@0x82030000，100kHz | 引脚/控制器配置一致；既有只读证据可读多个芯片 |
| 显示器 DDC | B1/C1，经TX DDC接口；与D1/E1芯片控制总线分开 | wrapper中两路各有正确IOBUF；未混接为PS I2C |
| HPD | E3接TX hpd，C_HPD_INVERT=false | 静态一致；显示器实际HPD尚未新测 |
| TX OE | A2，高有效，连接一位常量1 | 逻辑连接符合使能要求；未实测电压 |
| IDT RESET | UG1267 p61要求M12高；最终HWH与XDC为常量1、M12/LVCMOS33 | 静态符合；不能认定必须改为GPIO |
| IDT LOL | N11接PHY tx_refclk_rdy，C_Txrefclk_Rdy_Invert=1 | 与LOL高表示失锁的极性处理一致；实际锁定待测 |
| GT参考输入 | IDT输出接GTH参考T8/T7；XDC约束正端T8 | 与手册主路径一致；差分负端由GT专用引脚规则落实，尚未独立重跑report_io |
| TX时钟输出 | 当前XDC G21/LVDS；官方ZCU104 PYNQ也是G21；归档Vivado ZCU104示例明确注释rev B | 与该参考一致，但UG1267旧表为H9/G9；用户PCB修订版未知，此项保留待确认，不能盲改任何一边 |
| TX数据通道 | PHY为GTHE4、X0Y16/17/18三通道，内部LINK0/1/2与TX逐路相连 | HWH/子系统连接一致；最终封装管脚/极性仍需对应PCB原理图及routed report_io签核 |
| FMC命名 | 参考文件标题含FMC、实例名fmch_iic，但实际引脚D1/E1接本板控制总线 | 名称不能作为需要子卡的依据 |

## 3. 两处有实板证据的软件问题

### B1：IDT识别门槛与已配置状态不兼容

Renesas p16表7B明确DEV_ID/REV_ID是R/W；不是不可修改的只读身份熔丝。固定PYNQ初始化表会把0x0002/3/4写为ff。实板0x6c从0x0000读取16字节为：

`FF FF FF FF FF FE 6C 00 03 00 31 00 04 89 00 00`

这不是整块全ff；16字节接收完整。除了0x0006受保留位/地址脚影响的读回外，与固定IDT_Synth前缀吻合。不能据此断言芯片损坏、总线全失效，亦未确定具体是哪次初始化写入。此完整块的本次证据是一次读取；候选中的“双次稳定读取”尚未在板端执行。

当前程序仅允许0x0606，在PHY/TX配置前就拒绝0xffff，解释了现有初始化停止点。独立候选提供出厂身份或完整已核实配置态验证，不无条件接受0xffff；由于用户此前明确限制修改ID判据，该候选仍未应用。

### B2：输入器件被当成输出器件

实板0x5c身份是`TMDS181 `，0x5e身份是`DP159   `。UG1267明确U94 DP159属于输出、U19 TMDS181属于输入；TI p35表4的BC/BD为8位读写地址，对应7位0x5e。

当前代码在0x5c识别，若为TMDS181便跳过DP159配置。越过B1后仍会遗漏真正输出侧DP159的配置。应在本板已证实的0x5e验证DP159身份后配置，不能向输入芯片写输出配置。

额外核实：重新下载的官方PYNQ ZCU104 base.py也写了0x5c。它确实是ZCU104文件，但并不能推翻这块实板的身份读回；不同参考/修订的地址假定仍需逐板确认。不能称所有ZCU104统一只能用0x5e。

## 4. 时钟、复位、原生驱动和视频流

| 项目 | 本轮检查结果 | 边界 |
| --- | --- | --- |
| FCLK0 | 既有capture_fixed共64记录，含下载前后、Runner创建后及60个steady样本，均99.999MHz、15x1 | 寄存器推导值；本轮未重新采板，未用示波器测频 |
| 时钟角色 | FCLK0给AXI/DRP；IDT用40MHz晶体产生TX参考；PHY产生video/link时钟 | 三者不能都强制改成100MHz；149.9985MHz不是HDMI协议统一常量 |
| 720p60 | 官方视频表总行1650、总帧750，名义像素频率74.25MHz；2PPC有效视频时钟37.125MHz | GT参考可因PHY PLL/过采样选项变化，须记录官方函数返回与硬件回读，不硬编码为像素频率 |
| HWH时钟标签 | 部分接口标100/148.5/297MHz，XDC GT参考约束按297MHz | 是元数据/静态实现条件，不是运行时测量；运行模式由驱动动态配置 |
| 跨时钟 | TX子系统内部v_axi4s_vid_out的C_HAS_ASYNC_CLK=1，AXIS侧约100MHz，video侧接PHY输出 | 没有证据表明缺少跨时钟FIFO；无需因此先加外部clock converter |
| 数据宽度 | RGB888，2PPC=48位，packer/FIFO/TX接口一致；1280行宽是偶数 | AXIS的TUSER帧首/TLAST行尾连接存在，真实像素顺序和稳定性仍需画面验证 |
| 有效画布 | 显示RTL为1280x720，中心640x480灰度画面，偏移320/120，独立双帧缓存 | 低FPS摄像头与60Hz显示可以独立；摄像头5FPS本身不意味着HDMI应输出5Hz |
| VTC | 官方TX驱动按运行时PPC折算水平时序，负责消隐/同步；自定义RTL仅给有效区 | 不直接按VTC生成参数中的默认字段认定PPC错误；尚需实际bridge lock/STREAM_UP |
| PS复位 | aux reset低有效，实际接常量高；peripheral_aresetn供AXI模块 | 未发现旧版aux一直复位问题回归 |
| PHY配置 | GTHE4、TX-only、RX_PROTOCOL=3、NIDRU=0；原生库profile与最终HWH逐项一致 | stock PYNQ库不同配置不应替换当前匹配库 |
| 库来源 | 57份构建源码与receipt吻合；AArch64 ELF、库SHA和ABI检查通过 | 库内旧HWH哈希/旧reset元数据不等于混用bit；运行代码比较核心参数并单独核实新reset |
| IIC协议 | IDT用16位大端寄存器指针，DP159用8位指针；send/receive返回长度检查存在 | 历史末态寄存器被驱动清过，不能仅凭末态证明全过程ACK；不应全地址扫描 |
| 事件与超时 | 沿用官方HPD→格式→外部时钟→start→stream down/up流程，worker父进程超时有界 | 硬超时必须记UNKNOWN，不可当作正常停止；不能靠增加无限重试制造通过 |

## 5. 额外问题与验收缺口

### R1：默认启动环境不可重复

既有记录证明默认image.ub缺少DDR no-map；一次性RAM启动image17.ub后，两块预留和root检查才通过。普通重启/断电后默认仍可能回到未预留环境。必须在后续正式发布时明确选择并验证可重复启动的镜像流程，不能拿一次临时启动代表冷启动通过。本轮没有覆盖任何启动文件。

### R2：板卡修订和最终引脚尚未闭环

手册第11页明确要求版本对应。当前代码/XDC与G21的ZCU104参考一致，但用户未找到PCB版本，且未取得该实体版本完整原理图、未对最终DCP独立重跑report_io。因此还不能宣称每根输出线均已按实体板签核。这是待核实条件，不是已证明的引脚错误。

### R3/R4：实现报告不能概括成“完全没有问题”

最终reports/timing.rpt记WNS=0.047ns、WHS=0.002ns，已设时序约束满足；同时有61个constant-clock相关内部端点、6个输入与6个输出未给delay，report_methodology尚未运行。需要开发者解释这些路径是否为异步控制/禁用逻辑，并对最终DCP补充对应签核，不能为通过而乱加false_path。

最终DRC报告有589项Warning，无Error不等于零风险。其中PDRC-153与PLHOLDVIO-2涉及PHY的b0_clkdet_dru_refclk禁用/常量时钟路径；NIDRU=0可能解释它们，但本轮未完成逐路径豁免审查，不认定它们是当前IDT报错原因。RAM/AXI等其他告警也应交原开发者签核。

更需要说明的是最终impl_1/runme.log第362行出现HDPR-5从Error降级的工具警告。必须说明降级针对的具体检查、原因和依据；不能把抑制后的DRC无Error当作未加条件的签核。没有证据表明它导致当前黑屏，也没有在本轮更改任何严重度。

### R5：HDMI硬件评估许可

同一最终实现日志约第1340-1343行明确指出HDMI TX IP使用hardware_evaluation，运行一段时间后会停止。不能作为长期稳定运行的正式硬件。长期部署应取得相应正式许可并重新生成受影响IP和硬件；本轮不改变或绕过许可。

### R6：DP159模式寄存器读回有缺口

当前初始化器为了避开0x0a的自清除动作位，跳过了整个0x0a比较。TI p37表7表明只有部分位是写动作/硬件更新，其余还包含工作模式等可读写字段。应根据逐位访问属性比较稳定字段并记录实际模式；不宜把整个寄存器都当不可验证。该缺口尚未被证明是黑屏原因，也不应取消其他读回检查。

### R7/R8：未测项目与日志含义

当前没有候选修正后的HPD、EDID、外部参考频率、PLL锁定、bridge lock、STREAM_UP及屏幕图像证据。固定720p60尚未验证显示器EDID接受此格式。IIC可读证明不了整个HDMI物理链路已通。

run_pipeline.py中的HDMI_INIT_OK是在hdmi.init后、hdmi.start前打印，只表示初始化阶段返回，不是STREAM_UP或亮屏通过。视频正确、摄像头连续120秒、并发只读采时钟及真正冷启动复测仍需分别记录。Jupyter在上次probe前已停止，但本轮未重新查看当前板端进程，后续实测前仍要检查。

## 6. 硬件一致性与证据

| 文件 | SHA-256 |
| --- | --- |
| fengyan_v017_dpu.bit | `8a115a6f420529fcca1791a28978a63637991cb9f952aa56855cd5f2009b0440` |
| fengyan_v017_dpu.hwh | `8a556f2f1ee020932ee10352af887937f704d4637fa6ccd86d39adae191ccca8` |
| fengyan_v017_dpu.xclbin | `1903a6ea9cb9f2e997210340a59d64ed46ad3d3cc9b24d78e937f0e57d0f678a` |
| fengyan_v017_final.xsa | `4a8a60a4bf5847cddcbc304f32f2615fd2478b78de2a285330051e01996fb11a` |

XSA内bit和HWH逐字节哈希一致；xclbin在偏移816处包含完整相同bit。最终原生库SHA为adaa8aa8ffeb65054f9705d504ad2ffab4d14232420a95db131e506136108a1d。当前部署程序与待审候选的哈希由audit_results.json记录，前后未变。

本轮新增材料：results/zcu104_full_audit_20261102/audit_zcu104_hdmi.py、audit_results.json、official_excerpts.txt、implementation_warning_excerpt.txt、官方板卡定义/quickstart/PYNQ源码及各来源哈希、选页渲染图。历史实板原始证据仍在results/official_zcu104_manual和capture_fixed等目录。

## 7. 建议执行顺序

1. 原开发者先审阅两处有板端证据的软件候选；IDT判据调整需要确认原有明确限制，不能当作已获授权部署。补充DP159稳定字段读回与阶段日志含义，保留所有保护。
2. 再确认本次no-map、实际匹配Overlay、FCLK0及独占访问，做有超时的HDMI初始化/单图显示测试；同时记录HPD、EDID与PLL/参考频率/STREAM_UP。如果出现新错误，以实际阶段继续定位。
3. 如后续表现指向物理输出，再优先闭环PCB修订版、匹配原理图、最终report_io与时钟输出路径。现阶段没有依据要求先买子卡或强制重做PL；也不能保证软件两处修改足以包办所有问题。
4. 亮屏后做摄像头连续运行、只读时钟采样、停止/重新启动和真正冷启动。启动镜像、评估许可与实现警告的正式交付签核需同步闭环。

本报告是检查结论和后续验证依据，不是已亮屏、已修复或整机验收通过声明。


## 官方来源链接

- AMD ZCU104用户手册：https://docs.amd.com/api/khub/documents/g76en4BfB6qIp2gHDRkQxg/content
- AMD ZCU104快速入门：https://www.amd.com/content/dam/amd/en/documents/products/adaptive-socs-and-fpgas/boards-kits/quickstart-guides/xtp482-zcu104-quickstart.pdf
- Xilinx ZCU104板卡定义：https://github.com/Xilinx/XilinxBoardStore/tree/2022.2/boards/Xilinx/zcu104/1.1
- Xilinx PYNQ ZCU104参考：https://github.com/Xilinx/PYNQ/tree/v3.0.1/boards/ZCU104/base
- IDT器件资料：https://www.renesas.com/en/document/dst/8t49n241-datasheet
- DP159器件资料：https://www.ti.com/lit/ds/symlink/sn65dp159.pdf

每份下载资料与官方源码的URL、实际文件类型、大小和SHA-256均保存在随附JSON凭据中。
