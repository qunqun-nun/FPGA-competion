param(
 [ValidateSet('verify','export','open-static','open-final','rebuild-static','rebuild-final')][string]$Action='verify',
 [string]$Vivado='F:\Xilinx\Vivado\2022.2\bin\vivado.bat',
 [ValidatePattern('^[A-Z]$')][string]$Drive='W'
)
$ErrorActionPreference='Stop'
if (!(Test-Path -LiteralPath $Vivado)) {throw "Vivado 2022.2 not found: $Vivado"}
if (Test-Path -LiteralPath ($Drive+':\')) {throw "Drive $Drive is occupied; select another -Drive"}
& subst.exe ($Drive+':') $PSScriptRoot
if ($LASTEXITCODE -ne 0) {throw 'subst failed'}
$mapped=$Drive+':/'
New-Item -ItemType Directory -Path (Join-Path $PSScriptRoot 'logs') -Force | Out-Null
Push-Location ($Drive+':\')
try {
 $mode=if ($Action -like 'open-*') {'gui'} else {'batch'}
 $script='open_verify_export.tcl'
 $argument=$Action
 if ($Action -like 'rebuild-*') {$script='rebuild_existing.tcl'; $argument=$Action.Substring(8)}
 & $Vivado -mode $mode -source ($mapped+$script) -log ($mapped+'logs/'+$Action+'.log') -journal ($mapped+'logs/'+$Action+'.jou') -notrace -tclargs $argument
 $code=$LASTEXITCODE
 if ($code -ne 0) {throw "Vivado failed ($code); see logs/$Action.log"}
} finally {
 Pop-Location
 & subst.exe ($Drive+':') /D
}
