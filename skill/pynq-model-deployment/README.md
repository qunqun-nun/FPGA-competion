# 通用PYNQ模型部署Skill（含Vitis AI量化分支）

入口为 [SKILL.md](SKILL.md)。采用YAML触发描述、分阶段工作流、阶段进入条件、按需规则库和配套脚本；从真实失败提炼，不复制热门仓库的Star统计或未经核实的内容。

## 使用

把整个 `pynq-model-deployment/` 复制给另一队或Agent技能目录，要求助手读取SKILL.md。普通PYNQ使用环境/交付/验收阶段；AMD DPU项目再启用PTQ与目标编译分支。它是工作流及验证工具，不是一键支持任意网络的量化程序。

Python脚本仅标准库，面向Python3.8+；以下命令在该技能目录执行。Windows可用python，板端通常用对应venv的python3。

```bash
python scripts/probe_environment.py --out environment.json
python scripts/compare_map.py --input references/case.json --max-drop-pp 3
python scripts/verify_manifest.py --root delivery --manifest delivery/SHA256SUMS.json
```

第一项在板端采集，不下载Overlay；无PYNQ的PC会记录缺项。第二项为可直接运行的真实精度案例。第三项需替换为自己的交付包，格式为相对路径到SHA-256的JSON映射。

## 内容

- `references/ptq.md`：calib/test API骨架、配置与数值边界。
- `references/pitfalls.md`：触发条件、定位和修正方法及失效条件。
- `references/coverage.md`：对照完整对话逐项记录原版遗漏和当前覆盖位置。
- `references/environment-recovery.md`：Docker、执行层、依赖持久化、网络及断点恢复。
- `references/sources.md`：官方资料、版本查阅顺序及本地实践依据。
- `references/case.json`：实际精度和编译核验摘录。
- `assets/report.md`：跨项目输入输出契约和验收模板。
- `scripts/`：环境采集、文件校验、精度门槛工具。

## 已验证效果与失效条件

案例完成50轮训练、387张校准、90张独立测试：FP32 mAP50为76.7782%，INT8仿真74.7527%。编译检查一个DPU子图、六路中间特征，指纹/哈希一致；未进行本模型板端mAP实测。

脚本沿用本次已验证工具，测试覆盖篡改、缺文件、异常数值和精度门槛。`validation_results.json`记录PC验证，不是跨板卡证明。通用的是证据链与接口契约；Vitis API、具体算子支持及输出解析需按工具版本和网络调整。不能将本例ReLU、640输入、单子图、六路输出或指纹套用到其他题目。

本技能不依赖坦克类别和ZCU104；但量化分支仍绑定Vitis AI技术路线，不能将其宣称为任意PYNQ加速器通用量化器。
