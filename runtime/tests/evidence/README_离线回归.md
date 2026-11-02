# Runtime / Camera 离线回归记录

状态：OFFLINE_TEST_PASS；50 项测试全部通过，0 failure、0 error、0 expectedFailure、0 skip。测试时间及完整输出见 runtime_audit.json / runtime_audit.log。

复现命令（从 V0.17_完整系统集成_20261031 根目录运行）：

```powershell
python runtime/tests/run_runtime_audit.py
```

本轮只修改 tests 及其证据文件；没有修改任何生产源码。run_pipeline.py、camera_source.py、pl_runtime.py、native/memio.c、start.sh、hdmi/pynq_hdmi_init.py 测试前后 SHA256 一致。最新生产与测试来源指纹见 source_hashes.json；V0.16 RTL/BD 对照及当前 runtime 来源指纹见 rtl_review_sources.json。

## 本轮新增 10 项 Camera / main 测试

- 连续喂入三帧且消费者未取帧时，后台线程完成读取，next 只返回第三帧；返回数组为独立 copy。
- after 等于当前 sequence 时等待新帧而不重放旧帧；无帧时按传入 timeout 有界超时，timeout=0 立即拒绝。
- 模拟断开后拒绝返回缓存帧；捕获线程异常通知等待的消费者。
- close 唤醒等待 next 的消费者；read 尚未返回时不 release，read 返回并完成 join 后才 release。
- 模拟 read 卡住时 close 的约 1 秒 join 有界返回，不并发 release。测试之后显式解除 fake read 阻塞并 join，避免泄漏测试线程；这不声称真实后端卡死会自动恢复。
- main 摄像头路径传递最新 sequence（0→4→9），使用 camera.next / camera.close，不直接调用底层 capture.read / release。
- main 摄像头断开时退出 1，不写成功 JSONL，正确清理 camera 和 board。
- main 的 --load / --hdmi 缺省均 false，四种参数组合均通过正常 argparse 解析；以 stub 校验 load、Overlay(download=False) 和 HdmiSession init/start/service/close 的调用关系。结果记录始终保持 screen_picture_verified=false，stub 状态不代表真实显示。

start.sh 的默认 --load --hdmi 和 FY_SKIP_HDMI=1 下 --load 路径已只读核对并记录来源哈希；未在本机执行需要 root、PYNQ、设备加载和真实 HDMI 的启动脚本。CLI 四组合测试覆盖其调用参数组合。

## 保留的 PL / native 检查

原 40 项检查继续全部通过：保留内存拒绝、DMA IOC/错误及 W1C、请求 identity、RGBX→RGB、邮箱 shadow 提交、stale 拒绝、1 秒 owner timeout、边界框裁剪、native 指针与 barrier。

模拟主程序推理耗时 1.01 秒后明确报 PL owner timeout，退出 1，邮箱未接受结果，JSONL 不写成功记录。ACK 不会重置 owner 计时。

memio.c 原样通过 Windows x86_64 MinGW GCC 8.1 和 AArch64 Linux GCC 11.2 严格编译。本机分配 RAM 上验证了大于 4 GiB 虚拟地址的指针读写、uint32、偏移、复制保护字节和 Region 边界；汇编确认 x86_64 mfence / AArch64 dmb ish 保留于访问/复制前后。

**验证范围仅为 Python 离线协议模型、可控假摄像头线程、main 硬件 API stub、主机分配 RAM 上的 native 执行，以及 AArch64 交叉编译/汇编检查；没有运行真实 PL、RTL 仿真、UVC 摄像头、板端 AArch64 代码、真实 DMA/MMIO/cache coherency 或 HDMI 输出。这些结果不构成 USB→PL→DPU→HDMI 整链或检测精度验收。**

之前报告已保存在 history_before_camera_tests/；更早 4 项 expectedFailure 及未应用建议补丁保存在 history_before_R1_R2_R3_fixes/。本轮没有生成或应用源码修复补丁。
