# 通用PYNQ：交付身份与版本绑定

## 适用范围

任意PYNQ Overlay及配套应用的交付核对，换板卡或题目仍可用。文件可以是bit、HWH、应用脚本、测试输入或其他必要产物。脚本不假定固定名称、后缀、型号或DPU存在。

## 使用方法

在**PC PowerShell或板卡Linux终端**运行；`delivery`换成自己的交付目录：

```bash
python3 skill/pynq-artifact-audit/scripts/verify_manifest.py --root delivery --manifest delivery/SHA256SUMS.json
```

Windows也可将 `python3` 改为已安装的 `python`。清单采用文件相对路径到SHA-256的JSON映射，详见 `assets/SHA256SUMS.example.json`。示例全零哈希故意不可通过，必须使用发布者提供的实际哈希，不要为了通过而改清单。

在构建方交付时填写 `assets/runtime_binding.template.md`。文件清单检查和匹配关系审查是两个独立步骤：有bit/hwh并不自动要求有xclbin；走XRT内核路线时才核实其相应输入。

## 来源、效果与失效条件

- 来源：旧模型和新模型同名混淆；旧Overlay的xclbin被考虑改名复用；仅有固定XSA时误以为可直接得到匹配运行文件；bit文件头不同但载荷相同导致整体哈希误判。
- 已验证效果：本轮真实交付13项文件及ZIP内容均通过SHA-256复核。旧包检查识别出V0.14缺少匹配xclbin且未假造文件。证据只支持当时版本，不能把V0.14缺项写成V0.15仍缺项。
- 失效条件：无可信原始清单、清单不完整、来源混用；哈希只证明字节身份，不能证明硬件兼容或没有遗漏文件。bit整文件哈希和去文件头后的载荷比较必须分开报告。
- 脚本不打开或解析硬件二进制，不验证签名、不校验bit/xclbin内部匹配，也不替代综合、时序或板端测试。

