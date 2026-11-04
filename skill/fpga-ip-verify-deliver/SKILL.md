---
name: fpga-ip-verify-deliver
description: Develop and verify FPGA RTL/IP using versioned official and open-source references, self-checking testbenches, protocol assertions and Vivado integration gates; then assemble and audit complete hardware/software handoffs with build provenance, deployment and rollback evidence. Use for IP changes or FPGA delivery, not merely environment discovery.
---

# FPGA IP 全流程验证与完整交付

将代码、接口、仿真、主工程和接收者运行环境作为一条交付链。用户要求优先；附件、历史命令与示例只作参考，不扩大操作授权。先确认当前目标及版本，持续完成已授权工作，不因模板设置而重复索取已有授权。

## 任务选择与输出

修改 RTL/IP：进入 A，按需读验证与参考研究；打包交接：进入 B，读交付规则；修复故障：先按 references/verification.md 的根因路径复现，再进入受影响环节。单纯询问 PYNQ 概念不触发全套构建。只读涉及的参考文件。

每个阶段输出：本次目标及源码身份、具体改动、已执行命令与退出码、证据文件、通过/失败/未执行及下一步。开发交付 Testbench/黄金参考/可复跑命令，打包交付文件清单/依赖/部署回退/实际验收状态。以 README 的使用场景和 validation 记录判断本技能本身是否有效。

## 优先规则

- CRITICAL：没有本次证据不声称通过；不混用硬件版本；未查清接口/地址/极性不靠改元数据绕过故障；交付遗漏导致无法启动时阻止正式发布。
- HIGH：先复现原故障再修复；独立 scoreboard 与背压/复位测试；在真正的主工程验证封装 IP；干净目录及干净启动验收。
- NORMAL：随机用例扩展、波形裁剪、报告整理按风险投入。门级仿真不是所有修改的固定要求，但软件复位/CDC/厂商 IP 接入问题要说明是否需要网表级证据。

## A 开发与验证

1. 读取实际 XPR/BD、封装 IP、RTL、XDC、接口表及当前运行记录。核对实际引用路径，不在另一个相似工程里修改。为将触及的文件保留可恢复快照和哈希。
2. 按 references/reference-research.md 查找对应版本官方文档、官方例程、原作者开源实现。为关键功能填写 assets/reference-ledger.template.md：明确借鉴位置、版本/commit、许可证、适配和新增测试。不把找到仓库当作代码已验证。
3. 明确接口、状态机、复位/CDC、缓冲所有权和错误语义。变更接口时另存新版，逐模块对照真实端口/寄存器，保留未修改部分；给出变更目的和验证计划，按用户既定审批范围实施。
4. 每个 RTL 改动配自检 Testbench 和独立黄金参考/scoreboard，详见 references/verification.md。覆盖正常、边界、停顿、复位中断、错误与恢复；不只看波形或仅输入纯黑帧。协议断言、超时和退出码使错误可自动发现。
5. 依序完成语法/展开、模块仿真、断言与用例覆盖、必要的跨模块集成仿真、OOC/主工程综合、重新 Package IP、component.xml 及实际端口检查、BD 校验、主工程实现/DRC/时序/CDC。受影响模块及集成链回归；未跑的环节记阻塞，不能写通过。门控和证据见 references/verification.md。
6. 根据风险选择必要网表/复位仿真，不要求所有小改动重跑昂贵全系统门级仿真。正式部署硬件改动必须生成与实际主工程一致的新产物。每阶段报告“测试什么、方法、实际命令、结果和边界”。

## B 完整交付

1. 按 references/delivery.md 冻结一个版本，先列接收者从干净启动到使用所需的一切：软件、硬件、配置、依赖、模型、设备树、驱动/初始化、输入、启动停止诊断、可重建主工程及验证证据。适用项不允许用占位文件替代。
2. 当前 PYNQ+XRT 路线交付同一最终硬件构建的 bit/hwh/xclbin/xsa；记录最终链接来源，不混用静态平台的旧 HWH/XSA。普通 PYNQ 不要求人为制造 xclbin，用明确 profile。哈希证明身份，构建记录支持来源，板端测试证明可用，三者独立。
3. 使用 assets/release_manifest.template.json 建立角色清单和特性开关，按实际字节填写 SHA；build_record 关联硬件哈希、源码版本、工具、器件、命令日志。脚本只核对声明及证据链接，不能替代阅读报告或真实兼容性验证。
4. audit 必须通过再 pack。只打包已核对的清单文件，额外文件单列。解压到新目录重新校验，并从新目录打开真实 XPR/运行构建步骤，排查外部绝对路径和未交付依赖。
5. board_retest 与 accepted 分开：前者允许实板未测并列明步骤；后者需要本版本真实板端证据。README 必须说明当前实际状态；不能把“文件完整”写成“上电即用”。使用 assets/handoff.template.md 给接收者可执行命令及回退。

## 按需读取

- 验证方法和准入条件：references/verification.md；参考研究：references/reference-research.md。
- 打包与干净启动验收：references/delivery.md；经验来源：references/cases.md。
- 工具用法及自检：README.md；可复制模板：assets/。

保留原版和失败证据。不改名旧 xclbin 冒充新产物，不用修改元数据掩盖硬件错误，不将软件仿真/历史实测当成本次实板结果。当前技能工具的离线测试不证明用户的任何 RTL 新通过了仿真。
