# 交付清单字段与角色

manifest 顶层见模板。files 每项是独立文件，不是目录：

```json
{"role":"bit","path":"hardware/system.bit","sha256":"实际64位小写SHA256","build_id":"本次实际构建ID"}
```

bit/hwh/xsa/xclbin 的 build_id 必须与顶层一致；build_record 文件本身也列入 files。它的 artifacts 是角色到 path/sha256 对象映射，须与最终硬件一致。tools/target_part/source_revision/commands_log 必填，commands_log 必须指向已经列入清单的命令日志文件。

verification 每个阶段是 `{ "status":"PASS", "evidence":["validation/实际文件.log"] }`；其他状态必须带 reason。PASS 的证据路径必须在 files 中且其字节受校验，但脚本不解析证据内容以证明实际通过。board_retest 允许 board 未测；accepted 则 board 也须 PASS 且有记录。失败阶段始终阻止发布。

|必需角色|含义|
|---|---|
|bit/hwh/xsa|最终硬件；bit/hwh 同 stem|
|xclbin|pynq_xrt 必需，普通 pynq 可不提供|
|vivado_project/block_design|真实 XPR/BD|
|rtl/ip_metadata/constraints/build_script|源码、封装 component.xml、XDC、实际构建脚本|
|testbench/simulation_log/simulation_result|TB、原始日志、自检结果|
|build_record|同构建来源 JSON|
|synthesis_report/timing_report/drc_report/resource_report|主工程对应报告|
|software_source/software_entry/dependencies|运行源码、入口、依赖|
|start_script/stop_script/diagnostic_script|启动、停止、诊断|
|deployment_guide/rollback_guide|接收者操作与回退|

每种角色是最低数量检查，整个工程的所有其他必要文件也必须列入，源码不止一个时重复相同 role。单个 role 存在不能证明全部源码齐全。bit/hwh/xsa/xclbin/build_record 为唯一角色，不能同时塞旧新版混淆。

features 每个开关必填布尔值。启用 dpu 要 model/model_contract/labels；camera 要 camera_capture/frame_transport；hdmi 要 hdmi_init/display_runtime；device_tree 要 device_tree_source/device_tree_install；native_runtime 要 native_source/native_build。特性中的其他实际资源也应纳入，不能只满足最小角色数量。

原工具/IP/驱动存在不适用时按真实工程说明。此 schema 面向用户要求的完整工程交付，不适合只有 HLS 源或纯开发中局部模块。某阶段尚未执行可先 audit 得到 BLOCKED，不能伪造 PASS 让 pack 放行。
