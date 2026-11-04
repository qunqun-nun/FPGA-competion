# 历史问题逐项覆盖核对

核对日期：2026-11-04。来源是本次对话可见的实际日志、用户观察与已保存报告；未取得的底层日志不补造。下表将多个同根因重复报错合并，不代表每一行都已完成板端修复。

|历史问题或观察|原版状态|当前规则位置|证据边界|
|缺Linux发行版、Windows中执行Linux命令|缺少操作层细节|environment-recovery.md|环境准备类，不是量化算法错误|
|apt连接卡住/源配置/锁冲突|遗漏|environment-recovery.md|历史操作记录，不能盲删锁|
|docker socket权限|遗漏|environment-recovery.md|历史修正后可运行Docker|
|Windows命名管道context用于Linux|遗漏|environment-recovery.md|历史protocol not available|
|credential helper找不到、配置反复生效|遗漏|environment-recovery.md|历史独立配置目录拉取成功|
|Docker Hub超时、代理跨环境、镜像站白名单、EOF|遗漏|environment-recovery.md|历史最终镜像拉取完成；网络方法按环境适配|
|镜像型号/版本选择及容器重建丢包|部分覆盖|environment-recovery.md、pitfalls.md|固定依赖与镜像身份，不保证所有组合兼容|
|配置目录不可写、无CUDA、/dev/dri提示|遗漏|environment-recovery.md|警告须按实际路线判断|
|宿主/WSL/容器路径混淆、复制命令截断、检查失败退出shell|遗漏|environment-recovery.md|实际发生，通用化执行层检查|
|ultralytics/filelock缺失、不同解释器|已覆盖|pitfalls.md、environment-recovery.md|不自动升级厂商PyTorch|
|module误传tuple|已覆盖|pitfalls.md、ptq.md|module与input_args分别核对|
|Unsupported keyword param|已覆盖|pitfalls.md、ptq.md|配置schema与生成结果分开|
|只有校准JSON、没有XModel|部分覆盖|SKILL阶段3、pitfalls补充表|校准/测试/导出分阶段验收|
|随机dummy用于导出与真实图用于校准混淆|部分覆盖|pitfalls补充表|校准必须真实数据；导出需实际前向|
|找不到ReLU权重、替换后构图与校准不一致|缺明确条目|pitfalls补充表|不能搜索命中任意文件就当正确权重|
|SiLU不支持、Op_type 18、CPU回退|部分覆盖|pitfalls.md及补充表|错误码不能唯一定位某算子|
|旧output_ops编号不存在、JSON命令引号|编号已覆盖/引号遗漏|pitfalls补充表|结构化参数避免shell拼接|
|strided_slice-fix缺shape、多个DPU子图|已覆盖|pitfalls.md|重新编译输出边界；板端需复测|
|通用arch与真实Overlay指纹不同|部分覆盖|SKILL阶段5、pitfalls补充表|B4096相同不等于指纹相同|
|二次/255、二次fix_point缩放、解码重复|已覆盖|ptq.md、pitfalls.md|区分仿真与整数硬件输出|
|输出顺序变化、中间特征及CPU末层参数错配|已覆盖|pitfalls.md及补充表|不能硬编码六输出或列表下标|
|低对比度、校准样本数、CLE与fast finetune混称|部分覆盖|pitfalls补充表、ptq.md|不承诺某设置保证恢复精度|
|视频跨集、高验证低测试|已覆盖|pitfalls.md、SKILL阶段1|需要独立来源，不能测试集选权重|
|训练停止后被误报正常、续训到总轮数|缺明确条目|environment-recovery.md|本轮恢复完成50轮|
|XIR导入成功但Runner/实际推理未验证|已覆盖|SKILL阶段6、pitfalls.md|独立里程碑|
|模型与Overlay混版、缺xclbin、硬件复位卡住|部分覆盖|pitfalls补充表、SKILL阶段5/6|复位来自用户历史记录，修复后未实板验证|

以上覆盖当前可见历史中的主要独立故障和误判。技能用于诊断，不能声称所有历史问题已在任意板卡重新验证。
