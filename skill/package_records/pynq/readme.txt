# PYNQ 上板与证据交付技能包

对应 **3.3.5.2 技能包**。将真实协作中的流程、失败与观察提炼成可复用方法；RTL/HLS、模型和完整工程属于3.3.5.1，不重复混装。

## 快速使用

阅读 `pynq-board-evidence/SKILL.md`，填写 `assets/board-profile.json`，未知项保留null。向助手输入：`使用 $pynq-board-evidence，依据我的板卡配置完成上板验证与证据交付。历史通过不能当作本次通过。`

可将整个pynq-board-evidence目录复制到Codex用户skills目录，重载后使用；普通助手也可直接读取SKILL.md。本次仅生成交付，不自动安装或改全局配置。离线脚本只依赖Python 3.8+标准库，真实运行需要目标板的PYNQ/VART等环境。

## 范围、用法、失效条件和已验证效果

|条目|适用范围与使用方法|失效条件/边界|验证效果与来源|
|---|---|---|---|
|上板工作流|PYNQ Linux工程，按workflows.md预检、加载、完整输入输出验收|无真实连接、硬件契约或内存策略时停止配置|ZCU104 no-map检查失败后恢复正确镜像再通过，案例C1|
|模型切换|VART/XIR及CPU后处理，使用模型工作流与提示词2|指纹、输入FP、输出名称或CPU参数不匹配|两次新模型重新提取CPU头并执行真实推理，C3|
|性能采集|按measurement.md采样，用evidence.py stats复算|无原始时间戳/标注/目标时不生成相应结论|预热10次+120次任务，N/平均/P95可复算，C5|
|文件可复现性|evidence.py manifest/verify生成及验证文件SHA|哈希只证明身份；清单须可信|本机覆盖变更、缺失和路径越界拒绝|
|黄金参考校验|evidence.py compare比较同形数值JSON数组|不计算mAP，须先对齐输出顺序/坐标/量纲|本机容差、形状、非有限值测试|
|资源与时序检查|evidence.py limits读取从正式报告提取的正规化指标|缺项BLOCKED；不猜不同工具报告格式|本机通过、缺项、超限、负WNS测试|
|命令日志|run_logged.py OUT -- COMMAND ARGS保留stdout/stderr/退出码|不提供硬件授权，不自动重试|本机真实退出7及错误流验证|
|案例/排错/报告|pitfalls.md、cases.md和assets/report.md|仿真、功能、性能和现场结果各自陈述|C1–C6保留触发、方法、效果和限制|

## 目录与验收

SKILL.md为入口；references为按需读取的方法/提示词/案例；assets是可复制的配置和报告模板；scripts是可执行工具及失败路径测试；validation.md记录本次本机验证；SHA256SUMS.json是交付清单。每个条目的详细适用条件和停止条件在对应文档中。

运行自检：`python -m unittest discover -s skill/pynq-board-evidence/scripts -p "test_*.py"`。

通用技能不固定型号、密码、串口、物理内存、IIC地址或频率。ZCU104参数只在案例中出现。换板可配置复用，但尚未在第二种板卡实测。历史实板证据与本次脚本测试分别记录，不能称本次重新完成硬件测试。
