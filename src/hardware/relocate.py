"""Fix only package copies; safe to rerun after moving this directory."""
from pathlib import Path
import os,re,json,argparse,xml.etree.ElementTree as ET
r=Path(__file__).resolve().parent
a=argparse.ArgumentParser();a.add_argument('--vitis-ip',default='F:/Xilinx/Vitis/2022.2/data/ip');args=a.parse_args()
changes=[]
state=r/'relocation_root.json'
old_root=json.loads(state.read_text(encoding='utf-8'))['root'] if state.exists() else r.as_posix()
def lp(p):return Path('\\\\?\\'+str(p)) if os.name=='nt' else p
for rel in ['v014_main_project_20261024/project/fengyan_pl.xpr','build/link/_x/link/vivado/vpl/prj/prj.xpr',
            'v017_link/_x/link/vivado/vpl/prj/prj.xpr']:
 if not (r/rel).exists():continue
 p=r/rel;t=ET.parse(p);t.getroot().set('Path',p.as_posix())
 for e in t.findall('.//Option'):
  if e.get('Name')=='IPRepoPath':
   old=e.get('Val','')
   if re.match(r'^[A-Za-z]:[/\\]',old):e.set('Val',args.vitis_ip)
   elif old.endswith('/official_ip_repo') and '/.local/' not in old and rel.startswith('build/'):
    # Do not add a second copy of DPU IP already in the extracted platform repository.
    e.set('Val','$PPRDIR/../.local/hw_platform/iprepo')
 # Remove duplicate repository options, retaining ordering.
 conf=t.find('Configuration');seen=set()
 for e in list(conf):
  if e.get('Name')=='IPRepoPath':
   v=e.get('Val')
   if v in seen:conf.remove(e)
   seen.add(v)
 t.write(p,encoding='UTF-8',xml_declaration=True)
# Any executable historical script remains inside the copy, with no V016 target.
# Convert source-tree aliases R:/ and V:/ to the copied root. Vitis path is a tool prerequisite.
manifest=json.loads((r/'collection_manifest.json').read_text(encoding='utf-8'))
for item in manifest:
 p=r/item['path']
 if p.suffix.lower() not in ['.tcl','.ttcl','.ps1','.py','.bif','.cfg']:continue
 q=lp(p)
 try:text=q.read_text(encoding='utf-8-sig')
 except UnicodeDecodeError:continue
 new=text.replace(old_root,r.as_posix()).replace(old_root.replace('/','\\'),str(r))
 new=new.replace('R:/',r.as_posix()+'/').replace('V:/',r.as_posix()+'/')
 if p.suffix=='.ps1':new=new.replace('R:\\',r.as_posix()+'/').replace('V:\\',r.as_posix()+'/')
 # PowerShell root aliases must be local, never a shared drive mapping.
 if p.suffix=='.ps1':
  new=new.replace("$MappedRoot = 'V:\\'","$MappedRoot = $WorkRoot + [IO.Path]::DirectorySeparatorChar")
 if new!=text:
  q.write_text(new,encoding='utf-8');changes.append(item['path'])
# Tcl hooks source ipirun relative to the run directory (vpl/prj/prj.runs/impl_1).
# Make them independent of caller cwd.
base=r/'build/link/_x/link/vivado/vpl'
for p in (base/'scripts').rglob('*.tcl'):
 text=p.read_text(encoding='utf-8');new=text
 if p.parent.name=='impl_1':
  new=re.sub(r'source (\.\./\.\./\.\./scripts/[^\s]+)',lambda m:'source [file join [file dirname [info script]] .. '+Path(m.group(1)).name+']',new)
 new=new.replace('source ../../../ipirun.tcl','source [file join [file dirname [info script]] .. ipirun.tcl]')
 if new!=text:p.write_text(new,encoding='utf-8');changes.append(p.relative_to(r).as_posix())
(r/'relocation_changes.json').write_text(json.dumps(changes,ensure_ascii=False,indent=2),encoding='utf-8')
state.write_text(json.dumps({'root':r.as_posix()},ensure_ascii=False),encoding='utf-8')
print('Relocated copy scripts:',len(changes))
