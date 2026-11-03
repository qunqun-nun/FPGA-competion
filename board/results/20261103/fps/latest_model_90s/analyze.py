import json,sys,csv,math
from pathlib import Path
from collections import Counter
p=Path(sys.argv[1]);obj=json.loads((p/'evidence.json').read_text());rows=obj['records'];s=obj['summary'];st=Counter(r['result']['pl']['fusion'] for r in rows)
durations=sorted(r['result']['seconds']*1000 for r in rows)
with (p/'results.csv').open('w',newline='',encoding='utf-8-sig') as f:
 w=csv.writer(f);w.writerow(['observed_ns','request_sequence','frame_id','logged_loop_ms','detections_json','track_status','fusion_state','tracker_active','processing_busy','lost','completed','dropped'])
 for x in rows:
  r=x['result'];v=r['pl']['fusion'];w.writerow([x['observed_ns'],r['request_sequence'],r['frame_id'],r['seconds']*1000,json.dumps(r['detections']),v,v&7,bool(v&256),bool(v&512),bool(v&1024),r['pl']['completed'],r['pl']['dropped']])
metrics={'observation_seconds':s['window_seconds'],'detection_result_records':len(rows),'nonempty_detection_records':s['nonempty_detections'],'observed_detection_output_fps':s['observed_record_rate'],'logged_loop_ms_mean':sum(durations)/len(durations),'logged_loop_ms_p95':durations[math.ceil(.95*len(durations))-1],'track_status_counts_at_detection_records':dict(st),'records_tracker_active':sum(bool(r['result']['pl']['fusion']&256) for r in rows),'tracking_fps':None,'tracking_fps_reason':'No per-frame track-valid counter/frame ID exposed via current AXI register map; detection-time status samples cannot count tracking outputs.','pl_counter_deltas_between_first_last_records':s['pl_delta'],'valid_position_accuracy':None,'display_latency_ms':None}
(p/'metrics.json').write_text(json.dumps(metrics,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(metrics,ensure_ascii=False,indent=2))
for x in rows:
 r=x['result']
 if r['detections']: print('DETECTION',r['request_sequence'],json.dumps(r['detections']), 'STATUS',r['pl']['fusion'])
