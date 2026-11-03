# Re-export the already validated V0.15 extensible platform without modifying
# the XSA archive after Vivado writes its integrity digest.

set script_dir [file dirname [file normalize [info script]]]
set work_root [file dirname $script_dir]
set project_path [file join $work_root v014_main_project_20261024 project fengyan_pl.xpr]
set output_path [file join $work_root platform fengyan_v015_extensible_clean.xsa]
set report_path [file join $work_root logs clean_xsa_export_validation.txt]

open_project $project_path
set bd_file [get_files -quiet */design_1.bd]
if {[llength $bd_file] != 1} {
    error "Expected exactly one design_1.bd, found [llength $bd_file]"
}
open_bd_design $bd_file

validate_bd_design -force
save_bd_design
generate_target all $bd_file
update_compile_order -fileset sources_1

set fp [open $report_path w]
puts $fp "VIVADO=[version -short]"
puts $fp "PROJECT=$project_path"
puts $fp "PFM_NAME=[get_property PFM_NAME $bd_file]"
puts $fp "STATIC_DPU_COUNT=[llength [get_bd_cells -quiet DPUCZDX8G_0]]"
puts $fp "DYNAMIC_CONTROL=[get_property PFM.AXI_PORT [get_bd_cells dpu_control_interconnect]]"
puts $fp "BD_VALIDATION=PASS"
close $fp

write_hw_platform -force -file $output_path
close_project
puts "CLEAN_EXTENSIBLE_XSA=$output_path"
exit
