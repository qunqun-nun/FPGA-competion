# Convert the V0.15 copy of the fixed V0.14 design into an extensible Vitis platform.
# V0.14 is never opened or modified by this script.

set script_dir [file dirname [file normalize [info script]]]
set work_root [file dirname $script_dir]
set project_path [file join $work_root v014_main_project_20261024 project fengyan_pl.xpr]
set platform_dir [file join $work_root platform]
set log_dir [file join $work_root logs]
file mkdir $platform_dir
file mkdir $log_dir

proc require_one {objects description} {
    if {[llength $objects] != 1} {
        error "Expected exactly one $description, found [llength $objects]"
    }
    return $objects
}

open_project $project_path

# Import the synthesizable 32-bit-address AXI-Lite placeholder into the
# development project so the exported XSA remains path-portable.
set placeholder_rtl [file join $work_root rtl dpu_control_placeholder_axi.v]
if {![file exists $placeholder_rtl]} {error "Missing DPU control placeholder RTL: $placeholder_rtl"}
set_property source_mgmt_mode All [current_project]
foreach old_placeholder_file [get_files -quiet *dpu_control_placeholder_axi.v] {
    remove_files $old_placeholder_file
}
import_files -force -norecurse -fileset sources_1 $placeholder_rtl
update_compile_order -fileset sources_1

# Keep platform IP repositories as siblings of the Vivado project directory.
# write_hw_platform packages them at XSA root/iprepo, and the generated
# rebuild.tcl then resolves the same ../iprepo paths after extraction.
set local_user_repo [file join $work_root v014_main_project_20261024 iprepo ip_repo]
set local_official_repo [file join $work_root v014_main_project_20261024 iprepo official_ip_repo]
foreach repo [list $local_user_repo $local_official_repo] {
    if {![file isdirectory $repo]} {error "Missing local platform IP repository: $repo"}
}
set_property ip_repo_paths [list $local_user_repo $local_official_repo] [current_project]
update_ip_catalog

# Both XDC files remain active in constrs_1. Clear obsolete target-file hints:
# import_files flattens their paths while rebuilding a Vitis platform, making
# the original target_constrs_file/target_ucf strings invalid.
set_property target_constrs_file {} [get_filesets constrs_1]
set_property target_ucf {} [get_filesets constrs_1]

set bd_file [require_one [get_files -quiet */design_1.bd] "design_1.bd"]
open_bd_design $bd_file

set dpu [get_bd_cells -quiet DPUCZDX8G_0]
if {[llength $dpu] == 1} {
    delete_bd_objs $dpu
}

# The instruction SmartConnect served only the fixed DPU instruction master.
set instr_sc [get_bd_cells -quiet dpu_instr_smartconnect]
if {[llength $instr_sc] == 1} {
    delete_bd_objs $instr_sc
}

set ctrl_sc [require_one [get_bd_cells -quiet control_smartconnect] "control_smartconnect"]
set ps [require_one [get_bd_cells -quiet zynq_ultra_ps_e_0] "Zynq UltraScale+ PS"]
set clk_wiz [require_one [get_bd_cells -quiet dpu_clk_wiz] "DPU clock wizard"]
set irq_concat [require_one [get_bd_cells -quiet dpu_irq_concat] "DPU IRQ concat"]

# Removing the fixed DPU leaves its old interrupt net without a source.
# Delete that dangling net so Vitis can connect the linked kernel to In1.
foreach irq_net [get_bd_nets -quiet -of_objects [get_bd_pins dpu_irq_concat/In1]] {
    delete_bd_objs $irq_net
}

# V0.14 already occupies M00..M05 for static control slaves.  Materialize M06
# and feed a dedicated AXI Interconnect.  The 2022.2 Vitis platform flow can
# auto-enable dynamic manager ports on AXI Interconnect, but not reliably on
# SmartConnect.  M00 is a tiny static placeholder; M01 is the DPU control slot.
set_property CONFIG.NUM_MI 7 $ctrl_sc
if {[llength [get_bd_intf_pins -quiet control_smartconnect/M06_AXI]] != 1} {
    error "Failed to materialize control_smartconnect/M06_AXI"
}
set_property PFM.AXI_PORT {} $ctrl_sc

foreach old_cell [get_bd_cells -quiet {dpu_control_interconnect dpu_control_placeholder}] {
    delete_bd_objs $old_cell
}
set dpu_ctrl_ic [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 dpu_control_interconnect]
set_property -dict [list CONFIG.NUM_SI 1 CONFIG.NUM_MI 1 CONFIG.M01_HAS_REGSLICE 1] $dpu_ctrl_ic
set dpu_ctrl_placeholder [create_bd_cell -type module -reference dpu_control_placeholder_axi dpu_control_placeholder]

connect_bd_intf_net [get_bd_intf_pins control_smartconnect/M06_AXI] [get_bd_intf_pins dpu_control_interconnect/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins dpu_control_interconnect/M00_AXI] [get_bd_intf_pins dpu_control_placeholder/S_AXI]

connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] \
    [get_bd_pins dpu_control_interconnect/ACLK] \
    [get_bd_pins dpu_control_interconnect/S00_ACLK] \
    [get_bd_pins dpu_control_interconnect/M00_ACLK] \
    [get_bd_pins dpu_control_placeholder/s_axi_aclk]
connect_bd_net [get_bd_pins proc_sys_reset_0/interconnect_aresetn] \
    [get_bd_pins dpu_control_interconnect/ARESETN] \
    [get_bd_pins dpu_control_interconnect/S00_ARESETN] \
    [get_bd_pins dpu_control_interconnect/M00_ARESETN] \
    [get_bd_pins dpu_control_placeholder/s_axi_aresetn]

assign_bd_address -offset 0x0082040000 -range 512 \
    -target_address_space [get_bd_addr_spaces zynq_ultra_ps_e_0/Data] \
    [get_bd_addr_segs dpu_control_placeholder/S_AXI/reg0] -force
set_property PFM.AXI_PORT {M01_AXI {memport "M_AXI_GP" sptag "DPU_CTRL"}} $dpu_ctrl_ic

# Preserve the V0.14 memory topology: instructions/profiling through HPC0,
# data banks through HP1 and HP2.
set_property PFM.AXI_PORT {\
    S_AXI_HPC0_FPD {memport "S_AXI_HPC" sptag "HPC0" memory "zynq_ultra_ps_e_0 HPC0_DDR_LOW"}\
    S_AXI_HP1_FPD  {memport "S_AXI_HP"  sptag "HP1"  memory "zynq_ultra_ps_e_0 HP1_DDR_LOW"}\
    S_AXI_HP2_FPD  {memport "S_AXI_HP"  sptag "HP2"  memory "zynq_ultra_ps_e_0 HP2_DDR_LOW"}\
} $ps

# DPU main clock and 2x clock. The associated reset blocks already exist in V0.14.
set_property PFM.CLOCK {\
    clk_out1 {id "0" is_default "true"  proc_sys_reset "dpu_rst_300" status "fixed"}\
    clk_out2 {id "1" is_default "false" proc_sys_reset "dpu_rst_600" status "fixed"}\
} $clk_wiz

# In0 remains occupied by the V0.14 system-control interrupt; Vitis owns In1.
set_property PFM.IRQ {In1 {id 1 range 1}} $irq_concat

set_property PFM_NAME "fengyan.org:xd:fengyan_v015_zcu104:1.0" $bd_file
set_property platform.default_output_type "xclbin" [current_project]
set_property platform.design_intent.embedded "true" [current_project]
set_property platform.extensible "true" [current_project]
set_property platform.design_intent.server_managed "false" [current_project]
set_property platform.design_intent.external_host "false" [current_project]
set_property platform.design_intent.datacenter "false" [current_project]

regenerate_bd_layout
validate_bd_design -force
save_bd_design
generate_target all $bd_file
update_compile_order -fileset sources_1

set validation_report [file join $log_dir platform_bd_validation.txt]
set fp [open $validation_report w]
puts $fp "VIVADO=[version -short]"
puts $fp "PROJECT=$project_path"
puts $fp "DPU_STATIC_COUNT=[llength [get_bd_cells -quiet DPUCZDX8G_0]]"
puts $fp "PFM_NAME=[get_property PFM_NAME $bd_file]"
puts $fp "PFM_CONTROL=[get_property PFM.AXI_PORT $dpu_ctrl_ic]"
puts $fp "CONTROL_NUM_MI=[get_property CONFIG.NUM_MI $ctrl_sc]"
puts $fp "CONTROL_M06_COUNT=[llength [get_bd_intf_pins -quiet control_smartconnect/M06_AXI]]"
puts $fp "CONTROL_M06_ADDR_WIDTH=[get_property CONFIG.ADDR_WIDTH [get_bd_intf_pins control_smartconnect/M06_AXI]]"
puts $fp "PFM_MEMORY=[get_property PFM.AXI_PORT $ps]"
puts $fp "PFM_CLOCK=[get_property PFM.CLOCK $clk_wiz]"
puts $fp "PFM_IRQ=[get_property PFM.IRQ $irq_concat]"
puts $fp "BD_VALIDATION=PASS"
close $fp

set xsa_path [file join $platform_dir fengyan_v015_extensible.xsa]
write_hw_platform -force -file $xsa_path
close_project
puts "V015_EXTENSIBLE_XSA=$xsa_path"
exit
