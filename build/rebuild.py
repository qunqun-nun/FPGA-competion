import argparse
import json
from pathlib import Path
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--vitis-bin', type=Path, default=Path('F:/Xilinx/Vitis/2022.2/bin'))
    args = parser.parse_args()
    xpfm = ROOT/'build/inputs/platform/fengyan_v017_zcu104.xpfm'
    xo = ROOT/'build/inputs/dpu_b4096.xo'
    xsa = ROOT/'build/inputs/platform/hw/fengyan_v017_extensible.xsa'
    for path in (xpfm, xo, xsa):
        if not path.is_file():
            raise FileNotFoundError(path)
    for path in (xo, xsa):
        with zipfile.ZipFile(path) as archive:
            if archive.testzip():
                raise RuntimeError('Damaged archive: '+str(path))
    print('LINK_INPUT_ARCHIVES_OK')
    if args.check:
        return 0
    out = ROOT/'build/output'
    out.mkdir(exist_ok=False)
    hook = (ROOT/'build/pre_bitstream_hold_fix.tcl').as_posix()
    cfg = ('[connectivity]\nnk=DPUCZDX8G:1:DPUCZDX8G_1\n'
           'sp=DPUCZDX8G_1.M_AXI_GP0:HPC0\nsp=DPUCZDX8G_1.M_AXI_HP0:HP1\nsp=DPUCZDX8G_1.M_AXI_HP2:HP2\n'
           '[clock]\nfreqHz=299997003:DPUCZDX8G_1.aclk\nfreqHz=599994006:DPUCZDX8G_1.ap_clk_2\n'
           '[advanced]\nmisc=:solution_name=link\n[vivado]\nparam=general.maxThreads=4\n'
           'prop=run.impl_1.strategy=Performance_Explore\n'
           'prop=run.impl_1.STEPS.WRITE_BITSTREAM.TCL.PRE='+hook+'\n')
    (out/'link.cfg').write_text(cfg, encoding='utf-8')
    vpp = args.vitis_bin/('v++.bat' if sys.platform=='win32' else 'v++')
    command = [str(vpp),'--link','--target','hw','--no_ip_cache','--platform',str(xpfm),'--config',str(out/'link.cfg'),
               '--save-temps','--temp_dir',str(out/'_x'),'--log_dir',str(out/'logs'),'--output',str(out/'fengyan.xclbin'),str(xo)]
    (out/'command.json').write_text(json.dumps(command,indent=2), encoding='utf-8')
    return subprocess.call(command, cwd=str(out))


if __name__ == '__main__':
    sys.exit(main())
