import hashlib
import json
from pathlib import Path


def verify(root):
    root = Path(root).resolve()
    manifest = json.loads((root / 'manifest.json').read_text(encoding='utf-8'))
    for name, expected in manifest['files'].items():
        file = (root / name).resolve()
        if root not in file.parents:
            raise RuntimeError('Unsafe manifest path: ' + name)
        if not file.is_file():
            raise RuntimeError('Missing package file: ' + name)
        digest = hashlib.sha256(file.read_bytes()).hexdigest()
        if digest != expected:
            raise RuntimeError('SHA256 mismatch: ' + name)
    print('PACKAGE_SHA256_OK %d files' % len(manifest['files']))


if __name__ == '__main__':
    verify(Path(__file__).resolve().parent.parent)
