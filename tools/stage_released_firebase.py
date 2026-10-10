"""Stage a Firebase variant from an exact released ordinary package.

The complete main CI stays authoritative. Firebase emulator/compiled UI checks
run again against those same runtime bytes; this tool has no deployment API.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess

import build_firebase
from artifacts import sha256, validate_export_inventory
from firebase_release_event import artifact_for, download
from firebase_release_gate import require
from project_layout import source_path
from reuse_main_ci import GitHub, bind_package, require_jobs
from run_firebase_focused import COMMANDS

IDENTITY = ['qualification_run_id', 'qualification_attempt', 'artifact_id', 'artifact_digest',
            'qualified_manifest_sha256', 'source_commit', 'source_tree', 'version']
FULLFLOW_SOURCES = ['firebase/fullflow.test.mjs', 'firebase/fullflow_fixtures.mjs',
    'firebase/fullflow_network.mjs', 'tests/probe_cloud_recovery_geometry.gd',
    'tools/prepare_browser_qa.py', 'web/little_leaf_firebase.js', 'web/little_leaf_firebase_session.js',
    'web/little_leaf_firebase_boot.mjs', 'web/little_leaf_update.js', 'firebase/firestore.rules']


def source_identity(root, selection):
    git = lambda *a: subprocess.check_output(['git', '-C', str(root), *a], text=True).strip()
    require(git('rev-parse', 'HEAD') == selection['source_commit']
            and git('rev-parse', 'HEAD^{tree}') == selection['source_tree'], 'Exact released checkout required')
    for args in [('diff', '--quiet', 'HEAD', '--'), ('diff', '--cached', '--quiet', 'HEAD', '--')]:
        require(subprocess.run(['git', '-C', str(root), '-c', 'core.autocrlf=false', *args]).returncode == 0,
                'Unchanged released checkout required')


def prepare(root, reuse, selection, output, api):
    source_identity(root, selection)
    qualification = json.loads((reuse / 'qualification.json').read_text())
    require(all(qualification.get(k) == selection['qualification'].get(k) for k in IDENTITY)
            and qualification.get('tag') == '' and qualification.get('mandatory_gate_success') is True
            and qualification.get('qualified_payload_unchanged') is True
            and qualification.get('packed_startup') == 'passed', 'Reuse differs from completed release')
    run = api.read(f"actions/runs/{qualification['qualification_run_id']}")
    require_jobs(api.pages(f"actions/runs/{run['id']}/attempts/{run['run_attempt']}/jobs", 'jobs'))
    base = bind_package(reuse / 'web', root, selection['source_commit'], selection['source_tree'], run)
    require(base.get('release_reuse') == qualification, 'Ordinary reuse manifest differs')
    evidence_artifact = artifact_for(api, run,
        f"little-leaf-evidence-{selection['source_commit']}-{qualification['qualification_attempt']}")
    download(api, evidence_artifact, output)
    native = output / 'engine-evidence/summary.json'
    report = json.loads(native.read_text())
    original = json.loads((output / 'web-build/evidence/export-report.json').read_text())
    unmodified = dict(base)
    unmodified.pop('release_reuse')
    require(original.get('manifest') == unmodified and sha256(native) == base['test_report_sha256']
            and report.get('status') == 'passed' and report.get('player_save_used') is False
            and report.get('source_commit') == selection['source_commit']
            and report.get('total_checks') == base['engine_checks']
            and report.get('test_processes') == base['test_processes'], 'Original native/export evidence differs')
    require(original.get('stages') and all(s.get('exit_code') == 0 for s in original['stages']),
            'Original export stages failed')
    # These original receipts remain bound to the immutable CI archive, never relabelled as new tests.
    for name, (relative, key, expected) in build_firebase.BROWSER_GATES.items():
        if name == 'firebase-fullflow':
            continue
        value = json.loads((output / 'web-build/evidence' / relative).read_text())
        require(value.get(key) == expected and (key != 'passed' or value[key] is True),
                'Missing original ordinary browser gate: ' + name)
    proof = {'schema_version': 1, 'qualification': qualification,
             'ordinary_evidence_artifact': evidence_artifact,
             'original_native_summary_sha256': sha256(native), 'new_engine_suite_run': False}
    (output / 'reuse-inputs.json').write_text(json.dumps(proof, indent=2) + '\n')
    return proof


def validate_focused(root, folder, source, tree, run, attempt):
    require(str(run).isdigit() and int(run) > 0 and str(attempt).isdigit() and int(attempt) > 0,
            'Explicit current staging run/attempt required')
    records = {}
    for name in build_firebase.FOCUSED_LOGS:
        log = folder / name
        path = folder / (name + '.json')
        require(log.is_file() and log.stat().st_size > 0, 'Missing Firebase focused log: ' + name)
        receipt = json.loads(path.read_text())
        expected = {'schema_version': 1, 'status': 'passed', 'exit_code': 0, 'command': COMMANDS[name],
            'source_commit': source, 'source_tree': tree, 'workflow_run': str(run),
            'workflow_attempt': str(attempt), 'log_sha256': sha256(log)}
        require(receipt == expected, 'Wrong source/attempt or failed focused gate: ' + name)
        records[name] = sha256(log)
        records[name + '.json'] = sha256(path)
    return records


def stage(root, reuse, selection, evidence, focused, fullflow, output, run, attempt):
    source_identity(root, selection)
    base = validate_export_inventory(reuse / 'web')
    inputs = json.loads((evidence / 'reuse-inputs.json').read_text())
    qualification = json.loads((reuse / 'qualification.json').read_text())
    require(inputs['qualification'] == qualification == base.get('release_reuse')
            and all(qualification.get(k) == selection['qualification'].get(k) for k in IDENTITY),
            'Qualification changed after preparation')
    native = evidence / 'engine-evidence/summary.json'
    require(sha256(native) == base['test_report_sha256'] == inputs['original_native_summary_sha256'],
            'Native evidence changed before staging')
    records = validate_focused(root, focused, selection['source_commit'], selection['source_tree'], run, attempt)
    flow_path = fullflow / 'firebase-fullflow.json'
    flow = json.loads(flow_path.read_text())
    expected = {'passed': True, 'source_commit': selection['source_commit'], 'source_tree': selection['source_tree'],
        'export_manifest_sha256': sha256(reuse / 'web/release-manifest.json'),
        'native_report_sha256': sha256(native), 'real_compiled_ui': True, 'real_firestore_rules': True,
        'synthetic_only': True, 'browser_sandbox': True, 'real_google_sign_in': False, 'diagnostic_only': False}
    require(all(type(flow.get(k)) is type(v) and flow.get(k) == v for k, v in expected.items())
            and flow.get('checks') and flow.get('source_sha256') ==
            {n: sha256(source_path(root, n)) for n in FULLFLOW_SOURCES}, 'Compiled Firebase full-flow proof differs')
    records['firebase-fullflow.json'] = sha256(flow_path)
    config = json.loads((root / 'platform/firebase/public-config.json').read_text())
    require(config.get('projectId') == 'little-leaf-41e5d'
            and config.get('authDomain') == 'little-leaf-41e5d.firebaseapp.com', 'Wrong public Firebase project')
    # The existing shell transformation is reused with an explicit source root.
    # No boot/build source, runtime byte, security rule, or auth diagnostic is edited.
    previous_root = build_firebase.ROOT
    try:
        build_firebase.ROOT = root
        build_firebase.stage(reuse, output, config)
    finally:
        build_firebase.ROOT = previous_root
    target = output / 'evidence'
    target.mkdir()
    shutil.copy2(native, target / 'base-native-summary.json')
    shutil.copy2(evidence / 'web-build/evidence/export-report.json', target / 'base-export-report.json')
    shutil.copy2(flow_path, target / 'firebase-fullflow.json')
    for name in build_firebase.FOCUSED_LOGS:
        for suffix in ['', '.json']:
            shutil.copy2(focused / (name + suffix), target / (name + suffix))
    proof = {**inputs, 'status': 'qualified-release-firebase-gates-passed',
        'source_commit': selection['source_commit'], 'source_tree': selection['source_tree'],
        'staging_run_id': str(run), 'staging_attempt': str(attempt),
        'release_run_id': selection['release_run_id'], 'release_tag': selection['release_tag'],
        'fresh_firebase_gate_sha256': records, 'hosted_acceptance': False,
        'live_activation_allowed': False, 'production_security_changes': False}
    coordinator = Path(__file__).resolve().parents[1]
    proof['coordinator_source_commit'] = subprocess.check_output(
        ['git', '-C', str(coordinator), 'rev-parse', 'HEAD'], text=True).strip()
    proof['coordinator_source_tree'] = subprocess.check_output(
        ['git', '-C', str(coordinator), 'rev-parse', 'HEAD^{tree}'], text=True).strip()
    proof['coordinator_sha256'] = {name: sha256(coordinator / name) for name in [
        'tools/firebase_release_event.py', 'tools/firebase_release_gate.py',
        'tools/reuse_released_web.py', 'tools/stage_released_firebase.py',
        '.github/workflows/release-firebase.yml', '.github/workflows/stage-firebase.yml']}
    (target / 'released-ci-reuse.json').write_text(json.dumps(proof, indent=2) + '\n')
    path = output / 'firebase-variant-manifest.json'
    manifest = json.loads(path.read_text())
    manifest.update(source_commit=selection['source_commit'], source_tree=selection['source_tree'],
        canonical_game_url='https://little-leaf-41e5d.firebaseapp.com/', qualified_release_reuse=proof,
        live_activation_allowed=False)
    # Do not present this package as an old fresh-build or preview-reuse contract.
    manifest['status'] = 'qualified-release-staged-not-deployable'
    manifest['files'] = {p.relative_to(output).as_posix(): sha256(p) for p in sorted(output.rglob('*'))
                         if p.is_file() and p != path}
    path.write_text(json.dumps(manifest, indent=2) + '\n')
    for name in ['index.js', 'index.wasm', 'index.pck']:
        require(sha256(output / 'public' / name) == base['files'][name]['sha256'], 'Released runtime bytes changed')
    result = {'source_sha': selection['source_commit'], 'manifest_sha256': sha256(path),
        'artifact_name': 'little-leaf-firebase-' + selection['source_commit'] + '-' + str(attempt)}
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a') as stream:
            for key, value in result.items():
                stream.write(f'{key}={value}\n')
    return result


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('mode', choices=['prepare', 'stage'])
    for name in ['source-root', 'reuse', 'selection', 'evidence']:
        p.add_argument('--' + name, type=Path, required=True)
    for name in ['focused', 'fullflow', 'output']:
        p.add_argument('--' + name, type=Path)
    args = p.parse_args()
    selection = json.loads(args.selection.read_text())
    if args.mode == 'prepare':
        result = prepare(args.source_root.resolve(), args.reuse, selection, args.evidence,
                         GitHub(os.environ.get('GH_TOKEN', '')))
    else:
        require(all([args.focused, args.fullflow, args.output]), 'Stage evidence paths required')
        result = stage(args.source_root.resolve(), args.reuse, selection, args.evidence,
            args.focused, args.fullflow, args.output, os.environ.get('GITHUB_RUN_ID'),
            os.environ.get('GITHUB_RUN_ATTEMPT'))
    print(json.dumps(result))


if __name__ == '__main__':
    main()
