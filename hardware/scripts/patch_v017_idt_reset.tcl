# Modify the existing static project copy; no project creation or synthesis/implementation.
set root [file dirname [file dirname [file normalize [info script]]]]
if {![string match *2022.2* [version -short]]} {error "Vivado 2022.2 required"}
if {![file exists [file join $root change_backup affected_files.json]]} {error "Run prepare_v017_change.py first"}
set prj [file join $root v014_main_project_20261024 project fengyan_pl.xpr]
set xdc [file join $root v014_unified_work_20261024 constraints hdmi_zcu104_tx_v014.xdc]
open_project $prj
set bd [get_files -quiet */design_1.bd]
if {[llength $bd]!=1} {error "Expected one design_1.bd"}
open_bd_design $bd
set one [get_bd_cells -quiet const_one]
if {[llength $one]!=1} {error "Missing existing const_one"}
if {[get_property CONFIG.CONST_VAL $one]!=1 || [get_property CONFIG.CONST_WIDTH $one]!=1} {error "const_one is not a one-bit constant 1"}
set port [get_bd_ports -quiet IDT_8T49N241_RST_OUT]
if {[llength $port]==0} {set port [create_bd_port -dir O IDT_8T49N241_RST_OUT]}
if {[get_property DIR $port] ne "O"} {error "IDT port must be output"}
if {[llength [get_bd_nets -quiet -of_objects $port]]==0} {
 connect_bd_net [get_bd_pins const_one/dout] $port
}
set net [get_bd_nets -of_objects $port]
if {[lsearch -exact [get_bd_pins -of_objects $net] /const_one/dout]<0} {error "IDT output must be on const_one/dout net"}
set f [open $xdc r];set contents [read $f];close $f
if {![string match *IDT_8T49N241_RST_OUT* $contents]} {
 set f [open $xdc a]
 puts $f "\n# V0.17: UG1267 p61: drive HDMI clock recovery reset high (enable)."
 puts $f {set_property PACKAGE_PIN M12 [get_ports IDT_8T49N241_RST_OUT]}
 puts $f {set_property IOSTANDARD LVCMOS33 [get_ports IDT_8T49N241_RST_OUT]}
 close $f
}
set_property PFM_NAME fengyan.org:xd:fengyan_v017_zcu104:1.0 $bd
set_property platform.vendor fengyan.org [current_project]
set_property platform.board_id xd [current_project]
set_property platform.name fengyan_v017_zcu104 [current_project]
set_property platform.version 1.0 [current_project]
set_property platform.extensible true [current_project]
validate_bd_design -force
save_bd_design
generate_target all $bd
set wrapper [make_wrapper -files $bd -top -force]
if {[llength [get_files -quiet $wrapper]]==0} {add_files -norecurse $wrapper}
set_property top design_1_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1
set f [open [file join $root logs v017_bd_validation.txt] w]
puts $f "VIVADO=[version -short]\nBD_VALIDATE=PASS\nIDT_PORT=[get_bd_ports IDT_8T49N241_RST_OUT]\nDRIVER=[get_bd_pins -of_objects $net]\nCONST_WIDTH=[get_property CONFIG.CONST_WIDTH $one]\nCONST_VALUE=[get_property CONFIG.CONST_VAL $one]\nPIN=M12\nIOSTANDARD=LVCMOS33\nWRAPPER=$wrapper\nPFM_NAME=[get_property PFM_NAME $bd]\nEXTENSIBLE=[get_property platform.extensible [current_project]]"
close $f
# Prove the run property is writable, then restore; no incremental state saved to this project.
set run [get_runs impl_1]
set f [open [file join $root logs v017_incremental_property.txt] w]
puts $f "RUN=$run\nMATCHING_PROPERTIES=[lsort [lsearch -all -inline -glob [list_property $run] *INCREMENTAL*]]"
set dcp [file join $root build link _x link vivado vpl prj prj.runs impl_1 design_1_wrapper_routed.dcp]
if {![file exists $dcp]} {error "Missing old routed checkpoint"}
set old [get_property INCREMENTAL_CHECKPOINT $run]
puts $f "BEFORE=$old\nREFERENCE_DCP=$dcp"
if {[catch {set_property INCREMENTAL_CHECKPOINT $dcp $run} err]} {puts $f "SET_SUPPORTED=0\nERROR=$err"} else {
 puts $f "SET_SUPPORTED=1\nREADBACK=[get_property INCREMENTAL_CHECKPOINT $run]"
 set_property INCREMENTAL_CHECKPOINT $old $run
 puts $f "RESTORED=[get_property INCREMENTAL_CHECKPOINT $run]"
}
close $f
file mkdir [file join $root platform]
write_hw_platform -force -file [file join $root platform fengyan_v017_extensible.xsa]
puts "V017_EXTENSIBLE_XSA_EXPORTED"
close_project
exit
