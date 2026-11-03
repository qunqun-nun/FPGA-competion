# 生成新的启动 DTB（不安装）

在装有 Python 3.8+ 和 `fdtget`、`fdtput` 的 Linux 主机运行。Debian/Ubuntu 的工具包名为 `device-tree-compiler`；不依赖 Python 第三方包，不调用 runtime overlay。

```sh
python3 prepare_boot_dtb.py /path/to/current-boot.dtb -o ./fengyan-boot-prepared.dtb
```

输入必须是丙实际启动使用的完整 DTB，不是 DTBO。只输出新 DTB 和 `<新DTB>.manifest.json`（记录输入/输出 SHA-256、复用/新增节点、工具路径和验证结果）。已存在的输出/manifest 一律拒绝。工具不复制到 /boot，不改 U-Boot 配置，不替换启动文件，不加载 FPGA，也不应用 overlay。真实启动 DTB 尚未提供，因此本次没有生成声称可用于丙板卡的 DTB。

三帧区为 `0x20000000 + 0x004b0000`，输入区为 `0x21000000 + 0x00200000`。读取根节点的 address/size cells（缺失时用 DT 标准默认 2/1 并记录）；支持 1/2 cell，不修改根或硬件节点。已有 reserved-memory 的 cells 必须与根相符，ranges 必须为空；缺失的这三个保留区父属性可补充。

完全覆盖目标、已启用、空 no-map 属性且不带 reusable 的现有固定区域直接复用，包括一个较大区域同时覆盖两个目标的情况。部分覆盖、禁用、缺 no-map、reusable、原有固定保留区互相重叠、与 DTB header memreserve 重叠均拒绝。启用的动态保留区若没有 alloc-ranges 或可能分配到目标，也拒绝。不会拆分、缩小、重命名或删除已有节点。

所有 fdtput 操作只作用于临时副本；用内部 FDT 解析器与 fdtget 双重核查，再逐个比较所有原有节点/属性字节值、header memreserve 和 boot CPU ID，确认只发生计划内新增，并重新检查保留区。源文件生成前后字节相同才允许发布。输出以独占创建方式写入，防止覆盖已有文件。

离线测试：`python3 -m unittest discover -s . -p test_prepare_boot_dtb.py -v`。测试涵盖 32/64 位 cells、较大区域复用、冲突拒绝、硬件属性保护、工具缺失、输出拒覆盖和临时副本生成流程；没有 fdtget/fdtput 时实际 libfdt 集成用例明确 SKIP，fixture 后端不代表真实工具已验证。

新 DTB 仍需主集成代理检查并纳入真正的启动流程；Linux 启动后再用 hdmi/collect-linux-inputs.py 和 /proc/iomem 验证实际生效。此工具不完成 HDMI 初始化，也不改变已有 HDMI 阻塞结论。
