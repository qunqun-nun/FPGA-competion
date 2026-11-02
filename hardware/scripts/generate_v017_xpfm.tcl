# XSCT 2022.2. All inputs/output roots are relative to this script.
set root [file dirname [file dirname [file normalize [info script]]]]
set hw [file join $root platform fengyan_v017_extensible.xsa]
if {![file exists $hw]} {error "Missing V017 XSA: $hw"}
set out [file join $root platform generated_v017]
if {[file exists [file join $out fengyan_v017_zcu104]]} {error "V017 platform already exists; preserve it"}
platform create -name fengyan_v017_zcu104 -desc "V017 ZCU104 extensible platform: IDT clock reset M12 driven high" -hw $hw -out $out -no-boot-bsp
domain create -name xrt -proc psu_cortexa53 -os linux -runtime opencl
platform generate
puts "V017_XPFM_GENERATED_UNDER=$out"
exit
