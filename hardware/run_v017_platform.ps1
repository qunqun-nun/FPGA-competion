param([ValidateSet('patch','export','xpfm')][string]$Stage='patch',[string]$XilinxRoot='F:\Xilinx',[ValidatePattern('^[A-Z]$')][string]$Drive='W')
$ErrorActionPreference='Stop'
if (Test-Path -LiteralPath ($Drive+':\')) {throw "Drive $Drive occupied"}
& subst.exe ($Drive+':') $PSScriptRoot
if ($LASTEXITCODE -ne 0) {throw 'subst failed'}
Push-Location ($Drive+':\')
try {
 $r=$Drive+':/'
 if ($Stage -in @('patch','export')) {
  $script=if ($Stage -eq 'patch') {'patch_v017_idt_reset.tcl'} else {'export_v017_platform.tcl'}
  & (Join-Path $XilinxRoot 'Vivado\2022.2\bin\vivado.bat') -mode batch -source ($r+'scripts/'+$script) -log ($r+'logs/v017_platform_'+$Stage+'.log') -journal ($r+'logs/v017_platform_'+$Stage+'.jou') -notrace
 } else {
  & (Join-Path $XilinxRoot 'Vitis\2022.2\bin\xsct.bat') ($r+'scripts/generate_v017_xpfm.tcl') 2>&1 | Tee-Object -FilePath ($r+'logs/v017_xpfm.log')
 }
 if ($LASTEXITCODE -ne 0) {throw "Platform $Stage failed: $LASTEXITCODE"}
} finally {Pop-Location; & subst.exe ($Drive+':') /D}
