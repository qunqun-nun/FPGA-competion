from pathlib import Path
import os, csv, json, hashlib, re, fnmatch, xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parent
def long(p):
    return Path('\\\\?\\'+str(p)) if os.name=='nt' and not str(p).startswith('\\\\?\\') else p
def exists(p): return long(p).exists()
def expand(v,p):
    for k,val in {'$PPRDIR':p.parent,'$PSRCDIR':p.parent/(p.stem+'.srcs'),'$PGENDIR':p.parent/(p.stem+'.gen'),'$PRUNDIR':p.parent/(p.stem+'.runs'),'$PIPUSERFILESDIR':p.parent/(p.stem+'.ip_user_files'),'$PCACHEDIR':p.parent/(p.stem+'.cache')}.items():v=v.replace(k,str(val))
    return Path(os.path.normpath(v))
rows=[]
def relevant(p):
    return not any(x in ['change_backup','failed_attempts','.Xil','__pycache__','rebuild_outputs'] or x.endswith('.cache') for x in p.relative_to(ROOT).parts)
def files_matching(pattern):
    for folder,dirs,names in os.walk(str(long(ROOT))):
        dirs[:]=[d for d in dirs if d not in ['change_backup','failed_attempts','.Xil','__pycache__','rebuild_outputs'] and not d.endswith('.cache')]
        native=folder[4:] if folder.startswith('\\\\?\\') else folder
        for name in names:
            if fnmatch.fnmatch(name,pattern):yield Path(native)/name
def row(owner,kind,raw,p,optional=False):
    alias=str(p).replace('\\','/')
    if alias.lower().startswith('w:/'):
        p=ROOT/alias[3:]
    p=Path(os.path.normpath(p))
    external=not str(p).lower().startswith(str(ROOT).lower())
    rows.append({'owner':str(owner.relative_to(ROOT)),'kind':kind,'reference':raw,'resolved':str(p),'exists':exists(p),'scope':'tool_install' if external else 'package','required':not optional})
projects=['v014_main_project_20261024/project/fengyan_pl.xpr','build/link/_x/link/vivado/vpl/prj/prj.xpr',
          'v017_link/_x/link/vivado/vpl/prj/prj.xpr']
for rel in projects:
    if not (ROOT/rel).exists():continue
    p=ROOT/rel;t=ET.parse(p)
    for f in t.findall('.//File'):row(p,'XPR File',f.get('Path'),expand(f.get('Path'),p))
    for e in t.findall('.//Option'):
        if e.get('Name') in ['IPRepoPath','BoardPartRepoPaths']:
            row(p,e.get('Name'),e.get('Val'),expand(e.get('Val'),p))
for p in files_matching('component.xml'):
    if not relevant(p):continue
    try:t=ET.parse(long(p))
    except ET.ParseError:continue
    ns={'s':'http://www.spiritconsortium.org/XMLSchema/SPIRIT/1685-2009'}
    for f in t.findall('.//s:file/s:name',ns):
        raw=f.text or ''
        if raw.startswith(('https://','http://')):continue  # remote documentation, not a source dependency
        q=Path(raw) if re.match(r'^[A-Za-z]:',raw) else p.parent/raw
        row(p,'IP-XACT file',raw,q)
for p in files_matching('*.bd'):
    if not relevant(p):continue
    try:data=json.loads(long(p).read_text(encoding='utf-8'))
    except (ValueError,UnicodeDecodeError):continue
    def walk(obj):
        if isinstance(obj,dict):
            for k,v in obj.items():
                if k=='xci_path' and isinstance(v,str):
                    q=p.parent/v.replace('\\','/')
                    if not exists(q) and '.srcs' in str(q):q=Path(str(q).replace('.srcs','.gen'))
                    row(p,'BD generated XCI',v,q)
                else:walk(v)
        elif isinstance(obj,list):
            for v in obj:walk(v)
    walk(data)
for p in files_matching('*.xpfm'):
    if not relevant(p):continue
    t=ET.parse(long(p));ns='{http://www.xilinx.com/sdx}'
    for e in t.iter():
        if e.tag.split('}')[-1] in ['hardwarePlatform','softwarePlatform']:
            raw=e.get(ns+'path','')+'/'+e.get(ns+'name','');row(p,'XPFM dependency',raw,p.parent/raw)
base=ROOT/'build/link/_x/link/vivado/vpl'
for p in list((base/'scripts').rglob('*.tcl'))+list((base/'.local').glob('*.tcl'))+[base/'ipirun.tcl']:
    for line in p.read_text(encoding='utf-8').splitlines():
        line=line.strip()
        if not line.startswith('source '):continue
        if '$local_dir/' in line:
            name=re.search(r'\$local_dir/([^"\s]+)',line).group(1)
            row(p,'Tcl source',line,base/'.local'/name)
        elif '[file dirname [info script]]' in line:
            tail=line.split('[file dirname [info script]]',1)[1].strip().rstrip(']').strip()
            row(p,'Tcl source',line,p.parent.joinpath(*tail.split()))
out=ROOT/'dependency_paths.csv'
with out.open('w',encoding='utf-8-sig',newline='') as f:
    w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
missing=[r for r in rows if r['required'] and not r['exists']]
outside=[r for r in rows if r['scope']=='tool_install']
unexpected=[r for r in outside if r['kind'] not in ('IPRepoPath','BoardPartRepoPaths')]
result={'checked':len(rows),'missing':len(missing),'missing_items':missing,
        'external_tool_repositories':outside,'unexpected_external_sources':unexpected,
        'scope':'XPR File/repositories + IP-XACT fileGroups + BD XCI + XPFM; no rebuild performed'}
(ROOT/'dependency_validation.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'checked':len(rows),'missing':len(missing)},ensure_ascii=False))
for x in missing[:25]:print(x['kind'],x['reference'],x['resolved'])
raise SystemExit(bool(missing or unexpected))
