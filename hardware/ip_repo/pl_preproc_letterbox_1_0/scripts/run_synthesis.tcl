set script_dir [file dirname [file normalize [info script]]]
set ip_root [file normalize [file join $script_dir ..]]
set report_dir [file join $ip_root reports]
set part_name xczu7ev-ffvc1156-2-e
set rtl_file [file join $ip_root src pl_preproc_letterbox.sv]
file mkdir $report_dir

create_project -in_memory -part $part_name
read_verilog -sv $rtl_file
synth_design -mode out_of_context -top pl_preproc_letterbox -part $part_name
write_checkpoint -force [file join $report_dir pl_preproc_letterbox_ooc.dcp]
report_utilization -file [file join $report_dir synthesis_utilization.rpt]
report_timing_summary -file [file join $report_dir synthesis_timing_summary.rpt]
puts "LETTERBOX_SYNTHESIS_PASS"
close_project
exit
