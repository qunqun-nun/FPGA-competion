set project_name {edit_dummy_video_in_source_v1_0}
set project_dir  {C:/Users/Admin/Desktop/ip_repo}
set rtl_file     {C:/Users/Admin/Desktop/ip_repo/dummy_video_in_source_1_0/src/dummy_video_in_source.v}
set unit_tb      {C:/Users/Admin/Desktop/ip_repo/dummy_video_in_source_1_0/tb/tb_dummy_video_in_source.sv}
set integ_tb     {C:/Users/Admin/Desktop/ip_repo/dummy_video_in_source_1_0/tb/tb_dummy_pl_video_in_integration.sv}
set protocol_tb  {C:/Users/Admin/Desktop/ip_repo/dummy_video_in_source_1_0/tb/tb_formal_pl_video_in_protocol.sv}
set video_in_rtl {C:/Users/Admin/Desktop/ip_repo/pl_video_in_1_0/src/pl_video_in.v}

create_project $project_name $project_dir -part xczu7ev-ffvc1156-2-e -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

add_files -fileset sources_1 -norecurse $rtl_file
set_property top dummy_video_in_source [get_filesets sources_1]

add_files -fileset sim_1 -norecurse [list $unit_tb $integ_tb $protocol_tb $video_in_rtl]
set_property file_type SystemVerilog [get_files -quiet [list $unit_tb $integ_tb]]
set_property top tb_dummy_video_in_source [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "EDIT_PROJECT_CREATED=[get_property directory [current_project]]/$project_name.xpr"
puts "DESIGN_TOP=[get_property top [get_filesets sources_1]]"
puts "SIM_TOP=[get_property top [get_filesets sim_1]]"
close_project
exit
