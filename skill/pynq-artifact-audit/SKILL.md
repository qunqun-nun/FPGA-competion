---
name: pynq-artifact-audit
description: Verify arbitrary PYNQ deployment artifacts against SHA-256 manifests and separate file identity from hardware runtime compatibility.
---

读取 [README.md](README.md)，明确运行路线，再核对该路线所需文件和构建来源。使用 `scripts/verify_manifest.py` 检查清单，不假设所有项目必须有xclbin。验证路径限于包内，不读取逃逸路径。

结果只证明文件与提供的清单一致。若清单与文件来自同一未知来源，不能证明发布者可信；即使哈希一致，也不代表bit/HWH地址、内核元数据、时钟、中断或驱动相容。用模板分别记录这些证据。

