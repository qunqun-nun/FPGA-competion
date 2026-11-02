set project_file {C:/Users/Admin/Desktop/project_1/project_1.xpr}
set bd_file {C:/Users/Admin/Desktop/project_1/project_1.srcs/sources_1/bd/design_1/design_1.bd}
set expected_vlnv {xilinx.com:user:pl_video_in:1.0}

open_project $project_file
update_ip_catalog
report_ip_status
open_bd_design $bd_file

set cells [get_bd_cells -quiet -filter "VLNV == $expected_vlnv"]
if {[llength $cells] != 1} {
    error "Expected one $expected_vlnv cell, got: $cells"
}
set cell [lindex $cells 0]
if {[get_property CONFIG.IMAGE_WIDTH $cell] != 640 ||
    [get_property CONFIG.IMAGE_HEIGHT $cell] != 480} {
    error "Unexpected pl_video_in dimensions"
}

validate_bd_design
puts "PROJECT1_PL_VIDEO_IN_CELL=$cell"
puts "PROJECT1_PL_VIDEO_IN_WIDTH=[get_property CONFIG.IMAGE_WIDTH $cell]"
puts "PROJECT1_PL_VIDEO_IN_HEIGHT=[get_property CONFIG.IMAGE_HEIGHT $cell]"
puts {PROJECT1_BLOCK_DESIGN_VALIDATION_PASS}
close_bd_design [current_bd_design]
close_project
exit
