param(
 [string]$Vivado='F:\Xilinx\Vivado\2022.2\bin\vivado.bat',
 [string]$Vitis='F:\Xilinx\Vitis\2022.2\bin',
 [ValidateSet('platform','link')][string]$FromStep='platform'
)
$ErrorActionPreference='Stop'
if(-not('FyV017PathMap' -as [type])) {
 Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
using System.Text;
public class FyV017PathMap {
 [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
 public static extern uint QueryDosDevice(string name, StringBuilder target, int length);
}
'@
}
function MappedRoot {
 $buffer=[Text.StringBuilder]::new(32768)
 if([FyV017PathMap]::QueryDosDevice('W:',$buffer,$buffer.Capacity) -eq 0) {return ''}
 $devicePath=$buffer.ToString().Split([char]0)[0]
 if(-not $devicePath.StartsWith('\??\')) {return ''}
 return $devicePath.Substring(4)
}
$buildRoot=$PSScriptRoot
if($buildRoot -match '^W:\\?$') {
 $buildRoot=MappedRoot
 if(-not $buildRoot) {throw 'W: is not a subst mapping'}
}
$deliveryRoot=Split-Path $buildRoot
function State([string]$stage,[string]$status) {
 @{stage=$stage;status=$status;time=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss');board_verified=$false} |
 ConvertTo-Json | Set-Content -LiteralPath (Join-Path $buildRoot 'build_status.json') -Encoding utf8
 Write-Host "V017_STAGE=$stage STATUS=$status"
}
function Check([string]$what) {if($LASTEXITCODE -ne 0) {throw "$what failed: exit $LASTEXITCODE"}}
$mapped=$false
if(-not(Test-Path 'W:\')) { & subst.exe W: $buildRoot; Check 'subst'; $mapped=$true }
$existingMapping=MappedRoot
if(-not $existingMapping -or $existingMapping.TrimEnd('\') -ne $buildRoot.TrimEnd('\')) {throw 'W: belongs to a different directory'}
if((Get-Content -LiteralPath 'W:\deployment.json' -ErrorAction SilentlyContinue)) {throw 'W mapping is not a rebuild folder'}
if(-not(Test-Path 'W:\scripts\export_v017_after_package.tcl')) {throw 'W is not this rebuild folder'}
Push-Location 'W:\'
try {
 if($FromStep -eq 'platform') {
  State 'PLATFORM_EXPORT' 'RUNNING'
  & $Vivado -mode batch -notrace -source 'W:/scripts/export_v017_after_package.tcl' -log 'W:/logs/v017_final_platform_export.log' -journal 'W:/logs/v017_final_platform_export.jou'
  Check 'Vivado platform export'
  State 'XPFM_GENERATE' 'RUNNING'
  & (Join-Path $Vitis 'xsct.bat') 'W:/scripts/generate_v017_xpfm.tcl'
  Check 'XSCT platform'
 }
 & python (Join-Path $deliveryRoot 'tools\validate_v017_inputs.py')
 Check 'Platform source identity'
 State 'VITIS_LINK' 'RUNNING'
 & (Join-Path $Vitis 'v++.bat') --link --target hw --no_ip_cache --platform 'W:/platform/generated_v017/fengyan_v017_zcu104/export/fengyan_v017_zcu104/fengyan_v017_zcu104.xpfm' --config 'W:/config/link_v017.cfg' --save-temps --temp_dir 'W:/v017_link/_x' --log_dir 'W:/v017_link/logs' --output 'W:/v017_link/fengyan_v017_dpu.xclbin' 'W:/build/dpu_kernel/dpu_b4096.xo'
 Check 'Vitis hardware link'
 State 'SIGNOFF_AND_PACKAGE' 'RUNNING'
 & python (Join-Path $deliveryRoot 'tools\finish_v017.py') --vivado $Vivado --xclbinutil (Join-Path $Vitis 'xclbinutil.bat')
 Check 'Same-build checks and ZIP packaging'
 State 'PACKAGE_READY' 'PASS_BOARD_ACCEPTANCE_PENDING'
} catch {
 State 'STOPPED' ('FAILED: '+$_.Exception.Message)
 throw
} finally {
 Pop-Location
 if($mapped) {& subst.exe W: /D}
}
