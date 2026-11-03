# ZCU104 FMC HDMI 2.0 TX pin constraints.
# Port names match the V0.14 official HDMI TX/PHY Block Design integration.

set_property PACKAGE_PIN T8 [get_ports TX_REFCLK_P_IN]

# Constrain only the board-level GT reference clock here.  The Video PHY and
# HDMI TX subsystem create the link/video clocks internally; adding primary
# clocks on txoutclk or tx_video_clk overrides those generated-clock relations
# and triggers TIMING-2/3/4/6 methodology violations.
create_clock -name v014_hdmi_gt_refclk -period 3.367 [get_ports TX_REFCLK_P_IN]

set_property PACKAGE_PIN G21 [get_ports HDMI_TX_CLK_P_OUT]
set_property IOSTANDARD LVDS [get_ports HDMI_TX_CLK_P_OUT]

set_property PACKAGE_PIN E3 [get_ports TX_HPD_IN]
set_property IOSTANDARD LVCMOS33 [get_ports TX_HPD_IN]

set_property PACKAGE_PIN B1 [get_ports TX_DDC_OUT_scl_io]
set_property IOSTANDARD LVCMOS33 [get_ports TX_DDC_OUT_scl_io]
set_property PACKAGE_PIN C1 [get_ports TX_DDC_OUT_sda_io]
set_property IOSTANDARD LVCMOS33 [get_ports TX_DDC_OUT_sda_io]

set_property PACKAGE_PIN D1 [get_ports fmch_iic_scl_io]
set_property IOSTANDARD LVCMOS33 [get_ports fmch_iic_scl_io]
set_property PACKAGE_PIN E1 [get_ports fmch_iic_sda_io]
set_property IOSTANDARD LVCMOS33 [get_ports fmch_iic_sda_io]

set_property PACKAGE_PIN D5 [get_ports HDMI_LOCKED_LED]
set_property IOSTANDARD LVCMOS33 [get_ports HDMI_LOCKED_LED]
set_property PACKAGE_PIN N11 [get_ports IDT_8T49N241_LOL_IN]
set_property IOSTANDARD LVCMOS33 [get_ports IDT_8T49N241_LOL_IN]
set_property PACKAGE_PIN A2 [get_ports TX_EN_OUT]
set_property IOSTANDARD LVCMOS33 [get_ports TX_EN_OUT]

# V0.17: UG1267 p61: drive HDMI clock recovery reset high (enable).
set_property PACKAGE_PIN M12 [get_ports IDT_8T49N241_RST_OUT]
set_property IOSTANDARD LVCMOS33 [get_ports IDT_8T49N241_RST_OUT]
