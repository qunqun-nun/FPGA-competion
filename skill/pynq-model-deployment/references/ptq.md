# PTQ实施与数值契约

以下是API骨架，需在当前工具容器验证；load_model、calibration_loader、evaluate不是已实现的通用函数，必须按任务实现。优先读取当前安装版本示例，不能将此骨架当成可直接运行的完整应用。

```python
model = load_model().cpu().eval()  # 返回nn.Module，不能是(model, info)
dummy = next(iter(calibration_loader))  # 黄金预处理后的真实输入
q = torch_quantizer('calib', model, input_args=(dummy,),
                    device=torch.device('cpu'), output_dir=output_dir)
q.quant_model.eval()
with torch.no_grad():
    for images in calibration_loader:
        q.quant_model(images)
q.export_quant_config()
del q
# 重新加载相同权重/结构，使用同一个校准输出目录
q = torch_quantizer('test', load_model().cpu().eval(),
                    input_args=(dummy,), device=torch.device('cpu'),
                    output_dir=output_dir)
q.quant_model.eval()
with torch.no_grad():
    q.quant_model(dummy)
# 在此以正确的CPU/DPU输出边界执行同集精度评估
q.export_xmodel(output_dir=export_dir)
```

需要配置CLE/校准算法时，用当前版本支持的quant_config_file；calib与test参数保持一致。不要将生成的quant_info.json误当用户配置。不同版本export_xmodel参数及支持的算子可能变化。

## 最小数值对照

|边界|必须记录|典型错误|
|原图→预处理|灰度/RGB/BGR、插值、尺寸、补边、原始范围|训练letterbox，部署直接拉伸|
|预处理→浮点输入|NCHW/NHWC、dtype、归一化次数|已经/255又除一次|
|浮点输入→硬件输入|张量量化属性、舍入、饱和、数据类型|原像素直接astype(int8)溢出|
|量化仿真输出|是否已反量化、输出语义|NNDCT输出再乘反量化因子|
|硬件整数输出|每个张量的量化参数|所有输出共用一个fix_point|
|特征→预测|CPU末层、DFL/sigmoid、anchors/stride、NMS|把中间特征当框；重复sigmoid|

对于**确认为有符号定点、scale=2^fix_point且零点为0**的张量，可按q=clip(round(x*2^fix_point))、x≈q*2^-fix_point理解；舍入和饱和须对齐实际实现。其他量化格式不能直接套用此式。

校准数量和算法需实验决定；训练样本代表性比重复凑数重要。灰度转三通道、特定补边值都是案例参数。若修改输入或模型结构，旧校准参数失效。Vitis AI 3.5模型与Vitis AI 2.5运行栈不能只看B4096相同就判兼容，要核实图算子、ISA指纹及实际运行。
