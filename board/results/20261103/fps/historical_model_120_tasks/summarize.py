import csv,json,math,statistics
from pathlib import Path
B=Path(__file__).parent; E=B/'board'; entries=list(E.glob('*/tasks.jsonl')); assert len(entries)==1,entries
P=entries[0].parent; allrows=[json.loads(l) for l in (P/'tasks.jsonl').read_text().splitlines()]; rows=[r for r in allrows if not r['warmup']]
assert len(rows)>=100
capture=json.loads((P/'capture.json').read_text());session=json.loads((P/'session.json').read_text());meta=json.loads((P/'metadata.json').read_text());seconds=(session['end_ns']-session['start_ns'])/1e9
keys=['input_tensor_ms','dpu_submit_to_ready_ms','cpu_heads_ms','decode_nms_restore_ms','detection_service_ms','submit_to_pl_accept_ms','observed_request_to_accept_ms']
def stats(vals):
    vals=sorted(vals);return {'n':len(vals),'mean_ms':statistics.mean(vals),'p95_ms':vals[math.ceil(.95*len(vals))-1],'min_ms':vals[0],'max_ms':vals[-1]}
summary={'measured_tasks':len(rows),'warmup_tasks':len(allrows)-len(rows),'duration_seconds':seconds,'successful_camera_read_fps':capture['window_successful_reads']/seconds,'full_detection_service_fps':len(rows)/seconds,'detection_service_only_reciprocal_not_system_fps':1000/statistics.mean(r['detection_service_ms'] for r in rows),'nonempty_detection_tasks':sum(bool(r['detections']) for r in rows),'nonempty_detection_publication_fps':sum(bool(r['detections']) for r in rows)/seconds,'phase_timings':{k:stats([r[k] for r in rows]) for k in keys},'start_counters':allrows[9]['pl'],'end_counters':rows[-1]['pl'],'counter_deltas':{k:(rows[-1]['pl'][k]-allrows[9]['pl'][k])%(2**32) for k in ('frames','completed','dropped','stale_results','aborted','profiler_timeouts')},'track_status_values':sorted(set(r['track_status'] for r in rows)),'exitcode':(P/'exitcode').read_text().strip(),'all_records_stream_up':all(json.loads(l)['hdmi']['stream_up'] for l in (P/'pipeline_results.jsonl').read_text().splitlines()),'metadata':meta}
(B/'summary.json').write_text(json.dumps(summary,indent=2,ensure_ascii=False),encoding='utf8')
with (B/'tasks.csv').open('w',newline='',encoding='utf-8-sig') as f:
    fields=['task','warmup','frame_id','request_sequence','buffer_id','generation','request_observed_ns','accepted_ns','capture_count','track_status','result_status']+keys+['detections_json','pl_json'];w=csv.DictWriter(f,fieldnames=fields);w.writeheader()
    for r in allrows:
        o={k:r[k] for k in fields if k in r};o['detections_json']=json.dumps(r['detections']);o['pl_json']=json.dumps(r['pl']);w.writerow(o)
print(json.dumps({k:v for k,v in summary.items() if k!='metadata'},indent=2))
