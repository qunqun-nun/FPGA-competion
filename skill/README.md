# 开发与部署技能包

本目录维护三个独立技能，分别覆盖 FPGA IP 开发验证、PYNQ 模型部署，以及板端部署与故障诊断。各技能保留自己的入口、参考资料、模板、脚本和验证记录，不合并为一个工作流。

## 技能索引

| 技能 | 适用场景 | 入口 |
| --- | --- | --- |
| FPGA IP 验证与完整交付 | 开发或修改 RTL/IP，编写自检 Testbench、协议断言与回归测试；检查硬件软件配套材料并打包交付 | [使用说明](fpga-ip-verify-deliver/README.md) · [SKILL.md](fpga-ip-verify-deliver/SKILL.md) |
| PYNQ 模型部署（含 Vitis AI 分支） | 核对 PYNQ 环境、模型与硬件契约、交付身份；按需开展 PTQ、精度对比、目标编译和环境恢复 | [使用说明](pynq-model-deployment/README.md) · [SKILL.md](pynq-model-deployment/SKILL.md) |
| PYNQ 部署与故障诊断专业版 | 组织上板验收，排查内存、时钟、加载、I²C、显示及运行环境问题，整理版本和性能证据 | [使用说明](pynq-board-deployment-pro/README.md) · [SKILL.md](pynq-board-deployment-pro/pynq-board-evidence/SKILL.md) |

## 目录结构

```text
skill/
├── README.md
├── import_manifest.json
├── fpga-ip-verify-deliver/
│   ├── SKILL.md
│   ├── references/
│   ├── assets/
│   ├── scripts/
│   ├── evals/
│   └── validation/
├── pynq-model-deployment/
│   ├── SKILL.md
│   ├── references/
│   ├── assets/
│   └── scripts/
└── pynq-board-deployment-pro/
    ├── README.md
    ├── validation/
    └── pynq-board-evidence/
        ├── SKILL.md
        ├── references/
        ├── assets/
        └── scripts/
```

专业版保留原包的两层结构：外层为包级说明和验证资料，内层 `pynq-board-evidence/` 是实际技能目录。其余两个技能的入口直接位于各自根目录。每个技能中的 `SHA256SUMS.json` 和验证记录均保留原有作用域。

## 使用方式

1. 根据任务选择一个技能，先阅读对应 README 和 SKILL.md。
2. 向支持技能的 Agent 提供整个技能目录，而不是单独复制入口文件；专业版应提供内层 `pynq-board-evidence/`，并保留外层验证资料用于查阅。
3. 按入口指引填写当前工程的接口、板卡、环境与文件配置，只加载当前任务涉及的参考资料。
4. 执行对应检查或开发流程，保存命令、配置、输出和失败证据。不要把示例地址、频率、模型参数或历史结果作为当前工程的默认值。

这些技能是开发与验证方法及工具，不包含可直接烧录的硬件设计、完整运行环境或许可证。具体软件依赖和终端位置以各技能说明为准。

## 离线检查

以下命令从仓库根目录执行，使用 Python 3.8 及以上版本。Windows 的 Python 命令按实际环境设置。

FPGA 交付检查工具测试：

```sh
python -B skill/fpga-ip-verify-deliver/scripts/test_release_check.py
```

模型量化指标案例检查：

```sh
python -B skill/pynq-model-deployment/scripts/compare_map.py --input skill/pynq-model-deployment/references/case.json --max-drop-pp 3
```

专业版证据工具测试：

```sh
python -B -m unittest discover -s skill/pynq-board-deployment-pro/pynq-board-evidence/scripts -p "test_*.py" -v
```

第一、三项检查工具的正常和失败路径；第二项比较随包案例中的既有精度指标，不运行模型，也不计算新的板端 mAP。环境探测及上板操作应在目标板卡的实际应用环境执行。

## 验证与维护约定

- 分别记录脚本自测、RTL 仿真、硬件构建和实板验收，前一层通过不能替代后一层。
- 引用官方文档和开源实现时记录适用版本、采用方法和验证依据。
- 硬件、软件、模型及初始化依赖按当前工程版本配套；文件哈希只证明字节身份。
- 修改单个技能时同步更新该技能的说明、测试和清单，保持其他技能独立。历史验证记录不自动成为修改后版本的验证结果。
- 当前目录仅收录本次选定的三个版本。导入来源、原始 ZIP 哈希及逐文件记录见 [import_manifest.json](import_manifest.json)。
