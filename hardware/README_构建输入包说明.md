# 候选联调包：V0.16 构建输入整理副本

**交付状态：候选联调包。最终 HDMI 软件仍有真实阻塞，未通过全链实板验收。** 本文所述工程打开、依赖检查和 XSA 导出只证明相应文件操作的结果，不能代替 HDMI 软件联调或整机实板验收。

**后续授权变更：** 静态主工程副本已用于 V017 M12 时钟芯片使能修复，详情和新平台入口见 [V017 平台修复与增量参考说明](V017_平台修复与增量参考说明.md)。下文 V016 文件数及 `final_validation.json` 是首次输入整理的历史结果；V017 新结果单独记录于 `v017_platform_validation.json`、`v017_platform_paths.json` 和 `index.sha256`。旧最终 `prj.xpr`、旧 XSA 仍保持原样；旧最终结果没有新增 M12 修复，不能作为 V017 新 bit 交付。

本目录来源于 `V0.16_复位修复_20261031`。仅整理工程副本、修复副本路径、检查依赖并尝试导出同次整机构建 XSA；没有运行综合、实现、IP 升级或硬件重建。未修改 V016 原件，也未操作 runtime 或其他 agent 文件。目录名称沿用用户指定的 20261031；整理跨至 2026-11-01。

本次最终结果：收集 3070 个源/依赖文件，共 781,496,199 字节（约 745.3 MiB）；排除 10738 个文件、约 2.61 GiB。包内硬链接去重节省约 76.9 MiB。696 项静态依赖路径检查无缺失，Vivado 动态 source paths 检查缺失数为 0。已成功导出最终 XSA（4,897,793 字节），其内嵌 bit 与最终工程 bit 的 SHA256 完全一致，顶层 HWH 也一致。已核对全部 3070 个收集来源的原件哈希，未发现原件变化。具体哈希与告警详见清单及日志。

## 两个真实工程

| 用途 | 相对本目录的工程路径 |
| --- | --- |
| 最终完整链接工程，含 DPU | `build/link/_x/link/vivado/vpl/prj/prj.xpr` |
| 链接前静态平台主工程 | `v014_main_project_20261024/project/fengyan_pl.xpr` |

两者均保留原有 `.xpr`、`.srcs` 内的 `design_1.bd`、XDC、RTL 和对应 `.gen` 输出产品。没有用 `create_project` 重建工程。最终工程额外保留同次 `impl_1/design_1_wrapper_routed.dcp`、`.bit` 和必要运行元数据，以便加载既有实现结果并导出。

最终工程的 RTL 已导入自己的 `.srcs`，与静态平台工程直接引用的 `v014_unified_work_20261024/sources` 不能混淆。`ImportPath` 在副本中指向实际导入的 File，避免为历史导入出处再复制一整套大工程；原始引用仍可从原件及 `path_patches.json` 追溯。

## 输入与依赖

- 链接输入：`config/link.cfg`、`build/dpu_kernel/dpu_b4096.xo`、`platform/generated/fengyan_v015_zcu104/export/fengyan_v015_zcu104/fengyan_v015_zcu104.xpfm`。
- XPFM 所需 XSA、SPFM、BIF、QEMU 配置按原相对目录保留。其 `hw/fengyan_v015_extensible.xsa` 是链接前可扩展平台，不能当作最终含 DPU 的整机 XSA。
- XO 原样保留；对应 `kernel.xml` 位于 `build/link/_x/link/int/xo/DPUCZDX8G/DPUCZDX8G/kernel.xml`，另保留 TRD 原始 kernel XML、DPU 配置、加密 HDL、打包脚本与已打包 IP。
- 自研/官方 IP 仓库、最终链接提取的 `.local/hw_platform/iprepo`、DPU RTLKernel 仓库与 board 仓库均保留。实现钩子的 `source` 依赖包含 `ipirun.tcl` 及 `.local/*.tcl`；必要的 `hw_platform` 元数据也保留。
- `dependency_paths.csv` 给出每个 XPR File、IP/board 仓库、IP-XACT 文件、BD XCI、XPFM 以及直接 Tcl source 引用的解析路径和存在性。远程 IP 文档 URL 不作为本地源文件缺失处理。
- `collection_manifest.json` 记录每个收集文件的 V016 相对来源与原始 SHA256；`source_copy_manifest.csv` 对照原件/副本哈希并标识修改；`package_sha256.csv` 为交付文件校验清单。

排除失败链接目录、`.cache` / `logs.ipcache` /独立 `ipcache`、`.Xil`、仿真缓存、重复交付 ZIP、旧版/备份 XO/XSA、历史验收工程、模型与板端软件、许可密钥。没有复制 Vivado/Vitis 安装目录。XSA/XO 自带内容原样保留，不拆改输入平台归档内的输出产品；`.gen` 是当前真实工程打开时会登记的 IP 输出文件，不能当作无用缓存全部删除。最终 run 的 DCP、bit 与少量元数据是恢复既有实现所需的例外保留。

`excluded_inventory.csv` 记录未纳入包的源文件与排除原因。为保留真实引用路径，大于等于 1 MiB 且完全同哈希的包内文件使用内部硬链接减少物理重复，见 `internal_hardlinks.json`；没有任何硬链接指向 V016 原件。若需单独修改其中某份大文件，请先复制替换该文件以断开内部硬链接；普通跨磁盘复制或归档解压会恢复为独立文件。

## 环境与路径

使用 Vivado **2022.2** / Vitis **2022.2**、ZCU104 对应器件 `xczu7ev-ffvc1156-2-e` 和 board 支持。工具安装默认 `F:/Xilinx`。HDMI IP 授权必须在目标机器自行提供，包内没有许可密钥。

XPR 中 R: 项目位置改为工程宏路径，IPOutputRepo 改为副本位置；移除作为输入仓库的独立 IP cache。副本 Tcl 的 R:/V: 路径已调整，实现钩子的 source 改为相对脚本路径。迁移目录或改变 Vitis 安装位置后先执行：

```powershell
Set-Location 'C:\Users\Admin\Desktop\大创\V0.17_完整系统集成_20261031\rebuild'
python .\relocate.py --vitis-ip 'F:/Xilinx/Vitis/2022.2/data/ip'
python .\audit_dependencies.py
```

Windows 中文长路径下请优先用下列入口。入口临时将本目录映射为 W:，结束后移除自己的映射；W: 被占用会报错，可加 `-Drive Q` 指定其他空闲盘符，不覆盖既有映射。直接使用资源管理器复制时应使用支持长路径的工具。

本机原有 R:/subst 可继续用于读取原件，但本文入口始终映射到整理副本，且拒绝覆盖已有盘符。不要将重建命令指向原件所在 R:；V0.16 原件始终只读。

## 打开与只读检查

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\run_vivado.ps1 -Action verify
powershell -NoProfile -ExecutionPolicy Bypass -File .\run_vivado.ps1 -Action open-final
powershell -NoProfile -ExecutionPolicy Bypass -File .\run_vivado.ps1 -Action open-static
```

`verify` 和两个 GUI 入口均 `open_project -read_only`，不保存或修改硬件。可通过 `-Vivado '其他位置\Vivado\2022.2\bin\vivado.bat'` 指定工具。GUI 关闭后释放临时映射。

## 导出同次最终 XSA

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\run_vivado.ps1 -Action export
```

该命令只读打开副本最终 `prj.xpr`，`open_run impl_1` 加载保留的既有实现，再执行：

```tcl
write_hw_platform -fixed -include_bit -force -file <rebuild>/fengyan_v016_final_same_build.xsa
```

没有调用 `launch_runs` 或 `write_bitstream`。第一次仅打开工程后导出因未打开 implemented design 失败，日志保存在 `logs/export_attempt1_failed.log`；后续导出结果见 `logs/export.log`。以 `final_validation.json` 中的 XSA ZIP CRC、内嵌 bit 与原最终 bit 的 SHA256 对比、HWH 与最终工程 HWH 的对比作为实际导出证据。文件存在本身不等于验证通过。

## 后续确需重建时才运行

以下命令会更改**副本**并执行硬件构建；本次整理没有运行。建议先复制本目录留档。它们打开既有工程，不创建新的源工程，也不自动升级 IP：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\run_vivado.ps1 -Action rebuild-static
powershell -NoProfile -ExecutionPolicy Bypass -File .\run_vivado.ps1 -Action rebuild-final
```

对应 `rebuild_existing.tcl` 会生成输出产品、reset/launch 既有 synth_1/impl_1，再导出 `rebuilt_static.xsa` 或 `rebuilt_final.xsa`。如目标机器报告 IP 锁定、版本/许可问题，应先检查 `report_ip_status`，不能将打开成功视为重建成功。

也可从收集的 XPFM/XO/配置重新执行完整 Vitis 链接：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\relink_inputs.ps1
```

其输出独立放在 `rebuild_outputs/link`，由 v++ 产生中间构建工程；目录已有时拒绝覆盖。不会替换保存的原链接结果。本次没有执行这个命令。原 `scripts` / TRD /统一工作区脚本作为历史和依赖保留，其中可能有创建工程、打包交付或硬编码盘符逻辑；不要将它们替代本文入口直接批量运行。`collect_inputs.py` 是初始收集过程留档，不是最终完整包的重新生成入口。

## 实测边界与 HDMI evaluation

本机 Vivado 2022.2 已只读打开上述两个副本；路径验证与导出结果分别见 `dependency_validation.json`、`logs/vivado_source_paths.tsv`、`logs/export.log` 和 `final_validation.json`。只读打开会出现 BD/IP 锁定告警；静态工程未保留历史 runs 的日志/中间结果，因此会提示部分 GeneratedRun 文件缺失。这些告警必须与“源文件缺失”区分记录。没有做异机打开、异机重建、时序重签核或上板验证。

原最终实现日志明确指出 `design_1_v014_hdmi_tx_ss_0` 和 `bd_1bda_v_hdmi_tx_0` 使用 **hardware_evaluation**，见 `logs/hdmi_evaluation_original_excerpt.txt`。这类核心经过一定运行时间会停止工作/HDMI 停流，现有 bit/XSA 仍带该限制，导出 XSA 不会解除限制；不要将评估构建设为长期连续运行或生产可用。未根据日志推断具体超时秒数。换正式授权后，需要在另外的构建副本中 reset/re-generate 对应 IP 输出产品并重新实现/生成 bit，不能只替换许可证文件后继续交付旧 bit。

官方依据：[Vivado 2022.2 write_hw_platform](https://docs.amd.com/r/2022.2-English/ug835-vivado-tcl-commands/write_hw_platform)、[AMD HDMI TX PG235，evaluation 超时行为](https://www.amd.com/content/dam/xilinx/support/documents/ip_documentation/v_hdmi_tx_ss/v3_0/pg235-v-hdmi-tx-ss.pdf)。
