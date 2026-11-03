# ZCU104 新模型独立启动配置记录

配置日期：2026-11-03（北京时间）。板端时钟仍为 2022 年，不作为实际测试日期。

- 工程：`/home/xilinx/fengyan_v0173_model50_iicfix1_20261102`，新模型 SHA256 `64fde5e0f8f21c1d42c253e29db2104c31b6b226a40b2269d3fba40b33b3b5e3`。
- `/boot/uEnv.txt` 设置 `fitimage_name=image17.ub`。原 BOOT.BIN、image.ub、boot.scr 未改动。image17.ub SHA256 `85e95b12459440348cb43c20c2b202b01be513b8df704ec1a85681e9da240902`。
- 启用 `fengyan-camera.service`，入口 `/usr/local/sbin/fengyan-camera-start`；root 运行，无需登录、网络或电脑。
- 显式设置 XILINX_XRT=/usr 和 PYNQ Python。等待 /dev/video0 最多120秒，检查 no-map 内存预留、清理已不存在进程的旧PID文件，再持续运行摄像头新模型。
- 失败停止，不自动反复重配硬件。systemd 停止会向整个进程组发送 TERM，最多等待45秒。
- 为避免默认 Overlay、PL 状态清理及 Jupyter 的间接依赖抢占硬件，停用并 mask bootpy、clear_pl_statefile、jupyter、pynq-x11 四个服务。原状态已保存，均原先 enabled。
- 每60条推理结果保留一次 journal 摘要，其余启动、错误、退出信息全部保留。
- 原启动文件和服务状态备份：`/home/xilinx/autostart_backup_20261103`。

## 使用

先接摄像头、HDMI OUT 和已打开的显示器，再给板卡上电。初始化需要约1～2分钟；摄像头等待可能另增加最多120秒。实际输入采集/推理速度不等于 HDMI 的720p60刷新率，未达到请求的5次/秒。检测框需有模型识别到的目标；文字OSD未实现。

查看状态：`sudo systemctl status fengyan-camera --no-pager`
查看本次启动日志：`sudo journalctl -b -u fengyan-camera --no-pager`
停止：`sudo systemctl stop fengyan-camera`
关机：`sudo poweroff`，等待关机完成后断电。

## 回退（按需执行）

先 `sudo systemctl disable --now fengyan-camera.service`，停止硬件后删除新增 `/boot/uEnv.txt`（此前不存在），原默认启动镜像将恢复。不要运行工程，原默认镜像缺少 no-map。
恢复原服务：`sudo systemctl unmask bootpy clear_pl_statefile jupyter pynq-x11`，然后 `sudo systemctl enable bootpy clear_pl_statefile jupyter pynq-x11`，再重启。

## 验证进度

1. 首次服务启动因缺失 XRT 环境失败，已补齐。
2. 第二次发现 clear_pl_statefile 的 Requires 间接启动 Jupyter，已移除竞争服务启动。
3. 最终正常重启（无人干预 U-Boot）boot_id=6529bf8d-1454-4d76-a43a-6a5c1f37dbe6，内存预留、包校验1185文件、HDMI_INIT_OK、STREAM_UP和真实DPU推理通过。
4. 断电冷启动和完全拔除电脑后的现场画面确认待完成。

## 最终正常重启现场结果

用户确认自动启动后有实时画面。已正常停止服务，journal 报 Deactivated successfully。保留的第60次推理摘要：PL completed99、dropped39、error0、stale0、aborted0、profiler_timeouts0；存在丢弃计数，因此不声称持续运行零丢帧。现场画面正常与吞吐/丢帧验收分开记录。

已再次挂载 SD 启动分区并核对 uEnv.txt 仍为 image17.ub，四个原启动文件 SHA256 均与部署前一致。停用 bootpy/Jupyter 后 /boot 不再自动挂载，但 U-Boot 在 Linux 前仍可从 FAT 分区读取 uEnv 和镜像，工程不依赖 /boot 挂载。需要修改或回退启动配置时，先执行 `mountpoint -q /boot || sudo mount /dev/mmcblk0p1 /boot`。

已于2026-11-03操作正常关机并捕获 `reboot: Power down`。已请用户拔除电脑连接后进行真实断电冷启动，现场结果待反馈。原启动日志、故障和最终成功记录保留于上级 serial_full.log / serial_commands.log，本目录 autostart_reboot.log 为完整串口重启捕获。

## 独立供电冷启动验收

2026-11-03，用户按拔除电脑 USB/串口和网线、断电至少5秒、显示器先开机后板卡上电的操作要求，反馈“有画面了”。据此确认脱离电脑后可以冷启动并自动出画面。此次未连接电脑采集冷启动日志；用户未单独明确确认冻结/花屏情况，不将这些细项记为已验证。此前正常重启的实时画面已现场确认。
