"""Refresh current package hashes and V017 path index; does not edit/link source files."""
from pathlib import Path
import csv,json,hashlib
r=Path(__file__).resolve().parent
def lp(p):return Path('\\\\?\\'+str(p))
def sha(p):
 h=hashlib.sha256()
 with lp(p).open('rb') as f:
  for b in iter(lambda:f.read(1048576),b''):h.update(b)
 return h.hexdigest()
keys={
 'new_extensible_xsa':'platform/fengyan_v017_extensible.xsa',
 'new_xpfm':'platform/generated_v017/fengyan_v017_zcu104/export/fengyan_v017_zcu104/fengyan_v017_zcu104.xpfm',
 'xpfm_hw':'platform/generated_v017/fengyan_v017_zcu104/export/fengyan_v017_zcu104/hw/fengyan_v017_extensible.xsa',
 'static_project':'v014_main_project_20261024/project/fengyan_pl.xpr',
 'bd':'v014_main_project_20261024/project/fengyan_pl.srcs/sources_1/bd/design_1/design_1.bd',
 'wrapper':'v014_main_project_20261024/project/fengyan_pl.gen/sources_1/bd/design_1/hdl/design_1_wrapper.v',
 'xdc':'v014_unified_work_20261024/constraints/hdmi_zcu104_tx_v014.xdc',
 'incremental_reference':'build/link/_x/link/vivado/vpl/prj/prj.runs/impl_1/design_1_wrapper_routed.dcp',
 'xo':'build/dpu_kernel/dpu_b4096.xo',
 'kernel_xml':'build/link/_x/link/int/xo/DPUCZDX8G/DPUCZDX8G/kernel.xml',
 'incremental_config':'config/link_v017_incremental.cfg',
 'normal_config':'config/link_v017_normal.cfg',
 'validation':'v017_platform_validation.json',
 'property_proof':'logs/v017_incremental_property.txt',
 'platform_identity':'logs/v017_platform_identity.txt',
 'instructions':'V017_平台修复与增量参考说明.md'}
paths={}
for key,rel in keys.items():
 p=r/rel
 if not lp(p).is_file():raise SystemExit('Missing '+rel)
 paths[key]={'relative_path':rel,'absolute_path':p.as_posix(),'bytes':lp(p).stat().st_size,'sha256':sha(p)}
(r/'v017_platform_paths.json').write_text(json.dumps(paths,ensure_ascii=False,indent=2),encoding='utf-8')
hashpaths=list(keys.values())+['v017_platform_paths.json','scripts/patch_v017_idt_reset.tcl','scripts/export_v017_platform.tcl','scripts/generate_v017_xpfm.tcl','scripts/prepare_v017_link_config.py','run_v017_platform.ps1']
(r/'index.sha256').write_text(''.join(sha(r/rel)+'  '+rel+'\n' for rel in hashpaths),encoding='utf-8')
files=[]
for p in r.rglob('*'):
 rel=p.relative_to(r)
 if not lp(p).is_file() or p.name=='package_sha256.csv' or any(x in ['.Xil','__pycache__'] or x.endswith('.cache') for x in rel.parts):continue
 files.append({'path':rel.as_posix(),'bytes':lp(p).stat().st_size,'sha256':sha(p)})
with (r/'package_sha256.csv').open('w',encoding='utf-8-sig',newline='') as f:
 w=csv.DictWriter(f,fieldnames=['path','bytes','sha256']);w.writeheader();w.writerows(files)
print('INDEX_READY',len(paths),'key paths,',len(files),'package files')
