# Explicit future rebuild of an existing project copy; not run during collection.
set root [file dirname [file normalize [info script]]]
set which [lindex $argv 0]
if {![string match *2022.2* [version -short]]} {error "Vivado 2022.2 required"}
if {$which eq "static"} {
    set rel v014_main_project_20261024/project/fengyan_pl.xpr
} elseif {$which eq "final"} {
    set rel build/link/_x/link/vivado/vpl/prj/prj.xpr
} else {error "Usage: -tclargs static|final"}
open_project [file join $root $rel]
set bds [get_files -quiet */design_1.bd]
if {[llength $bds] != 1} {error "Expected exactly one design_1.bd"}
# Do not upgrade IP or change BD connectivity. Recreate output products from saved sources.
generate_target all $bds
reset_runs synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "Synthesis did not complete"}
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "Implementation did not complete"}
write_hw_platform -fixed -include_bit -force -file [file join $root rebuilt_${which}.xsa]
close_project
exit
