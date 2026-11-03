set root [file dirname [file dirname [file normalize [info script]]]]
set project [file join $root build output _x link vivado vpl prj prj.xpr]
if {![file exists $project]} {error "Run build/rebuild.py first"}
open_project $project
open_run impl_1
set out [file join $root build output delivery]
file mkdir $out
report_timing_summary -file [file join $out timing.rpt]
report_utilization -file [file join $out utilization.rpt]
report_drc -file [file join $out drc.rpt]
write_hw_platform -fixed -include_bit -force -file [file join $out fengyan.xsa]
file copy -force [file join $root build output fengyan.xclbin] [file join $out fengyan.xclbin]
set bits [glob -nocomplain [file join [get_property DIRECTORY [get_runs impl_1]] *.bit]]
if {[llength $bits] != 1} {error "Expected one bitstream"}
file copy -force [lindex $bits 0] [file join $out fengyan.bit]
set hwh [file join [file dirname $project] prj.gen sources_1 bd design_1 hw_handoff design_1.hwh]
if {![file exists $hwh]} {error "Matching HWH missing"}
file copy -force $hwh [file join $out fengyan.hwh]
close_project
exit
