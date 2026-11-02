# FengYan ZCU104 Infrared Video System

FengYan is a ZCU104/PYNQ-based infrared video processing prototype. The current open-source snapshot combines the latest board-side software fixes from **V0.17.3** with the latest complete hardware baseline from **V0.17**.

## Current Status

- Software version: V0.17.3
- Hardware version: V0.17
- Target board: Xilinx ZCU104
- Runtime target: PYNQ 3.0.1 / Vitis 2022.2 environment
- Status: offline tests passed; HDMI board retest is still pending

V0.17.3 is a software repair package. It keeps the V0.17 bitstream/HWH/XCLBIN/XSA artifacts and adds board-side fixes for FCLK0 adaptation, HDMI TX address handling, IDT clock validation, DP159 validation, EDID checks, and PIO status collection.

## Repository Layout

```text
.
├── hardware/          # RTL, custom IP, constraints, rebuild scripts, current V0.17 artifacts
├── runtime/           # Latest V0.17.3 board-side Python/runtime code
├── models/            # Labels and current xmodel
├── samples/           # Sample image and labels for offline smoke tests
├── docs/              # Interface docs, retest handoff, validation reports, source evidence
├── tools/             # Reserved for future repo utilities
├── deployment.json    # V0.17.3 package metadata
├── release_manifest_v0173.json
└── SHA256SUMS_v0173.txt
```

## Quick Start on Board

Copy the repository to the board, then from the repository root:

```bash
cd runtime
python3 verify_package.py ..
python3 diagnose.py
./start.sh
```

For the full V0.17.3 board retest sequence, read:

- `docs/BOARD_BRINGUP_V0173.md`
- `docs/BOARD_RETEST_HANDOFF.md`
- `docs/reports/V0.17.3_修复与验证报告.md`

## Hardware Rebuild Notes

The hardware source snapshot is under `hardware/`:

- `hardware/rtl/`: custom RTL and display pipeline sources
- `hardware/ip_repo/`: custom Vivado IP packages
- `hardware/constraints/`: board and pipeline constraints
- `hardware/scripts/`: Vivado/Vitis helper scripts
- `hardware/artifacts/`: current V0.17 bit/hwh/xclbin/xsa deployment artifacts

The original V0.17 rebuild notes are kept in `hardware/README_构建输入包说明.md` and `hardware/V017_平台修复与增量参考说明.md`.

## Validation Boundary

This snapshot preserves the V0.17.3 validation boundary from the source package:

- 94 offline/runtime/HDMI behavior tests were reported passing.
- The package replays existing board JSONL evidence for HDMI validation logic.
- The repository does **not** claim fresh board access, HPD/EDID live read, PLL lock, video output, detection boxes, camera input, or cold boot have passed after V0.17.3.
- The default `image.ub` reserved-memory issue is not solved by this software-only repair.

## Third-Party Dependencies

Large third-party reference trees and generated Vivado/Vitis output are intentionally not included as first-class repository source. See `THIRD_PARTY_NOTICES.md` for the omitted reference trees and expected external toolchain dependencies.

## Development Checks

Portable checks for this GitHub-ready tree:

```bash
python -m compileall runtime
python runtime/device_tree/test_prepare_boot_dtb.py
```

Some HDMI tests in the original validation package use pinned PYNQ/Xilinx reference snapshots. Those snapshots were omitted from this GitHub-ready tree to keep licensing boundaries clear; fetch them separately or run those tests inside the original V0.17.3 delivery package when needed.

## License

Original project code in this repository is released under the MIT License. Third-party IP, generated hardware artifacts, vendor libraries, model files, and board support components may have separate licenses or evaluation restrictions. Review `THIRD_PARTY_NOTICES.md` before publishing or redistributing binaries.
