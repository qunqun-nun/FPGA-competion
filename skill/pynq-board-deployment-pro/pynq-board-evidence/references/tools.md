# 离线校验工具

在技能目录运行。仅使用Python 3.8+标准库，不连接板卡。

## 文件身份

```sh
python scripts/evidence.py manifest /path/to/project NEW_MANIFEST.json
python scripts/evidence.py verify /path/to/project NEW_MANIFEST.json
```

输出必须为新文件。清单应来自可信构建，验证仅覆盖列出的文件，不认证额外文件。生成时拒绝符号链接；读取时拒绝跨根目录路径。哈希一致不等于功能或可重建性通过。

## 黄金参考

```sh
python scripts/evidence.py compare reference.json actual.json --atol 0.001 --rtol 0.0001
```

输入为同形、有限数值数组，按abs(actual−gold)≤atol+rtol×abs(gold)比较。形状错误、NaN/Inf和空参考被拒绝。该工具不计算mAP，预测框需先按适当规则匹配。

## 统计

```sh
python scripts/evidence.py stats references/evidence/tasks.jsonl NEW_STATS.json
```

随包数据为历史真实任务的字段正规化副本，应复算得到120样本、83.9340675秒和1.4296936104 FPS；回放不构成新的实板测试。

## 资源与时序

```sh
python scripts/evidence.py limits assets/metrics.json
```

依据正式完成的实现报告填写资源使用量/容量、阈值、WNS、TNS、未约束路径和约束覆盖情况，并记录报告SHA256与工具版本。模板null表示未知，返回BLOCKED。源报告提取过程需另行核验，脚本不自动解析所有工具报告。

## 命令日志

```sh
python scripts/run_logged.py NEW_RUN -- python -c "import sys; print('sample'); sys.exit(7)"
```

保存stdout、stderr、参数、工作目录、UTC起止时间和真实退出码。无shell执行、不自动重试；无法启动时记录launch_error，不伪造子进程退出码。不得将凭据写入命令或输出。

## 返回码与测试

校验工具返回0=PASS、1=FAIL、2=BLOCKED或非法输入。日志工具返回实际可表示的命令退出码。

```sh
python -B -m unittest discover -s scripts -p "test_*.py" -v
```

测试使用合成输入，验证工具语义，不证明板端模型精度。
