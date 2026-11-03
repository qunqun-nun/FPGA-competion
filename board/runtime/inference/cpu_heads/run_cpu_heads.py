"""NumPy execution of the six extracted 1x1 CPU heads; no CPU Runner .so.

Input arrays must be the named raw INT8 outputs of the DPU Runner, in NHWC.
The output is six float32 logits, before DFL/sigmoid/NMS.
"""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np

class CpuHeads:
    def __init__(self, directory=None):
        self.directory=Path(directory or Path(__file__).resolve().parent)
        self.spec=json.loads((self.directory/'heads.json').read_text(encoding='utf-8'))
        with np.load(self.directory/'constants.npz',allow_pickle=False) as arrays:
            self.constants={k:arrays[k].copy() for k in arrays.files}

    def run(self, named_features):
        outputs={}
        for branch in self.spec['branches']:
            name=branch['name']
            tensor_name=branch['input_name']
            if tensor_name not in named_features:
                raise ValueError('Missing exact DPU tensor name: '+tensor_name)
            x=np.asarray(named_features[tensor_name])
            if x.dtype!=np.int8 or list(x.shape)!=branch['input_shape']:
                raise ValueError('Expected raw NHWC int8 '+str(branch['input_shape'])+' for '+name)
            # Exact integer accumulation followed by power-of-two scaling.
            # Weights and bias have already passed the XModel fix operators.
            w=self.constants[name+'_weight'].astype(np.int32)
            acc=x.astype(np.int32) @ w.T
            y=np.ldexp(acc.astype(np.float32),-(branch['input_fix_point']+branch['weight_fix_point']))
            bias=np.ldexp(self.constants[name+'_bias'].astype(np.float32),-branch['bias_fix_point'])
            y=(y+bias).astype(np.float32)
            if list(y.shape)!=branch['output_shape'] or not np.isfinite(y).all():
                raise ValueError('Invalid head output '+name)
            outputs[name]=y
        return outputs

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--features',required=True,type=Path)
    ap.add_argument('--output',required=True,type=Path)
    args=ap.parse_args()
    if args.output.exists():
        raise FileExistsError(args.output)
    heads=CpuHeads()
    with np.load(args.features,allow_pickle=False) as features:
        outputs=heads.run(features)
    np.savez(args.output,**outputs)
    print('CPU_SIX_HEADS_EXECUTE_OK; DFL_NMS_NOT_RUN')
    for k,v in outputs.items():
        print(k,list(v.shape),float(v.min()),float(v.max()))

if __name__=='__main__':
    main()
