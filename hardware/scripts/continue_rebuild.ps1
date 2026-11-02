$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
Push-Location 'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/logs'
try {
    $exportLog = Join-Path $taskRoot 'logs\vivado.log'
    while (-not ((Get-Content -LiteralPath $exportLog -Tail 12 -ErrorAction SilentlyContinue) -match 'Exiting Vivado')) {
        Start-Sleep -Seconds 10
    }
    if (-not (Test-Path 'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/platform\fengyan_v015_extensible.xsa')) {throw 'Platform export did not complete'}
    & 'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/scripts\sanitize_extensible_xsa.ps1' -XsaPath 'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/platform\fengyan_v015_extensible.xsa'
    & 'F:\Xilinx\Vitis\2022.2\bin\xsct.bat' 'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/scripts\generate_xpfm.tcl' 2>&1 | Tee-Object 'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/logs\generate_xpfm.log'
    if ($LASTEXITCODE -ne 0) {throw 'XPFM failed'}
    & 'F:\Xilinx\Vitis\2022.2\bin\v++.bat' --link --target hw --platform 'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/platform\generated\fengyan_v015_zcu104\export\fengyan_v015_zcu104\fengyan_v015_zcu104.xpfm' --config 'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/config\link.cfg' --save-temps --temp_dir 'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/build\link\_x' --log_dir 'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/build\link\logs' --output 'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/build\link\fengyan_v016_dpu.xclbin' 'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/build\dpu_kernel\dpu_b4096.xo' 2>&1 | Tee-Object 'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/logs\vpp_link.log'
    if ($LASTEXITCODE -ne 0) {throw 'Vitis link failed'}
    Write-Output 'BUILD_COMPLETE_PENDING_ACCEPTANCE'
} finally {Pop-Location}
