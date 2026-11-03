# 仿真与离线验证

在仓库根目录执行 `python sim/run_checks.py`；安装 Vivado 2022.2 后执行 `python sim/run_checks.py --rtl --vivado-bin F:/Xilinx/Vivado/2022.2/bin`。

依赖：Python 3.8+、numpy、pillow；本机原生内存测试需要 C 编译器。原始日志与汇总在 results/。RTL 仿真调用真实 xvlog/xelab/xsim，测试 AXI-Lite 读写/背压、dummy 视频源，以及 dummy 到 pl_video_in 的完整帧传输。

软件单元测试使用受控模拟对象，不访问板卡；不能代替实际 DMA、DPU、HDMI 或整机 RTL 验证。设备树部分测试可能因本机没有 dtc 而跳过，汇总明确记录。
