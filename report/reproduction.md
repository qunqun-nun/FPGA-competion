# 目录与复现说明

README.md 按要求仅复制技术文档摘要，实际验收状态以本文件和测试日志为准。

| 目录 | 内容 |
|---|---|
| src/ | 自研 RTL、封装 IP、约束和原始整机工程源文件 |
| sim/ | 可执行离线测试、RTL 仿真入口及原始结果 |
| build/ | Vitis 平台/XO 输入、可迁移链接脚本和真实历史综合实现报告 |
| board/ | 配套硬件、模型、PS 运行源码、部署配置及分版本上板证据 |
| data/ | 样例图片、标注、FP32/INT8 仿真精度参考，实板金标准对比仍待补 |
| skill/ | 两份用户提供的技能包合并内容、原包与校验记录 |
| report/ | 技术报告、历史说明、大模型协作记录、目录改名记录 |

先阅读 build/README.md 和 sim/README.md。设计报告源文件及 PDF 在 report/design/。文档摘要描述设计目标，不代表目录整理时新增验证了全部功能。旧文档中的 runtime/、hardware/、models/ 和 samples/ 根路径分别对应 board/runtime/、board/hardware/、board/models/ 和 data/samples/。

当前可复现的是离线软件测试与已提供的 RTL 仿真。完整重建脚本已提供，尚未在本次整理中跑完整机链接。2026-11-03 新增的分版本实板日志、FPS、仿真精度和重启证据见 board_evidence_20261103.md；其中模型与当前仓库附带模型不同，不能宣称本仓库整机验收通过。HDMI 仍有评估许可限制。

文件名使用英文；按指定模板保留 README.md、LICENSE 及 Git 隐藏元数据惯用名称。原始厂商归档内部文件名保留，以免破坏 IP/XSA/XO。
