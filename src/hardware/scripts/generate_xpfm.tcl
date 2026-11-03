# XSCT script: generate a Vitis platform from the extensible V0.15 XSA.

set script_dir [file dirname [file normalize [info script]]]
set work_root [file dirname $script_dir]
set xsa_path [file join $work_root platform fengyan_v015_extensible.xsa]
set platform_out [file join $work_root platform generated]

if {![file exists $xsa_path]} {
    error "Missing extensible XSA: $xsa_path"
}

file mkdir $platform_out
platform create -name fengyan_v015_zcu104 -desc "Fengyan V0.15 extensible ZCU104 platform with static video/SAD/fusion/display design" -hw $xsa_path -out $platform_out -no-boot-bsp
domain create -name xrt -proc psu_cortexa53 -os linux -runtime opencl
platform generate
puts "V015_XPFM_GENERATED_UNDER=$platform_out"
exit
