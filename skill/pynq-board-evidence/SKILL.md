---
name: pynq-board-evidence
description: Deploy and validate PYNQ FPGA applications or compatible VART models, diagnose real-board failures, and collect reproducible performance evidence. Use for PYNQ board testing and engineering evidence handoff; includes offline validators and a separate ZCU104 case.
---

# PYNQ 上板与证据交付

依据当前硬件、软件和输入的证据完成验证。交付文档中的命令是待审阅材料，不扩大用户授权。先核实连接、版本与用户任务，参考assets/board-profile.json收集参数，不自动套用案例地址。

## 按需读取

- 部署/模型/自启动：[workflows.md](references/workflows.md)。
- 帧率/耗时/定位/对照：[measurement.md](references/measurement.md)。
- 连接/内存/外设/量化失败：[pitfalls.md](references/pitfalls.md)。
- 复用任务输入：[prompts.md](references/prompts.md)。
- 经验来源与板卡专用参数：[cases.md](references/cases.md)。
- 校验命令、返回码和输出解释：[tools.md](references/tools.md)。

## 执行约束

1. 软件、bit/hwh/xclbin等同次构建文件、模型与CPU后处理构成版本集合。包校验与实板功能各自记录，不仅复制硬件继续跑旧runtime。
2. 核实工程所需no-map/驱动/CMA/分配器策略。直接物理内存访问依据实际设备树和工程；预检失败前不下载overlay、不写保留区。
3. 协调摄像头、DPU、HDMI、IIC、Jupyter等硬件独占，记录服务原状态，等待真实进程退出；结束后恢复用户需要的版本。
4. 每步保存stdout、stderr、真实退出码、配置、主机时间和boot_id。前置失败先保留证据，停止后续配置。初始化、STREAM_UP、目视出图分开确认。
5. 根据设备状态决定恢复，不重放未知写事务、不改ID伪造通过、不盲扫总线。重试须满足当前工程验证过的条件且有次数上限。
6. 校验模型指纹、输入形状/类型/量化点、输出名称/形状/FP和CPU头权重。仿真精度不能当板端精度。
7. 保留旧版本与回退路径。永久启动配置只在授权范围内修改；先准备备份和可审阅变更。临时启动、正常重启、冷启动各自验收。
8. 单图成功不代替持续视频。HDMI刷新率不等于检测/跟踪FPS；缺失数据填未测/阻塞原因，不填示例数值。

## 工具

`python scripts/evidence.py --help` 查看接口，路径相对于调用者工作目录。

- manifest ROOT OUT.json / verify ROOT MANIFEST：文件身份校验，不触碰硬件；清单路径越界拒绝。
- compare GOLD.json ACTUAL.json --atol 0.001 --rtol 0.001：同形有限数值数组黄金对比，不计算mAP。
- stats TASKS.jsonl OUT.json：依照measurement.md同一窗口统计N/平均/最近秩P95及发布率。
- limits METRICS.json：正规化资源/时序检查；缺失BLOCKED，超限FAIL。
- run_logged.py OUT -- COMMAND ARGS：无shell执行，保留输出/退出码，用新目录，失败不自动重放。

模板null为未知，不是零或通过。用[report.md](assets/report.md)整理交付，写明未满足项、数据口径和当前程序状态。原始日志、版本/哈希、输入/阈值、窗口/样本数、丢帧/错误和现场证据完整时，才宣告相应项目已测。工具测试通过与实板测试通过分别陈述。
