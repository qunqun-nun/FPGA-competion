# dummy_video_in_source v1.0

This IP generates a continuous 640x480 GRAY8 AXI4-Stream video source. With the default `PIXEL_VALUE=8'h00`, every pixel is black.

## Open and inspect in Vivado

Open this editable project:

```text
C:\Users\Admin\Desktop\ip_repo\edit_dummy_video_in_source_v1_0.xpr
```

The maintained RTL source is:

```text
C:\Users\Admin\Desktop\ip_repo\dummy_video_in_source_1_0\src\dummy_video_in_source.v
```

The editable project also contains both testbenches under Simulation Sources.

## Packaged IP

```text
VLNV: xilinx.com:user:dummy_video_in_source:1.0
IP root: C:\Users\Admin\Desktop\ip_repo\dummy_video_in_source_1_0
```

The AXI4-Stream master interface is named `m_axis`. `video_aclk` is associated with `m_axis` and the active-low `video_aresetn`. `soft_reset` remains a plain control port.

## Verification scripts

All scripts are in the `scripts` directory:

- `run_simulations.tcl`: unit and `pl_video_in` integration simulations.
- `run_synthesis.tcl`: ZCU104-device synthesis and reports.
- `package_ip.tcl`: packages the current RTL as IP v1.0.
- `verify_component.tcl`: validates `component.xml` ports, parameters and interfaces.
- `validate_packaged_ip_bd.tcl`: instantiates the packaged IP in an isolated Block Design and validates it.

The main `project_1` design is not modified by these scripts.
