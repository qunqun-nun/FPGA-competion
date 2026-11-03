param([string]$Vivado='F:\Xilinx\Vivado\2022.2\bin\vivado.bat')
$ErrorActionPreference='Stop'
if(Test-Path 'W:\') {throw 'W: already occupied. Use the existing mapping only if it points to this rebuild directory.'}
& subst.exe W: $PSScriptRoot
try {
 if($LASTEXITCODE -ne 0) {throw 'subst failed'}
 & $Vivado 'W:/v017_link/_x/link/vivado/vpl/prj/prj.xpr'
 if($LASTEXITCODE -ne 0) {throw 'Vivado failed'}
} finally {& subst.exe W: /D}
