"""One fixed failed2290 Linux prefix/offline observation; never qualification."""
import argparse
from datetime import datetime, timezone
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys

from current_handoff_route import FLOW_SOURCES, remaining, source_hashes
from retained_handoff_route import image_gate, run, sha, unpack

SOURCE = '2290efe446bff96d6539903b8d01133281e02d9f'
TREE = '639a85ee0c988da21b6486006aec9af7305190cd'
MAIN_RUN = 38532667084
FAILED_RUN = 38538647565
REPOSITORY = 1403804463
ARTIFACTS = {
    'web': (11879080515, 'little-leaf-web-'+SOURCE+'-1', 32631092,
            '60a2eee2589d2823cc39ea8a60764ec10ab0960531fa4cdfb6240fdf8ea16ae3', MAIN_RUN),
    'native': (11879246791, 'little-leaf-evidence-'+SOURCE+'-1', 11743896,
               '831c80a16fb7d9a871f8c9edb0de2e88bced8360f9dab17644b829fddc14faec', MAIN_RUN),
    'failure': (11881876241, 'little-leaf-firebase-release-evidence-38538647565-1', 2473827,
                '6f4f569ab41ec2973a9348c7a0fa1d44e729ef490a3e36f660c4d9a0f6a50d24', FAILED_RUN),
}
MAIN_MANIFEST = '3faad0ed4b6177217ff72edd5dc46d1a33501659486b93584c3b5f614efecc88'
EXPORT = 'bae2c97221554f4968bb1042172acf410fff413f4d847962b8c3861471f37143'
NATIVE = 'd22e723e4e3d5751f9a34e0cf6e9b3b5b0abcf81021ffc07e6dd6e2261a07506'
REPORT = 'f982328deddbedcccb9e53787bb2c48d51bd473c05b515352d783aecba82ff46'
ENTRY = '8d5d334664416147997a85fbd69ceeeb1362afc3e7cbd52ade19b076f8f47fc2'
DRIVER = '7fdaeed22fc2b8b59c6bfe78a2cd4df3e71cbcb418497ef8166e55fc15009727'
TRACE = '6180b1ab871eafd99a2368ff0c3639e31ee235bf63de448c0217c5c6c1af84f7'
DRIVER_NAME = 'current2290_offline_prefix_driver.mjs'


def validate_run(record, identifier):
    main = identifier == MAIN_RUN
    expected = {'id': identifier, 'run_attempt': 1, 'head_sha': SOURCE,
                'head_branch': 'main', 'status': 'completed',
                'conclusion': 'success' if main else 'failure',
                'event': 'push' if main else 'workflow_run',
                'path': '.github/workflows/ci.yml' if main else '.github/workflows/release-firebase.yml'}
    if (identifier not in {MAIN_RUN, FAILED_RUN}
            or any(type(record.get(k)) is not type(v) or record[k] != v for k, v in expected.items())
            or record.get('repository', {}).get('id') != REPOSITORY):
        raise ValueError('Exact fixed main-success or released-failure run required')


def validate_artifact(kind, artifact, run_record):
    identifier, name, size, digest, run_id = ARTIFACTS[kind]
    validate_run(run_record, run_id)
    expected = {'id': identifier, 'name': name, 'size_in_bytes': size,
                'digest': 'sha256:'+digest, 'expired': False}
    owner = artifact.get('workflow_run', {})
    if (any(type(artifact.get(k)) is not type(v) or artifact[k] != v for k, v in expected.items())
            or owner.get('id') != run_id or owner.get('head_sha') != SOURCE
            or owner.get('repository_id') != REPOSITORY or owner.get('head_repository_id') != REPOSITORY):
        raise ValueError('Exact fixed artifact origin/digest/size required')
    expiry = datetime.fromisoformat(artifact.get('expires_at', '').replace('Z', '+00:00'))
    if expiry.tzinfo is None or expiry <= datetime.now(timezone.utc):
        raise ValueError('Expired retained input; no rebuild fallback')


def failed_report(root):
    path = root/'failure/firebase-fullflow/firebase-fullflow.json'
    if sha(path) != REPORT:
        raise ValueError('Original failed report bytes changed')
    report = json.loads(path.read_bytes())
    expected = {'source_commit': SOURCE, 'source_tree': TREE, 'export_manifest_sha256': EXPORT,
                'native_report_sha256': NATIVE, 'itch_entry_sha256': ENTRY,
                'headless_browser': False, 'passed': False}
    if (any(type(report.get(k)) is not type(v) or report[k] != v for k, v in expected.items())
            or report.get('source_sha256') != source_hashes(root/'source')):
        raise ValueError('Original headed Linux failure/source bindings differ')
    return report


def variant_hash(root):
    folder = root/'variant'
    path = folder/'firebase-variant-manifest.json'
    manifest = json.loads(path.read_bytes())
    if (manifest.get('status') != 'prepared-same-itch-local-candidate-not-deployable'
            or manifest.get('source_commit') != SOURCE or manifest.get('source_tree') != TREE
            or sha(folder/'public/itch/index.html') != ENTRY):
        raise ValueError('Exact reconstructed failed same-page surface required')
    actual = {p.relative_to(folder).as_posix() for p in folder.rglob('*') if p.is_file()}
    if actual != set(manifest['files']) | {'firebase-variant-manifest.json'}:
        raise ValueError('Complete variant member set changed')
    for name, expected in manifest['files'].items():
        p = PurePosixPath(name)
        if p.is_absolute() or '..' in p.parts or chr(92) in name or ':' in name:
            raise ValueError('Unsafe variant member')
        file = folder/name
        if file.is_symlink() or sha(file) != expected:
            raise ValueError('Variant bytes changed')
    base = json.loads((root/'build/web/release-manifest.json').read_bytes())
    for surface in ['public', 'public/itch', 'itch-wrapper']:
        for name in ['index.js', 'index.wasm', 'index.pck']:
            if sha(folder/surface/name) != base['files'][name]['sha256']:
                raise ValueError('Original compiled runtime changed')
    return sha(path)


def overlay_hashes(root):
    source = root/'source'
    expected = {source/'platform/firebase'/DRIVER_NAME: DRIVER,
                source/'tests/diagnostics/firebase_offline_phase_trace.mjs': TRACE}
    if any(p.is_symlink() or sha(p) != digest for p, digest in expected.items()):
        raise ValueError('Reviewed diagnostic overlays changed')


def prepare(root, coordinator):
    remaining()
    records = {MAIN_RUN: json.loads((root/'main-run.metadata.json').read_bytes()),
               FAILED_RUN: json.loads((root/'failure-run.metadata.json').read_bytes())}
    for kind, values in ARTIFACTS.items():
        validate_artifact(kind, json.loads((root/(kind+'.metadata.json')).read_bytes()), records[values[4]])
    source = root/'source'
    git = lambda value: subprocess.check_output(['git', '-C', str(source), 'rev-parse', value],
                                               timeout=min(15, remaining())).decode().strip()
    if git('HEAD') != SOURCE or git('HEAD^{tree}') != TREE:
        raise ValueError('Exact old2290 source checkout required')
    if subprocess.run(['git', '-C', str(source), 'diff', '--quiet', 'HEAD', '--'],
                      timeout=min(15, remaining())).returncode:
        raise ValueError('Retained tracked source changed')
    unpack(root/'web.zip', root/'build/web', ARTIFACTS['web'][3])
    unpack(root/'native.zip', root/'evidence', ARTIFACTS['native'][3],
           ['engine-evidence/summary.json', 'engine-evidence/test_cloud_recovery_ui.log',
            'engine-evidence/test_update_notice.log'])
    unpack(root/'failure.zip', root/'failure', ARTIFACTS['failure'][3],
           ['firebase-fullflow/firebase-fullflow.json', 'reuse/qualification.json'])
    native = root/'evidence/engine-evidence/summary.json'
    manifest_path = root/'build/web/release-manifest.json'
    base = json.loads(manifest_path.read_bytes())
    engine = json.loads(native.read_bytes())
    if (sha(manifest_path) != MAIN_MANIFEST or sha(native) != NATIVE
            or base.get('source_commit') != SOURCE or base.get('source_tree') != TREE
            or base.get('test_report_sha256') != NATIVE or base.get('packed_smoke') != 'passed'
            or engine.get('source_commit') != SOURCE or engine.get('status') != 'passed'
            or engine.get('player_save_used') is not False
            or engine.get('total_checks') != base.get('engine_checks')):
        raise ValueError('Original complete main export/native receipt required')
    actual = {p.relative_to(root/'build/web').as_posix():p for p in (root/'build/web').rglob('*') if p.is_file()}
    if set(actual) != set(base['files']) | {'release-manifest.json'}:
        raise ValueError('Original complete Web member set required')
    for name, expected in base['files'].items():
        name_path = PurePosixPath(name)
        if (name_path.is_absolute() or '..' in name_path.parts or chr(92) in name or ':' in name
                or actual[name].is_symlink() or sha(actual[name]) != expected['sha256']
                or actual[name].stat().st_size != expected['bytes']):
            raise ValueError('Original Web payload changed')
    failed_report(root)
    reuse = json.loads((root/'failure/reuse/qualification.json').read_bytes())
    if (reuse.get('source_commit') != SOURCE or reuse.get('source_tree') != TREE
            or reuse.get('qualification_run_id') != MAIN_RUN or reuse.get('qualification_attempt') != 1
            or reuse.get('artifact_id') != ARTIFACTS['web'][0]
            or reuse.get('artifact_digest') != 'sha256:'+ARTIFACTS['web'][3]
            or reuse.get('qualified_manifest_sha256') != MAIN_MANIFEST
            or reuse.get('mandatory_gate_success') is not True or reuse.get('packed_startup') != 'passed'
            or reuse.get('qualified_payload_unchanged') is not True):
        raise ValueError('Original common-tag reuse receipt changed')
    base['tag'] = 'v0.1.11-pre.2290efe4'; base['release_reuse'] = reuse
    manifest_path.write_text(json.dumps(base, indent=2)+'\n', encoding='utf-8')
    if sha(manifest_path) != EXPORT:
        raise ValueError('Original failed common manifest not reproduced')
    sys.path.insert(0, str(source/'tools'))
    from build.build_itch_trusted_preview import prepare_stable
    from build.project_layout import stage_project, source_path
    from qualification.prepare_browser_qa import EXCLUDE
    prepare_stable(root/'build', root/'variant',
                   json.loads((source/'platform/firebase/public-config.json').read_bytes()), SOURCE, TREE)
    variant = variant_hash(root)
    geometry = root/'geometry'
    geometry.mkdir()
    stage_project(source, geometry/'project', tests=True, ignore=EXCLUDE)
    shutil.copyfile(source/'tests/diagnostics/probe_cloud_recovery_geometry.gd',
                    geometry/'project/tests/probe_cloud_recovery_geometry.gd')
    (geometry/'binding.json').write_text(json.dumps({'synthetic_only': True, 'source_commit': SOURCE,
        'source_sha256': {n:sha(source_path(source, n)) for n in
            ['tests/diagnostics/probe_cloud_recovery_geometry.gd', 'tests/persistence/test_cloud_recovery_ui.gd',
             'scripts/ui/cafe_compact_ui.gd', 'scripts/persistence/cafe_web_save.gd']}}, indent=2)+'\n')
    for frozen, destination, digest in [
            (coordinator/'platform/firebase/diagnostics'/DRIVER_NAME, source/'platform/firebase'/DRIVER_NAME, DRIVER),
            (coordinator/'tests/diagnostics/firebase_offline_phase_trace.mjs',
             source/'tests/diagnostics/firebase_offline_phase_trace.mjs', TRACE)]:
        if frozen.is_symlink() or sha(frozen) != digest or destination.exists():
            raise ValueError('Fresh reviewed overlay must not replace original source')
        shutil.copyfile(frozen, destination)
    overlay_hashes(root)
    failed_report(root)
    geometry_files = {p.relative_to(geometry/'project').as_posix():sha(p)
                      for p in (geometry/'project').rglob('*') if p.is_file()}
    binding = {'diagnostic_only': True, 'deployable': False, 'release_qualification': False,
               'compiled_source': SOURCE, 'compiled_tree': TREE, 'original_failed_run': FAILED_RUN,
               'source_sha256': source_hashes(source), 'driver_sha256': DRIVER, 'observer_sha256': TRACE,
               'export_manifest_sha256': EXPORT, 'native_sha256': NATIVE, 'original_failed_report_sha256': REPORT,
               'original_linux_entry_sha256': ENTRY, 'reconstructed_variant_manifest_sha256': variant,
               'geometry_binding_sha256': sha(geometry/'binding.json'), 'geometry_source_sha256': geometry_files,
               'headless_browser': False,
               'first_cases': ['cache', 'graceful', 'local-choice', 'cloud-choice', 'offline'],
               'original_offline_deadline_ms': 45000, 'stop_before_updates': True}
    with (root/'diagnostic-binding.json').open('x', encoding='utf-8') as f:
        f.write(json.dumps(binding, indent=2)+'\n'); f.flush(); os.fsync(f.fileno())
    if os.environ.get('GITHUB_ENV'):
        with open(os.environ['GITHUB_ENV'], 'a') as f:
            f.write('LL_CURRENT_BINDING_SHA256='+sha(root/'diagnostic-binding.json')+'\n')
    remaining()
    return binding


def main():
    image_gate(os.environ)
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--coordinator', type=Path, required=True)
    parser.add_argument('--run', action='store_true')
    args = parser.parse_args(); root = args.root.resolve()
    if not args.run:
        prepare(root, args.coordinator.resolve()); return
    remaining()
    path = root/'diagnostic-binding.json'
    if sha(path) != os.environ.get('LL_CURRENT_BINDING_SHA256'):
        raise ValueError('Prepared receipt changed')
    binding = json.loads(path.read_bytes())
    failed_report(root); overlay_hashes(root)
    geometry = root/'geometry/project'
    geometry_files = {p.relative_to(geometry).as_posix():sha(p) for p in geometry.rglob('*') if p.is_file()}
    if (any(p.is_symlink() for p in geometry.rglob('*'))
            or geometry_files != binding['geometry_source_sha256']
            or source_hashes(root/'source') != binding['source_sha256']
            or variant_hash(root) != binding['reconstructed_variant_manifest_sha256']
            or sha(root/'geometry/binding.json') != binding['geometry_binding_sha256']):
        raise ValueError('Fixed prepared inputs changed')
    run(root, os.environ, driver=DRIVER_NAME)
