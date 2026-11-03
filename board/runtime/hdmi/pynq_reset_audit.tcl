# Read-only routed checkpoint inspection. No implementation or bit generation.
set checkpoint [lindex $argv 0]
open_checkpoint $checkpoint
puts "RESET_AUDIT_UNUSEDPIN=[get_property BITSTREAM.CONFIG.UNUSEDPIN [current_design]]"
puts "RESET_AUDIT_M12_PORTS=[get_ports -quiet -filter {PACKAGE_PIN == M12}]"
puts "RESET_AUDIT_M12_PACKAGE=[get_package_pins -quiet M12]"
puts "RESET_AUDIT_IDT_RESET_PORTS=[get_ports -quiet *IDT*RST*]"
puts "RESET_AUDIT_TX_EN_PIN=[get_property PACKAGE_PIN [get_ports TX_EN_OUT]]"
close_design
exit
