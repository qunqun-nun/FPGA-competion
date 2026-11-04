# FPGA IP 充分验证与完整交付技能包

版本 1.0，2026-11-04。提炼乙的两项核心经验：开发不是写完 RTL，交付不是只给 bit。适用于 Vivado 自研 IP、AXI/视频/DMA 集成及 PYNQ/XRT 硬件软件交接；可换算法、项目和板卡，具体接口与构建必须重新配置。

这是比赛 3.3.5.2 的可复用技能包，含提示词工作流、规则、模板、交付校验脚本及反例测试。它补充之前的通用 PYNQ 环境与部署技能，不替换原包，不包含你的工程、模型、许可证或真实 Overlay。

## 使用方法

把整个 skill 目录交给助手，先读 [SKILL.md](SKILL.md)。人工可从以下三种任务开始：

|任务|入口/输入|应得到的输出|失效或停止条件|
|---|---|---|---|
|开发或修改 IP|[验证规则](references/verification.md)、真实源码/接口|独立 TB、scoreboard、断言、覆盖与集成证据|工具缺失/接口未定则记录阻塞，不能声明通过|
|故障修复|同版本失败日志、[反例](references/cases.md)|复现→假设→最小修复→原故障和邻接回归|无可复现记录时先采证，不反复堆补丁|
|打包给下个人|[交付规则](references/delivery.md)、实际构建与运行材料|角色清单、来源记录、ZIP、部署/回退及验收状态|缺硬件/软件/依赖/证据时阻止打包|

参考检索：[研究流程](references/reference-research.md)。提示词：[直接使用](references/prompts.md)。模板：[验证矩阵](assets/verification-matrix.template.md)、[参考台账](assets/reference-ledger.template.md)、[交接说明](assets/handoff.template.md)、[交付清单](assets/release_manifest.template.json)、[构建来源](assets/build-record.template.json)。

所有命令从包含 skill 的父目录执行；Windows 可把 python3 换成自己的 python。脚本使用 Python 3.8+ 标准库，无 Vivado/PYNQ 也能审查已经准备好的材料，但不会执行 RTL 仿真或访问板卡。

```sh
python3 -B skill/scripts/test_release_check.py
python3 skill/scripts/release_check.py audit MY_DELIVERY MY_DELIVERY/release_manifest.json
python3 skill/scripts/release_check.py pack MY_DELIVERY MY_DELIVERY/release_manifest.json --output NEW_DELIVERY.zip
```

退出码：0=声明范围内 PASS；1=FAIL；2=BLOCKED/输入错误。pack 仅在 audit PASS 后生成新 ZIP，不覆盖旧包。解压后须重跑 audit，并执行实际软件及工程迁移验收。不要使用模板假文件取得 PASS。

填写清单的具体字段和角色见 [schema](references/manifest-schema.md)。重新验证整个技能：`python3 -B skill/scripts/validate_skill.py --output NEW_VALIDATION_DIR`，输出目录必须为新目录。新结果不会覆盖本次交付的验证记录。

## 交付检查的范围

pynq_xrt 用于本项目硬件四件套 bit/hwh/xclbin/xsa；pynq 不强制 xclbin。两种 profile 都面向“含可重建工程的完整交付”，会要求 XPR、BD、RTL/IP、XDC、构建脚本、TB/报告及软件入口，不是只有部署文件的小包。

特性开关显式控制 DPU 模型、摄像头传输、HDMI 初始化、设备树及本地编译依赖。检查清单角色、实际字节 SHA、硬件构建标识、构建记录及验证材料链接。报告额外未列文件但不偷偷打进去，接收方须审查其是否为遗漏依赖。

工具不能证明报告内容真实、位流内部兼容、源码没有隐藏绝对路径或系统必然可启动。它防止已声明材料的机械遗漏，仍需按交付工作流做干净目录和实板验收。board_retest 允许明确未测实板；accepted 要求本次板端记录。验收状态填写造假不能被哈希检测出来。

## 经验、验证与限制

来源见 [案例与依据](references/cases.md)。本包自身的脚本用合成夹具验证，夹具中的 bit/hwh 等都是普通文本，绝不用于下载，不能当作工程产物。实测结果见 [验证记录](validation/验证报告.md)。没有重新跑你的 RTL、生成新四件套或新增实板测试。

本包采用“触发条件→阶段门控→按需规则→确定性工具→证据与反例”组织，参考用户提供的 Skill 写法，未采信未核验的 Star 排名，也未拷贝外部技能全文。技能入口保持精简，深度由具体准入标准和测试提供。
