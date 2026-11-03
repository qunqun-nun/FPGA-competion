---
name: vitis-ptq-review
description: Review Vitis AI PTQ preprocessing, output semantics and matched FP32/INT8 evaluation before DPU compilation, using evidence from prior YOLO deployment failures.
---

读取 [README.md](README.md) 和 [references/pitfalls.md](references/pitfalls.md)。先固定最佳权重及测试集，确认激活函数和预处理一致性，再校准。使用 `scripts/compare_map.py` 对同一测试集结果执行用户选择的下降门槛。

FP32与INT8必须采用等价输出语义和后处理。区分NNDCT已反量化输出与VART原始整数张量；不得重复缩放。动态枚举当前图输出，不复用旧编号，不修改二进制属性规避解析错误。编译后检查实际指纹与目标、子图数、输出契约及MD5；板端未测必须标明。

