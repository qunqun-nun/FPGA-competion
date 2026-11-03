$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent $PSScriptRoot
$log='C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/build\link\logs\v++_fengyan_v016_dpu.log'
while($true) {
 if(Test-Path -LiteralPath $log) {
  $tail=Get-Content -LiteralPath $log -Tail 40
  if($tail -match 'Failed to finish linking|Kernel link failed|link run .*failed'){throw 'Link failed; inspect logs'}
  if($tail -match 'Successfully created.*xclbin|BUILD_COMPLETE|Total elapsed time'){break}
 }
 Start-Sleep -Seconds 15
}
$xcl='C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/build\link\fengyan_v016_dpu.xclbin'
if(-not(Test-Path $xcl)){throw 'Missing xclbin'}
$hwh='C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/build\link\_x\link\vivado\vpl\prj\prj.gen\sources_1\bd\design_1\hw_handoff\design_1.hwh'
& 'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/scripts\audit_final_hwh.ps1' -Hwh $hwh | Tee-Object 'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/logs\final_hwh_audit.txt'
& 'F:\Xilinx\Vivado\2022.2\bin\vivado.bat' -mode batch -source 'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/scripts\generate_final_checkpoint_reports.tcl' -notrace 2>&1 | Tee-Object 'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/logs\final_signoff.log'
if($LASTEXITCODE -ne 0){throw 'Signoff report generation failed'}
$timing=Get-Content 'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/build\final_checkpoint_reports\design_1_wrapper_timing_summary_signoff.rpt' -Raw
if($timing -notmatch 'All user specified timing constraints are met'){throw 'Timing did not pass'}
$route=Get-Content 'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/build\final_checkpoint_reports\design_1_wrapper_route_status.rpt' -Raw
if($route -notmatch '# of nets with routing errors\.+\s*:\s*0\s*:'){throw 'Route errors or unexpected report'}
$bus=Get-Content 'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/build\final_checkpoint_reports\design_1_wrapper_bus_skew.rpt' -Raw
if($bus -match 'VIOLATED'){throw 'Bus skew violation'}
$drc=Get-Content 'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/build\final_checkpoint_reports\design_1_wrapper_drc_routed.rpt' -Raw
if($drc -match '\|\s*(Error|Critical Warning)\s*\|'){throw 'DRC error requires review'}
if((Get-Content 'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/build\reset_sim\xsim.log' -Raw) -notmatch 'RESET_NETLIST_TEST_PASS'){throw 'Reset simulation missing pass'}
$pkg=Join-Path $taskRoot 'V0.16_给丙上板包'
foreach($d in @('hardware','model','reports','source')){New-Item -ItemType Directory -Path (Join-Path $pkg $d) -Force|Out-Null}
Copy-Item -LiteralPath $xcl -Destination (Join-Path $pkg 'hardware\fengyan_v016_dpu.xclbin')
Copy-Item -LiteralPath 'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/build\link\_x\link\int\system.bit' -Destination (Join-Path $pkg 'hardware\fengyan_v016_dpu.bit')
Copy-Item -LiteralPath $hwh -Destination (Join-Path $pkg 'hardware\fengyan_v016_dpu.hwh')
$arch='C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/build\link\_x\link\vivado\vpl\prj\prj.gen\sources_1\bd\design_1\ip\design_1_dpuczdx8g_1_0\arch.json'
Copy-Item -LiteralPath $arch -Destination (Join-Path $pkg 'hardware\arch.json')
$archData=Get-Content -LiteralPath $arch -Raw | ConvertFrom-Json
if([Convert]::ToUInt64($archData.fingerprint.Replace('0x',''),16) -ne [Convert]::ToUInt64('0101000016010407',16)){throw 'Architecture fingerprint changed'}
Copy-Item -LiteralPath 'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/models\tank_yolov8n_relu_latest_six_outputs.xmodel' -Destination (Join-Path $pkg 'model')
Get-ChildItem 'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/build\final_checkpoint_reports' -File | Copy-Item -Destination (Join-Path $pkg 'reports')
Copy-Item -LiteralPath 'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/build\reset_sim\xsim.log' -Destination (Join-Path $pkg 'reports\reset_sim.log')
Copy-Item -LiteralPath 'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/logs\reset_connections.txt' -Destination (Join-Path $pkg 'reports')
Copy-Item -LiteralPath 'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/logs\final_hwh_audit.txt' -Destination (Join-Path $pkg 'reports')
Copy-Item -LiteralPath 'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/logs\vpp_link.log' -Destination (Join-Path $pkg 'reports')
Copy-Item -LiteralPath 'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/rtl\tb_reset_release.sv' -Destination (Join-Path $pkg 'source')
Copy-Item -LiteralPath 'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/scripts\fix_reset_export.tcl' -Destination (Join-Path $pkg 'source')
& 'F:\Xilinx\Vitis\2022.2\bin\xclbinutil.bat' --info --input $xcl 2>&1 | Set-Content -LiteralPath (Join-Path $pkg 'reports\xclbin_info.txt')
if($LASTEXITCODE -ne 0){throw 'Xclbin inspection failed'}
& 'F:\Xilinx\Vitis\2022.2\bin\xclbinutil.bat' --input $xcl --dump-section "BITSTREAM:RAW:C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/build/embedded_v016.bit" --force
if($LASTEXITCODE -ne 0){throw 'Bitstream extraction failed'}
if((Get-FileHash 'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/build\embedded_v016.bit').Hash -ne (Get-FileHash (Join-Path $pkg 'hardware\fengyan_v016_dpu.bit')).Hash){throw 'Embedded bit mismatch'}
$report=@'
# V0.16 电脑端验证结果与板端待验收项

自动检查已通过：三处低有效辅助复位接常量1；三个复位IP功能网表11项场景；完整Vitis链接；时序约束；路由零错误；无DRC Error/Critical Warning；bus-skew无违反；XCLBIN内嵌bit与外置bit一致；单核DPU架构指纹0x0101000016010407。

模型文件MD5与丙记录一致；此项仅为文件身份核对。未在本机运行XIR/VART模型推理。

CDC明细报告和DRC Warning需保留审查，自动检查不等于整个系统CDC功能验证。100→300MHz的AXI控制通路没有完成端到端事务仿真，仍需板端控制访问验证。

请丙验证：硬件完整加载返回、0x80020000控制访问与真实指纹、中断ID1映射、XRT2.13兼容性、Runner创建、六输出实际推理、视频输入及跟踪/融合/OSD/HDMI。

HDMI评估许可和XSA摘要告警沿用现状，以原始日志为证；正式长期运行仍需要解决HDMI许可。所有板端项目在取得实际日志前均为待验证。

本文件由构建后检查生成；还需查看原始CDC/DRC报告进行人工审阅。上板包属于候选验收包，不表示已完成实物板验收。
'@
$report | Set-Content -LiteralPath (Join-Path $pkg '电脑端验证与板端待验收.md') -Encoding utf8
$manifest=[ordered]@{}
Get-ChildItem -LiteralPath $pkg -Recurse -File | Where-Object {$_.Name -ne 'manifest.json'} | ForEach-Object {$manifest[$_.FullName.Substring($pkg.Length+1)]=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}
$manifest|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $pkg 'manifest.json') -Encoding utf8
Write-Output 'ARTIFACTS_PACKAGED_PENDING_ENGINEER_REVIEW'
