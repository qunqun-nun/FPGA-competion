# 官方与开源参考研究

先查当前工具/IP 版本的官方规范和例程，再查原作者开源仓库，最后才用二手文章辅助。按模块开展检索，不为每行代码找形式上的链接。不得因代码来自官方或 GitHub 就跳过验证。

## 记录的最小信息

为 AXI、复位/CDC、DMA/DDR、算法与封装各关键设计填写 assets/reference-ledger.template.md：URL、章节/文件、版本/commit、访问日期、许可证、采用方法、未采用原因、改动差异与验证用例。GitHub 记录具体 commit 和所用代码/测试路径；引用与复制代码分清，遵守实际许可证，不默认商业 IP 可再分发。

检索结果必须阅读全文中相关接口/限制，确认依赖、工具版本、端序、位宽、复位、背压、延迟及参数。选择已有验证的协议驱动和 scoreboard 有助于发现时序边界；不能只看 README 就引入未兼容的库。只有确实执行后，才写“复现通过”。

## 参考入口

- [AMD UG900 2022.2 仿真](https://docs.amd.com/r/2022.2-English/ug900-vivado-logic-simulation)：Testbench、行为/综合后/实现后仿真方法。按目标版本使用，不能从工具菜单存在推导测试已跑。
- [AMD UG1118 IP Packaging Basics](https://docs.amd.com/r/2023.1-English/ug1118-vivado-creating-packaging-custom-ip/IP-Packaging-Basics)：封装构成及文件组织，目标若是 2022.2 须切换/核对其对应版本后采用。
- [AMD UG934 AXI 视频](https://docs.amd.com/r/en-US/ug934_axi_videoIP/AXI4-Stream-Specific-Parameterization)：视频流约定；先确定目标 IP/版本以及 SOF/EOL 含义。
- [cocotbext-axi 原作者仓库](https://github.com/alexforencich/cocotbext-axi)：AXI/AXI-Lite/AXI-Stream 仿真驱动与接收，参考测试组织和插入停顿；固定版本并验证所选模拟器兼容性。
- [verilog-axi 原作者仓库](https://github.com/alexforencich/verilog-axi)：AXI 模块与测试组织；使用前阅读仓库维护状态、许可证及依赖，不承诺任意 Vivado 版本可直接运行。
- [PYNQ Overlay 设计](https://pynq.readthedocs.io/en/latest/overlay_design_methodology/overlay_design.html)：bit/hwh、IP 元数据与驱动关系，用于交付审查。

这些是本技能编写时查阅的入口，未将外部仓库代码直接复制入本包，未在本机安装或运行其 RTL 例程。用例实际开发时补上精确版本和运行证据。
