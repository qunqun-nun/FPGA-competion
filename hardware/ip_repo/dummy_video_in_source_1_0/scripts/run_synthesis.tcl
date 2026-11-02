set project_file {C:/Users/Admin/Desktop/ip_repo/edit_dummy_video_in_source_v1_0.xpr}
set report_dir  {C:/Users/Admin/Desktop/ip_repo/dummy_video_in_source_1_0/reports}

open_project $project_file
update_compile_order -fileset sources_1
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1

set status [get_property STATUS [get_runs synth_1]]
set progress [get_property PROGRESS [get_runs synth_1]]
puts "DUMMY_SYNTH_STATUS=$status"
puts "DUMMY_SYNTH_PROGRESS=$progress"

if {$status ne {synth_design Complete!}} {
    close_project
    error "Synthesis failed with status: $status"
}

open_run synth_1
report_utilization -file $report_dir/synthesis_utilization.rpt
report_timing_summary -file $report_dir/synthesis_timing_summary.rpt
puts "DUMMY_SYNTHESIS_PASS"
close_project
exit
