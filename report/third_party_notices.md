# Third-Party Notices

This repository contains original project source, current deployment artifacts, and references to external FPGA/software components.

## Included Artifacts

- `hardware/artifacts/*.bit`, `*.hwh`, `*.xclbin`, `*.xsa`: generated from the V0.17 hardware baseline and may include vendor IP or evaluation-licensed HDMI components.
- `runtime/hdmi/pynq_native/libfengyan_xhdmi.so`: native helper library built for the board runtime.
- `models/*.xmodel`: deployed model artifact.

These artifacts are kept so the repository reflects the latest working package, but their redistribution terms may differ from the MIT license used for original project code.

## External Toolchains

- Xilinx Vivado/Vitis 2022.2
- PYNQ 3.0.1
- Xilinx/Vitis AI runtime components as required by the target board image

## Omitted Reference Trees

The source delivery package contained pinned reference snapshots such as PYNQ, Xilinx HDMI/Linux driver sources, embeddedsw, and bare-metal HDMI examples. They were not copied as repository source to keep the open-source tree clean and avoid mixing unclear or toolchain-specific license scopes.

If full HDMI reference comparison tests are needed, use the original V0.17.3 delivery package or fetch the pinned upstream projects separately according to their licenses.

