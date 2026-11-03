# 离线工具用法

以下在技能目录 `pynq-board-evidence` 中运行。Python指当前可用的3.8+解释器。脚本不连接板卡、不读写寄存器、不收集密码。

## 文件身份

```sh
python scripts/evidence.py manifest /path/to/project NEW_MANIFEST.json
python scripts/evidence.py verify /path/to/project NEW_MANIFEST.json
```

输出清单应放工程外；若放内部，本次新清单不将自身纳入。manifest输出必须不存在；verify逐个比较被列文件，附加未列文件不自动认证。拒绝跨根目录路径和生成时的符号链接。仅SHA匹配不是功能/重新构建通过，清单来源本身也须可信。

## 黄金参考

```sh
python scripts/evidence.py compare reference.json actual.json --atol 0.001 --rtol 0.0001
```

两个JSON均为同形嵌套数值数组。按 `abs(actual-gold) <= atol + rtol*abs(gold)` 通过，拒绝NaN/Inf、非数字和空参考。比较输出属于确定性数值容差检查。对于目标检测先对齐帧、类别和坐标，不能直接把不同顺序预测框当数值数组比较；AP和IoU匹配须另用对应评估器。

## 统计回放

```sh
python scripts/evidence.py stats references/evidence/historical_tasks.jsonl NEW_STATS.json
```

文件已存在则拒绝覆盖。历史回放应得到120样本、83.9340675秒、1.4296936104 FPS。该数据不是新板或新模型的实测；字段与窗口见measurement.md。

## 资源与时序

复制assets/metrics.json，依据同一次正式实现报告填写字段。source_report_sha256用该报告字节SHA256，tool_version填写实际工具。检查报告已完成实现、目标时钟约束覆盖、所有相关资源及容量、WNS/TNS和未约束路径；资源max_ratio由本项目预算决定，模板0.9仅是可修改阈值。

```sh
python scripts/evidence.py limits /path/to/completed-metrics.json
```

只有给定指标满足时PASS；缺项BLOCKED；任一已知违反约束FAIL，即使另有缺项也列出。没有通用报告解析器，禁止把手工填入的PASS当成工具实际报告。报告哈希须另与源文件校对，脚本不验证提取过程的真实性。

## 日志和退出码

```sh
python scripts/run_logged.py NEW_RUN -- python -c "import sys; print('sample'); sys.exit(7)"
```

建立新目录，保存stdout.log、stderr.log和command.json（参数、工作目录、UTC起止时刻、原始退出码）。脚本返回7；不经过shell，不把tee返回码冒充程序返回码。若无法启动，exitcode=null并记录launch_error；不自动重试，不提供超时或进程树恢复。不要把密码/token写入命令参数或输出。

所有evidence命令：0=PASS、1=FAIL、2=BLOCKED/非法输入。退出状态也必须由调用方捕获；实际运行项目需按工作流逐步失败停止。
