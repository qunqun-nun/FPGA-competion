# Optional future v++ link using collected XPFM/XO/link.cfg. Not executed by collection.
param([string]$Vpp='F:\Xilinx\Vitis\2022.2\bin\v++.bat',[ValidatePattern('^[A-Z]$')][string]$Drive='W')
$ErrorActionPreference='Stop'
if (Test-Path -LiteralPath ($Drive+':\')) {throw "Drive $Drive occupied"}
if (!(Test-Path -LiteralPath $Vpp)) {throw "Vitis 2022.2 missing: $Vpp"}
& subst.exe ($Drive+':') $PSScriptRoot
if ($LASTEXITCODE -ne 0) {throw 'subst failed'}
$r=$Drive+':/'
$xpfm=$r+'platform/generated/fengyan_v015_zcu104/export/fengyan_v015_zcu104/fengyan_v015_zcu104.xpfm'
$xo=$r+'build/dpu_kernel/dpu_b4096.xo'
$cfg=$r+'config/link.cfg'
Push-Location ($Drive+':\')
try {
 foreach ($p in @($xpfm,$xo,$cfg)) {if (!(Test-Path -LiteralPath $p)) {throw "Missing $p"}}
 $out=$r+'rebuild_outputs/link'
 if (Test-Path -LiteralPath $out) {throw 'rebuild_outputs/link exists: select a fresh work copy to avoid overwriting results'}
 New-Item -ItemType Directory -Path $out -Force | Out-Null
 & $Vpp --link --target hw --platform $xpfm --config $cfg --save-temps --temp_dir ($out+'/_x') --log_dir ($out+'/logs') --output ($out+'/fengyan_v016_dpu.xclbin') $xo
 if ($LASTEXITCODE -ne 0) {throw "v++ failed: $LASTEXITCODE"}
} finally {Pop-Location; & subst.exe ($Drive+':') /D}
