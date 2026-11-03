set ip_root {C:/Users/Admin/Desktop/ip_repo/pl_preproc_letterbox_1_0}
set validation_dir [file join $ip_root reports bd_validation]
set repo_dir {C:/Users/Admin/Desktop/ip_repo}
set expected_vlnv {xilinx.com:user:pl_preproc_letterbox:1.0}

create_project pl_preproc_letterbox_bd_validation $validation_dir \
    -part xczu7ev-ffvc1156-2-e -force
set_property ip_repo_paths $repo_dir [current_project]
update_ip_catalog

set definitions [get_ipdefs -all -quiet $expected_vlnv]
if {[llength $definitions] != 1} {
    error "Expected exactly one catalog definition for $expected_vlnv, got: $definitions"
}

create_bd_design letterbox_ip_validation
set cell [create_bd_cell -type ip -vlnv $expected_vlnv pl_preproc_letterbox_0]

foreach interface_name {s_axis m_axis} {
    make_bd_intf_pins_external [get_bd_intf_pins $cell/$interface_name]
    set_property name $interface_name \
        [get_bd_intf_ports ${interface_name}_0]
}

foreach pin_name {aclk aresetn error out_frame_start out_frame_done} {
    make_bd_pins_external [get_bd_pins $cell/$pin_name]
    set_property name $pin_name [get_bd_ports ${pin_name}_0]
}
set_property CONFIG.FREQ_HZ 100000000 [get_bd_ports aclk]
set_property CONFIG.POLARITY ACTIVE_LOW [get_bd_ports aresetn]

validate_bd_design
save_bd_design
puts "BD_VALIDATED_CELL_VLNV=[get_property VLNV $cell]"
puts "LETTERBOX_PACKAGED_IP_BLOCK_DESIGN_VALIDATION_PASS"
close_project
exit
