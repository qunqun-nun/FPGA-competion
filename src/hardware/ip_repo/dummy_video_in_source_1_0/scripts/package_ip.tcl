set project_file {C:/Users/Admin/Desktop/ip_repo/edit_dummy_video_in_source_v1_0.xpr}
set ip_root      {C:/Users/Admin/Desktop/ip_repo/dummy_video_in_source_1_0}
set unit_tb      {C:/Users/Admin/Desktop/ip_repo/dummy_video_in_source_1_0/tb/tb_dummy_video_in_source.sv}
set integ_tb     {C:/Users/Admin/Desktop/ip_repo/dummy_video_in_source_1_0/tb/tb_dummy_pl_video_in_integration.sv}
set protocol_tb  {C:/Users/Admin/Desktop/ip_repo/dummy_video_in_source_1_0/tb/tb_formal_pl_video_in_protocol.sv}
set video_in_rtl {C:/Users/Admin/Desktop/ip_repo/pl_video_in_1_0/src/pl_video_in.v}

proc ensure_bus_parameter {interface name value} {
    set parameter [ipx::get_bus_parameters -quiet $name -of_objects $interface]
    if {[llength $parameter] == 0} {
        set parameter [ipx::add_bus_parameter $name $interface]
    }
    set_property value $value $parameter
}

open_project $project_file

# Keep verification sources in the editable project, but out of the packaged core.
set verification_files [get_files -quiet [list $unit_tb $integ_tb $video_in_rtl]]
if {[llength $verification_files] > 0} {
    remove_files $verification_files
}
update_compile_order -fileset sources_1

ipx::package_project -root_dir $ip_root -vendor xilinx.com -library user \
    -taxonomy /UserIP -import_files -force
set core [ipx::current_core]

set_property name dummy_video_in_source $core
set_property display_name {Dummy Video Input Source} $core
set_property description {640x480 GRAY8 AXI4-Stream black-frame test source} $core
set_property vendor_display_name {User} $core
set_property version 1.0 $core
set_property supported_families {zynquplus Production} $core

if {[llength [ipx::get_bus_interfaces -quiet m_axis -of_objects $core]] == 0} {
    ipx::infer_bus_interface m_axis xilinx.com:interface:axis_rtl:1.0 $core
}
if {[llength [ipx::get_bus_interfaces -quiet video_aclk -of_objects $core]] == 0} {
    ipx::infer_bus_interface video_aclk xilinx.com:signal:clock_rtl:1.0 $core
}
if {[llength [ipx::get_bus_interfaces -quiet video_aresetn -of_objects $core]] == 0} {
    ipx::infer_bus_interface video_aresetn xilinx.com:signal:reset_rtl:1.0 $core
}
set axis_if [ipx::get_bus_interfaces m_axis -of_objects $core]
set clk_if  [ipx::get_bus_interfaces video_aclk -of_objects $core]
set rst_if  [ipx::get_bus_interfaces video_aresetn -of_objects $core]

set_property interface_mode master $axis_if
ensure_bus_parameter $clk_if ASSOCIATED_BUSIF m_axis
ensure_bus_parameter $clk_if ASSOCIATED_RESET video_aresetn
ensure_bus_parameter $rst_if POLARITY ACTIVE_LOW

foreach {parameter_name display_name} {
    IMAGE_WIDTH  {Image Width}
    IMAGE_HEIGHT {Image Height}
    PIXEL_VALUE  {Pixel Value}
} {
    set user_parameter [ipx::get_user_parameters -quiet $parameter_name -of_objects $core]
    if {[llength $user_parameter] > 0} {
        set_property display_name $display_name $user_parameter
    }
}

ipx::merge_project_changes files $core
ipx::merge_project_changes ports $core
ipx::merge_project_changes parameters $core
set soft_reset_if [ipx::get_bus_interfaces -quiet soft_reset -of_objects $core]
if {[llength $soft_reset_if] > 0} {
    ipx::remove_bus_interface soft_reset $core
}
if {[llength [ipx::get_bus_interfaces -quiet soft_reset -of_objects $core]] != 0} {
    error {soft_reset was incorrectly retained as a reset bus interface}
}
ipx::create_xgui_files $core
ipx::update_checksums $core
ipx::check_integrity $core
ipx::save_core $core

puts "PACKAGED_VLNV=[get_property vlnv $core]"
puts "PACKAGED_INTERFACES=[ipx::get_bus_interfaces -of_objects $core]"
puts "DUMMY_PACKAGE_IP_PASS"

ipx::unload_core $core

# Restore verification sources so the .xpr remains convenient to inspect and rerun.
add_files -fileset sim_1 -norecurse [list $unit_tb $integ_tb $protocol_tb $video_in_rtl]
set_property file_type SystemVerilog [get_files -quiet [list $unit_tb $integ_tb]]
set_property top tb_dummy_video_in_source [get_filesets sim_1]
update_compile_order -fileset sim_1
close_project
exit
