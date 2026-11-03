set script_dir [file dirname [file normalize [info script]]]
set work_root [file dirname $script_dir]
set rtl_file [file join $work_root rtl dpu_control_placeholder_axi.v]

create_project -in_memory probe_placeholder -part xczu7ev-ffvc1156-2-e
set_property source_mgmt_mode All [current_project]
add_files -norecurse $rtl_file
update_compile_order -fileset sources_1
create_bd_design probe
set cell [create_bd_cell -type module -reference dpu_control_placeholder_axi dpu_control_placeholder]
puts "INTERFACES=[get_bd_intf_pins -quiet dpu_control_placeholder/*]"
set s_axi [get_bd_intf_pins -quiet dpu_control_placeholder/S_AXI]
puts "S_AXI_COUNT=[llength $s_axi]"
if {[llength $s_axi] == 1} {
    puts "S_AXI_ADDR_WIDTH=[get_property CONFIG.ADDR_WIDTH $s_axi]"
    puts "S_AXI_PROTOCOL=[get_property CONFIG.PROTOCOL $s_axi]"
}
puts "ADDR_SEGS=[get_bd_addr_segs -quiet dpu_control_placeholder/*]"
puts "PINS=[get_bd_pins -quiet dpu_control_placeholder/*]"
validate_bd_design -force
exit
