$ErrorActionPreference = 'Stop'

$WorkRoot = Split-Path -Parent $PSScriptRoot
$MappedRoot = $WorkRoot + [IO.Path]::DirectorySeparatorChar
$ExistingMap = ((& subst.exe) | Where-Object { $_ -match '^C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/\:' }) -join "`n"
if (-not $ExistingMap) {
    & subst.exe V: $WorkRoot
} elseif (-not (Test-Path -LiteralPath 'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/README.md') -or
          (Get-FileHash -Algorithm SHA256 -LiteralPath 'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/README.md').Hash -ne
          (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $WorkRoot 'README.md')).Hash) {
    throw "V: is already mapped to another location: $ExistingMap"
}
$Xpfm = Join-Path $MappedRoot 'platform\generated\fengyan_v015_zcu104\export\fengyan_v015_zcu104\fengyan_v015_zcu104.xpfm'
$Xo = Join-Path $MappedRoot 'build\dpu_kernel\dpu_b4096.xo'
$Cfg = Join-Path $MappedRoot 'config\link.cfg'
$OutDir = Join-Path $MappedRoot 'build\link'
$LogDir = Join-Path $MappedRoot 'logs'
$Vpp = 'F:\Xilinx\Vitis\2022.2\bin\v++.bat'

foreach ($Required in @($Xpfm, $Xo, $Cfg, $Vpp)) {
    if (-not (Test-Path -LiteralPath $Required)) { throw "Missing required link input: $Required" }
}

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$Xclbin = Join-Path $OutDir 'fengyan_v015_dpu.xclbin'

& $Vpp --link --target hw --platform $Xpfm --config $Cfg --save-temps --temp_dir (Join-Path $OutDir '_x') --log_dir (Join-Path $OutDir 'logs') --output $Xclbin $Xo 2>&1 | Tee-Object -FilePath (Join-Path $LogDir 'vpp_link.log')
if ($LASTEXITCODE -ne 0) { throw "v++ link failed with exit code $LASTEXITCODE" }
if (-not (Test-Path -LiteralPath $Xclbin)) { throw "Expected XCLBIN was not generated: $Xclbin" }

Get-FileHash -Algorithm SHA256 -LiteralPath $Xclbin | Format-List | Out-File -FilePath (Join-Path $LogDir 'xclbin_sha256.txt') -Encoding utf8
Write-Host "XCLBIN=$Xclbin"
