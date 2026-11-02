set root [file dirname [file dirname [file normalize [info script]]]]
set ipdir [file join $root third_party DPUCZDX8G_TRD_2022.1 prj Vitis packaged_kernel_DPUCZDX8G_hw_zcu104]
set core [ipx::open_core [file join $ipdir component.xml]]
# The imported relative src/dpu_conf.vh is already present. Remove only the
# duplicate absolute header reference left by the original TRD packager.
if {![file exists [file join $ipdir src dpu_conf.vh]]} {error "Missing relative DPU config"}
set removed 0
foreach group [ipx::get_file_groups -of_objects $core] {
    foreach f [ipx::get_files -of_objects $group] {
        set name [get_property NAME $f]
        if {[regexp {^[A-Za-z]:/.*dpu_conf\.vh$} $name]} {
            ipx::remove_file $name $group
            incr removed
        } elseif {[regexp {^[A-Za-z]:/} $name]} {error "Unexpected absolute source: $name"}
    }
}
if {$removed != 2} {error "Expected 2 absolute header entries; removed $removed"}
ipx::update_checksums $core
ipx::save_core $core
package_xo -force -xo_path [file join $root build dpu_kernel dpu_b4096.xo] -kernel_name DPUCZDX8G -ip_directory $ipdir -kernel_xml [file join $root third_party DPUCZDX8G_TRD_2022.1 prj Vitis kernel_xml dpu kernel.xml]
puts "PORTABLE_XO_PACKAGED removed_absolute_entries=$removed"
exit
