---
name: pynq-board-evidence
description: Deploy PYNQ FPGA applications and compatible VART models, diagnose board failures, and collect reproducible functional and performance results. Includes deployment procedures, version history, and offline verification tools.
---

# PYNQ 应用部署与验证

根据当前工程的硬件构建、模型契约和实际运行状态执行部署与验证。硬件访问、模型切换及持久启动修改应限于明确授权范围。

## 文档入口

- 部署、启动和回退：[运行说明](references/deployment.md)。
- 具体报错及处理：[故障诊断与修复](references/troubleshooting.md)。
- 硬件与软件变化：[版本演进](references/version-history.md)。
- 模块与数据流：[最终数据通路](references/dataflow.md)。
- 性能和精度评估：[测量方法](references/measurement.md)。
- 脚本接口：[校验工具](references/tools.md)。
- 可复用任务输入：[任务模板](references/prompts.md)。

## 执行要求

1. 校验同次构建的bit、hwh、xclbin及XSA，核对模型指纹、输入输出和CPU后处理参数。
2. 直接访问物理DDR前核查启动设备树与内存保留策略；前置检查失败时停止硬件配置。
3. 保证摄像头、DPU、HDMI及IIC独占，记录现有服务状态。测试完成后恢复指定版本。
4. 保存stdout、stderr、真实退出码、单调时间戳和boot_id；失败后先留存证据，再决定恢复步骤。
5. 初始化、STREAM_UP、可见图像、检测框与有效跟踪分别验证；单图测试不替代持续视频测试。
6. 指纹兼容的模型替换通常不需要重新实现Overlay，但必须同步量化点、输出名称、CPU权重及后处理。
7. 未测项目记录原因。显示刷新率、DPU耗时倒数和跟踪状态采样不能替代整机有效帧率。
8. 启动配置修改前备份原状态；正常重启与断电冷启动分别验收。

配置模板中的null表示未知。交付至少包含配置、原始日志、统计方法、版本哈希、运行结果、限制和回退方式。
