# PYNQ FPGA 应用部署与故障诊断技能包

适用于基于PYNQ、XRT/VART的FPGA视频处理应用，提供部署流程、故障修复、版本变更及离线校验工具。运行命令中的工程路径须按实际部署设置；脚本名称和接口以对应运行包为准。

## 使用

1. 配置板卡、Python环境、硬件构建和模型信息。
2. 按运行说明完成包校验、内存检查、硬件加载与完整链路测试。
3. 根据故障现象选择诊断步骤，保留原始日志与退出码。
4. 使用统计和文件校验工具生成结果，并记录未完成的验证项。

将pynq-board-evidence目录放入Codex技能目录后，可通过`$pynq-board-evidence`调用。其他执行环境可直接读取技能入口。离线工具要求Python 3.8+；实板流程需要匹配的PYNQ、XRT、VART及板级驱动。

## 内容

|内容|作用|
|---|---|
|[运行说明](pynq-board-evidence/references/deployment.md)|前置检查、单图与摄像头测试、模型切换、自启动和回退|
|[故障诊断与修复](pynq-board-evidence/references/troubleshooting.md)|故障现象、定位依据、修改措施与验证结果|
|[版本演进](pynq-board-evidence/references/version-history.md)|硬件、Overlay与软件的主要变化及验证范围|
|[最终数据通路](pynq-board-evidence/references/dataflow.md)|输入、DDR、PL、DPU、后处理与显示之间的关系|
|[测量方法](pynq-board-evidence/references/measurement.md)|FPS、阶段耗时、定位与精度评估的统计口径|
|[校验工具](pynq-board-evidence/references/tools.md)|哈希、黄金参考、资源时序、日志与统计工具|
|[任务模板](pynq-board-evidence/references/prompts.md)|部署、模型替换和性能诊断任务输入|

## 验证范围

板级经验来自ZCU104，最终硬件基线为V0.17；后续V0.17.3、IIC修复、模型切换与自启动沿用该硬件。未进行其他型号板卡的实测。文件哈希一致、软件测试通过、实板功能通过和精度通过分别记录，不相互替代。

离线回归包括7项测试，覆盖文件变更、路径越界、数值容差、P95、无效输入、资源时序判定和命令退出码。运行方式见校验工具说明。
