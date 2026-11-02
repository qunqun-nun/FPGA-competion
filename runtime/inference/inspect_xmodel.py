"""Read-only XModel inspection on a PC with AMD protobuf bindings.

Usage: py -3.12 inspect_xmodel.py --model ... --proto-dir ... --deps-dir ...
Writes model_inspection.json only next to this script; never modifies XModel.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys
sys.dont_write_bytecode = True


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--model', required=True, type=Path)
    ap.add_argument('--proto-dir', required=True, type=Path)
    ap.add_argument('--deps-dir', type=Path)
    args=ap.parse_args()
    if args.deps_dir: sys.path.insert(0,str(args.deps_dir))
    sys.path.insert(0,str(args.proto_dir))
    from graph_proto_v2_pb2 import Graph
    raw=args.model.read_bytes()
    graph=Graph.FromString(raw)
    def val(a):
        k=a.WhichOneof('value'); result=getattr(a,k)
        if k.endswith('_vec_value'): return list(result.value)
        return result
    ops={o.op_name:o for o in graph.op_node}
    subgraphs=[]
    def walk(s):
        if 'device' in s.subg_attr:
            subgraphs.append({'name':s.subgraph_name,'device':val(s.subg_attr['device']),
                              'member_op_types':[ops[n].op_type for n in s.op_name]})
        for child in s.subg_child: walk(child)
    walk(graph.subg_root)
    uploads=[o for o in graph.op_node if o.op_type=='upload']
    heads=json.loads(Path(__file__).with_name('cpu_heads').joinpath('heads.json').read_text(encoding='utf-8'))
    digest=hashlib.sha256(raw).hexdigest()
    assert digest==heads['model_sha256']
    assert sum(s['device']=='DPU' for s in subgraphs)==1
    assert sum(s['device']=='CPU' for s in subgraphs)==6
    assert len(uploads)==1
    for b in heads['branches']:
        external=next(o for o in graph.op_node if o.output_tensor.tensor_name==b['input_name'])
        assert list(external.output_tensor.tensor_dim)==b['input_shape']
        assert val(external.output_tensor.tensor_attr['fix_point'])==b['input_fix_point']
        conv=next(o for o in graph.op_node if o.output_tensor.tensor_name==b['output_name'])
        assert conv.op_type=='conv2d'
        assert list(conv.output_tensor.tensor_dim)==b['output_shape']
        for key,expected in [('kernel',[1,1]),('stride',[1,1]),('pad',[0,0,0,0]),('group',1)]:
            assert val(conv.op_attr[key])==expected
    u=uploads[0]
    input_info={'name':u.output_tensor.tensor_name,'shape':list(u.output_tensor.tensor_dim),
                'attrs':{k:val(v) for k,v in u.output_tensor.tensor_attr.items()}}
    assert input_info['shape']==[1,640,640,3]
    assert input_info['attrs']['fix_point']==6
    report={'model_sha256':digest,'model_bytes':len(raw),'op_count':len(ops),
            'input':input_info,'subgraphs':subgraphs,'six_cpu_contracts_verified':True,
            'reg_max':16,'num_classes':1,'strides':[8,16,32],
            'decode_structure_basis':'six output shapes + Ultralytics YOLOv8 DFL convention',
            'status':'STATIC_INSPECTION_ONLY_BOARD_VALIDATION_PENDING'}
    dest=Path(__file__).with_name('model_inspection.json')
    dest.write_text(json.dumps(report,indent=2,ensure_ascii=False),encoding='utf-8')
    print(json.dumps(report,indent=2,ensure_ascii=False))

if __name__=='__main__': main()
