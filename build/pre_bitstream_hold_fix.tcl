# AMD UG904 2022.2: post-route physical optimization; no timing exceptions.
# Called inside the genuine Vitis implementation before writing its bitstream.
puts "V017_POSTROUTE_HOLDFIX_BEGIN"
set fy_hold [get_timing_paths -delay_type min -max_paths 1]
if {[llength $fy_hold] == 0} {error "No hold timing paths found"}
set fy_hold_before [get_property SLACK $fy_hold]
puts "V017_HOLD_BEFORE=$fy_hold_before"
if {$fy_hold_before < 0} {
    report_timing -delay_type min -max_paths 10 -file v017_hold_before.rpt
    phys_opt_design -hold_fix
    set fy_hold [get_timing_paths -delay_type min -max_paths 1]
    if {[get_property SLACK $fy_hold] < 0} {
        phys_opt_design -aggressive_hold_fix
    }
}
set fy_hold_after [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
set fy_setup_after [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
puts "V017_HOLD_AFTER=$fy_hold_after SETUP_AFTER=$fy_setup_after"
report_timing_summary -max_paths 10 -file v017_postroute_holdfix_timing.rpt
if {$fy_hold_after < 0 || $fy_setup_after < 0} {error "Post-route timing remains negative"}
# Keep the implemented checkpoint and Vitis-produced bitstream identical.
write_checkpoint -force design_1_wrapper_routed.dcp
puts "V017_POSTROUTE_HOLDFIX_PASS"
