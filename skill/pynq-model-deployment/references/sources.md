# 参考资料及查阅顺序

1. **实际安装版本的API、示例及源码**：首先查torch_quantizer签名、quant_config示例、export_xmodel实现、当前网络forward返回值、DpuOverlay加载逻辑。它们决定本次可执行参数，不能用网络新版本覆盖旧容器行为。
2. [Vitis AI官方仓库](https://github.com/Xilinx/Vitis-AI)：选择与实际工具一致的release/tag，查PyTorch Quantizer、编译器、DPU架构和VART资料；本项目实践为3.5，不意味着其他版本可原样运行。
3. [DPU-PYNQ官方仓库](https://github.com/Xilinx/DPU-PYNQ)：2026-11-04查阅时README声明该发布支持PYNQ3.0/Vitis AI2.5.0。仓库已归档，需按实际系统确认支持范围，不能把构建侧3.5等同板端2.5。
4. [PYNQ Overlay官方说明](https://pynq.readthedocs.io/en/latest/overlay_design_methodology/overlay_design.html)：bit/HWH配套、HWH描述IP/中断/复位等信息。该资料不意味着每个Overlay都需要xclbin。
5. 当前训练框架官方源码：核实预处理、评估器输入、Detect头返回结构、DFL和NMS行为。不同模型库版本的字典/tuple结构可能不同。

## 本地实践依据

`case.json`来自本次实际训练、量化和编译结果；`pitfalls.md`来自协作中tuple输入、依赖丢失、配置schema、SiLU兼容、二次缩放、节点编号及XIR解析等错误。效果只覆盖已执行检查，板端未验收项不宣称成功。

附件中的热门Skill示例仅用于组织方式：状态阶段、按需读取、规则库与可测试资源；没有复核或引用其Star数量，也未复制外部Skill正文。
