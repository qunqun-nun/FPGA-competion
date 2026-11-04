"""Audit declared FPGA delivery evidence and package exactly the audited files."""
import argparse
import hashlib
import json
import sys
import zipfile
from pathlib import Path, PureWindowsPath


BASE_ROLES = {
    'bit', 'hwh', 'xsa', 'vivado_project', 'block_design', 'rtl', 'ip_metadata',
    'constraints', 'build_script', 'testbench', 'simulation_log', 'simulation_result',
    'build_record', 'synthesis_report', 'timing_report', 'drc_report', 'resource_report',
    'software_source', 'software_entry', 'dependencies', 'start_script', 'stop_script',
    'diagnostic_script', 'deployment_guide', 'rollback_guide',
}
FEATURE_ROLES = {
    'dpu': {'model', 'model_contract', 'labels'},
    'camera': {'camera_capture', 'frame_transport'},
    'hdmi': {'hdmi_init', 'display_runtime'},
    'device_tree': {'device_tree_source', 'device_tree_install'},
    'native_runtime': {'native_source', 'native_build'},
}
GATES = {'syntax', 'module_simulation', 'protocol_assertions', 'packaged_ip',
         'block_design', 'synthesis', 'implementation', 'timing', 'drc'}
HARDWARE = {'bit', 'hwh', 'xsa', 'xclbin'}


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def relative_file(root, name):
    if (not isinstance(name, str) or not name or '\\' in name or ':' in name
            or Path(name).is_absolute() or PureWindowsPath(name).drive or '..' in Path(name).parts):
        raise ValueError('Use portable relative paths: ' + str(name))
    destination = (root / name).resolve()
    if root not in destination.parents:
        raise ValueError('Path outside package: ' + name)
    return destination


def valid_hash(value):
    return isinstance(value, str) and len(value) == 64 and all(char in '0123456789abcdef' for char in value)


def audit(root, manifest_path):
    root = Path(root).resolve()
    manifest_path = Path(manifest_path).resolve()
    manifest = read(manifest_path)
    if not isinstance(manifest, dict) or manifest.get('profile') not in ('pynq', 'pynq_xrt'):
        raise ValueError('profile must be pynq or pynq_xrt')
    if manifest.get('stage') not in ('board_retest', 'accepted'):
        raise ValueError('stage must be board_retest or accepted')
    if not isinstance(manifest.get('build_id'), str) or not manifest['build_id']:
        raise ValueError('Missing build identity')
    files = manifest.get('files')
    if not isinstance(files, list) or not files:
        raise ValueError('Nonempty files list required')
    failures, missing, roles, listed = [], [], {}, {}
    for item in files:
        name, role = item['path'], item['role']
        if name == 'release_manifest.json':
            raise ValueError('Manifest is archived separately; do not list it as payload')
        path = relative_file(root, name)
        if name in listed or path in [value['resolved'] for value in listed.values()]:
            raise ValueError('Duplicate file path: ' + name)
        if not isinstance(role, str) or not role or not valid_hash(item.get('sha256')):
            raise ValueError('Invalid role/hash: ' + name)
        listed[name] = dict(item, resolved=path)
        roles.setdefault(role, []).append(item)
        if not path.is_file():
            missing.append(name)
        elif sha256(path) != item['sha256']:
            failures.append('hash:' + name)
        if role in HARDWARE and item.get('build_id') != manifest['build_id']:
            failures.append('hardware_build_id:' + name)
    required = set(BASE_ROLES)
    if manifest['profile'] == 'pynq_xrt':
        required.add('xclbin')
    features = manifest.get('features')
    if not isinstance(features, dict) or set(features) != set(FEATURE_ROLES):
        raise ValueError('Explicit booleans required for every supported feature')
    for feature, enabled in features.items():
        if type(enabled) != bool:
            raise ValueError('Feature must be boolean: ' + feature)
        if enabled:
            required.update(FEATURE_ROLES[feature])
    missing.extend('role:' + role for role in sorted(required - set(roles)))
    for role in HARDWARE | {'build_record'}:
        if len(roles.get(role, [])) > 1:
            failures.append('ambiguous_role:' + role)
    if roles.get('bit') and roles.get('hwh'):
        if Path(roles['bit'][0]['path']).stem != Path(roles['hwh'][0]['path']).stem:
            failures.append('bit_hwh_stem')
    record_items = roles.get('build_record', [])
    if len(record_items) == 1:
        record_path = relative_file(root, record_items[0]['path'])
        if record_path.is_file():
            record = read(record_path)
            if record.get('build_id') != manifest['build_id']:
                failures.append('build_record_identity')
            for field in ('tools', 'target_part', 'source_revision', 'commands_log'):
                if not record.get(field):
                    missing.append('build_record:' + field)
            for role in HARDWARE & set(roles):
                item = roles[role][0]
                proof = record.get('artifacts', {}).get(role, {})
                if proof.get('path') != item['path'] or proof.get('sha256') != item['sha256']:
                    failures.append('build_record_artifact:' + role)
            command_log = record.get('commands_log')
            if isinstance(command_log, str) and command_log not in listed:
                missing.append('build_command_log:' + command_log)
    verification = manifest.get('verification')
    if not isinstance(verification, dict):
        raise ValueError('verification object required')
    for gate in GATES | {'board'}:
        evidence = verification.get(gate, {})
        status = evidence.get('status')
        required_pass = gate != 'board' or manifest['stage'] == 'accepted'
        if required_pass and status != 'PASS':
            missing.append('gate:' + gate)
        if status == 'FAIL':
            failures.append('failed_gate:' + gate)
        elif status not in ('PASS', 'NOT_RUN', 'BLOCKED', 'FAIL'):
            missing.append('gate_status:' + gate)
        if status == 'PASS':
            paths = evidence.get('evidence')
            if not isinstance(paths, list) or not paths:
                missing.append('gate_evidence:' + gate)
            else:
                missing.extend('unlisted_evidence:' + str(name) for name in paths if name not in listed)
        elif not evidence.get('reason'):
            missing.append('gate_reason:' + gate)
    unlisted = sorted(path.relative_to(root).as_posix() for path in root.rglob('*')
                      if path.is_file() and path.resolve() != manifest_path
                      and path.relative_to(root).as_posix() not in listed
                      and '__pycache__' not in path.parts)
    return {'status': 'FAIL' if failures else 'BLOCKED' if missing else 'PASS',
            'stage': manifest['stage'], 'build_id': manifest['build_id'], 'checked_files': len(files),
            'failures': failures, 'missing': missing, 'unlisted_not_packaged': unlisted,
            'scope': 'Declared files, hashes, role coverage and evidence linkage only',
            'not_proven': ['truth_of_test_results', 'binary_hardware_compatibility',
                           'absence_of_undeclared_dependencies', 'clean_boot_board_success']}


def pack(root, manifest, output):
    root, manifest, output = Path(root).resolve(), Path(manifest).resolve(), Path(output).resolve()
    if output.exists() or output == root or root in output.parents:
        raise ValueError('ZIP must be new and outside the delivery root')
    result = audit(root, manifest)
    if result['status'] != 'PASS':
        return result
    declared = read(manifest)
    with output.open('xb') as destination:
        with zipfile.ZipFile(destination, 'w', zipfile.ZIP_DEFLATED) as archive:
            archive.write(manifest, 'release_manifest.json')
            for item in declared['files']:
                archive.write(relative_file(root, item['path']), item['path'])
    with zipfile.ZipFile(output) as archive:
        if archive.testzip() is not None:
            raise ValueError('ZIP CRC failed')
        for item in declared['files']:
            if hashlib.sha256(archive.read(item['path'])).hexdigest() != item['sha256']:
                raise ValueError('ZIP member changed: ' + item['path'])
    return dict(result, zip=str(output), zip_sha256=sha256(output),
                crc_and_member_hashes='PASS', note='No extra unlisted file was silently included')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('audit', 'pack'))
    parser.add_argument('root', type=Path)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    try:
        if args.command == 'pack':
            if args.output is None:
                parser.error('pack requires --output')
            result = pack(args.root, args.manifest, args.output)
        else:
            result = audit(args.root, args.manifest)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return {'PASS': 0, 'FAIL': 1, 'BLOCKED': 2}[result['status']]
    except (ValueError, OSError, TypeError, KeyError, AttributeError, zipfile.BadZipFile) as exc:
        print(json.dumps({'status': 'BLOCKED', 'reason': str(exc)}, ensure_ascii=False))
        return 2


if __name__ == '__main__':
    sys.exit(main())
