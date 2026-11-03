"""Offline replay: exact tensor-name NPZ -> source-pixel xywh JSON."""
import argparse
import json
from pathlib import Path
import numpy as np
if __package__:
    from .cpu_heads.run_cpu_heads import CpuHeads
    from .postprocess import ImageTransform, decode
else:
    from cpu_heads.run_cpu_heads import CpuHeads
    from postprocess import ImageTransform, decode


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--features',required=True,type=Path)
    p.add_argument('--confidence',type=float,default=0.25)
    p.add_argument('--iou',type=float,default=0.45)
    p.add_argument('--source-width',type=int,default=640)
    p.add_argument('--source-height',type=int,default=480)
    p.add_argument('--scale',type=float,default=1.0)
    p.add_argument('--pad-x',type=float,default=0.0)
    p.add_argument('--pad-y',type=float,default=80.0)
    a=p.parse_args()
    with np.load(a.features,allow_pickle=False) as f:
        logits=CpuHeads().run(f)
    t=ImageTransform(a.source_width,a.source_height,a.scale,a.pad_x,a.pad_y)
    print(json.dumps({'detections':decode(logits,t,a.confidence,a.iou),
                      'validation':'OFFLINE_REPLAY_ONLY_NOT_ACCURACY_VALIDATION'},ensure_ascii=False))

if __name__=='__main__': main()
