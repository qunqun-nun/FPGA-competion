set component_file {C:/Users/Admin/Desktop/ip_repo/pl_preproc_letterbox_1_0/component.xml}

proc require_exactly_one {objects label} {
    if {[llength $objects] != 1} {
        error "Expected exactly one $label, got: $objects"
    }
    return [lindex $objects 0]
}

set core [ipx::open_ipxact_file $component_file]
if {[get_property vlnv $core] ne {xilinx.com:user:pl_preproc_letterbox:1.0}} {
    error "Unexpected VLNV: [get_property vlnv $core]"
}

set s_axis_if [require_exactly_one \
    [ipx::get_bus_interfaces -quiet s_axis -of_objects $core] {s_axis interface}]
set m_axis_if [require_exactly_one \
    [ipx::get_bus_interfaces -quiet m_axis -of_objects $core] {m_axis interface}]
set clk_if [require_exactly_one \
    [ipx::get_bus_interfaces -quiet aclk -of_objects $core] {aclk interface}]
set rst_if [require_exactly_one \
    [ipx::get_bus_interfaces -quiet aresetn -of_objects $core] {aresetn interface}]

if {[get_property interface_mode $s_axis_if] ne {slave}} {
    error {s_axis is not an AXI4-Stream slave}
}
if {[get_property interface_mode $m_axis_if] ne {master}} {
    error {m_axis is not an AXI4-Stream master}
}

foreach interface_name {s_axis m_axis} {
    set interface [ipx::get_bus_interfaces $interface_name -of_objects $core]
    foreach logical_port {TDATA TVALID TREADY TUSER TLAST} {
        require_exactly_one [ipx::get_port_maps -quiet $logical_port -of_objects $interface] \
            "$interface_name $logical_port port map"
    }
}

foreach rtl_port {
    aclk aresetn
    s_axis_tdata s_axis_tvalid s_axis_tready s_axis_tuser s_axis_tlast
    m_axis_tdata m_axis_tvalid m_axis_tready m_axis_tuser m_axis_tlast
    error out_frame_start out_frame_done
} {
    require_exactly_one [ipx::get_ports -quiet $rtl_port -of_objects $core] \
        "$rtl_port RTL port"
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

if {[get_property value $associated_busif] ne {s_axis:m_axis}} {
    error {aclk ASSOCIATED_BUSIF is not s_axis:m_axis}
}
if {[get_property value $associated_reset] ne {aresetn}} {
    error {aclk ASSOCIATED_RESET is not aresetn}
}
if {[get_property value $reset_polarity] ne {ACTIVE_LOW}} {
    error {aresetn is not ACTIVE_LOW}
}

ipx::check_integrity $core
puts "VERIFIED_VLNV=[get_property vlnv $core]"
puts "VERIFIED_INTERFACES=[ipx::get_bus_interfaces -of_objects $core]"
puts "LETTERBOX_COMPONENT_XML_VERIFICATION_PASS"
ipx::unload_core $core
exit
