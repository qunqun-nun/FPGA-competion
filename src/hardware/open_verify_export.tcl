# Existing projects only. Never launches synthesis/implementation or saves a project.
set root [file dirname [file normalize [info script]]]
set action [lindex $argv 0]
if {$action eq ""} {set action verify}
if {![string match *2022.2* [version -short]]} {error "Vivado 2022.2 required"}
set projects [list v014_main_project_20261024/project/fengyan_pl.xpr build/link/_x/link/vivado/vpl/prj/prj.xpr]
file mkdir [file join $root logs]
set report [open [file join $root logs vivado_source_paths.tsv] w]
puts $report "project\ttype\tpath\texists"
set missing 0
foreach rel $projects {
    if {$action eq "open-static" && [string match build/* $rel]} {continue}
    if {$action eq "open-final" && ![string match build/* $rel]} {continue}
    puts "OPEN_READ_ONLY=$rel"
    open_project -read_only [file join $root $rel]
    foreach f [get_files -all -quiet] {
        set name [get_property NAME $f]
        set ok [file exists $name]
        puts $report "$rel\tfile\t$name\t$ok"
        if {!$ok} {incr missing; puts "MISSING_SOURCE=$name"}
    }
    foreach repo [get_property ip_repo_paths [current_project]] {
        puts $report "$rel\tip_repo\t$repo\t[file isdirectory $repo]"
        if {![file isdirectory $repo]} {incr missing; puts "MISSING_REPO=$repo"}
    }
    puts "OPEN_OK=$rel"
    if {$action eq "export" && [string match build/* $rel]} {
        set bit [file join [get_property DIRECTORY [get_runs impl_1]] design_1_wrapper.bit]
        if {![file exists $bit]} {error "Existing final bitstream missing: $bit"}
        open_run impl_1
        write_hw_platform -fixed -include_bit -force -file [file join $root fengyan_v016_final_same_build.xsa]
        puts "SAME_BUILD_XSA_EXPORTED"
    }
    if {[string match open-* $action]} {close $report; return}
    close_project
}
close $report
puts "SOURCE_PATH_MISSING_COUNT=$missing"
if {$missing} {error "Missing file or repository paths; inspect logs/vivado_source_paths.tsv"}
exit
