# Refresh metadata only after RTL freeze; do not change ports/parameters.
set root [file dirname [file dirname [file normalize [info script]]]]
set staged [file join $root scheduler_fix package_check component.xml]
if {![file exists $staged]} {error "Missing staged core"}
set core [ipx::open_core $staged]
ipx::update_checksums $core
ipx::check_integrity -quiet $core
ipx::save_core $core
puts "SCHEDULER_PACKAGE_CHECKSUMS_UPDATED"
exit
