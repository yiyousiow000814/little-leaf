"""Reuse a successful exact-commit main CI package; never export or publish."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import time
import urllib.request
import zipfile

from artifacts import sha256, validate_export_inventory
from build_web import (PRODUCTION_DIRS, PRODUCTION_FILES, REQUIRED_NOTICES,
                       verify_installer_receipt)
from project_layout import resource_name, source_path
from release_metadata import version

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = 'yiyousiow000814/little-leaf'
WORKFLOW = '.github/workflows/ci.yml'
REQUIRED_JOBS = {'web / guard', 'web / historical', 'web / build', 'web / gate',
    'web / browser (play)', 'web / browser (recovery)',
    'web / compatibility (compatibility, old_opened_after_new)',
    'web / compatibility (compatibility, already_open_old)',
    *(f'web / engine ({i})' for i in range(5))}


class NoAuthorizationRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, url):
        if not url.startswith('https://'):
            raise ValueError('Artifact redirects must use HTTPS')
        redirected = super().redirect_request(request, fp, code, message, headers, url)
        redirected.remove_header('Authorization')
        return redirected


class GitHub:
    def __init__(self, token):
        if not token:
            raise ValueError('Read-only GitHub Actions access is required')
        self.token = token
        self.opener = urllib.request.build_opener(NoAuthorizationRedirect())

    def read(self, path, binary=False):
        request = urllib.request.Request('https://api.github.com/repos/' + REPOSITORY + '/' + path,
            headers={'Authorization': 'Bearer ' + self.token,
                     'Accept': 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28'})
        with self.opener.open(request, timeout=60) as response:
            data = response.read(100 * 1024 * 1024 + 1)
        if len(data) > 100 * 1024 * 1024:
            raise ValueError('Response exceeds the bounded artifact size')
        return data if binary else json.loads(data)

    def pages(self, path, key):
        result = []
        for page in range(1, 11):
            rows = self.read(path + ('&' if '?' in path else '?') + f'per_page=100&page={page}')[key]
            result.extend(rows)
            if len(rows) < 100:
                return result
        raise ValueError('API inventory exceeded its bounded pagination')


def trusted(run, sha, workflow_id):
    return (run.get('head_sha') == sha and run.get('workflow_id') == workflow_id
            and run.get('event') in {'push', 'workflow_dispatch'} and run.get('head_branch') == 'main'
            and run.get('repository', {}).get('full_name') == REPOSITORY
            and run.get('head_repository', {}).get('full_name') == REPOSITORY)


def require_jobs(jobs):
    names = [j['name'] for j in jobs]
    if len(names) != len(set(names)) or not REQUIRED_JOBS.issubset(names):
        raise ValueError('Complete mandatory main CI job inventory is required')
    gates = [j for j in jobs if j['name'] == 'web / gate']
    if len(gates) != 1 or gates[0]['conclusion'] != 'success':
        raise ValueError('The complete main CI acceptance gate must pass')
    if any(j['status'] != 'completed' or
           (j['conclusion'] != 'success' and not
            (j['name'] == 'web / firebase' and j['conclusion'] == 'skipped')) for j in jobs):
        raise ValueError('A mandatory CI job did not succeed')


def resolve(api, sha, wait_seconds=1200, *, clock=time.monotonic, sleep=time.sleep):
    workflow = api.read('actions/workflows/ci.yml')
    if workflow.get('path') != WORKFLOW or workflow.get('state') != 'active':
        raise ValueError('The trusted main CI workflow is unavailable')
    deadline = clock() + wait_seconds
    absent_deadline = clock() + min(wait_seconds, 60)
    while True:
        runs = [r for r in api.pages('actions/workflows/ci.yml/runs?head_sha=' + sha, 'workflow_runs')
                if trusted(r, sha, workflow['id'])]
        if runs:
            run = max(runs, key=lambda r: r['id'])
            if run['status'] == 'completed':
                if run['conclusion'] != 'success':
                    raise ValueError(f"Exact main CI {run['id']} failed; require a successful qualifying build")
                require_jobs(api.pages(f"actions/runs/{run['id']}/attempts/{run['run_attempt']}/jobs", 'jobs'))
                expected = f"little-leaf-web-{sha}-{run['run_attempt']}"
                artifacts = [a for a in api.pages(f"actions/runs/{run['id']}/artifacts", 'artifacts')
                             if a.get('name') == expected]
                if len(artifacts) != 1 or artifacts[0].get('expired'):
                    raise ValueError('The exact qualified Web artifact is missing or expired')
                artifact = artifacts[0]
                if (type(artifact.get('id')) is not int or artifact['id'] <= 0
                        or artifact.get('workflow_run', {}).get('id') != run['id']
                        or artifact.get('workflow_run', {}).get('head_sha') != sha):
                    raise ValueError('Artifact belongs to a different qualification run/source')
                if not re.fullmatch(r'sha256:[0-9a-f]{64}', artifact.get('digest', '')):
                    raise ValueError('An immutable artifact SHA256 digest is mandatory')
                return run, artifact
        elif clock() >= absent_deadline:
            raise ValueError('No exact main CI exists; run Check and build Web on this main commit first')
        if clock() >= deadline:
            raise ValueError('Exact main CI is still running; no duplicate matrix was started')
        print('Waiting for exact main CI qualification', flush=True)
        sleep(15)


def extract(data, expected_digest, destination):
    if hashlib.sha256(data).hexdigest() != expected_digest:
        raise ValueError('GitHub artifact archive digest mismatch')
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        members = archive.infolist()
        if len(members) > 500 or sum(m.file_size for m in members) > 100 * 1024 * 1024:
            raise ValueError('Artifact exceeds extraction bounds')
        seen = set()
        for member in members:
            name = member.filename
            if (not name or PurePosixPath(name).name != name or name.startswith('.')
                    or any(c in name for c in '\\:/\r\n') or member.is_dir()
                    or stat.S_ISLNK(member.external_attr >> 16) or name.casefold() in seen):
                raise ValueError('Unsafe or duplicate Web artifact member')
            seen.add(name.casefold())
        destination.mkdir(parents=True, exist_ok=False)
        for member in members:
            (destination / member.filename).write_bytes(archive.read(member))


def bind_package(web, root, sha, tree, run, tag=''):
    manifest = validate_export_inventory(web)
    value = version(root, tag)
    if (manifest.get('source_commit') != sha or manifest.get('source_tree') != tree
            or manifest.get('version') != value or manifest.get('tag') not in {'', tag}
            or str(manifest.get('workflow_run')) != str(run['id'])
            or str(manifest.get('workflow_attempt')) != str(run['run_attempt'])
            or manifest.get('packed_smoke') != 'passed' or manifest.get('engine_checks', 0) <= 0
            or manifest.get('test_processes', 0) <= 0
            or manifest.get('toolchain_verification') != 'checksum-pinned-official-archives'):
        raise ValueError('The package does not bind this exact qualified source/version/run')
    tracked = subprocess.check_output(['git', '-C', str(root), 'ls-files', '-z']).decode().split('\0')
    expected = {name for p in tracked if (name := resource_name(p)) and
                (name in PRODUCTION_FILES or Path(name).parts[0] in PRODUCTION_DIRS)}
    if set(manifest.get('production_sha256', {})) != expected:
        raise ValueError('Complete production source inventory is required')
    for name, digest in manifest['production_sha256'].items():
        if sha256(source_path(root, name)) != digest:
            raise ValueError('Qualified production source changed: ' + name)
    for name, target in REQUIRED_NOTICES.items():
        if sha256(root / name) != manifest['files'][target]['sha256']:
            raise ValueError('Required distribution notice differs')
    if b'https://sdk.crazygames.com/crazygames-sdk-v3.js' in (web / 'index.html').read_bytes():
        raise ValueError('An ordinary Web package is required')
    if (web / 'index.wasm').read_bytes()[:4] != b'\0asm' or (web / 'index.pck').read_bytes()[:4] != b'GDPC':
        raise ValueError('Invalid qualified Web binary headers')
    return manifest


def packed_smoke(web, output):
    binary = Path(os.environ['GODOT_BIN']) if 'GODOT_BIN' in os.environ else Path(
        subprocess.check_output(['which', 'godot'], text=True).strip())
    verify_installer_receipt(binary, Path(os.environ['GODOT_TEMPLATE']),
                             Path(os.environ['GODOT_TOOLCHAIN_RECEIPT']))
    env = os.environ.copy()
    for key in ['GH_TOKEN', 'GITHUB_TOKEN', 'BUTLER_API_KEY']:
        env.pop(key, None)
    profile = output / 'disposable-startup-profile'
    profile.mkdir()
    for key in ['HOME', 'APPDATA', 'LOCALAPPDATA', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME']:
        env[key] = str(profile)
    result = subprocess.run([str(binary), '--headless', '--main-pack', str(web / 'index.pck'), '--',
        '--self-check', '--fresh-review', '--visual-qa', '--skip-intro'], env=env,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
    log = result.stdout.decode(errors='replace')
    (output / 'packed-startup.log').write_text(log, encoding='utf-8')
    if result.returncode or 'ERROR:' in log or 'SCENE_READY furniture=' not in log:
        raise ValueError('Final packed startup did not pass')
    if list(profile.rglob('little_leaf_cafe_layout_motion_v15.json')):
        raise ValueError('Startup unexpectedly wrote a normal save')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sha', required=True)
    parser.add_argument('--tag', default='')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--wait-seconds', type=int, default=1200)
    args = parser.parse_args()
    if not re.fullmatch('[0-9a-f]{40}', args.sha) or not 0 <= args.wait_seconds <= 1200:
        raise ValueError('Exact SHA and bounded wait are required')
    git = lambda *a: subprocess.check_output(['git', '-C', str(ROOT), *a], text=True).strip()
    if git('rev-parse', 'HEAD') != args.sha or git('status', '--porcelain', '--untracked-files=no'):
        raise ValueError('Checkout must be the unchanged exact release source')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    api = GitHub(os.environ.get('GH_TOKEN', ''))
    run, artifact = resolve(api, args.sha, args.wait_seconds)
    digest = artifact['digest'].removeprefix('sha256:')
    data = api.read(f"actions/artifacts/{artifact['id']}/zip", binary=True)
    web = output / 'web'
    extract(data, digest, web)
    manifest = bind_package(web, ROOT, args.sha, git('rev-parse', 'HEAD^{tree}'), run, args.tag)
    original_manifest = sha256(web / 'release-manifest.json')
    packed_smoke(web, output)
    # Only release metadata is added. Every qualified runtime/asset byte stays exact.
    receipt = {'schema_version': 1, 'repository': REPOSITORY, 'workflow': WORKFLOW,
        'source_commit': args.sha, 'source_tree': manifest['source_tree'], 'tag': args.tag,
        'qualification_run_id': run['id'], 'qualification_attempt': run['run_attempt'],
        'artifact_id': artifact['id'], 'artifact_digest': 'sha256:' + digest,
        'version': manifest['version'], 'mandatory_gate_success': True,
        'qualified_manifest_sha256': original_manifest, 'packed_startup': 'passed',
        'qualified_payload_unchanged': True}
    manifest['tag'] = args.tag
    manifest['release_reuse'] = receipt
    (web / 'release-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    validate_export_inventory(web)
    (output / 'qualification.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps(receipt))


if __name__ == '__main__':
    main()
