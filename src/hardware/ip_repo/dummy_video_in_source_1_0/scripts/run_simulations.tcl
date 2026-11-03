set project_file {C:/Users/Admin/Desktop/ip_repo/edit_dummy_video_in_source_v1_0.xpr}
set report_dir {C:/Users/Admin/Desktop/ip_repo/dummy_video_in_source_1_0/reports/stage1}
set xsim_log {C:/Users/Admin/Desktop/ip_repo/edit_dummy_video_in_source_v1_0.sim/sim_1/behav/xsim/simulate.log}
file mkdir $report_dir

proc run_testbench {top_name expected_marker report_dir xsim_log} {
    set_property top $top_name [get_filesets sim_1]
    update_compile_order -fileset sim_1
    launch_simulation -simset sim_1 -mode behavioral
    run all
    close_sim
    set input [open $xsim_log r]
    set log_text [read $input]
    close $input
    file copy -force $xsim_log "$report_dir/${top_name}.log"
    if {[string first $expected_marker $log_text] < 0} {
        error "Simulation $top_name did not emit expected marker: $expected_marker"
    }
    puts "VERIFIED_$expected_marker"
}

open_project $project_file
set protocol_tb {C:/Users/Admin/Desktop/ip_repo/dummy_video_in_source_1_0/tb/tb_formal_pl_video_in_protocol.sv}
if {[llength [get_files -quiet $protocol_tb]] == 0} {
    add_files -fileset sim_1 -norecurse $protocol_tb
}
run_testbench tb_dummy_video_in_source TB_DUMMY_VIDEO_IN_SOURCE_PASS $report_dir $xsim_log
run_testbench tb_dummy_pl_video_in_integration TB_DUMMY_PL_VIDEO_IN_INTEGRATION_PASS $report_dir $xsim_log
run_testbench tb_formal_pl_video_in_protocol {FORMAL_PL_VIDEO_IN_PROTOCOL_TEST PASS} $report_dir $xsim_log
close_project
exit
