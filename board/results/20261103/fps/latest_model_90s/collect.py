import time,json,hashlib,zlib,base64
from pathlib import Path
p=Path('/home/xilinx/fengyan_v0173_grouped_20261103/state/results.jsonl')
out=Path('/home/xilinx/live_sampling_'+str(time.monotonic_ns()));out.mkdir()
probe=out/'write_probe.txt';probe.write_text('recording probe\n');assert probe.read_text()=='recording probe\n'
rows=[];errors=[];size0=p.stat().st_size
with p.open() as f:
 f.seek(0,2);f.readline();start=time.monotonic_ns();end=start+90_000_000_000
 with (out/'observed_results.jsonl').open('x') as dest:
  while time.monotonic_ns()<end:
   pos=f.tell();line=f.readline()
   if not line or not line.endswith('\n'):
    f.seek(pos);time.sleep(.03);continue
   try:
    r=json.loads(line);row={'observed_ns':time.monotonic_ns(),'result':r};rows.append(row);dest.write(json.dumps(row)+'\n');dest.flush()
   except Exception as e:errors.append(str(e))
stop=time.monotonic_ns()
summary={'board_directory':str(out),'boot_id':Path('/proc/sys/kernel/random/boot_id').read_text().strip(),'window_seconds':(stop-start)/1e9,'new_records':len(rows),'parse_errors':errors,'source_bytes_before':size0,'source_bytes_after':p.stat().st_size,'board_write_read_verified':True,'nonempty_detections':sum(bool(x['result'].get('detections')) for x in rows),'note':'Read-only observation of existing application output; polling timestamps are not internal stage timestamps or display latency.'}
if rows:
 first=rows[0]['result'];last=rows[-1]['result'];summary['first_request']=first.get('request_sequence');summary['last_request']=last.get('request_sequence');summary['last_hdmi_phase']=last.get('hdmi',{}).get('phase');summary['pl_last']=last.get('pl');summary['pl_delta']={k:last['pl'][k]-first['pl'][k] for k in ('completed','dropped','stale_results','aborted','profiler_timeouts')};summary['observed_record_rate']=len(rows)/summary['window_seconds'];summary['logged_seconds_mean']=sum(x['result']['seconds'] for x in rows)/len(rows)
(out/'summary.json').write_text(json.dumps(summary,indent=2))
data=json.dumps({'summary':summary,'records':rows}).encode();sha=hashlib.sha256(data).hexdigest()
(out/'evidence.json').write_bytes(data)
print('PREFLIGHT_SUMMARY '+json.dumps(summary));print('EVIDENCE_SHA256 '+sha);print('EVIDENCE_ZLIB_BASE64 '+base64.b64encode(zlib.compress(data)).decode())
