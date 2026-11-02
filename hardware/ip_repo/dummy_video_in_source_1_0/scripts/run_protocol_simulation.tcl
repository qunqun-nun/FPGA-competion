set project_file {C:/Users/Admin/Desktop/ip_repo/edit_dummy_video_in_source_v1_0.xpr}
set protocol_tb {C:/Users/Admin/Desktop/ip_repo/dummy_video_in_source_1_0/tb/tb_formal_pl_video_in_protocol.sv}

open_project $project_file
if {[llength [get_files -quiet $protocol_tb]] == 0} {
    add_files -fileset sim_1 -norecurse $protocol_tb
}
set_property top tb_formal_pl_video_in_protocol [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation -simset sim_1 -mode behavioral
run all
close_sim
close_project
exit
