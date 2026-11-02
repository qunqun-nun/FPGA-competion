set root [file dirname [file dirname [file normalize [info script]]]]
if {![string match *2022.2* [version -short]]} {error "Vivado 2022.2 required"}
open_project [file join $root v014_main_project_20261024 project fengyan_pl.xpr]
set_property platform.name fengyan_v017_zcu104 [current_project]
update_ip_catalog -rebuild
set bd [get_files */design_1.bd]
open_bd_design $bd
report_ip_status -file [file join $root logs v017_ip_status_before_upgrade.rpt]
set scheduler [get_ips -all -quiet design_1_pl_frame_scheduler_0_0]
if {[llength $scheduler]!=1} {error "Missing scheduler IP instance"}
if {[get_property IS_LOCKED $scheduler]} {
 upgrade_ip $scheduler
}
report_ip_status -file [file join $root logs v017_ip_status_after_upgrade.rpt]
validate_bd_design -force
save_bd_design
generate_target all $bd
write_hw_platform -force -file [file join $root platform fengyan_v017_extensible.xsa]
puts "FINAL_V017_PLATFORM_EXPORTED_WITH_UPDATED_PACKAGE"
close_project
exit
