import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def hardware_paths():
    config = json.loads((ROOT / 'deployment.json').read_text(encoding='utf-8'))
    if not config.get('hardware_build_complete'):
        raise RuntimeError('V0.17 hardware build is not complete; this preparation directory is not a deployment package')
    stem = config['hardware_stem']
    if not stem.replace('_', '').isalnum():
        raise RuntimeError('Invalid hardware stem')
    return config, {suffix: ROOT / 'hardware' / (stem + '.' + suffix)
                    for suffix in ('bit', 'hwh', 'xclbin')}
