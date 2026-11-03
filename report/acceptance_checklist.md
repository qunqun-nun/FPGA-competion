# 工程包内容核对

| 要求 | 本仓库位置 | 状态 |
|---|---|---|
| 设计源码与工程文件 | src/hardware/、src/project_sources/、board/runtime/ | 已收录。原始 XPR 仅溯源，使用 build/ 重建入口迁移 |
| 仿真与验证脚本、结果 | sim/run_checks.py、sim/results/ | 本次实际执行 89 项软件测试通过，1 项设备树测试因无 dtc 跳过，三组 RTL 仿真通过 |
| 综合与实现报告 | build/reports/original_v017/ | 收录已有硬件的真实报告，非本次重新构建 |
| 资源、时钟和性能指标 | build/README.md、board/results/20261103/、board_evidence_20261103.md | 已收录分版本实测 FPS 及仿真精度；实板 mAP、跟踪 FPS 等仍待补 |
| 上板工程与启动脚本 | board/hardware/、board/runtime/ | 已收录，新增目录的文件校验清单已重建 |
| 实测输出与参考结果对比 | board/results/20261103/、data/reference/20261103/ | 已收录运行、FPS、重启与仿真精度参考；模型版本和未测项明确分开 |
| 可复现构建脚本 | build/rebuild.py、build/export_results.tcl | 已制作并通过输入归档检查；新入口整机重新链接尚未执行 |
| 技能包 | skill/README.md | 已合并收录用户提供的两份技能包，共六个技能目录，保留原包与校验记录 |
| 技术文档和协作记录 | report/design/、report/llm_collaboration.md | 技术文档已复制，协作记录已整理；明确标注人工复核及实板验收的待完成事项 |

## 本次仿真范围

- AXI-Lite 占位控制模块：复位、读写、字节使能、背压。
- dummy 视频源：已有 Testbench 的启动、数据和帧协议检查。
- dummy 视频源到 pl_video_in：实际 RTL 帧传输与集成仿真。
- 软件：运行时协议、摄像头对象行为、流水线进度、时钟策略、设备树校验、HDMI I2C 和板级身份/EDID 策略。

原始输出见 sim/results/summary.json 与各日志；软件测试并不等价于整机 RTL 仿真或实板验收。

## 硬件一致性

build/reports/repository_validation.json 记录硬件 SHA-256、XSA 内嵌 bit/hwh 对比以及模型 MD5。模型文件身份匹配不等于检测精度通过。原有 V0.17 硬件保持不变，V0.17.3 软件修复已保留；仍需在 ZCU104 进行最终复测。

## Git 状态

本次没有提交、推送或修改远程仓库地址。需在 GitHub Desktop 检查本地变更后自行提交并推送。build/ 和 .rpt 原先被忽略，现已解除相关忽略，并保留对输出缓存的忽略。二进制文件继续使用已有 Git LFS 配置。
