# Verify all set_bus_skew constraints in the final routed design.

set script_dir [file dirname [file normalize [info script]]]
set work_root [file dirname $script_dir]
set checkpoint [file join $work_root build link _x link vivado vpl prj prj.runs impl_1 design_1_wrapper_routed.dcp]
set report_path [file join $work_root build final_checkpoint_reports design_1_wrapper_bus_skew.rpt]

if {![file exists $checkpoint]} {
    error "Missing routed checkpoint: $checkpoint"
}

open_checkpoint $checkpoint
report_bus_skew -warn_on_violation -file $report_path
close_design
puts "BUS_SKEW_REPORT=$report_path"
exit
