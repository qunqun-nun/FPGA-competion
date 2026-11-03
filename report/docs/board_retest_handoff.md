# V0.17.3：丙的板端复测操作

本包软件版本 V0.17.3，硬件仍是同次构建的 V0.17 bit/hwh/xclbin/xsa。修复本板 TX DP159 地址、IDT 合法配置态识别、DP159 字段回读，并增加 EDID 和 TX PIO 状态。保留 V0.17.1 的 FCLK0 约 100 MHz 修复。软件版本升级不代表重新生成了硬件。

目前仅离线验证通过，未取得新版本亮屏或检测框证据。本包面向丙已使用的 ZCU104 PYNQ 3.0.1、匹配 VART/XIR/XRT 环境；无需重新安装这些库。原硬件仍有 HDMI hardware_evaluation 授权限制。

## 1. 解压和准备

将 ZIP 完整解压到新目录，例如 /home/xilinx/fengyan_v0173，不覆盖 V0.17.1 或 V0.17.2。以下命令均在该目录执行。使用串口终端或 SSH；网页串口不能自动操作时，可直接由操作者在终端输入命令。

停止其他相机、DPU、HDMI、IIC 和 Jupyter 硬件任务。接 ZCU104 主板上层 HDMI OUT 与显示器。不用 FMC 子卡。摄像头先不作为第一项测试输入。

```sh
cd /home/xilinx/fengyan_v0173
PY=/usr/local/share/pynq-venv/bin/python3
"$PY" runtime/verify_package.py
sudo -E "$PY" runtime/diagnose.py > environment_v0173.log 2>&1
sudo -E "$PY" -c 'import sys; sys.path.insert(0,"runtime"); from pl_runtime import check_reserved; check_reserved(); print("RESERVED_MEMORY_PASS")'
```

如果实际 PYNQ Python 路径不同，替换 PY 并记录。内存保护失败就停止，不跳过保护。此前默认 image.ub 缺少 no-map，仅临时启动 image17.ub 后通过。若需使用丙已验证的候选镜像，先核对该文件及哈希，在 U-Boot 打断自动启动后按原已验证操作执行：

```text
fatload mmc 0:1 0x10000000 image17.ub
bootm 0x10000000
```

这只临时从 RAM 启动，不替换启动文件；Linux 启动后重新执行上述内存检查。候选 image17.ub 由丙现有介质提供，本包没有伪造新的启动镜像。断电重启后要重新确认实际启动的是哪一个镜像。

## 2. 加载、时钟、只读器件验证

确认保护检查通过后运行（会下载本包硬件）：

```sh
sudo -E "$PY" runtime/collect_pl_clock.py --out capture_v0173_clock --load --runner --seconds 10 > clock_v0173.log 2>&1
echo $? > clock_v0173.exitcode
```

退出非零时先停下并保存结果。正常情况下加载后、Runner 创建后及持续采样约为 99.999 MHz。

```sh
sudo -E "$PY" runtime/collect_hdmi_iic.py --out capture_v0173_probe > probe_v0173.log 2>&1
echo $? > probe_v0173.exitcode
```

该入口不下载 Overlay、不配置芯片，仅发送读寄存器所需的地址指针。应在 0x5e 读到 ASCII「DP159   」。IDT 0x6c 应有两次相同的完整 16 字节证据，符合工厂态或固定官方驱动配置态。全 FF、短读、变化或未知配置会明确失败；不得修改 ID 使检查通过。

## 3. 初始化和重复初始化

```sh
sudo -E "$PY" runtime/collect_hdmi_iic.py --out capture_v0173_init --initialize > init_v0173.log 2>&1
echo $? > init_v0173.exitcode
sudo -E "$PY" runtime/collect_hdmi_iic.py --out capture_v0173_init_again --initialize > init_again_v0173.log 2>&1
echo $? > init_again_v0173.exitcode
```

第二条应在第一条成功后、不重启、不重新下载的条件下执行，以验证已配置态。初始化会写入官方 IDT 配置并做回读；关闭会停止 TX 输出，但不会恢复 IDT 上一次配置。

HDMI_INIT_OK 只代表该初始化阶段完成，此时尚未要求 EDID、STREAM_UP 或显示画面通过。独立采集器的 --start 会尝试启动视频，但不主动启动 PL 帧源；正式亮屏验收请使用下面的完整流水线。

## 4. 单图完整通路

```sh
sudo -E env FY_PYTHON="$PY" sh runtime/start.sh --image samples/tank_test.jpg --frames 30 --fps 5 > pipeline_v0173.log 2>&1
echo $? > pipeline_v0173.exitcode
```

程序将加载匹配硬件、初始化 HDMI、启动 PL，并调用受父进程超时保护的 EDID/模式/时钟/输出流程。

依次核查：

- 包 SHA 校验、内存检查、FCLK0 均通过。
- TX 地址为 94（十进制），即 0x5e；IDT 证据保留原始 0xffff，不伪装为 0x0606。
- IDT 初始配置和时钟配置回读通过，DP159 0x0A 稳定位与 0x0B 稳定位通过。
- EDID 头和已读块校验和有效；已读块证明支持 720p60。读取最大 256 字节；若声明更多扩展，all_declared_blocks_read=false，不将未读块算通过。若支持信息仅在后续未读扩展，程序拒绝强制输出，带回 EDID 继续处理。
- 日志显示请求/实测参考频率、PLL 锁定、STREAM_UP、bridge_locked。PIO 原始值只表示核内采样，须结合 pio_running 和 external_reset_bits（本核复位输出低表示复位）解释，不能冒充外部电压测量。
- 实际显示器出现测试图，并记录是否存在真实检测框。picture_verified 不自动置 true，必须另附照片/视频。

EDID 原始数据会存为 state/hdmi_iic.edid.bin，详细 IIC、回读、EDID 和阶段状态位于 state/hdmi_iic.jsonl。失败时保留完整日志和退出码；不要仅取最后一行。若有 UNKNOWN_REBOOT_REQUIRED，停止继续试写，重启回已验证的启动环境后再测。

## 5. 成功后测摄像头、重复启动和冷启动

先核对实际 /dev/video*，再运行：

```sh
sudo -E env FY_PYTHON="$PY" sh runtime/start.sh --camera /dev/video0 --fps 5 > camera_v0173.log 2>&1
```

持续至少 120 秒后正常 Ctrl+C，保存画面视频、检测框和实际帧率。另一个终端可以只读采样：

```sh
sudo -E "$PY" runtime/collect_pl_clock.py --out capture_v0173_running_clock --seconds 60
```

运行中不能用 --load 重新下载。停止后，再运行一次单图入口，验证设置视频时钟后仍可重新初始化。最后做一次真正断电启动，记录实际选择的启动镜像，再执行内存检查及单图入口；临时 image17.ub 启动成功与默认自动启动成功分开记录。

## 6. 带回数据与回退

带回所有 capture_v0173_*、*.log、*.exitcode、state/hdmi_iic*、state/pl_clock.jsonl、state/results.jsonl，启动日志与镜像哈希，以及显示器型号、PCB 修订版照片、HDMI 画面照片/视频。

请分别报告：身份、初始化、EDID、PLL/参考时钟、桥接锁定、单图画面、摄像头、检测框和冷启动的通过/失败/未测状态。零检测如实记录，不降低阈值冒充修复。

旧版本原件保留。回退时先停止全部硬件任务，按旧包操作使用已知启动镜像并重新加载旧完整包。加载器对 /etc/vart.conf 的备份在 state/vart_backup_*；需要恢复时，选取本次测试前的正确备份并按 runtime/restore_vart_config.py --help 使用。配置恢复不等于 PL 已恢复，硬超时后先重启。不要混用不同包的硬件三件套或运行时文件。

本次未修改 RTL 或 IP 接口，无需新增接口表；板卡修订对应引脚、实现警告审阅、长期 HDMI 正式许可及永久启动镜像仍为后续独立事项。
