set component_file {C:/Users/Admin/Desktop/ip_repo/dummy_video_in_source_1_0/component.xml}

proc require_exactly_one {objects label} {
    if {[llength $objects] != 1} {
        error "Expected exactly one $label, got: $objects"
    }
    return [lindex $objects 0]
}

set core [ipx::open_ipxact_file $component_file]
if {[get_property vlnv $core] ne {xilinx.com:user:dummy_video_in_source:1.0}} {
    error "Unexpected VLNV: [get_property vlnv $core]"
}

set axis_if [require_exactly_one \
    [ipx::get_bus_interfaces -quiet m_axis -of_objects $core] {m_axis interface}]
set clk_if [require_exactly_one \
    [ipx::get_bus_interfaces -quiet video_aclk -of_objects $core] {video_aclk interface}]
set rst_if [require_exactly_one \
    [ipx::get_bus_interfaces -quiet video_aresetn -of_objects $core] {video_aresetn interface}]
if {[llength [ipx::get_bus_interfaces -quiet soft_reset -of_objects $core]] != 0} {
    error {soft_reset must remain a plain control port, not a reset bus interface}
}

if {[get_property interface_mode $axis_if] ne {master}} {
    error {m_axis is not an AXI4-Stream master}
}

foreach logical_port {TDATA TVALID TREADY TUSER TLAST} {
    require_exactly_one [ipx::get_port_maps -quiet $logical_port -of_objects $axis_if] \
        "m_axis $logical_port port map"
}

foreach rtl_port {
    video_aclk video_aresetn enable soft_reset
    m_axis_tdata m_axis_tvalid m_axis_tready m_axis_tuser m_axis_tlast
} {
    require_exactly_one [ipx::get_ports -quiet $rtl_port -of_objects $core] \
        "$rtl_port RTL port"
}

foreach parameter_name {IMAGE_WIDTH IMAGE_HEIGHT PIXEL_VALUE} {
    require_exactly_one [ipx::get_user_parameters -quiet $parameter_name -of_objects $core] \
        "$parameter_name user parameter"
}

set associated_busif [require_exactly_one \
    [ipx::get_bus_parameters -quiet ASSOCIATED_BUSIF -of_objects $clk_if] \
    {ASSOCIATED_BUSIF clock parameter}]
set associated_reset [require_exactly_one \
    [ipx::get_bus_parameters -quiet ASSOCIATED_RESET -of_objects $clk_if] \
    {ASSOCIATED_RESET clock parameter}]
set reset_polarity [require_exactly_one \
    [ipx::get_bus_parameters -quiet POLARITY -of_objects $rst_if] \
    {POLARITY reset parameter}]

if {[get_property value $associated_busif] ne {m_axis}} {
    error {video_aclk ASSOCIATED_BUSIF is not m_axis}
}
if {[get_property value $associated_reset] ne {video_aresetn}} {
    error {video_aclk ASSOCIATED_RESET is not video_aresetn}
}
if {[get_property value $reset_polarity] ne {ACTIVE_LOW}} {
    error {video_aresetn is not ACTIVE_LOW}
}

ipx::check_integrity $core
puts "VERIFIED_VLNV=[get_property vlnv $core]"
puts "VERIFIED_INTERFACES=[ipx::get_bus_interfaces -of_objects $core]"
puts "COMPONENT_XML_VERIFICATION_PASS"
ipx::unload_core $core
exit
