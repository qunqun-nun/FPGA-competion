set project_file {C:/Users/Admin/Desktop/ip_repo/edit_pl_preproc_letterbox_v1_0.xpr}
set ip_root      {C:/Users/Admin/Desktop/ip_repo/pl_preproc_letterbox_1_0}
set unit_tb      {C:/Users/Admin/Desktop/ip_repo/pl_preproc_letterbox_1_0/tb/tb_pl_preproc_letterbox.sv}
set protocol_tb  {C:/Users/Admin/Desktop/ip_repo/pl_preproc_letterbox_1_0/tb/tb_pl_preproc_letterbox_protocol.sv}

proc ensure_bus_parameter {interface name value} {
    set parameter [ipx::get_bus_parameters -quiet $name -of_objects $interface]
    if {[llength $parameter] == 0} {
        set parameter [ipx::add_bus_parameter $name $interface]
    }
    set_property value $value $parameter
}

open_project $project_file

# Keep verification sources in the editable project, but out of the packaged IP.
set verification_files [get_files -quiet [list $unit_tb $protocol_tb]]
if {[llength $verification_files] > 0} {
    remove_files $verification_files
}
update_compile_order -fileset sources_1

ipx::package_project -root_dir $ip_root -vendor xilinx.com -library user \
    -taxonomy /UserIP -import_files -force
set core [ipx::current_core]

set_property name pl_preproc_letterbox $core
set_property display_name {PL Video Preprocess Letterbox} $core
set_property description {640x480 GRAY8 to 640x640 RGB888 AXI4-Stream letterbox} $core
set_property vendor_display_name {User} $core
set_property version 1.0 $core
set_property supported_families {zynquplus Production} $core

if {[llength [ipx::get_bus_interfaces -quiet s_axis -of_objects $core]] == 0} {
    ipx::infer_bus_interface s_axis xilinx.com:interface:axis_rtl:1.0 $core
}
if {[llength [ipx::get_bus_interfaces -quiet m_axis -of_objects $core]] == 0} {
    ipx::infer_bus_interface m_axis xilinx.com:interface:axis_rtl:1.0 $core
}
if {[llength [ipx::get_bus_interfaces -quiet aclk -of_objects $core]] == 0} {
    ipx::infer_bus_interface aclk xilinx.com:signal:clock_rtl:1.0 $core
}
if {[llength [ipx::get_bus_interfaces -quiet aresetn -of_objects $core]] == 0} {
    ipx::infer_bus_interface aresetn xilinx.com:signal:reset_rtl:1.0 $core
}

set s_axis_if [ipx::get_bus_interfaces s_axis -of_objects $core]
set m_axis_if [ipx::get_bus_interfaces m_axis -of_objects $core]
set clk_if    [ipx::get_bus_interfaces aclk -of_objects $core]
set rst_if    [ipx::get_bus_interfaces aresetn -of_objects $core]

set_property interface_mode slave $s_axis_if
set_property interface_mode master $m_axis_if
ensure_bus_parameter $clk_if ASSOCIATED_BUSIF {s_axis:m_axis}
ensure_bus_parameter $clk_if ASSOCIATED_RESET aresetn
ensure_bus_parameter $rst_if POLARITY ACTIVE_LOW

ipx::merge_project_changes files $core
ipx::merge_project_changes ports $core
ipx::merge_project_changes parameters $core
ipx::create_xgui_files $core
ipx::update_checksums $core
ipx::check_integrity $core
ipx::save_core $core

puts "PACKAGED_VLNV=[get_property vlnv $core]"
puts "PACKAGED_INTERFACES=[ipx::get_bus_interfaces -of_objects $core]"
puts "LETTERBOX_PACKAGE_IP_PASS"

ipx::unload_core $core

# Restore verification sources so the editable project remains convenient to inspect.
add_files -fileset sim_1 -norecurse [list $unit_tb $protocol_tb]
set_property file_type SystemVerilog [get_files -quiet [list $unit_tb $protocol_tb]]
set_property top tb_pl_preproc_letterbox [get_filesets sim_1]
update_compile_order -fileset sim_1
close_project
exit
