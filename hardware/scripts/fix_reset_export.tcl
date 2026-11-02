set root [file dirname [file dirname [file normalize [info script]]]]
open_project [file join $root v014_main_project_20261024 project fengyan_pl.xpr]
open_bd_design [get_files */design_1.bd]
if {[llength [get_bd_cells -quiet reset_aux_inactive_high]] == 0} {
    create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 reset_aux_inactive_high
}
set_property -dict {CONFIG.CONST_WIDTH 1 CONFIG.CONST_VAL 1} [get_bd_cells reset_aux_inactive_high]
set report [open [file join $root logs reset_connections.txt] w]
foreach name {proc_sys_reset_0 dpu_rst_300 dpu_rst_600} {
    set cell [get_bd_cells $name]
    if {[llength $cell] != 1} {error "Missing reset controller $name"}
    if {[get_property CONFIG.C_AUX_RESET_HIGH $cell] != 0} {error "Unexpected aux polarity: $name"}
    set pin [get_bd_pins $name/aux_reset_in]
    puts $report "BEFORE $name AUX=[get_bd_nets -quiet -of_objects $pin]"
    foreach net [get_bd_nets -quiet -of_objects $pin] {disconnect_bd_net $net $pin}
    connect_bd_net [get_bd_pins reset_aux_inactive_high/dout] $pin
    puts $report "AFTER $name AUX=[get_bd_nets -of_objects $pin] POLARITY=ACTIVE_LOW INACTIVE_VALUE=1"
    foreach input {ext_reset_in dcm_locked mb_debug_sys_rst slowest_sync_clk} {
        puts $report "$name/$input=[get_bd_nets -quiet -of_objects [get_bd_pins $name/$input]]"
    }
}
close $report
validate_bd_design -force
save_bd_design
generate_target all [get_files */design_1.bd]
write_hw_platform -force -file [file join $root platform fengyan_v015_extensible.xsa]
close_project
exit
