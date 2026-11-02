# Re-export the validated existing project with consistent project/BD platform identity.
set root [file dirname [file dirname [file normalize [info script]]]]
open_project [file join $root v014_main_project_20261024 project fengyan_pl.xpr]
set_property platform.vendor fengyan.org [current_project]
set_property platform.board_id xd [current_project]
set_property platform.name fengyan_v017_zcu104 [current_project]
set_property platform.version 1.0 [current_project]
set_property platform.extensible true [current_project]
set bd [get_files */design_1.bd]
open_bd_design $bd
if {[llength [get_bd_ports -quiet IDT_8T49N241_RST_OUT]]!=1} {error "Missing repaired IDT port"}
set_property PFM_NAME fengyan.org:xd:fengyan_v017_zcu104:1.0 $bd
validate_bd_design -force
save_bd_design
set f [open [file join $root logs v017_platform_identity.txt] w]
foreach key {platform.vendor platform.board_id platform.name platform.version platform.extensible} {puts $f "$key=[get_property $key [current_project]]"}
puts $f "PFM_NAME=[get_property PFM_NAME $bd]"
close $f
write_hw_platform -force -file [file join $root platform fengyan_v017_extensible.xsa]
close_project
puts V017_IDENTITY_AND_XSA_EXPORTED
exit
