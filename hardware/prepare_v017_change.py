from pathlib import Path
import os,shutil,json,hashlib
r=Path(__file__).resolve().parent
backup=r/'change_backup'
if backup.exists():raise SystemExit('change_backup already exists: preserve first rollback snapshot')
backup.mkdir()
def lp(p):return Path('\\\\?\\'+str(p))
def sha(p):
 h=hashlib.sha256()
 with lp(p).open('rb') as f:
  for b in iter(lambda:f.read(1048576),b''):h.update(b)
 return h.hexdigest()
affected=['v014_main_project_20261024/project/fengyan_pl.xpr','v014_main_project_20261024/project/fengyan_pl.srcs/sources_1/bd/design_1/design_1.bd','v014_main_project_20261024/project/fengyan_pl.gen/sources_1/bd/design_1/hdl/design_1_wrapper.v','v014_unified_work_20261024/constraints/hdmi_zcu104_tx_v014.xdc']
records=[]
for rel in affected:
 p=r/rel;q=backup/rel;lp(q.parent).mkdir(parents=True,exist_ok=True);shutil.copy2(lp(p),lp(q));records.append({'path':rel,'sha256':sha(p)})
(backup/'affected_files.json').write_text(json.dumps(records,indent=2),encoding='utf-8')
# Only isolate files, no backup of generated trees. Vivado may rewrite any static output product.
detached=[]
for p in (r/'v014_main_project_20261024').rglob('*'):
 if lp(p).is_file() and lp(p).stat().st_nlink>1:
  tmp=p.with_name(p.name+'.v017_private_tmp');shutil.copy2(lp(p),lp(tmp));os.replace(lp(tmp),lp(p));detached.append(p.relative_to(r).as_posix())
for rel in affected:
 p=r/rel
 if lp(p).stat().st_nlink>1:
  tmp=p.with_name(p.name+'.v017_private_tmp');shutil.copy2(lp(p),lp(tmp));os.replace(lp(tmp),lp(p));detached.append(rel)
(r/'logs/v017_detached_hardlinks.json').write_text(json.dumps(detached,indent=2),encoding='utf-8')
protected=[]
for p in (r/'build/link').rglob('*'):
 if lp(p).is_file():protected.append({'path':p.relative_to(r).as_posix(),'sha256':sha(p)})
for p in r.rglob('*.xsa'):
 if lp(p).is_file():protected.append({'path':p.relative_to(r).as_posix(),'sha256':sha(p)})
(r/'logs/v017_protected_before.json').write_text(json.dumps(protected,indent=2),encoding='utf-8')
print('Backed up',len(records),'affected originals; detached',len(detached),'static hardlinks; protected',len(protected),'files')
