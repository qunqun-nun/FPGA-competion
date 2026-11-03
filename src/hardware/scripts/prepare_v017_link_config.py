"""Prepare configs only. Does not map a drive, launch v++, or edit any existing project."""
from pathlib import Path
import argparse,os
root=Path(__file__).resolve().parent.parent
p=argparse.ArgumentParser();p.add_argument('--mapped-root',help='Existing subst to this rebuild, e.g. W:/');args=p.parse_args()
mapped=Path(args.mapped_root) if args.mapped_root else root
if args.mapped_root:
 a=root/'change_backup/affected_files.json';b=mapped/'change_backup/affected_files.json'
 if not b.exists() or not os.path.samefile(a,b):raise SystemExit('mapped-root must already refer to this rebuild')
dcp=mapped/'build/link/_x/link/vivado/vpl/prj/prj.runs/impl_1/design_1_wrapper_routed.dcp'
if not dcp.is_file():raise SystemExit('Retained routed checkpoint missing')
text=(root/'config/link.cfg').read_text(encoding='utf-8')
if '[vivado]' not in text:text+='\n[vivado]\n'
(root/'config/link_v017_normal.cfg').write_text(text,encoding='utf-8')
text+='\n# Reference only. New implementation and sign-off are still required.\n'
text+='prop=run.impl_1.AUTO_INCREMENTAL_CHECKPOINT=0\n'
text+='prop=run.impl_1.INCREMENTAL_CHECKPOINT='+dcp.as_posix()+'\n'
(root/'config/link_v017_incremental.cfg').write_text(text,encoding='utf-8')
print('INCREMENTAL_REFERENCE='+dcp.as_posix())
print('CONFIG='+str(root/'config/link_v017_incremental.cfg'))
print('NORMAL_FALLBACK_CONFIG='+str(root/'config/link_v017_normal.cfg'))
