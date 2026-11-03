# Generate an independent Vitis platform from the clean, digest-valid XSA.

set script_dir [file dirname [file normalize [info script]]]
set work_root [file dirname $script_dir]
set xsa_path [file join $work_root platform fengyan_v015_extensible_clean.xsa]
set platform_out [file join $work_root platform clean_generated]

if {![file exists $xsa_path]} {
    error "Missing clean extensible XSA: $xsa_path"
}

file mkdir $platform_out
platform create -name fengyan_v015_zcu104_clean \
    -desc "Fengyan V0.15 digest-valid extensible ZCU104 platform" \
    -hw $xsa_path -out $platform_out -no-boot-bsp
domain create -name xrt -proc psu_cortexa53 -os linux -runtime opencl
platform generate
puts "CLEAN_XPFM_GENERATED_UNDER=$platform_out"
exit
