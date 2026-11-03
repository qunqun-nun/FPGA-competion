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

$Xsct = 'F:\Xilinx\Vitis\2022.2\bin\xsct.bat'
$LogPath = 'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/logs\generate_clean_xpfm.log'
& $Xsct 'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/scripts\generate_clean_xpfm.tcl' 2>&1 | Tee-Object -FilePath $LogPath
if ($LASTEXITCODE -ne 0) {
    throw "Clean XPFM generation failed with exit code $LASTEXITCODE"
}

$Xpfm = 'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/platform\clean_generated\fengyan_v015_zcu104_clean\export\fengyan_v015_zcu104_clean\fengyan_v015_zcu104_clean.xpfm'
if (-not (Test-Path -LiteralPath $Xpfm)) {
    throw "Expected clean XPFM was not generated: $Xpfm"
}
Write-Host "CLEAN_XPFM=$Xpfm"
