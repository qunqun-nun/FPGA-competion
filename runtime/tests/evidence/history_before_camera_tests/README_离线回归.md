# R1 / R2 / R3 修复后的离线回归记录

状态：OFFLINE_TEST_PASS；40 项测试全部通过，0 failure、0 error、0 expectedFailure、0 skip。

复现命令（从 V0.17_完整系统集成_20261031 根目录运行）：

```powershell
python runtime/tests/run_runtime_audit.py
```

本轮只调整测试、审计脚本及证据文件；没有修改 pl_runtime.py、run_pipeline.py 或 native/memio.c。报告记录了测试前后这些源码的 SHA256 一致性。

- R1：真实超时原因（recovery reason=1 且 timeout counter 非零）抛出显式 TimeoutError；其他取消原因、零计数和 identity 改变保持拒绝，不误判为同一请求超时。模拟主程序推理耗时 1.01 秒后，stderr 明确出现 PL owner timeout，退出码为 1，邮箱没有接受结果，JSONL 不写成功记录。ACK 不会重置 owner 计时。
- R2：DMA ACK 使用 0x7000 W1C；错误检查包含 Err_Irq 0x4000，错误优先于 IOC；只有 idle、没有 IOC 会超时。错误原因位不被当作 W1C。
- R3：画面右下、左、右、上、下完全外部框都提交空目标，bbox/confidence/status 全部清零；没有 border pixel 伪目标。
- 保留内存拒绝、请求四元 identity、RGBX slot/stride/color 转 RGB、shadow 原子提交、空目标清除、stale 拒绝和 doorbell 时取消等检查均通过。
- native/memio.c 原样通过 Windows x86_64 MinGW GCC 8.1 和 AArch64 Linux GCC 11.2 严格编译；本地执行了大于 4 GiB 虚拟地址的指针读写、uint32 值、偏移、复制保护字节和 Region 边界检查。汇编检查确认 x86_64 的 mfence、AArch64 的 dmb ish 在访问/复制前后保留。

**验证范围仅为 Python 离线协议模型、主机分配 RAM 上的 native 执行，以及 AArch64 交叉编译/汇编检查；没有运行真实 PL、RTL 仿真、板端 AArch64 代码、真实 DMA/MMIO 或 cache coherency 测试。这些结果不构成真实 USB→PL→DPU→HDMI 或检测精度验收。**

`runtime_audit.json` / `runtime_audit.log` 为当前结果；`native_build.json`、`aarch64_build.json`、`pointer_test.json` 和汇编文件为 native 证据。`rtl_review_sources.json` 保存只读对照的 V0.16 RTL/BD 文件指纹。

先前 36 pass + 4 expectedFailure 的报告及未应用建议补丁已归档在 `history_before_R1_R2_R3_fixes/`；历史生成脚本改为 `.py.txt`，不会被当作可运行测试。没有再次生成建议补丁。
