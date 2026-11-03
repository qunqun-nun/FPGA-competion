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
$TrdRoot = 'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/third_party/DPUCZDX8G_TRD_2022.1'
$VitisPrj = 'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/third_party/DPUCZDX8G_TRD_2022.1/prj/Vitis'
$BuildDir = Join-Path $MappedRoot 'build\dpu_kernel'
$LogDir = Join-Path $MappedRoot 'logs'
$Vivado = 'F:\Xilinx\Vivado\2022.2\bin\vivado.bat'

New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

$env:TRD_PATH = $TrdRoot
$env:DIR_PRJ = $VitisPrj
$XoPath = (Join-Path $BuildDir 'dpu_b4096.xo').Replace('\', '/')
$LogPath = Join-Path $LogDir 'build_dpu_xo.log'

Push-Location $VitisPrj
try {
    & $Vivado -mode batch -source '.\scripts\gen_dpu_xo.tcl' -notrace -tclargs $XoPath DPUCZDX8G hw zcu104 2>&1 | Tee-Object -FilePath $LogPath
    if ($LASTEXITCODE -ne 0) { throw "Vivado DPU XO build failed with exit code $LASTEXITCODE" }
} finally {
    Pop-Location
}

if (-not (Test-Path -LiteralPath $XoPath)) { throw "Expected XO was not generated: $XoPath" }
Get-FileHash -Algorithm SHA256 -LiteralPath $XoPath | Format-List | Out-File -FilePath (Join-Path $LogDir 'dpu_xo_sha256.txt') -Encoding utf8
Write-Host "DPU_XO=$XoPath"
