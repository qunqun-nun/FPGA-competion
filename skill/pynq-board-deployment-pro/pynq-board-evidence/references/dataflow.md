# 数据通路

```text
USB摄像头 / PC视频 / 单张图片
              │
PS采集或解码 → 640×480 GRAY8 → DDR输入缓冲
              │
AXI DMA MM2S → pc_formatter_0 → pl_video_in_0
              │
      pl_axis_video_fork_0
              ├──────────────────────────────┐
              ▼                              ▼
       pl_sad_tracker_0              c_hdmi_display_0
     跟踪并传递像素                  显示双缓存与OSD
              │                              │
   pl_preproc_letterbox_0             hdmi_axis_pack_0
       补边及三通道复制                  1PPC→2PPC
              │                              │
 pl_frame_write_adapter_0          v014_hdmi_axis_fifo
       打包及写命令                       同步流缓冲
              │                              │
      axi_datamover_0                v014_hdmi_tx_ss
              │                              │
         DDR三缓冲区                   v014_vid_phy
              │                              │
   PS按请求取完整帧并量化                 HDMI显示器
              │
   DPU读取输入 → 六路特征写回DDR
              │
 PS：六路CPU末层 → DFL/sigmoid/NMS → 坐标还原
              │
       pl_sys_ctrl结果邮箱
              │
       pl_track_fusion_0
              ├─ 初始化/校正SAD
              ├─ 输出显示框
              └─ 控制重新检测请求
```

## 关键约束

- 摄像头由PS/Linux采集，不直接接入PL像素引脚。
- 检测DDR三缓冲和显示双缓存用途不同；显示可重复最近完整帧，不等待每次DPU推理。
- 请求以frame_id、buffer_id及generation关联。回写结果必须匹配有效所有权，禁止提交过期框。
- 模型输入为640×640，HDMI输出为1280×720；640×480画面居中显示，左右320、上下120补黑。
- DPU通过DDR任务缓冲读写，不是像素流上的直接末级模块；六路中间特征仍需CPU计算后形成框。

## 时钟核对

最终HWH中，外部HDMI FIFO的IS_ACLK_ASYNC=0。FIFO、packer和TX的AXIS侧均使用pl_clk0。TX的video_clk来自PHY，因此外部FIFO应标为同步流缓冲，AXIS与视频时钟关系由匹配HDMI子系统内部处理。

PC视频、单图和USB摄像头具有不同接入程序。结构上支持多种输入不代表每条接入路径都完成相同范围的持续实测。
