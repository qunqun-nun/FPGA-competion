# 六输出 YOLOv8 推理与后处理模块（交接主代理）

只在本 inference 目录新增/修改文件。原 V0.16 XModel、旧 CPU 修复包和丙交付包均只读。本目录不下载 bitstream、不访问摄像头、不操作 PL 寄存器或 HDMI；主程序在硬件加载、指纹匹配、帧同步完成后调用下列接口。

## 主代理接入接口

从 runtime 目录可使用 `from inference import Detector, ImageTransform`。

```python
from inference import Detector
# model_path 是板端原始 six_outputs.xmodel 的路径，须与提取权重哈希一致。
detector = Detector(model_path='/home/xilinx/models/tank_yolov8n_relu_latest_six_outputs.xmodel')
boxes = detector.detect(gray480)  # np.uint8, shape=(480,640)
# 返回列表，每项：
# {'bbox': [left, top, width, height], 'confidence': float, 'class_id': 0}
# bbox 为源 640x480 图像的浮点像素坐标，左上角 xywh，绝不是中心点 xywh。
```

空帧返回 `[]`；执行失败、名称/shape/fix_point 不符会抛异常，不会伪装为空检测。类别只支持此模型的单类别 class_id=0。置信度是分类 sigmoid，没有额外 objectness。

USB→PL→DDR→DPU 路径优先调用：

```python
# PL 已生成640x640 RGB888（原640x480上下各填80行114）：
boxes = detector.detect_pl_rgb888(rgb640)  # uint8 HWC，不再次letterbox
# 或CPU可读的packed R,G,B字节缓冲区，支持每行末尾padding：
boxes = detector.detect_pl_ddr(ddr_buffer, stride_bytes=1920)
# 若上游已经做了量化，直接传INT8 NHWC，不再归一化/量化：
boxes = detector.detect_quantized(q)  # int8 shape=(1,640,640,3)
```

`detect_pl_ddr`读取的是CPU可见的像素字节，非物理地址。调用者须等待帧完成、锁定当前帧并执行所需DMA cache invalidate/sync。应确认DDR内真实字节顺序确为R,G,B；AXI TDATA[23:0]打包的字在小端CPU上可能呈B,G,R，需要调用者按实际写DDR逻辑整理。当前灰度复制三通道时色序不影响像素，但彩色输入仍须遵守RGB约定。

默认逆变换是 `(x, y-80)` 并裁剪到640x480。其他源几何应显式传 `ImageTransform(width, height, scale, pad_x, pad_y)` 到 `detect_pl_rgb888`、`detect_pl_ddr` 或 `detect_quantized`。本模块不负责HDMI画面缩放/窗口偏移；主程序按显示布局转换返回框后提交OSD。OSD若需要整数，可left/top向下取整、right/bottom向上取整，再裁剪到源图范围。

## 模型与数值约定

原模型 SHA256：`9f6302986694ead804ae7542d7c39fbbb49cef5e9a28fa8419dc7e060a52568b`。

`model_inspection.json` 是实际XModel protobuf只读解析结果：263个算子、1个DPU子图、6个CPU子图；DPU输入 `[1,640,640,3]`，有符号8位，fix_point=6，DPU_ROUND。六CPU子图均为常量+fix+fix2float+1×1卷积，输出cv2的64通道和cv3的1通道，空间尺寸80/40/20。由输出结构与官方YOLOv8定义确定reg_max=16、stride=8/16/32、单类别；导出图不含DFL/sigmoid/NMS。

处理链：

1. GRAY8 640x480 → 通道复制，上下各填80行114；或直接接受PL已填充RGB888。
2. 原始0..255像素只在一个位置转换为 `floor(pixel/255*64+0.5)`，INT8饱和。拒绝预先归一化的float输入。已量化入口完全跳过此步。
3. 仅创建DPU Runner，不使用自动遍历CPU子图的GraphRunner。验证模型哈希、输入输出INT8、NHWC、精确名称/尺寸/fix_point，等待成功后取回原始INT8特征。
4. 原样集成CPU修复包的 `CpuHeads`，整数累加和幂次缩放只执行一次，输出FLOAT32 logits。DPU特征不要预先反量化。
5. cv2按四组连续16 bins执行稳定softmax及期望，网格中心偏移0.5，乘stride得到像素xyxy；cv3执行稳定sigmoid。
6. 三尺度合并，单类别IoU NMS（默认confidence=.25、IoU=.45、max_detections=100），再去padding/除scale/裁剪/转左上角xywh。退化框丢弃。框不除255，不除640，不重复归一化。

可注入 `Detector(backend=DpuRunner.from_runner(existing_dpu_only_runner))`，但调用者必须保证已有Runner来自上述同哈希模型；该注入入口仍检查tensor元数据，无法从Runner反查模型文件哈希。执行异步任务只允许一个Runner任务同时进行，兼容整数及(job_id,status)入队返回值和两种wait绑定。

## 离线验证与回放

运行环境已实测Python 3.8.15、NumPy 1.24.4；推理/后处理不需要OpenCV、PyTorch、protobuf。真实DPU构造额外需要板端xir/vart和已匹配硬件。静态inspect工具单独使用Python3.12和已有protobuf依赖。

```powershell
cd C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/runtime/inference
python run_offline_tests.py
python replay_features.py --features dpu_features.npz
```

回放NPZ的key必须为 `cpu_heads/heads.json` 中的精确DPU tensor名，数组必须为原始NHWC INT8。可在调用端对 `DpuRunner.run(q)` 的结果使用 `np.savez('dpu_features.npz', **features)` 留样。回放默认640x480源几何，也支持命令行 `--source-width/--source-height/--scale/--pad-x/--pad-y`。

测试记录见 `offline_test_report.json`、`offline_tests.log` 和 `cpu_heads/offline_test_report.json`。覆盖输入256个灰度值、letterbox、DDR行步长/RGB次序、三尺度DFL、uniform DFL、sigmoid极值、跨尺度NMS、坐标还原/裁剪、错误输入、模拟Runner乱序输出/错误状态/API变体和真实六CPU权重的合成链路。12,675个量化常量逐一独立标量核对，六CPU head用零/最小/最大/随机INT8输入与独立float64卷积对照。

**验证边界：未在板端执行DPU，未验证USB/PL/DDR/HDMI整链，未与官方CPU Runner或原训练框架对拍真实图像，未测FPS，未做检测精度验收。离线通过不代表检测精度通过。**

## 来源与复用记录

用户给定的 `Desktop/dachuang/DELIVERY_TO_B_20261011` 不存在。实际丙交付在 `Desktop/delivery_to_b_20261011/delivery_to_b_20261011/DPU_NMS`，dachuang的v014 third_party和_codex_tmp也有副本。检查board_single_infer.py、board_raw_infer.py、pc_preprocess.py：已有脚本只做到原始输出（脚本说明明确尚未解码），pc_preprocess含letterbox、逆坐标、NMS，未找到完整六head/DFL解码。故保留其640/114/80 padding及坐标/NMS思路，按当前模型补齐独立NumPy后端。交付包meta.json指向旧finetuned_100_fixed.xmodel，未把该旧模型的runner参数套用到当前模型。

`cpu_heads/run_cpu_heads.py`、heads.json、constants.npz从V0.17板端软件修复包复制；test_cpu_heads.py仅增加package导入兼容。核心CPU计算实现未变。来源原件SHA与本目录文件SHA见 `provenance.json` / `SHA256SUMS.txt`。

官方primary资料（已查阅，不要求离线运行时联网）：

- AMD VART execute_async，返回(jobid,status)：https://xilinx.github.io/Vitis-AI/3.5/html/doxygen/api/python/execute__async_8py.html
- AMD VART wait，0成功及tuple形式：https://xilinx.github.io/Vitis-AI/3.5/html/doxygen/api/python/wait_8py.html
- AMD VART DPU Runner调用流程：https://docs.amd.com/r/1.4-English/ug1414-vitis-ai/Using-Vitis-AI-Runtime-APIs
- Ultralytics YOLOv8 Detect，cv2/cv3、DFL、sigmoid：https://github.com/ultralytics/ultralytics/blob/v8.3.0/ultralytics/nn/modules/head.py
- Ultralytics DFL softmax及bins期望：https://github.com/ultralytics/ultralytics/blob/v8.3.0/ultralytics/nn/modules/block.py
- Ultralytics make_anchors(.5)、dist2bbox：https://github.com/ultralytics/ultralytics/blob/v8.3.0/ultralytics/utils/tal.py
- AMD XModel序列化定义：https://github.com/Xilinx/Vitis-AI/blob/v2.5/src/Vitis-AI-Runtime/VART/xir/src/xir/proto/graph_proto_v2.proto
