"""Bind the sibling's original variant evidence to the exact ordinary CI inputs."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

STAGES = ('sdk-contract', 'import', 'ack', 'playable-gate', 'dirty-cadence', 'music', 'export', 'packed-smoke')
NAME = 'pr-sibling-receipt.json'


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(path):
    require(path.is_file() and not path.is_symlink(), 'Expected regular file: ' + path.name)
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def ordinary_sibling_route(env):
    if env.get('GITHUB_EVENT_NAME') == 'pull_request':
        return True
    return (env.get('CI_ORDINARY_MAIN_VARIANT') == 'true'
            and env.get('GITHUB_EVENT_NAME') == 'push' and env.get('GITHUB_REF') in {'refs/heads/main', 'refs/heads/qa/main-10min-ci-407-stability2-optimized'})


def bind(root, env, phase):
    evidence = root / 'crazygames-build/evidence'
    ordinary = root / 'web-build/web/release-manifest.json'
    staged = root / 'crazygames-stage.json'
    native = root / 'engine-evidence/summary.json'
    report = evidence / 'export-report.json'
    r = json.loads(report.read_bytes())
    m = json.loads(ordinary.read_bytes())
    token = {k: env[k] for k in ('GITHUB_SHA', 'GITHUB_RUN_ID', 'GITHUB_RUN_ATTEMPT', 'CI_INPUTS_ID', 'VARIANT_ID')}
    require(ordinary_sibling_route(env) and m.get('tag') == ''
            and re.fullmatch('[0-9a-f]{40}', token['GITHUB_SHA'])
            and all(re.fullmatch('[1-9][0-9]*', v) for k, v in token.items() if k != 'GITHUB_SHA')
            and token['CI_INPUTS_ID'] != token['VARIANT_ID'], 'Exact untagged CI and immutable artifact identifiers required')
    tree = subprocess.check_output(['git', 'rev-parse', 'HEAD^{tree}'], text=True).strip()
    require(subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip() == token['GITHUB_SHA']
            and m['source_commit'] == r['source_commit'] == token['GITHUB_SHA'] and m['source_tree'] == r['source_tree'] == tree
            and m['workflow_run'] == token['GITHUB_RUN_ID'] and m['workflow_attempt'] == token['GITHUB_RUN_ATTEMPT']
            and m['test_report_sha256'] == sha(native), 'Wrong source, attempt or native gate')
    require(r['platform'] == 'crazygames' and r['save_variant']['name'] == 'production' and m['packed_smoke'] == 'passed'
            and 0 < m['engine_checks'] == r['existing_web_gate_checks']
            and m['toolchain_verification'] == r['toolchain_verification'] == 'checksum-pinned-official-archives'
            and r['stages'] == [{'stage': k, 'exit_code': 0} for k in STAGES], 'Incomplete variant qualification')
    files = {n + '.log' for n in STAGES} | {'export-report.json'}
    require(set(p.name for p in evidence.iterdir()) == (files if phase == 'record' else files | {NAME}), 'Evidence inventory differs')
    hashes = {n: sha(evidence/n) for n in sorted(files)}
    require('SCENE_READY furniture=' in (evidence/'packed-smoke.log').read_text(), 'Actual packed startup evidence required')
    receipt = {'binding': token, 'source_tree': tree, 'ordinary_manifest_sha256': sha(ordinary),
               'post_import_packet_sha256': sha(staged), 'evidence_sha256': hashes}
    target = evidence/NAME
    if phase == 'record':
        require(sha(root/'crazygames-build/web/crazygames-manifest.json') == hashes['export-report.json'],
                'Variant upload manifest must equal its original export report')
        with target.open('x') as out:
            json.dump(receipt, out, sort_keys=True)
    else:
        require(not target.is_symlink() and json.loads(target.read_text()) == receipt, 'Sibling evidence binding differs')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase', choices=('record', 'verify'))
    parser.add_argument('--root', required=True, type=Path)
    args = parser.parse_args()
    bind(args.root, os.environ, args.phase)
