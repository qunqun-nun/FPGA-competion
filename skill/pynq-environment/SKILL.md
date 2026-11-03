---
name: pynq-environment
description: Collect PYNQ interpreter, import and device-discovery evidence without programming an Overlay; diagnose No Devices Found across board projects.
---

先读取 [README.md](README.md)。在实际运行硬件程序的同一Python环境中执行 `scripts/probe_environment.py`。依据报告区分解释器错位、导入缺项、设备未发现和未知，先解决最早失败层。

不要把某个XRT根目录、sudo选项或venv路径当成所有板卡的固定配置。报告不加载Overlay，不创建Runner；不得由导入或设备枚举成功宣称硬件已运行。对导入超时或崩溃保留子进程退出码，不反复执行可能改变硬件状态的操作。

