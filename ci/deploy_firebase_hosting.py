"""Deploy an explicitly selected, hash-bound static test build with short-lived WIF auth.

Only classic Hosting in little-leaf-41e5d is reachable. No Firestore/Auth/IAM,
service creation, billing, personal credentials, or site/version deletion APIs.
Official protocol: https://firebase.google.com/docs/hosting/api-deploy
"""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import HTTPRedirectHandler, Request, build_opener

SITE = 'little-leaf-41e5d'
ORIGIN = 'https://' + SITE + '.firebaseapp.com/'
API = 'https://firebasehosting.googleapis.com/v1beta1/'
SITE_PATH = 'sites/' + SITE
VERSION_RE = re.compile(r'sites/' + SITE + r'/versions/[A-Za-z0-9_-]+')
RELEASE_RE = re.compile(r'sites/' + SITE + r'/releases/[A-Za-z0-9_-]+')
CONFIG = {'headers': [
    {'glob': '**/*.wasm', 'headers': {'Content-Type': 'application/wasm'}},
    {'glob': '**/*.html', 'headers': {'Cache-Control': 'no-cache'}},
    {'glob': '/hosting-release.json', 'headers': {'Cache-Control': 'no-store'}},
]}


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def verify_engine_provenance(folder, manifest):
    base = manifest.get('base_web_manifest', {})
    if (not re.fullmatch(r'[0-9a-f]{40}', base.get('source_commit', ''))
            or not re.fullmatch(r'[0-9a-f]{40}', base.get('source_tree', ''))
            or not re.fullmatch(r'[0-9a-f]{64}', base.get('test_report_sha256', ''))
            or not re.fullmatch(r'[0-9a-f]{64}', manifest.get('base_web_manifest_sha256', ''))
            or base.get('packed_smoke') != 'passed'
            or base.get('engine_checks', 0) <= 0 or base.get('test_processes', 0) <= 0):
        raise ValueError('Original complete native/export provenance is required')
    for name in ['index.js', 'index.wasm', 'index.pck']:
        expected = base.get('files', {}).get(name, {})
        file = folder / 'public' / name
        if (not file.is_file() or file.is_symlink() or file.stat().st_size != expected.get('bytes')
                or digest(file) != expected.get('sha256')):
            raise ValueError('Reviewed engine binary changed: ' + name)
    reuse = manifest.get('engine_reuse', {})
    if manifest.get('status') == 'prepared-local-test-artifact-not-deployed':
        if (reuse.get('source_commit') != base['source_commit']
                or reuse.get('gameplay_godot_inputs_byte_identical') is not True
                or reuse.get('base_test_report_sha256') != base['test_report_sha256']
                or reuse.get('native_checks') != base['engine_checks']
                or reuse.get('native_processes') != base['test_processes']
                or base.get('toolchain_verification') not in {'local-tools-unverified-for-release', 'checksum-pinned-official-archives'}):
            raise ValueError('Explicit reviewed local-preview reuse evidence required')
    elif manifest.get('staging_run_id') is not None:
        if (not re.fullmatch(r'[1-9][0-9]*', str(manifest.get('staging_run_id')))
                or not re.fullmatch(r'[1-9][0-9]*', str(manifest.get('staging_attempt')))
                or not re.fullmatch(r'[0-9a-f]{40}', manifest.get('reviewed_firebase_commit', ''))
                or base.get('toolchain_verification') != 'checksum-pinned-official-archives'
                or reuse.get('base_engine_source_commit') != base['source_commit']
                or reuse.get('base_engine_source_tree') != base['source_tree']
                or str(reuse.get('base_run_id')) != str(base.get('workflow_run'))
                or reuse.get('native_checks') != base['engine_checks']
                or reuse.get('native_processes') != base['test_processes']
                or reuse.get('production_inputs') != len(base.get('production_sha256', {}))
                or reuse.get('native_inputs', 0) <= 0 or reuse.get('new_engine_run') is not False
                or reuse.get('full_base_ci_passed') is not False):
            raise ValueError('Exact source-CI preview reuse provenance required')
        summary_path = folder / 'evidence/base-native-summary.json'
        if digest(summary_path) != base['test_report_sha256']:
            raise ValueError('Original native report hash mismatch')
        summary = json.loads(summary_path.read_text())
        export = json.loads((folder / 'evidence/base-export-report.json').read_text())
        proof = json.loads((folder / 'evidence/source-reuse.json').read_text())
        if (summary.get('source_commit') != base['source_commit'] or summary.get('status') != 'passed'
                or summary.get('total_checks') != base['engine_checks']
                or summary.get('test_processes') != base['test_processes']
                or summary.get('player_save_used') is not False or export.get('manifest') != base
                or proof.get('reuse') != reuse or proof.get('source_commit') != manifest.get('source_commit')
                or proof.get('source_tree') != manifest.get('source_tree')
                or str(proof.get('staging_run_id')) != str(manifest['staging_run_id'])
                or str(proof.get('staging_attempt')) != str(manifest['staging_attempt'])):
            raise ValueError('Source-CI evidence does not bind the selected preview')
        for name in ['adapter.log', 'delayed-network.log', 'rules.log', 'staging-tests.log', 'reuse-guards.log']:
            path = folder / 'evidence' / name
            if not path.is_file() or path.stat().st_size == 0:
                raise ValueError('Missing focused source-CI evidence')
    elif (base.get('source_commit') != manifest.get('source_commit', base['source_commit'])
            or base.get('toolchain_verification') != 'checksum-pinned-official-archives'
            or not re.fullmatch(r'[1-9][0-9]*', str(base.get('workflow_run')))):
        raise ValueError('A fresh exact-source CI build or explicit reviewed preview reuse is required')
    return base


def verify_package(folder, expected_sha, expected_manifest):
    if not re.fullmatch(r'[0-9a-f]{40}', expected_sha) or not re.fullmatch(r'[0-9a-f]{64}', expected_manifest):
        raise ValueError('Exact reviewed source and manifest hashes required')
    path = folder / 'firebase-variant-manifest.json'
    if path.is_symlink() or digest(path) != expected_manifest:
        raise ValueError('Reviewed Firebase package manifest hash differs')
    manifest = json.loads(path.read_text())
    base = manifest.get('base_web_manifest', {})
    sha = manifest.get('source_commit', base.get('source_commit'))
    tree = manifest.get('source_tree', base.get('source_tree', ''))
    if sha != expected_sha or not re.fullmatch(r'[0-9a-f]{40}', tree):
        raise ValueError('Firebase package source identity differs')
    if manifest.get('status') not in {'prepared-local-test-artifact-not-deployed', 'staged-not-published'}:
        raise ValueError('Unexpected Firebase package stage')
    if manifest.get('canonical_game_url', ORIGIN) != ORIGIN:
        raise ValueError('Package was staged for another game origin')
    files = manifest.get('files', {})
    if not isinstance(files, dict) or not files:
        raise ValueError('Missing file inventory')
    actual = {p.relative_to(folder).as_posix() for p in folder.rglob("*") if p.is_file()}
    expected_paths = set(files) | {"firebase-variant-manifest.json"}
    extras = actual - expected_paths
    if (any(p.is_symlink() for p in folder.rglob("*")) or expected_paths - actual
            or any(not (name.startswith("evidence/") or name in {"PREPARED-README.txt", "prepared-build-receipt.json"}) for name in extras)):
        raise ValueError("Package contains unexpected, missing or symlinked files")
    for name, expected in files.items():
        if (Path(name).is_absolute() or '..' in Path(name).parts or '\\' in name
                or not re.fullmatch(r'[0-9a-f]{64}', expected) or digest(folder / name) != expected):
            raise ValueError('Package file path/hash differs')
    public = folder / 'public'
    if not {'index.html', 'index.js', 'index.wasm', 'index.pck', 'hosting-release.json'}.issubset(
            {p.name for p in public.iterdir() if p.is_file()}):
        raise ValueError('Incomplete Firebase game')
    marker = json.loads((public / 'hosting-release.json').read_text())
    if (marker.get('source_commit') != sha or marker.get('source_tree') != tree
            or marker.get('base_web_manifest_sha256') != manifest.get('base_web_manifest_sha256')):
        raise ValueError('Hosting marker provenance differs')
    for file in public.rglob('*'):
        if file.is_file() and (any(part.startswith('.') for part in file.relative_to(public).parts)
                               or not re.fullmatch(r'[A-Za-z0-9_./-]+', file.relative_to(public).as_posix())):
            raise ValueError('Unexpected public artifact filename')
    verify_engine_provenance(folder, manifest)
    return manifest, marker


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise RuntimeError('Unexpected redirect; credentials were not forwarded')


class Transport:
    def __init__(self, token):
        if not token:
            raise ValueError('Missing short-lived workflow access token')
        self.token = token
        self.opener = build_opener(NoRedirect())

    def request(self, method, path, data=None, upload=False):
        if upload:
            if not re.fullmatch(re.escape('https://upload-firebasehosting.googleapis.com/upload/' + SITE_PATH) + r'/versions/[A-Za-z0-9_-]+/files/[0-9a-f]{64}', path):
                raise ValueError('Unexpected upload destination')
            url, payload, content_type = path, data, 'application/octet-stream'
        else:
            if not path.startswith(SITE_PATH + '/') or '..' in path:
                raise ValueError('API request escaped the approved site')
            url = API + path
            payload = None if data is None else json.dumps(data).encode()
            content_type = 'application/json'
        req = Request(url, data=payload, method=method,
                      headers={'Authorization': 'Bearer ' + self.token, 'Content-Type': content_type})
        try:
            with self.opener.open(req, timeout=180) as response:
                raw = response.read()
                return {} if upload or not raw else json.loads(raw)
        except HTTPError as error:
            raise RuntimeError('Hosting API request failed (HTTP ' + str(error.code) + '); no automatic mutation retry') from None
        except (URLError, TimeoutError):
            raise RuntimeError('Hosting API outcome uncertain; inspect receipt before retrying') from None


def release_head(api):
    records = api.request('GET', SITE_PATH + '/releases?pageSize=1').get('releases', [])
    if not records:
        return None
    version = records[0].get('version', {}).get('name')
    release = records[0].get('name')
    if not isinstance(version, str) or not VERSION_RE.fullmatch(version) or not isinstance(release, str) or not RELEASE_RE.fullmatch(release):
        raise ValueError('Cannot establish existing Hosting release; refusing publication')
    return {'release': release, 'version': version}


def deploy(folder, source_sha, manifest_sha, output, api, smoke):
    manifest, marker = verify_package(folder, source_sha, manifest_sha)
    receipt = {'schema_version': 1, 'status': 'validated', 'source_commit': source_sha,
               'source_tree': marker['source_tree'], 'variant_manifest_sha256': manifest_sha,
               'hosting_url': ORIGIN, 'live_marker': marker, 'hosted_acceptance': 'not-yet-tested'}
    def save():
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(receipt, indent=2) + '\n')
    save()
    previous = release_head(api)
    receipt['previous_hosting_version'] = previous['version'] if previous else None
    receipt['previous_hosting_release'] = previous['release'] if previous else None
    save()
    # Hash compressed bytes as required by the official Hosting upload protocol.
    compressed, paths = {}, {}
    for path in sorted((folder / 'public').rglob('*')):
        if not path.is_file():
            continue
        payload = gzip.compress(path.read_bytes(), mtime=0)
        hash_value = hashlib.sha256(payload).hexdigest()
        compressed[hash_value] = payload
        paths['/' + path.relative_to(folder / 'public').as_posix()] = hash_value
    version = api.request('POST', SITE_PATH + '/versions', {'config': CONFIG}).get('name', '')
    if not isinstance(version, str) or not VERSION_RE.fullmatch(version):
        raise ValueError('Unconfirmed version creation; do not retry blindly')
    receipt.update({'status': 'staging', 'hosting_version': version});save()
    result = api.request('POST', version + ':populateFiles', {'files': paths})
    upload_url = 'https://upload-firebasehosting.googleapis.com/upload/' + version + '/files'
    required = result.get('uploadRequiredHashes', [])
    if (result.get('uploadUrl') != upload_url or not isinstance(required, list)
            or len(set(required)) != len(required) or not set(required).issubset(compressed)):
        raise ValueError('Untrusted upload response; nothing outside the exact approved site will be sent')
    for hash_value in required:
        api.request('POST', upload_url + '/' + hash_value, compressed[hash_value], upload=True)
    finalized = api.request('PATCH', version + '?update_mask=status', {'status': 'FINALIZED'})
    if finalized.get('name') != version or finalized.get('status') != 'FINALIZED':
        raise ValueError('New Hosting version was not finalized; live release untouched')
    receipt['status'] = 'finalized-not-released';save()
    if release_head(api) != previous:
        raise RuntimeError('Another release changed during staging; live release untouched')
    receipt['status'] = 'release-outcome-pending';save()
    release = api.request('POST', SITE_PATH + '/releases?' + urlencode({'versionName': version}), {})
    if (not RELEASE_RE.fullmatch(release.get('name', ''))
            or release.get('version', {}).get('name') != version or release.get('type') != 'DEPLOY'):
        raise RuntimeError('Hosting release outcome uncertain; inspect before retrying')
    receipt.update({'status': 'published-pending-smoke', 'hosting_release': release['name']});save()
    if not smoke(marker):
        receipt['status'] = 'smoke-failed';save()
        if previous and release_head(api) == {'release': release['name'], 'version': version}:
            receipt['status'] = 'rollback-outcome-pending';save()
            rollback = api.request('POST', SITE_PATH + '/releases?' + urlencode({'versionName': previous['version']}), {})
            if rollback.get('version', {}).get('name') != previous['version'] or not RELEASE_RE.fullmatch(rollback.get('name', '')):
                raise RuntimeError('Rollback outcome uncertain; inspect Hosting before retrying')
            receipt.update({'status': 'smoke-failed-rolled-back', 'rollback_release': rollback['name']});save()
        raise RuntimeError('Hosted marker verification failed; review the retained deployment receipt')
    receipt['status'] = 'published-pending-hosted-acceptance';save()
    return receipt


def live_smoke(expected):
    deadline = time.monotonic() + 120
    opener = build_opener(NoRedirect())
    while time.monotonic() < deadline:
        try:
            with opener.open(Request(ORIGIN + 'hosting-release.json', headers={'Cache-Control': 'no-cache'}), timeout=15) as response:
                if json.load(response) == expected:
                    return True
        except (HTTPError, URLError, ValueError, RuntimeError, TimeoutError):
            pass
        time.sleep(5)
    return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--variant', required=True, type=Path)
    parser.add_argument('--sha', required=True)
    parser.add_argument('--manifest-sha256', required=True)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    if args.verify_only:
        verify_package(args.variant, args.sha, args.manifest_sha256)
        print('Exact selected package verified locally; no Hosting change or hosted acceptance claimed')
        return
    result = deploy(args.variant, args.sha, args.manifest_sha256, args.output,
                    Transport(os.environ.get('FIREBASE_HOSTING_ACCESS_TOKEN')), live_smoke)
    print('Published selected test build at ' + result['hosting_url'] + '; account/device acceptance remains pending')


if __name__ == '__main__':
    main()
