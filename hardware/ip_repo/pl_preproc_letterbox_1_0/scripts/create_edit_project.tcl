set project_name {edit_pl_preproc_letterbox_v1_0}
set project_dir  {C:/Users/Admin/Desktop/ip_repo}
set ip_root      {C:/Users/Admin/Desktop/ip_repo/pl_preproc_letterbox_1_0}
set rtl_file     {C:/Users/Admin/Desktop/ip_repo/pl_preproc_letterbox_1_0/src/pl_preproc_letterbox.sv}
set unit_tb      {C:/Users/Admin/Desktop/ip_repo/pl_preproc_letterbox_1_0/tb/tb_pl_preproc_letterbox.sv}
set protocol_tb  {C:/Users/Admin/Desktop/ip_repo/pl_preproc_letterbox_1_0/tb/tb_pl_preproc_letterbox_protocol.sv}

create_project $project_name $project_dir -part xczu7ev-ffvc1156-2-e -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

add_files -fileset sources_1 -norecurse $rtl_file
set_property top pl_preproc_letterbox [get_filesets sources_1]

add_files -fileset sim_1 -norecurse [list $unit_tb $protocol_tb]
set_property file_type SystemVerilog [get_files -quiet [list $unit_tb $protocol_tb]]
set_property top tb_pl_preproc_letterbox [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "EDIT_PROJECT_CREATED=[file join $project_dir ${project_name}.xpr]"
puts "DESIGN_TOP=[get_property top [get_filesets sources_1]]"
puts "SIM_TOP=[get_property top [get_filesets sim_1]]"
close_project
exit
