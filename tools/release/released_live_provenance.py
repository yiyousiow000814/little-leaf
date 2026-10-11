"""Strict offline manual released-runtime provenance; no deployment or credentials.

Authenticity is established separately by the successful exact main staging run
and immutable artifact origin. Packet receipts alone cannot authorize Hosting.
"""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re

if __name__ == "__main__":
    import sys
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from qualification.artifacts import sha256
from build_firebase import BROWSER_GATES, FOCUSED_LOGS
from firebase_release_gate import REPOSITORY, require, trusted_run
from run_firebase_focused import COMMANDS

STATUS = 'manual-released-live-qualified'
WORKFLOW = '.github/workflows/stage-firebase.yml'
TARGET = 'siowyiyou/little-leaf:html5'
RUNTIME = ['index.js', 'index.wasm', 'index.pck']
COORDINATOR_FILES = ['tools/firebase_release_event.py', 'tools/firebase_release_gate.py',
    'tools/qualification/reuse_released_web.py', 'tools/stage_released_firebase.py',
    '.github/workflows/release-firebase.yml', '.github/workflows/stage-firebase.yml',
    'tools/release/released_live_provenance.py', 'tools/deploy_firebase_hosting.py',
    '.github/workflows/deploy-firebase.yml']


def coordinator_files(paths):
    """Keep each authenticated coordinator's original finite path namespace."""
    paths = set(paths)
    resolved = []
    for name in COORDINATOR_FILES:
        if name == 'tools/qualification/reuse_released_web.py':
            aliases = ('tools/reuse_released_web.py', name)
        elif name == 'tools/release/released_live_provenance.py':
            aliases = ('tools/released_live_provenance.py', name)
        else:
            aliases = (name,)
        matches = [path for path in aliases if path in paths]
        require(len(matches) == 1, 'Missing or ambiguous coordinator source: ' + name)
        resolved.append(matches[0])
    return resolved


def publication_attempt(value):
    # GITHUB_RUN_ATTEMPT is a string in publisher receipts; the API uses an int.
    if type(value) is str and re.fullmatch(r'[1-9][0-9]*', value):
        value = int(value)
    require(type(value) is int and value > 0, 'Invalid canonical publication attempt')
    return value


def manual_context(selection, environment, run, attempt):
    publication = selection.get('publication', {})
    require(type(publication.get('itch_channel_version')) is int
        and 0 < publication['itch_channel_version'] <= 9007199254740991
        and publication.get('state') == 'completed' and publication.get('target') == TARGET
        and publication.get('source_commit') == selection['source_commit']
        and publication.get('tag') == selection['release_tag'],
        'Manual live reuse requires exact completed publication order')
    require(environment.get('GITHUB_REPOSITORY') == REPOSITORY
        and environment.get('GITHUB_EVENT_NAME') == 'workflow_dispatch'
        and environment.get('GITHUB_REF') == 'refs/heads/main'
        and re.fullmatch(r'[0-9a-f]{40}', environment.get('GITHUB_SHA', ''))
        and environment.get('GITHUB_WORKFLOW') == 'Stage Firebase preview'
        and str(attempt) == environment.get('GITHUB_RUN_ATTEMPT') == '1'
        and str(run) == environment.get('GITHUB_RUN_ID')
        and re.fullmatch(r'[1-9][0-9]*', str(run)), 'Exact main manual staging attempt required')
    return {'repository': REPOSITORY, 'workflow': WORKFLOW, 'event': 'workflow_dispatch',
        'ref': 'refs/heads/main', 'source_commit': selection['source_commit'],
        'source_tree': selection['source_tree'], 'staging_run_id': str(run), 'staging_attempt': '1',
        'release_run_id': selection['release_run_id'], 'coordinator_source_commit': environment['GITHUB_SHA']}


def validate_origin(manifest, origin):
    require(isinstance(origin, dict), 'Fresh authenticated staging origin required')
    run, artifact = origin['run'], origin['artifact']
    trusted_run(run, WORKFLOW, ('workflow_dispatch',))
    context = manifest['manual_live_reuse']['context']
    require(run.get('head_branch') == 'main' and run['run_attempt'] == 1
        and run['head_sha'] == context['coordinator_source_commit']
        and str(run['id']) == context['staging_run_id']
        and artifact.get('expired') is False
        and type(artifact.get('id')) is int and artifact['id'] > 0
        and artifact.get('name') == 'little-leaf-firebase-' + manifest['source_commit'] + '-1'
        and artifact.get('workflow_run', {}).get('id') == run['id']
        and artifact['workflow_run'].get('head_sha') == run['head_sha']
        and re.fullmatch(r'sha256:[0-9a-f]{64}', artifact.get('digest', '')),
        'Wrong, failed, stale or unqualified manual staging artifact')
    proof = manifest['qualified_release_reuse']
    require(origin.get('coordinator_source_tree') == context['coordinator_source_tree']
        and origin.get('coordinator_sha256') == proof['coordinator_sha256']
        and origin.get('released_transformer_sha256') == proof['released_transformer_sha256']
        and origin.get('public_config_sha256') == manifest['manual_live_reuse']['public_config_sha256']
        and origin.get('compiled_source_sha256') == manifest['manual_live_reuse']['compiled_source_sha256']
        and origin.get('source_is_coordinator_ancestor') is True,
        'Fresh API coordinator/source identity evidence required')
    q = manifest['manual_live_reuse']['qualification']; publication = manifest['manual_live_reuse']['publication']
    require(type(origin.get('publication_and_qualification', {}).get('release_attempt')) is int
        and origin.get('publication_and_qualification') == {
        'qualification_run_id': q['qualification_run_id'], 'qualification_attempt': q['qualification_attempt'],
        'artifact_id': q['artifact_id'], 'artifact_digest': q['artifact_digest'],
        'release_run_id': context['release_run_id'], 'release_attempt': publication_attempt(publication.get('workflow_attempt')),
        'source_commit': manifest['source_commit'], 'release_tag': publication['tag']},
        'Current completed publication and mandatory main gates must be revalidated')


def authenticate_origin(api, manifest, origin):
    """Fresh read-only API proof, not a receipt asserting its own authenticity."""
    run = api.read('actions/runs/' + str(origin['run']['id']))
    artifact = api.read('actions/artifacts/' + str(origin['artifact']['id']))
    require(run == origin['run'] and artifact == origin['artifact'], 'Staging origin changed since selection')
    trusted_run(run, WORKFLOW, ('workflow_dispatch',))
    source = manifest['source_commit']; coordinator = run['head_sha']
    require(api.read(f'compare/{source}...{coordinator}').get('status') in {'ahead', 'identical'},
        'Released source must be in this exact coordinator history')
    from firebase_release_event import peel
    from qualification.reuse_main_ci import require_jobs
    q = manifest['manual_live_reuse']['qualification']; publication = manifest['manual_live_reuse']['publication']
    qualification_run = api.read('actions/runs/' + str(q['qualification_run_id']))
    trusted_run(qualification_run, '.github/workflows/ci.yml', ('push', 'workflow_dispatch'))
    require(qualification_run['head_sha'] == source and qualification_run.get('head_branch') == 'main'
        and qualification_run['run_attempt'] == q['qualification_attempt'], 'Original main qualification became stale')
    require_jobs(api.pages(f"actions/runs/{qualification_run['id']}/attempts/{qualification_run['run_attempt']}/jobs", 'jobs'))
    original = api.read('actions/artifacts/' + str(q['artifact_id']))
    require(original.get('expired') is False and original.get('digest') == q['artifact_digest']
        and original.get('name') == f"little-leaf-web-{source}-{q['qualification_attempt']}"
        and original.get('workflow_run', {}).get('id') == q['qualification_run_id']
        and original['workflow_run'].get('head_sha') == source, 'Original qualified artifact became stale')
    release = api.read('actions/runs/' + str(manifest['manual_live_reuse']['context']['release_run_id']))
    trusted_run(release, '.github/workflows/release-itch.yml')
    require(release['head_sha'] == source and release.get('head_branch') == publication['tag']
        and release['run_attempt'] == publication_attempt(publication.get('workflow_attempt')) and peel(api, publication['tag']) == source,
        'Completed publication source/tag/attempt became stale')
    publishes = [job for job in api.pages(f"actions/runs/{release['id']}/attempts/{release['run_attempt']}/jobs", 'jobs')
                 if job.get('name') == 'publish']
    require(len(publishes) == 1 and publishes[0].get('run_id') == release['id']
        and publishes[0].get('run_attempt') == release['run_attempt']
        and publishes[0].get('status') == 'completed' and publishes[0].get('conclusion') == 'success',
        'Completed publication job became stale')
    def content_hash(path, commit):
        content = api.read(f'contents/{path}?ref={commit}')
        require(content.get('encoding') == 'base64', 'Expected immutable source content')
        return hashlib.sha256(base64.b64decode(content['content'], validate=False)).hexdigest()
    from stage_released_firebase import FULLFLOW_SOURCES
    # This opt-in contract supports canonical released sources only.
    source_names = {name: 'platform/' + name if name.startswith(('web/', 'firebase/')) else name
                    for name in FULLFLOW_SOURCES}
    coordinator_tree = api.read('git/commits/' + coordinator)['tree']['sha']
    tree = api.read('git/trees/' + coordinator_tree + '?recursive=1')
    require(tree.get('sha') == coordinator_tree and tree.get('truncated') is False,
        'Complete immutable coordinator tree required')
    paths = [entry['path'] for entry in tree['tree'] if entry.get('type') == 'blob']
    require(len(paths) == len(set(paths)), 'Duplicate coordinator source paths')
    evidence = {**origin, 'coordinator_source_tree': coordinator_tree,
        'coordinator_sha256': {name: content_hash(name, coordinator) for name in coordinator_files(paths)},
        'released_transformer_sha256': content_hash('tools/build_firebase.py', source),
        'public_config_sha256': content_hash('platform/firebase/public-config.json', source),
        'compiled_source_sha256': {name: content_hash(path, source) for name, path in source_names.items()},
        'source_is_coordinator_ancestor': True,
        'publication_and_qualification': {'qualification_run_id': q['qualification_run_id'],
            'qualification_attempt': q['qualification_attempt'], 'artifact_id': q['artifact_id'],
            'artifact_digest': q['artifact_digest'], 'release_run_id': release['id'],
            'release_attempt': release['run_attempt'], 'source_commit': source, 'release_tag': publication['tag']}}
    validate_origin(manifest, evidence)
    return evidence


def validate_released_live(folder, manifest, marker):
    from stage_released_firebase import FULLFLOW_SOURCES
    require(manifest.get('status') == STATUS, 'Explicit manual released-live contract required')
    actual = {path.relative_to(folder).as_posix() for path in folder.rglob('*') if path.is_file()}
    require(actual == set(manifest['files']) | {'firebase-variant-manifest.json'},
        'Complete exact manual reuse package inventory required')
    live = manifest.get('manual_live_reuse', {})
    read = lambda name: json.loads((folder / 'evidence' / name).read_text())
    require(live == read('manual-live-reuse.json') and type(live.get('schema_version')) is int
        and live['schema_version'] == 1 and live.get('new_engine_suite_run') is False
        and live.get('new_ordinary_browser_matrix_run') is False
        and live.get('production_security_changes') is False and live.get('hosted_acceptance') is False,
        'Manual reuse evidence differs')
    source, tree = manifest['source_commit'], manifest['source_tree']
    base = manifest['base_web_manifest']
    q = live['qualification']; context = live['context']
    require(context == {'repository': REPOSITORY, 'workflow': WORKFLOW, 'event': 'workflow_dispatch',
        'ref': 'refs/heads/main', 'source_commit': source, 'source_tree': tree,
        'staging_run_id': context.get('staging_run_id'), 'staging_attempt': '1',
        'release_run_id': context.get('release_run_id'),
        'coordinator_source_commit': context.get('coordinator_source_commit'),
        'coordinator_source_tree': context.get('coordinator_source_tree')}
        and re.fullmatch(r'[1-9][0-9]*', context.get('staging_run_id', ''))
        and type(context.get('release_run_id')) is int and context['release_run_id'] > 0,
        'Manual reuse source/event/attempt differs')
    proof = manifest.get('qualified_release_reuse', {})
    require(context['coordinator_source_commit'] == proof.get('coordinator_source_commit')
        and context['coordinator_source_tree'] == proof.get('coordinator_source_tree')
        and all(re.fullmatch(r'[0-9a-f]{40}', context.get(k, '')) for k in
            ['coordinator_source_commit', 'coordinator_source_tree'])
        and set(proof.get('coordinator_sha256', {})) == set(coordinator_files(proof.get('coordinator_sha256', {}))),
        'Explicit coordinator and released source binding required')
    require(q == base.get('release_reuse') and q.get('schema_version') == 1
        and q.get('repository') == REPOSITORY and q.get('workflow') == '.github/workflows/ci.yml'
        and q.get('source_commit') == base.get('source_commit') == source
        and q.get('source_tree') == base.get('source_tree') == tree
        and q.get('version') == base.get('version') == marker.get('version')
        and q.get('mandatory_gate_success') is True and q.get('packed_startup') == 'passed'
        and q.get('qualified_payload_unchanged') is True and q.get('tag') == ''
        and str(q.get('qualification_run_id')) == str(base.get('workflow_run'))
        and str(q.get('qualification_attempt')) == str(base.get('workflow_attempt'))
        and all(type(q.get(k)) is int and q[k] > 0 for k in
            ['qualification_run_id', 'qualification_attempt', 'artifact_id'])
        and re.fullmatch(r'sha256:[0-9a-f]{64}', q.get('artifact_digest', ''))
        and base.get('packed_smoke') == 'passed'
        and base.get('toolchain_verification') == 'checksum-pinned-official-archives',
        'Exact complete main qualification required')
    original_path = folder / 'evidence/base-web-manifest.json'
    original = read('base-web-manifest.json')
    unchanged = dict(base); unchanged.pop('release_reuse', None)
    require(original == unchanged and sha256(original_path) == q.get('qualified_manifest_sha256'),
        'Original qualified manifest bytes differ')
    selection = read('completed-release-selection.json'); publication = live['publication']
    require(selection.get('status') == 'qualified-release-selected-staging-only'
        and selection.get('source_commit') == source and selection.get('source_tree') == tree
        and selection.get('release_run_id') == context['release_run_id']
        and selection.get('release_tag') == marker.get('tag') == 'v' + base['version']
        and publication == selection.get('publication') == manifest.get('publication')
        and publication.get('source_commit') == source and publication.get('version') == base['version']
        and publication.get('tag') == marker['tag'] and publication.get('target') == TARGET
        and publication.get('state') == 'completed'
        and str(publication.get('workflow_run')) == str(context['release_run_id'])
        and type(publication.get('itch_build_id')) is int and publication['itch_build_id'] > 0
        and type(publication.get('itch_channel_version')) is int
        and 0 < publication['itch_channel_version'] <= 9007199254740991
        and marker.get('release_order') == {'target': TARGET, 'channel_version': publication['itch_channel_version']},
        'Exact completed publication chronology required')
    require(all(selection['qualification'].get(k) == q.get(k) == publication['qualification'].get(k)
        for k in ['qualification_run_id', 'qualification_attempt', 'artifact_id', 'artifact_digest',
            'qualified_manifest_sha256', 'source_commit', 'source_tree', 'version']),
        'Publication used another qualified package')
    native_path = folder / 'evidence/base-native-summary.json'; native = read('base-native-summary.json')
    export = read('base-export-report.json')
    require(sha256(native_path) == base['test_report_sha256'] and native.get('status') == 'passed'
        and native.get('source_commit') == source and native.get('player_save_used') is False
        and native.get('total_checks') == base['engine_checks'] > 0
        and native.get('test_processes') == base['test_processes'] > 0
        and export.get('manifest') == original and export.get('stages')
        and all(type(s.get('exit_code')) is int and s['exit_code'] == 0 for s in export['stages']),
        'Original complete native/export evidence differs')
    browsers = {name for name in BROWSER_GATES if name != 'firebase-fullflow'}
    require(set(live['ordinary_browser_sha256']) == browsers, 'Complete ordinary browser evidence required')
    for name in browsers:
        _, key, expected = BROWSER_GATES[name]
        path = folder / 'evidence/original-browser' / (name + '.json'); receipt = json.loads(path.read_text())
        require(sha256(path) == live['ordinary_browser_sha256'][name]
            and type(receipt.get(key)) is type(expected) and receipt[key] == expected,
            'Original ordinary browser gate differs: ' + name)
    records = {}
    for name in FOCUSED_LOGS:
        path = folder / 'evidence' / name; receipt_path = folder / 'evidence' / (name + '.json')
        require(path.stat().st_size > 0 and read(name + '.json') == {'schema_version': 1,
            'status': 'passed', 'exit_code': 0, 'command': COMMANDS[name], 'source_commit': source,
            'source_tree': tree, 'workflow_run': context['staging_run_id'], 'workflow_attempt': '1',
            'log_sha256': sha256(path)}, 'Failed or mismatched focused receipt: ' + name)
        records[name] = sha256(path); records[name + '.json'] = sha256(receipt_path)
    flow_path = folder / 'evidence/firebase-fullflow.json'; flow = read('firebase-fullflow.json')
    expected = {'passed': True, 'source_commit': source, 'source_tree': tree,
        'export_manifest_sha256': manifest['base_web_manifest_sha256'],
        'native_report_sha256': base['test_report_sha256'], 'real_compiled_ui': True,
        'real_firestore_rules': True, 'synthetic_only': True, 'browser_sandbox': True,
        'real_google_sign_in': False, 'diagnostic_only': False}
    require(all(type(flow.get(k)) is type(v) and flow[k] == v for k, v in expected.items())
        and isinstance(flow.get('checks'), list) and flow['checks']
        and all(isinstance(check, str) and check for check in flow['checks'])
        and flow.get('source_sha256') == live['compiled_source_sha256']
        and set(live['compiled_source_sha256']) == set(FULLFLOW_SOURCES)
        and all(re.fullmatch(r'[0-9a-f]{64}', value) for value in live['compiled_source_sha256'].values()),
        'Failed or mismatched compiled Firebase proof')
    # These adapter/rules inputs are covered by the original complete production inventory.
    for name in ['web/little_leaf_firebase.js', 'web/little_leaf_firebase_session.js',
                 'web/little_leaf_firebase_boot.mjs', 'web/little_leaf_update.js']:
        require(sha256(folder / 'public' / name.split('/')[-1]) == base['production_sha256'].get(name)
            == live['compiled_source_sha256'].get(name), 'Compiled adapter source differs')
    require(sha256(folder / 'firestore.rules') == live['compiled_source_sha256'].get('firebase/firestore.rules'),
        'Compiled rules source differs')
    records['firebase-fullflow.json'] = sha256(flow_path)
    require(records == live['fresh_firebase_gate_sha256'], 'Current Firebase evidence hashes differ')
    require(live['runtime_sha256'] == {name: base['files'][name]['sha256'] for name in RUNTIME}
        == {name: sha256(folder / 'public' / name) for name in RUNTIME}, 'Qualified runtime bytes differ')
    config_path = folder / 'evidence/public-config.json'; config = read('public-config.json')
    require(sha256(config_path) == live['public_config_sha256']
        and set(config) == {'apiKey', 'authDomain', 'projectId', 'appId'}
        and config['projectId'] == 'little-leaf-41e5d'
        and config['authDomain'] == 'little-leaf-41e5d.firebaseapp.com', 'Public config differs')
    html = (folder / 'public/index.html').read_text(encoding='utf-8')
    require(html.count('window.__littleLeafRelease=' + json.dumps(marker).replace('<', '\\u003c') + ';') == 1
        and html.count('m.start(' + json.dumps(config).replace('<', '\\u003c') + ')') == 1,
        'Loaded marker/config differs from the exact qualified package')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--variant', type=Path, required=True)
    parser.add_argument('--sha', required=True)
    parser.add_argument('--manifest-sha256', required=True)
    parser.add_argument('--origin', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    from deploy_firebase_hosting import verify_package, verify_live_package
    from qualification.reuse_main_ci import GitHub
    manifest, _ = verify_package(args.variant, args.sha, args.manifest_sha256)
    origin = json.loads(args.origin.read_text())
    if manifest.get('status') == STATUS:
        origin = authenticate_origin(GitHub(os.environ.get('GH_TOKEN', '')), manifest, origin)
    verify_live_package(args.variant, args.sha, args.manifest_sha256, staging_origin=origin)
    args.output.write_text(json.dumps(origin, indent=2) + '\n')


if __name__ == '__main__': main()
