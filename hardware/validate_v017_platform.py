from pathlib import Path
import os,json,hashlib,zipfile,xml.etree.ElementTree as E,collections
r=Path(__file__).resolve().parent;s=r.parent.parent/'V0.16_复位修复_20261031'
def lp(p):return Path('\\\\?\\'+str(p))
def sha(p):
 h=hashlib.sha256()
 with lp(p).open('rb') as f:
  for b in iter(lambda:f.read(1048576),b''):h.update(b)
 return h.hexdigest()
changed=[]
for x in json.loads((r/'logs/v017_protected_before.json').read_text()):
 if sha(r/x['path'])!=x['sha256']:changed.append(x['path'])
original_changed=[]
for x in json.loads((r/'collection_manifest.json').read_text(encoding='utf-8')):
 if sha(s/x['path'])!=x['source_sha256']:original_changed.append(x['path'])
project='v014_main_project_20261024/project/'
bdrel=project+'fengyan_pl.srcs/sources_1/bd/design_1/design_1.bd'
old=json.loads((r/'change_backup'/bdrel).read_text())['design'];new=json.loads((r/bdrel).read_text())['design']
def diff(a,b,path=''):
 result=[]
 if isinstance(a,dict) and isinstance(b,dict):
  for k in sorted(set(a)|set(b)):
   if k not in a:result.append({'path':path+'/'+k,'change':'added'})
   elif k not in b:result.append({'path':path+'/'+k,'change':'removed'})
   else:result+=diff(a[k],b[k],path+'/'+k)
 elif a!=b:result.append({'path':path,'before':a,'after':b})
 return result
delta=diff(old,new)
(r/'logs/v017_bd_json_diff.json').write_text(json.dumps(delta,ensure_ascii=False,indent=2),encoding='utf-8')
port='IDT_8T49N241_RST_OUT';nets=[(k,v) for k,v in new['nets'].items() if port in v.get('ports',[])]
wrapper=(r/(project+'fengyan_pl.gen/sources_1/bd/design_1/hdl/design_1_wrapper.v')).read_text()
xdc=(r/'v014_unified_work_20261024/constraints/hdmi_zcu104_tx_v014.xdc').read_text()
summary={'delivery_status':'候选联调包','originals_changed':original_changed,'old_final_project_and_xsa_changed':changed,'bd_port':new['ports'].get(port),'bd_nets':nets,'const_one':new['components']['const_one']['parameters'],'wrapper_contains_port':port in wrapper,'xdc_pin_m12':f'PACKAGE_PIN M12 [get_ports {port}]' in xdc,'xdc_lvcmos33':f'IOSTANDARD LVCMOS33 [get_ports {port}]' in xdc,'bd_diff_count':len(delta),'new_link_executed':False,'new_bit_xclbin_generated':False,'timing_drc_verified':False}
archives=[]
xsa=r/'platform/fengyan_v017_extensible.xsa'
with zipfile.ZipFile(xsa) as z:
 names=z.namelist();matches=[]
 for n in names:
  if n.endswith(('.hwh','.bd','.v','.xdc')):
   if port.encode() in z.read(n):matches.append(n)
 archives.append({'path':xsa.relative_to(r).as_posix(),'sha256':sha(xsa),'bytes':xsa.stat().st_size,'crc_error':z.testzip(),'new_port_members':matches,'contains_bit':any(n.endswith('.bit') for n in names)})
summary['archives']=archives
xpfm=r/'platform/generated_v017/fengyan_v017_zcu104/export/fengyan_v017_zcu104/fengyan_v017_zcu104.xpfm'
summary['xpfm']={'path':xpfm.relative_to(r).as_posix(),'sha256':sha(xpfm),'bytes':xpfm.stat().st_size}
hw=xpfm.parent/'hw/fengyan_v017_extensible.xsa'
summary['exported_xpfm_hw_matches_xsa']=sha(hw)==sha(xsa)
(r/'v017_platform_validation.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(summary,ensure_ascii=False,indent=2))
assert not original_changed and not changed
assert summary['wrapper_contains_port'] and summary['xdc_pin_m12'] and summary['xdc_lvcmos33'] and summary['exported_xpfm_hw_matches_xsa']
assert any('const_one/dout' in v.get('ports',[]) for _,v in nets)
assert summary['archives'][0]['crc_error'] is None and summary['archives'][0]['new_port_members']
