"""Run offline PL simulations and native RAM/build checks, never real PL."""
import hashlib
import io
import json
from pathlib import Path
import sys
import unittest
from datetime import datetime, timezone

ROOT=Path(__file__).resolve().parent
EVIDENCE=ROOT/'evidence'
EVIDENCE.mkdir(exist_ok=True)
sys.path.insert(0,str(ROOT))
source_names=('pl_runtime.py','native/memio.c','run_pipeline.py','camera_source.py',
              'start.sh','hdmi/pynq_hdmi_init.py')
before={name:hashlib.sha256((ROOT.parent/name).read_bytes()).hexdigest()
        for name in source_names}
suite=unittest.TestSuite()
for name in ('test_pl_runtime','test_memio_native','test_camera_source','test_pipeline_progress'):
    suite.addTests(unittest.defaultTestLoader.loadTestsFromName(name))
stream=io.StringIO()
result=unittest.TextTestRunner(stream=stream,verbosity=2).run(suite)
(EVIDENCE/'runtime_audit.log').write_text(stream.getvalue(),encoding='utf-8')
print(stream.getvalue())
sources={}
for name,old in before.items():
    digest=hashlib.sha256((ROOT.parent/name).read_bytes()).hexdigest()
    sources[name]={'sha256':digest,'matches_test_start':digest==old}
known=[str(test) for test,_ in result.expectedFailures]
failed=bool(result.errors or result.failures or result.unexpectedSuccesses or known or
            any(not x['matches_test_start'] for x in sources.values()))
report={'status':'OFFLINE_TEST_FAIL' if failed else ('OFFLINE_TEST_INCOMPLETE' if result.skipped else 'OFFLINE_TEST_PASS'),
 'run_utc':datetime.now(timezone.utc).isoformat(),
 'scope':'offline Python PL model + controlled camera threads + host RAM execution + AArch64 cross compilation; NOT real PL/RTL/UVC execution',
 'tests':result.testsRun,'ordinary_passes':result.testsRun-len(result.expectedFailures)-len(result.skipped)-len(result.errors)-len(result.failures)-len(result.unexpectedSuccesses),
 'expected_review_failures':known,'unexpected_failures':len(result.failures),'errors':len(result.errors),
 'unexpected_successes':[str(x) for x in result.unexpectedSuccesses],
 'skipped':[{'test':str(t),'reason':why} for t,why in result.skipped],
 'source_integrity':sources,'native_host_execution':'allocated RAM only',
 'aarch64_board_execution':'NOT_RUN','hardware_dma_mmio_cache_test':'NOT_RUN',
 'camera_device_test':'NOT_RUN',
 'camera_offline_scope':'latest replacement, disconnect/error propagation, bounded next/close, release not concurrent with read, main-loop next/close integration',
 'main_cli_offline_scope':'default --load/--hdmi false plus all four flag combinations and HdmiSession stub lifecycle; no real overlay download or HDMI initialization',
 'owner_timeout_mainloop':'simulated 1.01s inference; explicit PL owner timeout; exit 1; no committed result or JSONL success',
 'exit_code':1 if failed else (2 if result.skipped else 0)}
(EVIDENCE/'runtime_audit.json').write_text(json.dumps(report,indent=2,ensure_ascii=False),encoding='utf-8')
print(json.dumps(report,indent=2,ensure_ascii=False))
raise SystemExit(report['exit_code'])
