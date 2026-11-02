set repo_dir {C:/Users/Admin/Desktop/ip_repo}
set rtl_file {C:/Users/Admin/Desktop/ip_repo/pl_video_in_1_0/src/pl_video_in.v}
set component_file {C:/Users/Admin/Desktop/ip_repo/pl_video_in_1_0/component.xml}
set report_dir {C:/Users/Admin/Desktop/ip_repo/pl_video_in_1_0/reports/stage1}
file mkdir $report_dir

read_verilog $rtl_file
synth_design -top pl_video_in -part xczu7ev-ffvc1156-2-e -mode out_of_context
report_utilization -file $report_dir/pl_video_in_utilization.rpt
report_timing_summary -file $report_dir/pl_video_in_timing_summary.rpt
write_checkpoint -force $report_dir/pl_video_in_ooc.dcp
puts {PL_VIDEO_IN_OOC_SYNTHESIS_PASS}

set core [ipx::open_ipxact_file $component_file]
if {[get_property vlnv $core] ne {xilinx.com:user:pl_video_in:1.0}} {
    error "Unexpected VLNV: [get_property vlnv $core]"
}

foreach interface_name {s_axis m_axis video_aclk video_aresetn} {
    if {[llength [ipx::get_bus_interfaces -quiet $interface_name -of_objects $core]] != 1} {
        error "Missing or duplicate interface: $interface_name"
    }
}
foreach port_name {
    video_aclk video_aresetn enable soft_reset clear_error
    s_axis_tdata s_axis_tvalid s_axis_tready s_axis_tuser s_axis_tlast
    m_axis_tdata m_axis_tvalid m_axis_tready m_axis_tuser m_axis_tlast
    lock busy frame_done_pulse err err_code frame_cnt
} {
    if {[llength [ipx::get_ports -quiet $port_name -of_objects $core]] != 1} {
        error "Missing or duplicate RTL port: $port_name"
    }
}

set s_axis [ipx::get_bus_interfaces s_axis -of_objects $core]
set m_axis [ipx::get_bus_interfaces m_axis -of_objects $core]
if {[get_property interface_mode $s_axis] ne {slave}} {
    error {s_axis is not an AXI4-Stream slave}
}
if {[get_property interface_mode $m_axis] ne {master}} {
    error {m_axis is not an AXI4-Stream master}
}
foreach axis_if [list $s_axis $m_axis] {
    foreach logical_port {TDATA TVALID TREADY TUSER TLAST} {
        if {[llength [ipx::get_port_maps -quiet $logical_port -of_objects $axis_if]] != 1} {
            error "Missing $logical_port mapping on [get_property name $axis_if]"
        }
    }
}

ipx::check_integrity $core
puts "PL_VIDEO_IN_VERIFIED_VLNV=[get_property vlnv $core]"
puts {PL_VIDEO_IN_COMPONENT_XML_PASS}
ipx::unload_core $core
exit
