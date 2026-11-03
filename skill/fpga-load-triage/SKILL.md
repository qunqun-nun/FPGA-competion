---
name: fpga-load-triage
description: Separate FPGA file, environment, Overlay-loading and hardware reset or interrupt failures, and prepare an evidence-based handoff to the hardware builder.
---

读取 [README.md](README.md)。按最早未通过的里程碑定位，不反复触发已知会挂起的硬件加载。将文件推算指纹与真实硬件读回严格分开。

硬件连线缺陷需要工程修改和同次构建产物，不能通过编辑哈希、改名xclbin或改xmodel属性修复。复位极性必须由本工程IP配置确认，不能普遍认定aux_reset_in低有效。使用模板交接原始证据、可证伪假设和最小复测步骤。

