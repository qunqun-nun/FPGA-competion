from pathlib import Path
import os,json,csv,hashlib,zipfile,collections
r=Path(__file__).resolve().parent;s=r.parent.parent/'V0.16_复位修复_20261031'
def lp(p):return Path('\\\\?\\'+str(p)) if os.name=='nt' else p
def sha(p):
 h=hashlib.sha256()
 with lp(p).open('rb') as f:
  for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
 return h.hexdigest()
m=json.loads((r/'collection_manifest.json').read_text(encoding='utf-8'));issues=[];rows=[]
for x in m:
 p=r/x['path'];orig=s/x['path'];hs=sha(orig);hc=sha(p)
 if hs!=x['source_sha256']:issues.append(x['path'])
 rows.append(dict(x,copy_sha256=hc,copy_modified=hc!=x['source_sha256'],source_unchanged=hs==x['source_sha256']))
with (r/'source_copy_manifest.csv').open('w',encoding='utf-8-sig',newline='') as f:
 w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
selected={x['path'] for x in m};excluded=[]
for p in s.rglob('*'):
 if not lp(p).is_file():continue
 rel=p.relative_to(s).as_posix()
 if rel in selected:continue
 low=rel.lower()
 if p.suffix.lower() in ['.lic','.key','.pem']:reason='license/key excluded'
 elif 'failed_link' in low:reason='failed build excluded'
 elif any(v in low for v in ['.cache/','ipcache/','.xil/','__pycache__/','xsim.dir/']):reason='cache/simulation state excluded'
 elif any(v in low for v in ['backup','before_portable','pre_sanitize','legacy','evidence/']):reason='historical/backup duplicate excluded'
 elif low.startswith(('models/','tools/','v0.16_')) or '/board/' in low or '/pc/' in low:reason='software/model/tool/delivery outside hardware input scope'
 elif '.runs/' in low:reason='rebuildable run output excluded (final checkpoint/bit/metadata selected separately)'
 elif low.startswith('platform/'):reason='duplicate platform build workspace excluded; exported XPFM and dependencies selected'
 else:reason='not in dependency closure or redundant historical material'
 excluded.append({'path':rel,'bytes':lp(p).stat().st_size,'reason':reason})
with (r/'excluded_inventory.csv').open('w',encoding='utf-8-sig',newline='') as f:
 w=csv.DictWriter(f,fieldnames=['path','bytes','reason']);w.writeheader();w.writerows(excluded)
archive_info=[]
for rel in ['build/dpu_kernel/dpu_b4096.xo','platform/generated/fengyan_v015_zcu104/export/fengyan_v015_zcu104/hw/fengyan_v015_extensible.xsa','fengyan_v016_final_same_build.xsa']:
 p=r/rel
 if not p.exists():continue
 with zipfile.ZipFile(p) as z:
  bad=z.testzip();keys=[n for n in z.namelist() if n.lower().endswith(('.lic','.key','.pem'))]
  entry={'path':rel,'sha256':sha(p),'bytes':p.stat().st_size,'zip_crc_error':bad,'license_key_members':keys}
  if rel=='fengyan_v016_final_same_build.xsa':
   bit=r/'build/link/_x/link/vivado/vpl/prj/prj.runs/impl_1/design_1_wrapper.bit'
   entry['embedded_bits']={n:hashlib.sha256(z.read(n)).hexdigest() for n in z.namelist() if n.endswith('.bit')}
   entry['original_final_bit_sha256']=sha(bit)
   entry['same_build_bit_matches']=bool(entry['embedded_bits']) and all(h==sha(bit) for h in entry['embedded_bits'].values())
   hwh=r/'build/link/_x/link/vivado/vpl/prj/prj.gen/sources_1/bd/design_1/hw_handoff/design_1.hwh'
   entry['embedded_hwh']={n:hashlib.sha256(z.read(n)).hexdigest() for n in z.namelist() if n.endswith('.hwh')}
   entry['final_project_hwh_sha256']=sha(hwh)
   entry['hwh_matches_final_project']=sha(hwh) in entry['embedded_hwh'].values()
  archive_info.append(entry)
# Record physically deduplicated large identical files. No links to V016 originals.
groups=collections.defaultdict(list)
for x in rows:
 if x['bytes']>=1024*1024:groups[x['copy_sha256']].append(x['path'])
dedup=[]
for h,paths in groups.items():
 if len(paths)<2:continue
 first=r/paths[0]
 for rel in paths[1:]:
  p=r/rel;tmp=p.with_name(p.name+'.dedup_tmp')
  if not os.path.samefile(lp(first),lp(p)):
   os.link(lp(first),lp(tmp));os.replace(lp(tmp),lp(p))
  dedup.append({'canonical':paths[0],'alias':rel,'bytes':lp(p).stat().st_size,'sha256':h})
(r/'internal_hardlinks.json').write_text(json.dumps(dedup,ensure_ascii=False,indent=2),encoding='utf-8')
summary={'delivery_status':'候选联调包','hdmi_software_blocker':True,'full_chain_board_acceptance_passed':False,'collected_files':len(m),'collected_bytes':sum(x['bytes'] for x in m),'excluded_files':len(excluded),'excluded_bytes':sum(x['bytes'] for x in excluded),'internal_hardlink_saved_bytes':sum(x['bytes'] for x in dedup),'originals_changed':issues,'modified_copies':sum(x['copy_modified'] for x in rows),'archives':archive_info,'hardware_rebuild_executed':False,'cross_machine_build_verified':False}
(r/'final_validation.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
# Hash all deliverable files except transient Vivado state and this inventory itself.
allrows=[]
for p in r.rglob('*'):
 if lp(p).is_file() and not any(x in p.parts for x in ['.Xil','__pycache__']) and p.name!='package_sha256.csv':
  allrows.append({'path':p.relative_to(r).as_posix(),'bytes':lp(p).stat().st_size,'sha256':sha(p)})
with (r/'package_sha256.csv').open('w',encoding='utf-8-sig',newline='') as f:
 w=csv.DictWriter(f,fieldnames=['path','bytes','sha256']);w.writeheader();w.writerows(allrows)
print(json.dumps(summary,ensure_ascii=False,indent=2))
