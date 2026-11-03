# 构建与实现结果

版本：Vivado/Vitis 2022.2，器件 xczu7ev-ffvc1156-2-e，单核 DPU B4096。

## 入口

在仓库根目录执行：

```powershell
python build/rebuild.py --check
python build/rebuild.py --vitis-bin F:/Xilinx/Vitis/2022.2/bin
F:/Xilinx/Vivado/2022.2/bin/vivado.bat -mode batch -source build/export_results.tcl
```

第一条仅检查输入归档。第二条使用随仓库提供的平台与 XO 进行真实 v++ 链接，生成完整 Vivado 工程和 xclbin。第三条从同次实现导出配套 bit/hwh/xsa 及报告。请使用无空格、短英文路径；输出目录已存在会停止，避免覆盖既有结果。

平台内部没有静态 DPU，链接仅加入一个 DPU kernel；视频、跟踪、融合及显示逻辑由输入平台保留。输入位于 inputs/platform/ 与 inputs/dpu_b4096.xo，kernel.xml 同步提供。脚本生成完整 link.cfg，移除了旧机器的 W: 路径及旧增量检查点依赖。

需要目标机器提供 AMD 工具、ZCU104 board 支持及 HDMI IP 许可。现有硬件使用 HDMI hardware_evaluation 授权，存在评估运行时间限制。工具与许可不包含在仓库中。

## 验证范围

reports/original_v017/ 是已有 V0.17 硬件的真实综合/实现报告，配套 board/hardware/；V0.17.3 是软件修复，硬件沿用 V0.17。本次目录整理只检查构建输入、运行离线测试与部分 RTL 仿真，没有重新执行数小时的整机链接。新脚本的完整重建仍待在目标工具环境执行，不能把输入检查当成链接成功。

历史资源：LUT 70835/230400；BRAM 260.5/312；DSP 710/1728；WNS 0.047 ns；WHS 0.002 ns。详细时钟和 DRC 以原始报告为准。这些数值不能充当实板 FPS。

src/project_sources/ 保留原有最终工程的源文件及原始 XPR，后者是溯源文件，含历史路径，不能作为可迁移打开入口。可迁移重建以本目录入口为准。src/hardware/ 内历史构建脚本同样仅供追溯。
