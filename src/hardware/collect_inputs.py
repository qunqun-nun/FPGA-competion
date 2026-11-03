from pathlib import Path
import os, re, csv, json, shutil, hashlib, xml.etree.ElementTree as ET
from collections import Counter

ROOT = Path(__file__).resolve().parent
SRC = ROOT.parent.parent / 'V0.16_复位修复_20261031'
PROJECTS = ['v014_main_project_20261024/project/fengyan_pl.xpr', 'build/link/_x/link/vivado/vpl/prj/prj.xpr']
selected = {}
def add(rel, reason):
    p = SRC / rel
    if p.is_file(): selected[p.relative_to(SRC).as_posix()] = reason
def tree(rel, reason):
    p = SRC / rel
    if p.exists():
        for q in p.rglob('*'):
            if q.is_file() and not any(x in q.parts for x in ['.Xil','__pycache__','.git']) and q.suffix.lower() not in ['.lic','.jou','.log','.wdb','.pb','.pyc'] and not q.name.startswith(('._','.DS_Store')):
                add(q.relative_to(SRC), reason)
def expand(v,p):
    d=p.parent; stem=p.stem
    for key,val in {'$PPRDIR':d,'$PSRCDIR':d/(stem+'.srcs'),'$PGENDIR':d/(stem+'.gen'),'$PRUNDIR':d/(stem+'.runs'),'$PIPUSERFILESDIR':d/(stem+'.ip_user_files'),'$PCACHEDIR':d/(stem+'.cache')}.items():
        v=v.replace(key,str(val))
    return Path(os.path.normpath(v))
for rel in PROJECTS:
    add(rel,'existing project, never recreated')
    p=SRC/rel
    tree(p.parent.relative_to(SRC)/(p.stem+'.srcs'),'project sources and BD')
    tree(p.parent.relative_to(SRC)/(p.stem+'.gen'),'generated IP products required to reopen existing project')
    for e in ET.parse(p).findall('.//File'):
        q=expand(e.get('Path',''),p)
        if q.is_file() and SRC in q.parents: add(q.relative_to(SRC),'XPR File reference')
    for e in ET.parse(p).findall('.//Option'):
        if e.get('Name') in ['IPRepoPath','BoardPartRepoPaths']:
            q=expand(e.get('Val',''),p)
            if SRC in q.parents and q.exists() and 'ipcache' not in str(q): tree(q.relative_to(SRC),'XPR IP/board repository')
for rel in ['official_ip_repo','rtl','config','v014_unified_work_20261024/sources','v014_unified_work_20261024/constraints','v014_unified_work_20261024/ip_repo','v014_unified_work_20261024/third_party/delivery_to_b_20261011/hdmi_display_c_20261011/rtl','third_party/DPUCZDX8G_TRD_2022.1/dpu_ip','third_party/DPUCZDX8G_TRD_2022.1/prj/Vitis/scripts','third_party/DPUCZDX8G_TRD_2022.1/prj/Vitis/kernel_xml','third_party/DPUCZDX8G_TRD_2022.1/prj/Vitis/dpu_conf.vh','platform/generated/fengyan_v015_zcu104/export']:
    if (SRC/rel).is_dir():tree(rel,'hardware input / platform dependency')
    else:add(rel,'DPU configuration')
vpl='build/link/_x/link/vivado/vpl'
for rel in [vpl+'/scripts','build/link/_x/link/int/xo/ip_repo',vpl+'/.local/hw_platform/board',vpl+'/.local/hw_platform/iprepo']:
    tree(rel,'final link project transitive dependency')
for rel in [vpl+'/output/design_1_ooc_copy.xdc',vpl+'/output/_user_impl_clk.xdc',vpl+'/prj/prj.runs/impl_1/design_1_wrapper_routed.dcp',vpl+'/prj/prj.runs/impl_1/design_1_wrapper.bit',vpl+'/prj/prj.runs/impl_1/design_1_wrapper.vdi',vpl+'/prj/prj.runs/impl_1/.write_bitstream.end.rst',vpl+'/prj/prj.runs/impl_1/.vivado.end.rst','build/dpu_kernel/dpu_b4096.xo','build/link/_x/link/int/xo/DPUCZDX8G/DPUCZDX8G/kernel.xml']:
    add(rel,'same final build evidence / export input')
# Keep historical Tcl for reference, preserving their relative layout; not entrypoints.
tree('scripts','historical scripts: review before use')
tree('v014_unified_work_20261024/scripts','historical scripts: review before use')
# Capture other DPU packaging inputs but not temporary projects.
for q in (SRC/'third_party/DPUCZDX8G_TRD_2022.1/prj/Vitis').rglob('*'):
    if q.is_file() and len(q.relative_to(SRC/'third_party/DPUCZDX8G_TRD_2022.1/prj/Vitis').parts)==1:
        add(q.relative_to(SRC),'DPU build configuration')
manifest=[]
for rel,reason in sorted(selected.items()):
    src=SRC/rel; dst=ROOT/rel; dst.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(src,dst)
    manifest.append({'path':rel,'bytes':src.stat().st_size,'source_sha256':hashlib.sha256(src.read_bytes()).hexdigest(),'reason':reason})
# Fix only copies. XPR path macros keep projects movable.
patches=[]
for rel in PROJECTS:
    p=ROOT/rel; doc=ET.parse(p); base=p.parent
    doc.getroot().set('Path',p.as_posix())
    for e in doc.findall('.//Option'):
        if e.get('Name')=='IPRepoPath' and 'ipcache' in e.get('Val',''):
            e.set('Val','$PPRDIR/'+os.path.relpath(ROOT/'official_ip_repo',base).replace('\\','/'))
        if e.get('Name')=='IPOutputRepo':e.set('Val','$PPRDIR/'+p.stem+'.cache/ip')
    for e in doc.iter():
        for key,v in list(e.attrib.items()):
            if v.startswith(('R:/','V:/')):
                target=ROOT/v[3:]
                nv='$PPRDIR/'+os.path.relpath(target,base).replace('\\','/')
                patches.append([rel,v,nv]);e.set(key,nv)
    # ImportPath is provenance only; point to the actual copied File rather than duplicate extracted XSA project.
    for f in doc.findall('.//File'):
        for e in f.findall('.//Attr'):
            if e.get('Name')=='ImportPath':
                old=e.get('Val');e.set('Val',f.get('Path'));patches.append([rel,old,f.get('Path')])
    doc.write(p,encoding='UTF-8',xml_declaration=True)
# Script path patches use this package's absolute path. Re-run relocate.py after moving.
(ROOT/'collection_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
(ROOT/'path_patches.json').write_text(json.dumps(patches,ensure_ascii=False,indent=2),encoding='utf-8')
(ROOT/'collection_summary.json').write_text(json.dumps({'files':len(manifest),'bytes':sum(x['bytes'] for x in manifest),'original_root':str(SRC),'projects':PROJECTS},ensure_ascii=False,indent=2),encoding='utf-8')
print('COLLECTED',len(manifest),'files',round(sum(x['bytes'] for x in manifest)/1048576,1),'MiB')
