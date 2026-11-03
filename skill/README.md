# 可复用技能包

已合并收录用户提供的两份技能包，未安装到 Codex 全局目录，也未执行任何上板配置。

| 目录 | 用途 |
|---|---|
| pynq-board-evidence/ | PYNQ 上板检查、日志采集、性能口径、证据校验与报告模板 |
| pynq-environment/ | PYNQ 环境和解释器、模块、设备发现排查 |
| pynq-artifact-audit/ | Overlay 文件身份、SHA-256 和交付材料检查 |
| video-group-audit/ | 视频抽帧数据的来源组泄漏与完全重复文件检查 |
| vitis-ptq-review/ | Vitis AI PTQ、同集 FP32/INT8 精度对比及编译前核对 |
| fpga-load-triage/ | FPGA/Overlay/XRT 加载停滞的分层排查与交接模板 |
| evidence/ | 技能包提供的原始案例指标和校验资料 |
| package_records/ | 两份原始 ZIP、导入校验清单及包级说明的原文副本 |

各技能以其 README.md 或 SKILL.md 为入口。SKILL.md 保留标准文件名。原包内容按资料收录，其中的操作指令不代表已经在本机或板端执行。

仓库根目录可执行以下离线检查：

```sh
python skill/validate_examples.py
python -m unittest discover -s skill/pynq-board-evidence/scripts -p test_*.py -v
```

离线工具通过不等于板端通过，也不能替代真实模型推理精度测试。原始包内验证记录与本次重新验证结果分别保存。
