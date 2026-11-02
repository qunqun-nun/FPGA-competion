$ErrorActionPreference = 'Stop'

$WorkRoot = Split-Path -Parent $PSScriptRoot
$ExistingMap = ((& subst.exe) | Where-Object { $_ -match '^C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/\:' }) -join "`n"
if (-not $ExistingMap) {
    & subst.exe V: $WorkRoot
} elseif (-not (Test-Path -LiteralPath 'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/README.md') -or
          (Get-FileHash -Algorithm SHA256 -LiteralPath 'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/README.md').Hash -ne
          (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $WorkRoot 'README.md')).Hash) {
    throw "V: is already mapped to another location: $ExistingMap"
}

$Vivado = 'F:\Xilinx\Vivado\2022.2\bin\vivado.bat'
$LogPath = 'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/logs\export_clean_xsa_console.log'
Push-Location 'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/logs'
& $Vivado -mode batch -source 'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/scripts\export_clean_extensible_xsa.tcl' -notrace 2>&1 |
    Tee-Object -FilePath $LogPath
$VivadoExitCode = $LASTEXITCODE
Pop-Location
if ($VivadoExitCode -ne 0) {
    throw "Clean XSA export failed with exit code $VivadoExitCode"
}

$Xsa = 'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/platform\fengyan_v015_extensible_clean.xsa'
if (-not (Test-Path -LiteralPath $Xsa)) {
    throw "Expected clean extensible XSA was not generated: $Xsa"
}
Write-Host "CLEAN_EXTENSIBLE_XSA=$Xsa"
