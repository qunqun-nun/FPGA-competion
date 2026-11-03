from pathlib import Path
import hashlib
import json
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    hardware = ROOT/'board/hardware'
    stem = 'fengyan_v017_dpu'
    hashes = {p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in hardware.iterdir() if p.is_file()}
    with zipfile.ZipFile(hardware/'fengyan_v017_final.xsa') as archive:
        bit = [n for n in archive.namelist() if n.endswith('.bit')]
        assert len(bit)==1 and hashlib.sha256(archive.read(bit[0])).hexdigest()==hashes[stem+'.bit']
        hwh = [n for n in archive.namelist() if n.endswith('.hwh')]
        assert any(hashlib.sha256(archive.read(n)).hexdigest()==hashes[stem+'.hwh'] for n in hwh)
    model = ROOT/'board/models/tank_yolov8n_relu_latest_six_outputs.xmodel'
    model_md5 = hashlib.md5(model.read_bytes()).hexdigest()
    assert model_md5=='b54dc98912c20ff70b07e0201b97be3e'
    bad = []
    for path in ROOT.rglob('*'):
        if any(x in path.parts for x in ('.git','__pycache__','xsim.dir','evidence')):
            continue
        if path.name in ('README.md','SKILL.md','LICENSE'):
            continue
        if re.search('[^a-z0-9_.-]',path.name):
            bad.append(path.relative_to(ROOT).as_posix())
    report = dict(hardware_sha256=hashes,xsa_bit_hwh_match=True,model_md5=model_md5,
                  invalid_names=bad,board_verified=False)
    out=ROOT/'build/reports/repository_validation.json'
    out.write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps(report,indent=2))
    if bad:raise SystemExit(1)


if __name__=='__main__':main()
