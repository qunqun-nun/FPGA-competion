# V0.17.3 HDMI 软件修复板端复测包

先阅读包根《先给另一台电脑Codex看.md》，按步骤从保护检查、加载、器件探测、初始化到单图/相机复测。本包供丙当前 ZCU104/PYNQ 3.0.1 环境使用。

- hardware：原 V0.17 配套 bit/hwh/xclbin/xsa。
- runtime：V0.17.3 板端软件，保留 FCLK0 修复，修正 TX 地址、IDT 状态判断、DP159 回读，补 EDID 与 PIO 日志。
- models：同版 six_outputs 模型与标签；samples：单图测试输入。
- reports/document_b4b673343a.md：本次修改、94 项离线测试和实板未测边界；其余带旧版本号的报告是历史记录。
- reports/source_evidence：丙提供的核查报告及原始只读数据。
- docs：硬件接口与历史资料；硬件版本未变，未新增接口表。
- manifest.json、SHA256SUMS.txt：本包完整文件 SHA；runtime/verify_package.py 校验。

完整复测包包含板端运行文件，不包含重新复制的 Vivado/Vitis 工程。需要看硬件工程时仍使用旧的完整工程目录。原版本保留；新硬件未重建；新版本实板画面、摄像头、检测框与冷启动均待验证。HDMI 评估许可限制仍存在。
