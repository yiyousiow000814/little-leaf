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
import sys

if __name__ == "__main__":
    import sys
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from build import build_firebase
from qualification.artifacts import sha256, validate_export_inventory
from release.firebase_release_event import artifact_for, download
from release.firebase_release_gate import require
from build.project_layout import source_path
from qualification.reuse_main_ci import GitHub, bind_package, require_jobs
from qualification.run_firebase_focused import COMMANDS

IDENTITY = ['qualification_run_id', 'qualification_attempt', 'artifact_id', 'artifact_digest',
            'qualified_manifest_sha256', 'source_commit', 'source_tree', 'version']
FULLFLOW_SOURCES = ['firebase/fullflow.test.mjs', 'firebase/fullflow_fixtures.mjs',
    'firebase/fullflow_network.mjs', 'tests/diagnostics/probe_cloud_recovery_geometry.gd',
    'tools/qualification/prepare_browser_qa.py', 'web/little_leaf_firebase.js', 'web/little_leaf_firebase_session.js',
    'web/little_leaf_firebase_boot.mjs', 'web/little_leaf_update.js', 'firebase/firestore.rules']


def source_identity(root, selection):
    git = lambda *a: subprocess.check_output(['git', '-C', str(root), *a], text=True).strip()
    require(git('rev-parse', 'HEAD') == selection['source_commit']
            and git('rev-parse', 'HEAD^{tree}') == selection['source_tree'], 'Exact released checkout required')
    for args in [('diff', '--quiet', 'HEAD', '--'), ('diff', '--cached', '--quiet', 'HEAD', '--')]:
        require(subprocess.run(['git', '-C', str(root), '-c', 'core.autocrlf=false', *args]).returncode == 0,
                'Unchanged released checkout required')


def prepare(root, reuse, selection, output, api, *, common_tag=False):
    source_identity(root, selection)
    if common_tag:
        from release.common_tag import STATUS, verify_local
        require(selection.get('kind') == STATUS, 'Separate common-tag selection required')
        verify_local(root, reuse, selection, api)
    qualification = json.loads((reuse / 'qualification.json').read_text())
    require(all(qualification.get(k) == selection['qualification'].get(k) for k in IDENTITY)
            and qualification.get('tag') == (selection['release_tag'] if common_tag else '') and qualification.get('mandatory_gate_success') is True
            and qualification.get('qualified_payload_unchanged') is True
            and qualification.get('packed_startup') == 'passed', 'Reuse differs from completed release')
    endpoint=f"actions/runs/{qualification['qualification_run_id']}"
    if common_tag:
        endpoint+=f"/attempts/{qualification['qualification_attempt']}"
    run = api.read(endpoint)
    require_jobs(api.pages(f"actions/runs/{run['id']}/attempts/{run['run_attempt']}/jobs", 'jobs'))
    base = bind_package(reuse / 'web', root, selection['source_commit'], selection['source_tree'], run,
                        selection['release_tag'] if common_tag else '')
    require(base.get('release_reuse') == qualification, 'Ordinary reuse manifest differs')
    evidence_artifact = artifact_for(api, run,
        f"little-leaf-evidence-{selection['source_commit']}-{qualification['qualification_attempt']}")
    download(api, evidence_artifact, output)
    native = output / 'engine-evidence/summary.json'
    report = json.loads(native.read_text())
    original = json.loads((output / 'web-build/evidence/export-report.json').read_text())
    unmodified = dict(base)
    unmodified.pop('release_reuse')
    if common_tag:
        unmodified['tag'] = '' # Original main export remains an original main receipt.
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


def prepare_common_surface(root, reuse, selection, output):
    """Run only the frozen source's same-page transformer, before compiled gates."""
    source_identity(root, selection)
    require(selection.get('kind') == 'common-tag-qualified', 'Authenticated common tag required')
    require(not output.exists(), 'Same-page candidate output must be unused')
    command = ('import json,sys; from pathlib import Path; '
               'sys.path.insert(0,sys.argv[1]); '
               'from build.build_itch_trusted_preview import prepare_stable; '
               'prepare_stable(Path(sys.argv[2]),Path(sys.argv[3]),'
               'json.loads(Path(sys.argv[4]).read_text()),sys.argv[5],sys.argv[6])')
    environment = os.environ.copy()
    for key in ['GH_TOKEN', 'GITHUB_TOKEN', 'BUTLER_API_KEY', 'FIREBASE_HOSTING_ACCESS_TOKEN']:
        environment.pop(key, None)
    subprocess.run([sys.executable, '-c', command, str(root / 'tools'), str(reuse.resolve()),
                    str(output.resolve()), str(root / 'platform/firebase/public-config.json'),
                    selection['source_commit'], selection['source_tree']],
                   cwd=root, env=environment, check=True, timeout=90)
    return json.loads((output / 'firebase-variant-manifest.json').read_text())


def validate_common_surface(folder, selection, base, flow):
    manifest = json.loads((folder / 'firebase-variant-manifest.json').read_text())
    require(manifest.get('status') == 'prepared-same-itch-local-candidate-not-deployable'
            and manifest.get('source_commit') == selection['source_commit']
            and manifest.get('source_tree') == selection['source_tree']
            and manifest.get('base_web_manifest') == base,
            'Exact frozen common same-page candidate required')
    actual = {p.relative_to(folder).as_posix() for p in folder.rglob('*') if p.is_file()}
    require(not any(p.is_symlink() for p in folder.rglob('*'))
            and actual == set(manifest['files']) | {'firebase-variant-manifest.json'}
            and all(sha256(folder / name) == digest for name, digest in manifest['files'].items()),
            'Same-page candidate inventory changed after compiled qualification')
    require(flow.get('itch_test_entry') is True
            and flow.get('itch_ancestor_origins') == ['https://html-classic.itch.zone', 'https://siowyiyou.itch.io']
            and flow.get('itch_entry_sha256') == sha256(folder / 'public/itch/index.html'),
            'Original complete compiled same-page flow required')
    for surface in ['public', 'public/itch', 'itch-wrapper']:
        for name in ['index.js', 'index.wasm', 'index.pck']:
            require(sha256(folder / surface / name) == base['files'][name]['sha256'],
                    'Frozen common runtime changed on ' + surface)
    return manifest


def stage(root, reuse, selection, evidence, focused, fullflow, output, run, attempt, *, manual_live=False, common_tag=False, itch_variant=None):
    require(not (manual_live and common_tag), 'Separate typed staging contracts required')
    if common_tag:
        from release.common_firebase import common_context
        context = common_context(selection, os.environ, run, attempt)
    if manual_live:
        from release.released_live_provenance import manual_context
        context = manual_context(selection, os.environ, run, attempt)
        coordinator = Path(__file__).resolve().parents[2]
        require(subprocess.check_output(['git', '-C', str(coordinator), 'rev-parse', 'HEAD'], text=True).strip()
                == context['coordinator_source_commit'], 'Exact dispatch coordinator checkout required')
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
            {(source_path(root, n).relative_to(root).as_posix() if n.startswith('tools/') else n):
             sha256(source_path(root, n)) for n in FULLFLOW_SOURCES}, 'Compiled Firebase full-flow proof differs')
    records['firebase-fullflow.json'] = sha256(flow_path)
    config = json.loads((root / 'platform/firebase/public-config.json').read_text())
    require(config.get('projectId') == 'little-leaf-41e5d'
            and config.get('authDomain') == 'little-leaf-41e5d.firebaseapp.com', 'Wrong public Firebase project')
    # Execute the released source's transformer, never a newer main version
    # which might inject 0.1.11 binding modules into the frozen 0.1.10c runtime.
    transformer = source_path(root, 'tools/build/build_firebase.py')
    transformer_import = ('from build.build_firebase import stage' if transformer.parent.name == 'build'
                          else 'from build_firebase import stage')
    command = ('import json,sys; from pathlib import Path; '
               'sys.path.insert(0,sys.argv[1]); ' + transformer_import + '; '
               'publication=json.loads(Path(sys.argv[5]).read_text()); '
               'common_order=json.loads(Path(sys.argv[6]).read_text()) if len(sys.argv)>6 else None; '
               'stage(Path(sys.argv[2]),Path(sys.argv[3]),'
               'json.loads(Path(sys.argv[4]).read_text()),**({"common_order":common_order} if common_order is not None else {"publication":publication} if publication is not None else {}))')
    environment = os.environ.copy()
    for key in ['GH_TOKEN', 'GITHUB_TOKEN', 'BUTLER_API_KEY', 'FIREBASE_HOSTING_ACCESS_TOKEN']:
        environment.pop(key, None)
    publication_path=evidence/'completed-publication.json'
    publication=selection.get('publication')
    if publication and 'itch_channel_version' not in publication and '-pre.' not in base['version']:
        publication=None # Historical stable receipts predate channel-order support.
    require('-pre.' not in base['version'] or publication is not None or common_tag, 'Prerelease requires confirmed publication order')
    publication_path.write_text(json.dumps(publication)+'\n')
    order_args=[]
    if common_tag:
        order_path=evidence/'common-order.json'
        order_path.write_text(json.dumps(selection['common']['release_order'])+'\n')
        order_args=[str(order_path.resolve())]
    if common_tag:
        require(itch_variant is not None, 'Common release requires its qualified same-page candidate')
        validate_common_surface(itch_variant, selection, base, flow)
        shutil.copytree(itch_variant, output)
        # The played itch export keeps the frozen ordinary producer's Root/new-tab
        # account entry. The separately qualified same-page packet remains intact.
        shutil.copytree(reuse / 'web', output / 'itch-ordinary')
        # The frozen transformer supplied the tested bytes. Only the coordinator's
        # authenticated common chronology is added after those gates pass.
        from build.build_firebase import update_hosting_marker
        for surface in ['public', 'public/itch']:
            marker = json.loads((output / surface / 'hosting-release.json').read_text())
            marker.update(tag=selection['release_tag'], release_order=selection['common']['release_order'])
            update_hosting_marker(output / surface, marker)
    else:
        subprocess.run([sys.executable, '-c', command, str(root / 'tools'), str(reuse.resolve()),
                        str(output.resolve()), str(root / 'platform/firebase/public-config.json'), str(publication_path.resolve()), *order_args],
                       cwd=root, env=environment, check=True, timeout=90)
    marker_path = output / 'public/hosting-release.json'
    marker = json.loads(marker_path.read_text())
    marker['tag'] = selection['release_tag']
    marker_path.write_text(json.dumps(marker, indent=2) + '\n')
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
    proof['released_transformer_sha256'] = sha256(transformer)
    coordinator = Path(__file__).resolve().parents[2]
    proof['coordinator_source_commit'] = subprocess.check_output(
        ['git', '-C', str(coordinator), 'rev-parse', 'HEAD'], text=True).strip()
    proof['coordinator_source_tree'] = subprocess.check_output(
        ['git', '-C', str(coordinator), 'rev-parse', 'HEAD^{tree}'], text=True).strip()
    proof['coordinator_sha256'] = {name: sha256(coordinator / name) for name in [
        'tools/release/firebase_release_event.py', 'tools/release/firebase_release_gate.py',
        'tools/qualification/reuse_released_web.py', 'tools/release/stage_released_firebase.py',
        '.github/workflows/release-firebase.yml', '.github/workflows/stage-firebase.yml']}
    (target / 'released-ci-reuse.json').write_text(json.dumps(proof, indent=2) + '\n')
    path = output / 'firebase-variant-manifest.json'
    manifest = json.loads(path.read_text())
    manifest.update(source_commit=selection['source_commit'], source_tree=selection['source_tree'],
        release_tag=selection['release_tag'],
        canonical_game_url='https://little-leaf-41e5d.firebaseapp.com/', qualified_release_reuse=proof,
        live_activation_allowed=False)
    # Do not present this package as an old fresh-build or preview-reuse contract.
    manifest['status'] = 'qualified-release-staged-not-deployable'
    if common_tag:
        from release.common_firebase import STATUS, seal
        manifest.update(status=STATUS, production_release_eligible=True)
        seal(root, coordinator, output, manifest, selection, context, inputs, records, flow, evidence, reuse)
    if manual_live:
        from release.released_live_provenance import STATUS, COORDINATOR_FILES, validate_released_live
        require(context['coordinator_source_commit'] == proof['coordinator_source_commit'],
                'Dispatch coordinator differs from executing source')
        context['coordinator_source_tree'] = proof['coordinator_source_tree']
        proof['coordinator_sha256'] = {name: sha256(coordinator / name) for name in COORDINATOR_FILES}
        (target / 'released-ci-reuse.json').write_text(json.dumps(proof, indent=2) + '\n')
        # Separate opt-in contract, never promote the automatic proof's flags.
        for name, (relative, _, _) in build_firebase.BROWSER_GATES.items():
            if name != 'firebase-fullflow':
                destination = target / 'original-browser' / (name + '.json')
                destination.parent.mkdir(exist_ok=True)
                shutil.copy2(evidence / 'web-build/evidence' / relative, destination)
        shutil.copy2(reuse / 'main-release-manifest.json', target / 'base-web-manifest.json')
        shutil.copy2(root / 'platform/firebase/public-config.json', target / 'public-config.json')
        (target / 'completed-release-selection.json').write_text(json.dumps(selection, indent=2) + '\n')
        live = {'schema_version': 1, 'context': context,
            'qualification': qualification, 'publication': selection['publication'],
            'compiled_source_sha256': flow['source_sha256'],
            'public_config_sha256': sha256(target / 'public-config.json'),
            'fresh_firebase_gate_sha256': records,
            'ordinary_browser_sha256': {name: sha256(target / 'original-browser' / (name + '.json'))
                for name in build_firebase.BROWSER_GATES if name != 'firebase-fullflow'},
            'runtime_sha256': {name: sha256(output / 'public' / name)
                for name in ['index.js', 'index.wasm', 'index.pck']},
            'new_engine_suite_run': False, 'new_ordinary_browser_matrix_run': False,
            'production_security_changes': False, 'hosted_acceptance': False}
        (target / 'manual-live-reuse.json').write_text(json.dumps(live, indent=2) + '\n')
        manifest.update(status=STATUS, manual_live_reuse=live)
    manifest['files'] = {p.relative_to(output).as_posix(): sha256(p) for p in sorted(output.rglob('*'))
                         if p.is_file() and p != path}
    if manual_live:
        validate_released_live(output, manifest, marker)
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
    p.add_argument('mode', choices=['prepare', 'surface', 'stage'])
    p.add_argument('--manual-live', action='store_true', help='Exact main dispatch only; no deployment')
    p.add_argument('--common-tag', action='store_true', help='Independent exact common-tag qualification; no deployment')
    for name in ['source-root', 'reuse', 'selection', 'evidence']:
        p.add_argument('--' + name, type=Path, required=True)
    for name in ['focused', 'fullflow', 'output', 'itch-variant']:
        p.add_argument('--' + name, type=Path)
    args = p.parse_args()
    selection = json.loads(args.selection.read_text())
    if args.mode == 'prepare':
        result = prepare(args.source_root.resolve(), args.reuse, selection, args.evidence,
                         GitHub(os.environ.get('GH_TOKEN', '')), common_tag=args.common_tag)
    elif args.mode == 'surface':
        require(args.common_tag and args.output, 'Common same-page output required')
        result = prepare_common_surface(args.source_root.resolve(), args.reuse, selection, args.output)
    else:
        require(all([args.focused, args.fullflow, args.output]), 'Stage evidence paths required')
        result = stage(args.source_root.resolve(), args.reuse, selection, args.evidence,
            args.focused, args.fullflow, args.output, os.environ.get('GITHUB_RUN_ID'),
            os.environ.get('GITHUB_RUN_ATTEMPT'), manual_live=args.manual_live, common_tag=args.common_tag,
            itch_variant=args.itch_variant)
    print(json.dumps(result))


if __name__ == '__main__':
    main()
