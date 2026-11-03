"""External instrumentation; original package files are not modified."""
import sys,time,json,signal,os,runpy,threading,hashlib
from pathlib import Path
ROOT=Path('/home/xilinx/fengyan_v0173_model50_iicfix1_20261102')
sys.path.insert(0,str(ROOT/'runtime'))
OUT=Path(sys.argv[1]);OUT.mkdir(parents=True,exist_ok=True)
import cv2
from inference import detector as d
import pl_runtime as pl
clock=time.perf_counter_ns
state={'tasks':0,'capture_count':0,'capture_times':[],'ctx':{},'start_ns':None,'end_ns':None}
f=(OUT/'tasks.jsonl').open('w',buffering=1)
def wrap_stage(obj,name,key):
    original=getattr(obj,name)
    def timed(*a,**kw):
        t=clock();r=original(*a,**kw);state['ctx'][key]=(clock()-t)/1e6;return r
    setattr(obj,name,timed)
wrap_stage(d,'quantize_rgb888','input_tensor_ms')
wrap_stage(d,'decode','decode_nms_restore_ms')
wrap_stage(d.CpuHeads,'run','cpu_heads_ms')
orig_init=d.DpuRunner.__init__
class RunnerProxy:
    def __init__(self,runner):self.runner=runner
    def __getattr__(self,k):return getattr(self.runner,k)
    def execute_async(self,*a,**kw):
        state['dpu_submit_ns']=clock();return self.runner.execute_async(*a,**kw)
    def wait(self,*a,**kw):
        r=self.runner.wait(*a,**kw);state['ctx']['dpu_submit_to_ready_ms']=(clock()-state['dpu_submit_ns'])/1e6;return r
def runner_init(self,*a,**kw):
    orig_init(self,*a,**kw);self.runner=RunnerProxy(self.runner)
d.DpuRunner.__init__=runner_init
orig_detect=d.Detector.detect_pl_rgb888
def detect(self,*a,**kw):
    state['ctx']={};t=clock();r=orig_detect(self,*a,**kw);state['ctx']['detection_service_ms']=(clock()-t)/1e6;state['ctx']['detections']=r;return r
d.Detector.detect_pl_rgb888=detect
orig_capture=cv2.VideoCapture
class CaptureProxy:
    def __init__(self,*a,**kw):self.cap=orig_capture(*a,**kw)
    def __getattr__(self,k):return getattr(self.cap,k)
    def read(self,*a,**kw):
        ok,im=self.cap.read(*a,**kw)
        if ok:
            state['capture_count']+=1
            state['capture_times'].append(clock())
        return ok,im
cv2.VideoCapture=CaptureProxy
orig_request=pl.Board.request
def request(self,*a,**kw):
    t=clock();r=orig_request(self,*a,**kw)
    if r is not None:state['request_observed_ns']=t;state['request_ack_ns']=clock()
    return r
pl.Board.request=request
orig_publish=pl.Board.publish
def publish(self,request,detections):
    t=clock();orig_publish(self,request,detections);end=clock();state['tasks']+=1
    n=state['tasks'];row=dict(state['ctx']);row.update(task=n,warmup=n<=10,frame_id=request[1],request_sequence=request[0],buffer_id=request[2],generation=request[3],request_observed_ns=state.get('request_observed_ns'),accepted_ns=end,submit_to_pl_accept_ms=(end-t)/1e6,observed_request_to_accept_ms=(end-state['request_observed_ns'])/1e6,pl=self.snapshot(),track_status=self.ctrl.read(0xf8),result_status=self.ctrl.read(0x5c),capture_count=state['capture_count'])
    f.write(json.dumps(row)+'\n')
    if n==10:state['start_ns']=end
    if n>=130:
        state['end_ns']=end;os.kill(os.getpid(),signal.SIGTERM)
pl.Board.publish=publish
metadata={'host_test_date':'2026-11-03 Asia/Shanghai','boot_id':Path('/proc/sys/kernel/random/boot_id').read_text().strip(),'package':str(ROOT),'input_camera':[640,480],'input_dpu':[1,640,640,3],'hdmi':[1280,720,60],'confidence':0.25,'nms_iou':0.45,'requested_fps':5,'warmup_tasks':10,'target_measured_tasks':120,'instrumentation_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'model_sha256':hashlib.sha256((ROOT/'models/tank_yolov8n_relu_latest_six_outputs.xmodel').read_bytes()).hexdigest(),'limitations':['Capture FPS counts successful OpenCV read completions, not sensor exposure timestamps.','Request wait before software first observes it is not directly timestamped; unmeasured.','No display photon latency measurement.','Only deployed integrated hardware configuration tested; no fabricated ablation switches.']}
metadata['hardware_sha256']={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in (ROOT/'hardware').iterdir() if p.suffix in ('.bit','.hwh','.xclbin')}
(OUT/'metadata.json').write_text(json.dumps(metadata,indent=2))
sys.argv=[str(ROOT/'runtime/run_pipeline.py'),'--load','--hdmi','--camera','/dev/video0','--fps','5','--output',str(OUT/'pipeline_results.jsonl')]
try:runpy.run_path(str(ROOT/'runtime/run_pipeline.py'),run_name='__main__')
finally:
    f.close();end=state['end_ns'] or clock();start=state['start_ns'];times=state['capture_times'];(OUT/'capture.json').write_text(json.dumps({'successful_read_completion_ns':times,'window_start_ns':start,'window_end_ns':end,'window_successful_reads':sum(start<t<=end for t in times) if start else None,'total_successful_reads':state['capture_count']}));(OUT/'session.json').write_text(json.dumps({k:v for k,v in state.items() if k not in ('capture_times','ctx')},indent=2))
