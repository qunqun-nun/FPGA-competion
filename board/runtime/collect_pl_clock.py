#!/usr/bin/env python3
"""Collect real board evidence. Default is read-only; --load programs this package."""
import argparse
import hashlib
import inspect
import json
import platform
import shutil
import sys
import time
from pathlib import Path
from pl_clock import snapshot, assert_clock


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--out',type=Path,required=True)
    p.add_argument('--load',action='store_true')
    p.add_argument('--runner',action='store_true')
    p.add_argument('--seconds',type=int,default=60)
    a=p.parse_args()
    if a.runner and not a.load: p.error('--runner requires --load')
    if not 1 <= a.seconds <= 3600: p.error('seconds must be 1..3600')
    a.out.mkdir(parents=True,exist_ok=False)
    from pynq import Clocks, Overlay
    import pynq
    from package_config import hardware_paths
    config,files=hardware_paths()
    def emit(stage,check=False,extra=None):
        data=dict(stage=stage,**(assert_clock(files['hwh']) if check else snapshot()))
        if extra is not None:data['extra']=extra
        with (a.out/'clock.jsonl').open('a') as f:f.write(json.dumps(data)+'\n')
        print(json.dumps(data),flush=True)
    info=dict(python=sys.version,uname=platform.uname()._asdict(),pynq=pynq.__version__,
              hardware=config,hashes={k:hashlib.sha256(v.read_bytes()).hexdigest() for k,v in files.items()},
              board_acceptance='PENDING',frequency_kind='register-derived; not direct physical frequency counter')
    (a.out/'environment.json').write_text(json.dumps(info,indent=2))
    for module in ('pynq.ps','pynq.overlay','pynq.pl_server.hwh_parser','pynq_dpu.dpu'):
        try:
            mod=__import__(module,fromlist=['x'])
            (a.out/(module+'.py')).write_text(inspect.getsource(mod))
        except Exception as e:(a.out/(module+'.error.txt')).write_text(repr(e))
    for source,name in [('/sys/firmware/fdt','running.dtb'),('/proc/cmdline','cmdline.txt'),
                         ('/sys/kernel/debug/clk/clk_summary','kernel_clk_summary.txt')]:
        try:shutil.copyfile(source,str(a.out/name))
        except Exception as e:(a.out/(name+'.unavailable.txt')).write_text(repr(e))
    emit('before_parse_or_download')
    overlay=Overlay(str(files['bit']),download=False)
    emit('after_parse_without_download',extra={'clock_dict':overlay.clock_dict})
    if a.load:
        from load_overlay import main as load
        overlay=load()
        emit('after_fixed_pynq_download',True,{'clock_dict':overlay.clock_dict})
        if a.runner:
            from inference import Detector
            detector=Detector(model_path=Path(__file__).resolve().parent.parent/'models/tank_yolov8n_relu_latest_six_outputs.xmodel')
            emit('after_dpu_runner_creation',True)
    try:
        for i in range(a.seconds):
            emit('steady_'+str(i),check=a.load)
            time.sleep(1)
    finally:
        state=Path(__file__).resolve().parent.parent/'state/pl_clock.jsonl'
        if state.exists():shutil.copy2(str(state),str(a.out/'loader_pl_clock.jsonl'))
    (a.out/'result.json').write_text(json.dumps(dict(status='CLOCK_SAMPLING_PASS' if a.load else 'READONLY_CAPTURE_COMPLETE',
        samples=a.seconds,hdmi_verified=False,physical_frequency_measured=False)))


if __name__=='__main__':main()
