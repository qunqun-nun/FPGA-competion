param([Parameter(Mandatory=$true)][string]$Hwh)
$ErrorActionPreference='Stop'
[xml]$doc=Get-Content -LiteralPath $Hwh -Raw
$modules=@($doc.SelectNodes('//MODULE'))
foreach($name in @('proc_sys_reset_0','dpu_rst_300','dpu_rst_600')) {
 $m=@($modules|Where-Object {$_.INSTANCE -eq $name})
 if($m.Count -ne 1){throw "Missing reset $name"}
 $pol=$m[0].SelectSingleNode("PARAMETERS/PARAMETER[@NAME='C_AUX_RESET_HIGH']")
 $aux=$m[0].SelectSingleNode("PORTS/PORT[@NAME='aux_reset_in']")
 if($pol.VALUE -ne '0' -or $aux.SIGNAME -notmatch 'reset_aux_inactive_high'){throw "RESET_AUDIT_FAIL $name"}
 Write-Output "RESET_CONNECTION_PASS $name polarity=LOW net=$($aux.SIGNAME)"
}
$one=@($modules|Where-Object {$_.INSTANCE -eq 'reset_aux_inactive_high'})
if($one.Count -ne 1 -or $one[0].SelectSingleNode("PARAMETERS/PARAMETER[@NAME='CONST_VAL']").VALUE -notin @('1','0x1','0x00000001')){throw 'Constant is not one'}
$dpu=@($modules|Where-Object {$_.MODTYPE -eq 'DPUCZDX8G'})
if($dpu.Count -ne 1){throw 'Expected exactly one DPU'}
Write-Output "DPU_COUNT_PASS instance=$($dpu[0].INSTANCE)"
Write-Output 'FINAL_HWH_AUDIT_PASS'
