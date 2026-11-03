$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent $PSScriptRoot
$validated=Join-Path $taskRoot 'V0.16_给丙上板包'
$manifest=Join-Path $validated 'manifest.json'
$final=Join-Path $taskRoot 'V0.16_Overlay交付包'
while(-not(Test-Path -LiteralPath $manifest)){Start-Sleep -Seconds 15}
$hashes=Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json
New-Item -ItemType Directory -Path $final -Force|Out-Null
foreach($extension in @('bit','hwh','xclbin')) {
 $relative="hardware\fengyan_v016_dpu.$extension"
 $source=Join-Path $validated $relative
 $expected=$hashes.PSObject.Properties[$relative].Value
 if(-not $expected -or (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $expected){throw "Validation manifest mismatch: $relative"}
 Copy-Item -LiteralPath $source -Destination (Join-Path $final "fengyan_v016_dpu.$extension") -Force
}
if(@(Get-ChildItem -LiteralPath $final -File).Count -ne 3){throw 'Unexpected files in final Overlay directory'}
$archive=Join-Path $taskRoot 'V0.16_Overlay交付包.zip'
if(Test-Path -LiteralPath $archive){throw 'Archive already exists; preserve it'}
Compress-Archive -LiteralPath $final -DestinationPath $archive
Write-Output "OVERLAY_ONLY_PACKAGE_READY=$archive"
