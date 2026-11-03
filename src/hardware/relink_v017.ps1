param([string]$Vpp='F:\Xilinx\Vitis\2022.2\bin\v++.bat')
$ErrorActionPreference='Stop'
if(Test-Path 'W:\') {throw 'W: occupied; close the other mapped Vivado session first'}
& subst.exe W: $PSScriptRoot
try {
 if($LASTEXITCODE -ne 0) {throw 'subst failed'}
 if(Test-Path 'W:/v017_relink') {throw 'v017_relink exists; preserve it and choose a fresh work copy'}
 Push-Location 'W:\'
 try {
  & $Vpp --link --target hw --no_ip_cache --platform 'W:/platform/generated_v017/fengyan_v017_zcu104/export/fengyan_v017_zcu104/fengyan_v017_zcu104.xpfm' --config 'W:/config/link_v017.cfg' --save-temps --temp_dir 'W:/v017_relink/_x' --log_dir 'W:/v017_relink/logs' --output 'W:/v017_relink/fengyan_v017_dpu.xclbin' 'W:/build/dpu_kernel/dpu_b4096.xo'
  if($LASTEXITCODE -ne 0) {throw 'Vitis link failed'}
 } finally {Pop-Location}
} finally {& subst.exe W: /D}
