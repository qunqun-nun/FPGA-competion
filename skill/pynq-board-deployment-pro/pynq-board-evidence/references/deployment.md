# 运行说明

## 1. 前置条件

运行包应包含匹配的硬件文件、模型、CPU后处理参数与运行脚本。确认PYNQ Python可导入pynq、pynq_dpu、xir、vart、OpenCV及NumPy。禁止使用缺少板级依赖的解释器替代。

以下以已有runtime接口为例。`PROJECT`应指向实际部署目录，不能混用不同版本文件。

```sh
PROJECT=/home/xilinx/app
PY=/usr/local/share/pynq-venv/bin/python3
cd "$PROJECT" || exit 1
RUN=results_$(date +%Y%m%d_%H%M%S)
sudo mkdir "$RUN" && sudo chown "$(id -un):$(id -gn)" "$RUN" || exit 1
```

板端时间可能不准确，应同时记录主机时间、boot_id与文件哈希。

```sh
cat /proc/sys/kernel/random/boot_id
"$PY" runtime/verify_package.py
sudo env XILINX_XRT=/usr "$PY" -c 'import sys;sys.path.insert(0,"runtime");from pl_runtime import check_reserved;check_reserved();print("RESERVED_MEMORY_PASS")'
```

上述检查必须逐条确认退出码。缺少对应项目脚本时，应使用该工程实际验证入口，不能跳过检查。

## 2. 硬件独占

```sh
systemctl is-active fengyan-camera.service
ps -eo pid,args | grep -E 'run_pipeline|collect_pl_clock|jupyter'
sudo systemctl stop fengyan-camera.service
```

服务名称按实际配置调整。仅在确认进程用途后停止相关任务，避免重复访问DPU、HDMI或IIC。停止服务后检查进程确已退出，不通过删除PID文件强制绕过。

## 3. 时钟与HDMI分步检查

```sh
sudo env XILINX_XRT=/usr "$PY" runtime/collect_pl_clock.py --out "$RUN/clock" --load --runner --seconds 10
sudo env XILINX_XRT=/usr "$PY" runtime/collect_hdmi_iic.py --out "$RUN/probe"
sudo env XILINX_XRT=/usr "$PY" runtime/collect_hdmi_iic.py --out "$RUN/init" --initialize
sudo env XILINX_XRT=/usr "$PY" runtime/collect_hdmi_iic.py --out "$RUN/init_again" --initialize
```

执行顺序为加载后时钟检查、只读器件探测、初始化、不重启重复初始化。每一步保存日志和退出码；前一步失败时不得继续配置。

## 4. 单图与摄像头

```sh
sudo env XILINX_XRT=/usr FY_PYTHON="$PY" \
  sh runtime/start.sh --image samples/tank_test.jpg --frames 30 --fps 5
```

单图通过后，再执行摄像头测试。设备名以实际枚举结果为准。

```sh
ls /dev/video*
sudo env XILINX_XRT=/usr FY_PYTHON="$PY" \
  sh runtime/start.sh --camera /dev/video0 --frames 60 --fps 5 \
  > "$RUN/camera.stdout" 2> "$RUN/camera.stderr"
rc=$?
printf '%s\n' "$rc" > "$RUN/camera.exitcode"
if [ "$rc" -ne 0 ]; then
  exit "$rc"
fi
```

持续运行使用`--frames 0`。请求5 FPS仅表示软件限速参数，实际吞吐以测量结果为准。程序正常退出后可能关闭HDMI输出，应在有效运行窗口确认画面。

验收检查：PL完整帧、真实推理、结果提交均有进展；错误和超时符合要求；HDMI保持STREAM_UP；现场图像正常。空预测可表示当前输入未检出目标，不能仅据此判定DPU执行失败。

## 5. 模型替换

1. 核对目标DPU指纹及XModel哈希。
2. 解析输入形状、dtype、fix_point和六路输出名称、形状、量化点。
3. 若输出为中间特征，从同一模型提取CPU末层权重、偏置和量化参数。
4. 在独立部署目录更新模型、CPU参数、清单与版本配置。
5. 完成真实DPU任务、完整摄像头链路及重复启动验证后，切换运行入口。

输入或输出量化点变化时，不得复用旧CPU头。模型兼容验证通过不代表精度通过，精度需固定输入和标注单独评估。

## 6. 自启动及回退

启动入口应显式设置PYNQ解释器和`XILINX_XRT=/usr`，等待摄像头就绪，检查内存保留后运行。设备等待应有超时，硬件失败不应无限重配。

```sh
systemctl cat fengyan-camera.service --no-pager
systemctl list-dependencies --reverse jupyter.service --no-pager
systemctl is-enabled fengyan-camera.service
journalctl -b -u fengyan-camera.service --no-pager -n 30
```

检查默认Overlay加载、Jupyter间接依赖及PL状态清理服务是否与应用冲突。停用前记录原状态，不将特定服务禁用策略推广到所有PYNQ平台。

启动配置修改后依次验证正常重启、断电冷启动和独立供电运行。正常关机使用`sudo poweroff`，确认Power down后再断电。

回退时先停止硬件任务，恢复原服务入口和VART配置，再按对应版本重新启动或加载硬件。软件配置恢复不等于PL状态恢复。
