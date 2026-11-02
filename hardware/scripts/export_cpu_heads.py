"""Extract the six supported CPU heads from the approved original XModel.
Requires generated AMD serial_v2 protobuf bindings on the exporting PC only.
"""
import hashlib
import json
from pathlib import Path
import re
import numpy as np
from graph_proto_v2_pb2 import Graph

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'V0.16_给丙上板包' / 'board_support' / 'cpu_heads'

def value(attrs, key):
    attr = attrs[key]
    kind = attr.WhichOneof('value')
    result = getattr(attr, kind)
    return list(result.value) if kind.endswith('_vec_value') else result

def arg(op, key):
    matches = [a for a in op.args if a.arg_name == key]
    if len(matches) != 1 or len(matches[0].arg_ops) != 1:
        raise ValueError('Unexpected input: ' + op.op_name)
    return matches[0].arg_ops[0]

def quantized_const(ops, name):
    fix = ops[name]
    assert fix.op_type == 'fix'
    assert value(fix.op_attr, 'round_mode') == 'DPU_ROUND'
    assert value(fix.op_attr, 'bit_width') == 8
    assert value(fix.op_attr, 'if_signed') is True
    const = ops[arg(fix, 'input')]
    assert const.op_type == 'const'
    assert value(const.op_attr, 'data_type') == 'FLOAT32'
    data = np.frombuffer(const.op_attr['data'].bytes_value.value, dtype='<f4').copy()
    data = data.reshape(list(const.output_tensor.tensor_dim))
    assert np.isfinite(data).all()
    fp = value(fix.op_attr, 'fix_point')
    quant = np.clip(np.floor(data.astype(np.float64) * 2.0**fp + 0.5), -128, 127).astype(np.int8)
    return data, quant, fp

def main():
    model = ROOT / 'models/tank_yolov8n_relu_latest_six_outputs.xmodel'
    raw = model.read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    assert digest == '9f6302986694ead804ae7542d7c39fbbb49cef5e9a28fa8419dc7e060a52568b'
    graph = Graph.FromString(raw)
    ops = {o.op_name: o for o in graph.op_node}
    branches, arrays = [], {}
    def walk(s):
        if 'device' in s.subg_attr and value(s.subg_attr, 'device') == 'CPU':
            yield s
        for child in s.subg_child:
            yield from walk(child)
    for subgraph in walk(graph.subg_root):
        members = [ops[n] for n in subgraph.op_name]
        assert sorted(o.op_type for o in members) == ['const','const','conv2d','fix','fix','fix2float']
        conv, = [o for o in members if o.op_type == 'conv2d']
        m = re.search(r'Sequential_cv([23])__ModuleList_([012])__Conv2d_2', conv.op_name)
        assert m, conv.op_name
        kind, scale = m.groups()
        name = 'cv%s_%s' % (kind, scale)
        for key, expected in [('kernel',[1,1]),('stride',[1,1]),('dilation',[1,1]),('pad',[0,0,0,0]),('group',1),('bias_term',True)]:
            assert value(conv.op_attr,key) == expected, (name,key)
        dequant = ops[arg(conv, 'input')]
        assert dequant.op_type == 'fix2float'
        assert value(dequant.op_attr,'bit_width') == 8 and value(dequant.op_attr,'if_signed') is True
        external = ops[arg(dequant, 'input')]
        assert external.op_type == 'download'
        fp = value(dequant.op_attr,'fix_point')
        assert value(external.output_tensor.tensor_attr, 'fix_point') == fp
        w, qw, wfp = quantized_const(ops, arg(conv,'weights'))
        b, qb, bfp = quantized_const(ops, arg(conv,'bias'))
        shape = list(external.output_tensor.tensor_dim)
        assert shape == [1,80//2**int(scale),80//2**int(scale),64]
        assert w.shape == ((64 if kind=='2' else 1),1,1,64)
        arrays.update({name+'_weight':qw[:,0,0,:],name+'_bias':qb,
                       name+'_original_weight':w,name+'_original_bias':b})
        branches.append(dict(name=name, input_name=external.output_tensor.tensor_name,
                             input_shape=shape,input_fix_point=fp,weight_fix_point=wfp,
                             bias_fix_point=bfp,output_name=conv.output_tensor.tensor_name,
                             output_shape=list(conv.output_tensor.tensor_dim)))
    assert len(branches)==6 and len({b['input_name'] for b in branches})==6
    OUT.mkdir(parents=True,exist_ok=True)
    np.savez(OUT/'constants.npz',**arrays)
    info=dict(model_sha256=digest,branches=sorted(branches,key=lambda x:x['name']),
              status='OFFLINE_IMPLEMENTATION_BOARD_VALIDATION_PENDING')
    (OUT/'heads.json').write_text(json.dumps(info,indent=2),encoding='utf-8')
    print('MODEL_PARSED; SIX_CPU_HEADS_EXTRACTED; CONSTANT_QUANTIZATION_EXPORTED')

if __name__=='__main__':
    main()
