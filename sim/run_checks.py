import argparse
import datetime
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'sim/results'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--rtl', action='store_true')
    parser.add_argument('--vivado-bin', type=Path, default=Path('F:/Xilinx/Vivado/2022.2/bin'))
    args = parser.parse_args()
    OUT.mkdir(exist_ok=True)
    results = []
    runtime = ROOT / 'board/runtime'
    commands = [('runtime', [sys.executable, '-m', 'unittest', 'discover', '-s', str(runtime/'tests'), '-p', 'test_*.py', '-v']),
                ('device_tree', [sys.executable, str(runtime/'device_tree/test_prepare_boot_dtb.py')]),
                ('hdmi_iic', [sys.executable, str(runtime/'hdmi/test_hdmi_iic.py')]),
                ('hdmi_validation', [sys.executable, str(runtime/'hdmi/test_board_validation.py')])]
    for name, command in commands:
        proc = subprocess.run(command, cwd=str(ROOT), stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        text = proc.stdout.decode('utf-8', errors='replace')
        (OUT/(name+'.log')).write_text(text, encoding='utf-8')
        match = re.search(r'Ran (\d+) tests?', text)
        skipped = re.search(r'skipped=(\d+)', text)
        results.append(dict(name=name, exit_code=proc.returncode, tests=int(match[1]) if match else None,
                            skipped=int(skipped[1]) if skipped else 0))
    if args.rtl:
        ip = ROOT/'src/hardware/ip_repo'
        tests = [
            ('axi_control', 'tb_dpu_control_placeholder_axi', [ROOT/'src/hardware/rtl/dpu_control_placeholder_axi.v', ROOT/'src/hardware/rtl/tb_dpu_control_placeholder_axi.sv'], 'TB_PASS'),
            ('dummy_video', 'tb_dummy_video_in_source', [ip/'dummy_video_in_source_1_0/src/dummy_video_in_source.v', ip/'dummy_video_in_source_1_0/tb/tb_dummy_video_in_source.sv'], 'TB_DUMMY_VIDEO_IN_SOURCE_PASS'),
            ('video_integration', 'tb_dummy_pl_video_in_integration', [ip/'dummy_video_in_source_1_0/src/dummy_video_in_source.v', ip/'pl_video_in_1_0/src/pl_video_in.v', ip/'dummy_video_in_source_1_0/tb/tb_dummy_pl_video_in_integration.sv'], 'TB_DUMMY_PL_VIDEO_IN_INTEGRATION_PASS')]
        for name, top, sources, marker in tests:
            work = OUT/name
            work.mkdir(exist_ok=True)
            log = ''
            code = 0
            for tool, arguments in [('xvlog',['-sv']+list(map(str,sources))), ('xelab',[top,'-s',top+'_sim']), ('xsim',[top+'_sim','-runall'])]:
                executable = args.vivado_bin/(tool+('.bat' if sys.platform=='win32' else ''))
                proc = subprocess.run([str(executable)]+arguments, cwd=str(work), stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                log += proc.stdout.decode('utf-8', errors='replace')
                code = proc.returncode
                if code:
                    break
            (OUT/(name+'.log')).write_text(log, encoding='utf-8')
            results.append(dict(name=name, exit_code=code, pass_marker=marker in log,
                                fatal_message=bool(re.search(r'Fatal:|\$fatal', log))))
    passed = all(r['exit_code']==0 and r.get('pass_marker',True) and not r.get('fatal_message',False) for r in results)
    report = dict(timestamp=datetime.datetime.now().isoformat(), results=results, passed=passed,
                  board_verified=False, rtl_requested=args.rtl)
    (OUT/'summary.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report, indent=2))
    return 0 if passed else 1


if __name__ == '__main__':
    sys.exit(main())
