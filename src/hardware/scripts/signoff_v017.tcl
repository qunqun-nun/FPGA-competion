set root [file dirname [file dirname [file normalize [info script]]]]
if {![string match *2022.2* [version -short]]} {error "Vivado 2022.2 required"}
set prj [file join $root v017_link _x link vivado vpl prj prj.xpr]
set out [file join $root v017_signoff]
file mkdir $out
open_project -read_only $prj
open_run impl_1
set p [get_ports IDT_8T49N241_RST_OUT]
if {[llength $p]!=1} {error "Missing IDT reset release output"}
if {[get_property PACKAGE_PIN $p] ne "M12" || [get_property IOSTANDARD $p] ne "LVCMOS33"} {error "Wrong IDT pin constraints"}
set f [open [file join $out pin_check.txt] w]
puts $f "IDT_RESET_PIN=[get_property PACKAGE_PIN $p]\nIOSTANDARD=[get_property IOSTANDARD $p]"
close $f
report_timing_summary -file [file join $out timing.rpt]
report_bus_skew -warn_on_violation -file [file join $out bus_skew.rpt]
report_drc -file [file join $out drc.rpt]
report_utilization -file [file join $out utilization.rpt]
set setup [get_timing_paths -delay_type max -max_paths 1]
set hold [get_timing_paths -delay_type min -max_paths 1]
set f [open [file join $out timing_check.txt] w]
puts $f "WNS=[get_property SLACK $setup]\nWHS=[get_property SLACK $hold]"
close $f
if {[get_property SLACK $setup]<0 || [get_property SLACK $hold]<0} {error "Timing failed"}
if {[llength [get_drc_violations -filter {SEVERITY == Error}]]>0} {error "DRC errors"}
write_hw_platform -fixed -include_bit -force -file [file join $out fengyan_v017_final.xsa]
close_project
exit
