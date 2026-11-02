"""Offline tests with real model constants and synthetic DPU feature tensors."""
import json
import math
from pathlib import Path
import numpy as np
if __package__:
    from .run_cpu_heads import CpuHeads
else:
    from run_cpu_heads import CpuHeads

def reference_round(v):
    if v>127:return 127
    if v< -128:return -128
    if v<0 and v-math.floor(v)==0.5:return math.ceil(v)
    return math.floor(v+0.5) if v>=0 else math.ceil(v-0.5)

def main():
    heads=CpuHeads()
    count=0
    for b in heads.spec['branches']:
        for field in ('weight','bias'):
            original=heads.constants[b['name']+'_original_'+field]
            expected=np.array([reference_round(float(x)*2.0**b[field+'_fix_point']) for x in original.flat],dtype=np.int8)
            np.testing.assert_array_equal(expected,heads.constants[b['name']+'_'+field].reshape(-1))
            count+=expected.size
    rng=np.random.default_rng(20261031)
    cases=[]
    for mode in ('zero','min','max','random'):
        features={}
        for b in heads.spec['branches']:
            shape=b['input_shape']
            features[b['input_name']]=(rng.integers(-128,128,shape,dtype=np.int8) if mode=='random'
                else np.full(shape,{'zero':0,'min':-128,'max':127}[mode],dtype=np.int8))
        out=heads.run(features)
        max_error=0.0
        for b in heads.spec['branches']:
            x=features[b['input_name']].astype(np.float64)/2.0**b['input_fix_point']
            w=heads.constants[b['name']+'_weight'].astype(np.float64)/2.0**b['weight_fix_point']
            bias=heads.constants[b['name']+'_bias'].astype(np.float64)/2.0**b['bias_fix_point']
            ref=(np.einsum('nhwc,oc->nhwo',x,w,optimize=False)+bias).astype(np.float32)
            error=float(np.max(np.abs(ref-out[b['name']])))
            max_error=max(error,max_error)
            np.testing.assert_allclose(out[b['name']],ref,rtol=0,atol=1e-5)
        cases.append({'case':mode,'six_heads':'PASS','max_abs_error':max_error})
    sample={b['input_name']:np.zeros(b['input_shape'],np.int8) for b in heads.spec['branches']}
    for mode in ('missing','wrong_dtype','wrong_shape'):
        bad=dict(sample)
        key=next(iter(bad))
        if mode=='missing':del bad[key]
        elif mode=='wrong_dtype':bad[key]=bad[key].astype(np.float32)
        else:bad[key]=bad[key].reshape(-1)
        try:heads.run(bad)
        except ValueError:pass
        else:raise AssertionError('Did not reject '+mode)
    report={'status':'OFFLINE_TEST_PASS','quantized_constants_checked':count,'cases':cases,
            'invalid_input_checks':3,'board_execution':'PENDING',
            'vendor_cpu_runner_comparison':'PENDING',
            'scope':'real XModel constants, synthetic INT8 DPU features, independent float64 algebra reference'}
    path=Path(__file__).with_name('offline_test_report.json')
    path.write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps(report,indent=2))

if __name__=='__main__':main()
