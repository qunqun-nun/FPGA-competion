# Generate final sign-off reports from the routed checkpoint produced by v++.

set script_dir [file dirname [file normalize [info script]]]
set work_root [file dirname $script_dir]
set checkpoint [file join $work_root build link _x link vivado vpl prj prj.runs impl_1 design_1_wrapper_routed.dcp]
set report_dir [file join $work_root build final_checkpoint_reports]

if {![file exists $checkpoint]} {
    error "Missing routed checkpoint: $checkpoint"
}
file mkdir $report_dir

open_checkpoint $checkpoint
report_drc -file [file join $report_dir design_1_wrapper_drc_routed.rpt]
report_route_status -file [file join $report_dir design_1_wrapper_route_status.rpt]
report_bus_skew -warn_on_violation -file [file join $report_dir design_1_wrapper_bus_skew.rpt]
report_cdc -details -file [file join $report_dir design_1_wrapper_cdc.rpt]
report_utilization -hierarchical -file [file join $report_dir design_1_wrapper_utilization_hierarchical.rpt]
report_timing_summary -delay_type min_max -max_paths 20 -warn_on_violation \
    -file [file join $report_dir design_1_wrapper_timing_summary_signoff.rpt]
close_design
puts "FINAL_REPORT_DIR=$report_dir"
exit
