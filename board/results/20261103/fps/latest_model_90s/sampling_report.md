# 新模型现场连续采样（2026-11-03，北京时间）

采样方式：不停止或修改当前程序，只读取持续追加的state/results.jsonl。窗口90.00225151秒，59条完整记录，解析错误0；板端与电脑 evidence.json SHA256一致。使用板端单调时钟记录读取完成时刻，存在轮询与日志写入延迟，不是硬件逐帧时间戳。正式阶段计时探针未启用，未预热分段，本轮为现场观测样本。

- 检测结果输出观测速率：59/90.00225151 = 0.65554 FPS。跟踪期间DPU请求可能减少，此数值不是检测计算能力上限。
- 6条检测结果非空，类别ID均0，置信度约0.311—0.870。没有真值标注，不据此计算准确率或定位成功率。
- 原日志seconds平均352.776 ms，P95 364.322 ms（N=59，最近秩法）。该字段为循环部分耗时，包含取帧/处理/提交等，不是DPU独立时间，不是显示延迟，也不能直接取倒数当整机FPS。
- 首条到末条记录之间：PL completed +123，dropped +65，stale_results/aborted/profiler_timeouts均+0；末条error=0。存在历史累计丢弃，不称全程零丢帧。
- 59条记录的HDMI阶段可在原始JSON核对，末条STREAM_UP，不代表已目视验收。

## 跟踪帧率：未测得，不能填0或30 FPS

已保存跟踪状态原值和解码字段：状态257有3条、1有3条、259有7条、0有46条，其中tracker_active位为1的记录共10条。这些是在检测结果输出时读取的状态，不能作为逐帧有效跟踪次数，未采样到PL_TRACK状态也不能证明期间没有跟踪。

检查V0.17接口增量和交付pl_sys_ctrl AXI实现：0xF8只提供融合状态、tracker_active、processing_busy、LOST；0xFC是最近SAD值。当前CPU可读接口没有逐帧track_valid累计数或对应跟踪frame_id。不能将completed增量、tracker_active样本数或DPU间隔当作精确跟踪帧率。

要准确测量，应在匹配硬件中暴露每个有效SAD位置结果的单调累计计数及帧号（含窗口起止和时钟口径），然后以同一单调时间窗口的有效计数增量/时长统计。硬件内部tracker_frame_id和box_frame_id虽存在，但当前AXI映射未导出；本轮未修改或重构硬件。

## 证据

- evidence.json：原始回传包，含全部结果与观测时戳。
- observed_results.jsonl：逐条记录。
- results.csv：便于查看的表，含框、置信度、跟踪状态。
- metrics.json：统计及未测原因。
- serial_full.log / serial_commands.log：串口证据与实际命令完成码。

模型身份：此前同次运行预检核对SHA256 765a836d815ef8c9ebf6bcfb1811303768ba7d518cee3679b2c59a1eee989922，当前运行目录/home/xilinx/fengyan_v0173_grouped_20261103，boot_id 391a3e07-3eb0-4ec1-ae4c-a1f769972db3。测试结束未停止当前摄像头服务。

## 应用户要求补充粗估

5个DPU结果长间隔合计43.195秒，PL完成帧号推进69帧，约1.60 FPS；若扣除每段末尾一次DPU对应帧，剩余中间帧约1.48 FPS。可将当前跟踪阶段处理速率粗估为1.5—1.6 FPS（约1.6）。该推断依赖跟踪门控导致DPU长间隔的假设，包含初始化/失效可能性，不是逐帧有效SAD跟踪FPS，不可填入正式实测跟踪帧率列。详见tracking_estimate.json。
