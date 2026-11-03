# 板端工程与运行文件

hardware/ 是配套 bit/hwh/xclbin/xsa；runtime/ 是可编辑 PS 软件与启动、停止、诊断脚本；models/ 是已有模型和标签；deployment.json 是部署配置。用户提供的上板证据已收录到 results/20261103/，版本归属与剩余缺项见 ../report/board_evidence_20261103.md；这些日志使用的模型不同于本目录附带模型。

完整仓库复制到板端后，从仓库根目录执行：

```sh
sudo -E sh board/runtime/start.sh --camera /dev/video0 --fps 5
sudo -E sh board/runtime/stop.sh
```

必须先按 report/docs/ 中板端部署文档确认系统依赖、启动时 DDR 保留区、HDMI 库和时钟初始化。仅复制文件或上电不会自动运行程序。当前不提供新的 SD 启动镜像，不宣称通过摄像头到 HDMI 的整机实板验收。测试图片位于 data/samples/。
