set project_file {C:/Users/Admin/Desktop/ip_repo/edit_dummy_video_in_source_v1_0.xpr}

proc require_file {path label} {
    set result [get_files -quiet $path]
    if {[llength $result] != 1} {
        error "Editable project is missing $label: $path"
    }
}

open_project $project_file
if {[get_property part [current_project]] ne {xczu7ev-ffvc1156-2-e}} {
    error "Unexpected project part: [get_property part [current_project]]"
}
if {[get_property top [get_filesets sources_1]] ne {dummy_video_in_source}} {
    error "Unexpected design top: [get_property top [get_filesets sources_1]]"
}

require_file \
    {C:/Users/Admin/Desktop/ip_repo/dummy_video_in_source_1_0/src/dummy_video_in_source.v} \
    {dummy RTL source}
require_file \
    {C:/Users/Admin/Desktop/ip_repo/dummy_video_in_source_1_0/tb/tb_dummy_video_in_source.sv} \
    {unit testbench}
require_file \
    {C:/Users/Admin/Desktop/ip_repo/dummy_video_in_source_1_0/tb/tb_dummy_pl_video_in_integration.sv} \
    {integration testbench}
require_file \
    {C:/Users/Admin/Desktop/ip_repo/dummy_video_in_source_1_0/tb/tb_formal_pl_video_in_protocol.sv} \
    {protocol regression testbench}
require_file \
    {C:/Users/Admin/Desktop/ip_repo/pl_video_in_1_0/src/pl_video_in.v} \
    {pl_video_in integration source}

puts "EDITABLE_PROJECT_PART=[get_property part [current_project]]"
puts "EDITABLE_PROJECT_DESIGN_TOP=[get_property top [get_filesets sources_1]]"
puts "EDITABLE_PROJECT_SIM_TOP=[get_property top [get_filesets sim_1]]"
puts "EDITABLE_PROJECT_VERIFICATION_PASS"
close_project
exit
