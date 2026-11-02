# V0.17.1 PL_CLK0/FCLK0 修复与板端复测

状态：软件修复和61项离线回归通过，实板复测未完成。原V0.17不改动。

## 已核对的事实

V0.17 HWH：PS PL0目标100 MHz，实际元数据99.999001 MHz，IOPLL源，分频10×1，IOPLL FBDIV=60、DIV2=1。
最终XSA内psu_init.c：PL0写入掩码0x013F3F07，值0x01010A00，与HWH一致。
Vivado设计的PS配置也要求100 MHz。bit只配置PL，不能替代实际启动镜像执行FSBL的PS初始化。

PYNQ v3.0.1 Overlay.download使用clock_dict中的分频调用Clocks.set_pl_clk；HWH提供的是分频，并不会把整套启动PLL初始化成XSA配置。
如果运行时IOPLL为1499.985 MHz，套用HWH的÷10会产生149.9985 MHz。该机制已离线复现，尚待板端确认实际PLL。

本次修复：加载器在每次download之前，按当前实际PLL推算可用分频，更新本次Overlay对象的clock_dict，再让PYNQ正常download。1500 MHz场景使用15×1；1000 MHz场景保持10×1。
不写HWH，不改共享PLL，不修改FSBL/PMUFW，不覆盖启动文件。加载后、HDMI初始化后、Runner创建后和逐帧阶段均检查FCLK0；若再次改变则停止，不在DMA运行时强行调频。
只支持本工程IOPLL、整数PLL与100 MHz目标；其他源/分频不可达会拒绝执行。

## 请另一台电脑Codex执行

使用此前成功运行V0.17的PYNQ Python环境。解压本包到新目录，例如/home/xilinx/fengyan_v0171，不覆盖原V0.17。所有命令在新包根目录运行；如使用虚拟环境，将python3换成其绝对路径。先停止旧摄像头、推理、Jupyter后台Overlay操作和自动启动任务，避免并发写时钟。

1. 先校验包，不加载硬件：

```sh
python3 runtime/verify_package.py
sudo -E python3 runtime/collect_pl_clock.py --out ./capture_before --seconds 10
```

此采集默认不download、不改时钟。会解析当前包HWH，并记录解析前后的寄存器。

2. 确认原部署要求的DDR no-map启动内存预留已生效。再加载修复版，创建DPU Runner并持续采样60秒：

```sh
sudo -E python3 runtime/collect_pl_clock.py --load --runner --out ./capture_fixed --seconds 60
```

此步骤会真正下载本包硬件并设置PL0分频，加载器保留/etc/vart.conf备份。出现异常必须保留完整输出，不能修改HWH频率或跳过断言。

3. 完成上述采样后，使用新包真实启动入口验证原HDMI失败点：

```sh
sudo -E sh runtime/start.sh --image samples/tank_test.jpg --frames 30 --fps 5 2>&1 | tee hdmi_retest.log
```

日志命令使用tee时不要仅以tee退出码判断成功；应核对PIPELINE_FAILED、PL_PIPELINE_STOPPED、HDMI状态和屏幕画面。再运行摄像头入口，根据实际设备选择/dev/video0：

```sh
sudo -E sh runtime/start.sh --camera /dev/video0 --fps 5 2>&1 | tee camera_retest.log
```

至少观察60秒后Ctrl+C停止；从另一个终端做采样，不要使用--load再次下载：

```sh
sudo -E python3 runtime/collect_pl_clock.py --out ./capture_during_camera --seconds 60
```

4. 停止后冷启动，禁用其他自动加载Overlay任务，再执行步骤1、2，输出目录换成capture_cold_before/capture_cold_fixed。请记录你冷启动后到采集前执行过的命令。

## 带回哪些数据

- capture_before、capture_fixed、capture_during_camera及冷启动采集目录，尤其clock.jsonl、environment.json、loader_pl_clock.jsonl和result.json。
- state/pl_clock.jsonl、hdmi_retest.log、camera_retest.log，以及失败时完整traceback。若采集中断没有result.json，也请保留已写出的JSONL。
- 脚本自动保存实际安装的pynq.ps、pynq.overlay、hwh_parser、pynq_dpu源码、运行中DTB、/proc/cmdline和可读取的kernel clk_summary。
- 实际启动介质/镜像版本、BOOT.BIN路径及SHA256；若有FSBL/PMUFW ELF、BIF、启动串口日志及构建XSA，请提供。无需修改BOOT.BIN，也不要在Linux上执行psu_init.c/tcl。
- 若有其他自动加载脚本：提供其中设置fclk0_mhz、set_pl_clk或加载其他Overlay的相关片段和执行时序。

可将上述日志目录单独压成一个包带回，不必重新发送bit或模型。

## 判定标准

加载后FCLK0应在约100 MHz附近（与HWH目标相差不超过0.1%），不能回到150 MHz；Runner创建后、HDMI初始化后和持续采样也应保持。
PYNQ Clocks值是依据寄存器计算的频率，并非示波器测量。日志明确区分；若要物理频率证明，需额外使用硬件计数器/仪器。
频率正确但HDMI继续在其他步骤失败时，记录新错误，不能把时钟修复等同于HDMI亮屏通过。

## 文件与回退

硬件仍是原V0.17同次构建的bit/hwh/xclbin/xsa，字节与原交付一致，未重新生成或改名冒充新硬件。manifest.json、SHA256SUMS.txt覆盖本包。
软件版本V0.17.1；修改集中在runtime/pl_clock.py、load_overlay.py、run_pipeline.py，增加采集程序和测试。
回退：停止新程序，按原包说明恢复vart配置并重启，再使用完整原V0.17包。不要在运行中随意恢复PLL或分频寄存器。

官方参考：
- https://github.com/Xilinx/PYNQ/blob/v3.0.1/pynq/overlay.py
- https://github.com/Xilinx/PYNQ/blob/v3.0.1/pynq/ps.py
- https://github.com/Xilinx/PYNQ/blob/v3.0.1/pynq/pl_server/hwh_parser.py
- https://github.com/Xilinx/DPU-PYNQ/blob/v2.5.1/pynq_dpu/dpu.py
