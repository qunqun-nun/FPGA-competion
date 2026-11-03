# 效果证据与来源

|文件|内容|性质与边界|
|---|---|---|
|[latest_case.json](latest_case.json)|本次训练、量化、编译摘要及历史故障来源|摘要；创建时与本地原始结果核对|
|[fp32_int8_results.json](fp32_int8_results.json)|本次90张测试图片的FP32/INT8结果|从原量化输出复制，非板端mAP|
|[compiled_verification.json](compiled_verification.json)|当前图输出节点、DPU指纹、MD5和SHA-256|从原编译检查输出复制，板端状态为NOT_RUN|
|[dataset_audit.json](dataset_audit.json)|训练/验证/测试数量及来源组映射|从原训练准备输出复制；路径是历史记录|
|[current_dataset_manifest.csv](current_dataset_manifest.csv)|602条预处理PNG的相对路径、集合、来源组|由实际已训练数据生成；未随包分发图片|
|[current_dataset_audit_result.json](current_dataset_audit_result.json)|通用审计脚本对当前602张实际图片的结果|PASS；只检查声明ID和文件字节，未检查感知相似度|
|[current_delivery_hash_check.json](current_delivery_hash_check.json)|通用脚本对本次交付13项文件的SHA-256复核|全部PASS；文件身份，不是驱动/硬件兼容验证|

历史复位案例来自用户在本次协作中粘贴的《V0.15 上板进度与问题记录》，日期2026-10-31。没有把该用户记录伪装成当前新增实测；包内不包含其原始波形、网表或完整板端日志。若作为强证据提交，应另附构建方原始记录。

`../validation_results.json` 是本次新增脚本的PC测试记录；覆盖有效清单、篡改、缺文件、目录逃逸、空清单、分组通过、来源重叠、跨集合完全重复、真实精度门槛通过/失败、NaN拒绝，以及环境导入正常/缺模块。

读取结果时区分：实际执行结果、历史用户报告、可复用方法。没有真实硬件证据的项目保持NOT_RUN/UNKNOWN。

