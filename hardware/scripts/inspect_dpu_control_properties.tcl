set script_dir [file dirname [file normalize [info script]]]
set work_root [file dirname $script_dir]
set project_path [file join $work_root v014_main_project_20261024 project fengyan_pl.xpr]

open_project $project_path
set bd_file [lindex [get_files -quiet */design_1.bd] 0]
open_bd_design $bd_file

foreach obj_name {
    dpu_control_interconnect
    dpu_control_interconnect/S00_AXI
    dpu_control_interconnect/M00_AXI
    control_smartconnect/M06_AXI
    dpu_control_placeholder/S_AXI
} {
    set obj [get_bd_cells -quiet $obj_name]
    if {[llength $obj] == 0} {
        set obj [get_bd_intf_pins -quiet $obj_name]
    }
    puts "=== $obj_name ==="
    if {[llength $obj] == 0} {
        puts "NOT_FOUND"
        continue
    }
    foreach prop [lsort [list_property $obj]] {
        if {[regexp -nocase {ADDR|WIDTH|NUM_MI|PFM} $prop]} {
            puts "$prop=[get_property -quiet $prop $obj]"
        }
    }
}

set probe_name probe_axi_bram_ctrl
foreach old [get_bd_cells -quiet $probe_name] {delete_bd_objs $old}
set probe [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 $probe_name]
puts "=== $probe_name ==="
foreach prop [lsort [list_property $probe]] {
    if {[regexp -nocase {ADDR|WIDTH|PROTOCOL|SINGLE_PORT} $prop]} {
        puts "$prop=[get_property -quiet $prop $probe]"
    }
}
foreach pin_name [list ${probe_name}/S_AXI ${probe_name}/BRAM_PORTA] {
    set pin [get_bd_intf_pins -quiet $pin_name]
    puts "=== $pin_name ==="
    foreach prop [lsort [list_property $pin]] {
        if {[regexp -nocase {ADDR|WIDTH|PROTOCOL} $prop]} {
            puts "$prop=[get_property -quiet $prop $pin]"
        }
    }
}
delete_bd_objs $probe

set intc_name probe_axi_intc
foreach old [get_bd_cells -quiet $intc_name] {delete_bd_objs $old}
set intc [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_intc:4.1 $intc_name]
puts "=== $intc_name ==="
foreach pin_name [list ${intc_name}/s_axi] {
    set pin [get_bd_intf_pins -quiet $pin_name]
    foreach prop [lsort [list_property $pin]] {
        if {[regexp -nocase {ADDR|WIDTH|PROTOCOL} $prop]} {
            puts "$prop=[get_property -quiet $prop $pin]"
        }
    }
}
delete_bd_objs $intc

close_project
exit
