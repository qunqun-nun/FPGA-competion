create_project -in_memory probe_axi_intc -part xczu7ev-ffvc1156-2-e
create_bd_design probe
set intc [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_intc:4.1 probe_axi_intc]
set pin [get_bd_intf_pins probe_axi_intc/s_axi]
puts "INTC_ADDR_WIDTH=[get_property CONFIG.ADDR_WIDTH $pin]"
puts "INTC_DATA_WIDTH=[get_property CONFIG.DATA_WIDTH $pin]"
puts "INTC_PROTOCOL=[get_property CONFIG.PROTOCOL $pin]"
puts "INTC_PINS=[get_bd_pins -quiet probe_axi_intc/*]"
exit
