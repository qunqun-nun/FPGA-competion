# 通用PYNQ：解释器与设备发现

## 适用范围

PYNQ项目启动前检查，以及 `No Devices Found`、库找不到、venv与系统Python混用。支持更换任务、Overlay和板卡；不依赖YOLO、DPU或项目路径。

## 使用方法

在**板卡Linux终端**，进入包含 `skill/` 的目录；用运行应用时的Python执行：

```bash
python3 skill/pynq-environment/scripts/probe_environment.py --out pynq_environment.json
```

若应用使用venv，先激活该venv再执行。默认只探测PYNQ；DPU项目可明确增加：

```bash
python3 skill/pynq-environment/scripts/probe_environment.py --modules pynq,pynq_dpu,vart,xir --out pynq_environment.json
```

脚本收集Python绝对路径、系统版本、相关环境变量、模块可导入性和PYNQ设备枚举。每个导入在独立子进程执行，防止厂商库异常退出破坏整个采集。不编程PL。默认输出文件放当前目录。

## 可复用提示词

> 请依据附件JSON逐层诊断PYNQ环境。先报告实际Python路径，再列模块导入和设备枚举。区分“检查失败”与“尚未检查”。给出最早失败层的最小修复建议，注明命令在哪个终端执行。不要下载Overlay、重装系统、修改设备树或固定套用某个板卡的环境变量。所有硬件运行结论必须有对应日志。

## 来源、效果与失效条件

- 来源：历史板端普通sudo丢失所需环境导致 `No Devices Found`；保留环境后才进入XIR解析。后续用户记录设置实际XRT路径后发现一个EmbeddedDevice。
- 已验证效果：历史记录表明环境修正可以把卡点推进到后续阶段；本脚本在当前PC验证缺少PYNQ时能完整记录失败而非误报通过。**本脚本尚未在多种板卡实测。**
- 失效条件：无Python3；PYNQ API变化；模块导入超时；权限不足；驱动/设备树问题。设备列表为空不能单独证明FPGA损坏；系统Python的失败不能替代venv检查。
- 环境设置必须依据真实安装路径和启动脚本，不能把本项目的 `XILINX_XRT=/usr` 照抄到别的系统。

