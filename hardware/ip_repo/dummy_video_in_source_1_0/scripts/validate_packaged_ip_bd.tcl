set validation_dir {C:/Users/Admin/Desktop/ip_repo/dummy_video_in_source_1_0/reports/bd_validation}
set repo_dir       {C:/Users/Admin/Desktop/ip_repo}
set expected_vlnv  {xilinx.com:user:dummy_video_in_source:1.0}

create_project dummy_video_in_source_bd_validation $validation_dir \
    -part xczu7ev-ffvc1156-2-e -force
set_property ip_repo_paths $repo_dir [current_project]
update_ip_catalog

set definitions [get_ipdefs -all -quiet $expected_vlnv]
if {[llength $definitions] != 1} {
    error "Expected exactly one catalog definition for $expected_vlnv, got: $definitions"
}

create_bd_design dummy_ip_validation
set cell [create_bd_cell -type ip -vlnv $expected_vlnv dummy_video_in_source_0]

make_bd_intf_pins_external [get_bd_intf_pins $cell/m_axis]
set_property name m_axis [get_bd_intf_ports m_axis_0]

foreach pin_name {video_aclk video_aresetn enable soft_reset} {
    make_bd_pins_external [get_bd_pins $cell/$pin_name]
    set_property name $pin_name [get_bd_ports ${pin_name}_0]
}
set_property CONFIG.FREQ_HZ 100000000 [get_bd_ports video_aclk]
set_property CONFIG.POLARITY ACTIVE_LOW [get_bd_ports video_aresetn]

validate_bd_design
save_bd_design

puts "BD_VALIDATED_CELL_VLNV=[get_property VLNV $cell]"
puts "BD_VALIDATED_INTERFACES=[get_bd_intf_pins -of_objects $cell]"
puts "PACKAGED_IP_BLOCK_DESIGN_VALIDATION_PASS"
close_project
exit
