"""Run offline checks and save auditable reports only under this directory."""
import io
import json
from pathlib import Path
import platform
import unittest
import numpy as np
from cpu_heads.test_cpu_heads import main as test_cpu_heads
import test_inference

root=Path(__file__).resolve().parent
suite=unittest.defaultTestLoader.loadTestsFromModule(test_inference)
stream=io.StringIO()
result=unittest.TextTestRunner(stream=stream,verbosity=2).run(suite)
(root/'offline_tests.log').write_text(stream.getvalue(),encoding='utf-8')
print(stream.getvalue())
# Scalar quantization and independent float64 1x1 convolution reference.
test_cpu_heads()
report={'status':'OFFLINE_TEST_PASS' if result.wasSuccessful() else 'OFFLINE_TEST_FAIL',
        'python':platform.python_version(),'numpy':np.__version__,
        'inference_tests':result.testsRun,'failures':len(result.failures),'errors':len(result.errors),
        'cpu_heads_report':'cpu_heads/offline_test_report.json',
        'model_inspection':'model_inspection.json',
        'board_execution':'NOT_RUN','real_image_comparison':'NOT_RUN',
        'accuracy_validation':'NOT_RUN','camera_pl_dpu_hdmi_integration':'NOT_RUN'}
(root/'offline_test_report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
raise SystemExit(0 if result.wasSuccessful() else 1)
