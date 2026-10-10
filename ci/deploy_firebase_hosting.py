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
import shutil
import time
from datetime import datetime, timedelta, timezone
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, urlencode, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener
import zipfile

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


PREVIEW_CHANNEL = 'itch-embed-test'
PREVIEW_PATH = SITE_PATH + '/channels/' + PREVIEW_CHANNEL
FIXTURE_ORIGIN = 'https://' + SITE + '--itch-embed-test-localfixture.web.app'
ANCESTORS = ['https://html-classic.itch.zone', 'https://siowyiyou.itch.io']
FRAME_POLICY = 'frame-ancestors ' + ' '.join(ANCESTORS)
PREVIEW_ORIGIN_RE = re.compile(r'https://' + re.escape(SITE) + r'--itch-embed-test-[a-z0-9]+\.web\.app')


def verify_preview_package(folder, source_sha, manifest_sha):
    manifest, marker = verify_package(folder, source_sha, manifest_sha)
    if (manifest.get('runtime_origin') != FIXTURE_ORIGIN or marker.get('runtime_origin') != FIXTURE_ORIGIN
            or manifest.get('ancestor_origins') != ANCESTORS
            or manifest.get('auth_domains_modified') is not False
            or manifest.get('production_release_eligible') is not False
            or marker.get('test_surface') != 'trusted-itch-frame'):
        raise ValueError('Exact reviewed unbound trusted-frame packet required')
    config = json.loads((folder / 'firebase.json').read_text())
    if set(config) != {'hosting'} or config['hosting'].get('site') != SITE or config['hosting'].get('public') != 'public':
        raise ValueError('Preview packet must contain only the approved Hosting configuration')
    for path in ['public/index.html', 'itch-wrapper/index.html']:
        if (folder / path).read_text().count(FIXTURE_ORIGIN) != 1:
            raise ValueError('Preview origin binding must have exactly one reviewed marker per shell')
    for name in ['little_leaf_firebase_boot.mjs', 'little_leaf_firebase.js', 'little_leaf_firebase_session.js', 'little_leaf_update.js']:
        if manifest.get('source_sha256', {}).get('web/' + name) != digest(folder / 'public' / name):
            raise ValueError('Reviewed own-origin runtime source differs')
    for path in ['/', '/index.html']:
        records = [x for x in config['hosting'].get('headers', []) if x.get('source') == path]
        if len(records) != 1 or {'key':'Content-Security-Policy', 'value':FRAME_POLICY} not in records[0].get('headers', []):
            raise ValueError('Exact accepted ancestor policy required')
    return manifest, marker


class PreviewAPI:
    """Reject every request outside the explicit channel/version protocol, including live POSTs."""
    def __init__(self, api):
        self.api = api

    def request(self, method, path, data=None, upload=False):
        version = re.escape(SITE_PATH) + r'/versions/[A-Za-z0-9_-]+'
        selected_version = parse_qs(urlsplit(path).query).get('versionName', [''])[0]
        allowed = (
            (method == 'GET' and path in {SITE_PATH + '/releases?pageSize=1', SITE_PATH + '/channels?pageSize=100', PREVIEW_PATH})
            or (method == 'POST' and path == SITE_PATH + '/channels?channelId=' + PREVIEW_CHANNEL
                and isinstance(data, dict) and data.get('ttl') == '86400s' and set(data) == {'ttl', 'labels'})
            or (method == 'POST' and path == SITE_PATH + '/versions' and isinstance(data, dict)
                and set(data) == {'config'})
            or (method == 'POST' and re.fullmatch(version + ':populateFiles', path))
            or (method == 'PATCH' and re.fullmatch(version + r'\?update_mask=status', path) and data == {'status':'FINALIZED'})
            or (method == 'POST' and path == PREVIEW_PATH + '/releases?' + urlencode({'versionName':selected_version})
                and re.fullmatch(version, selected_version) and data == {})
            or (upload and method == 'POST' and re.fullmatch(
                re.escape('https://upload-firebasehosting.googleapis.com/upload/') + version + r'/files/[0-9a-f]{64}', path))
        )
        if not allowed or (upload and not path.startswith('https://upload-firebasehosting.googleapis.com/')):
            raise ValueError('Preview request escaped the approved channel protocol')
        return self.api.request(method, path, data, upload=upload)


def bind_preview_packet(folder, target, manifest, origin):
    if not PREVIEW_ORIGIN_RE.fullmatch(origin) or origin == FIXTURE_ORIGIN:
        raise ValueError('Server did not return an exact controlled preview origin')
    shutil.copytree(folder, target)
    for name in ['public/index.html', 'itch-wrapper/index.html']:
        path = target / name
        path.write_text(path.read_text().replace(FIXTURE_ORIGIN, origin))
    marker_path = target / 'public/hosting-release.json'
    marker = json.loads(marker_path.read_text());marker['runtime_origin'] = origin
    marker_path.write_text(json.dumps(marker, indent=2) + '\n')
    bound = dict(manifest);bound['runtime_origin'] = origin
    bound['files'] = {name:digest(target / name) for name in manifest['files']}
    (target / 'firebase-variant-manifest.json').write_text(json.dumps(bound, indent=2) + '\n')
    verify_package(target, manifest['source_commit'], digest(target / 'firebase-variant-manifest.json'))
    return marker


def deploy_preview(folder, source_sha, manifest_sha, output, api, smoke):
    if output.exists():raise ValueError('Existing preview receipt requires inspection; no automatic retry')
    manifest, _ = verify_preview_package(folder, source_sha, manifest_sha)
    api = PreviewAPI(api)
    receipt = {'schema_version':1, 'status':'validated-preview-packet', 'source_commit':source_sha,
               'source_tree':manifest['source_tree'], 'unbound_manifest_sha256':manifest_sha,
               'channel':PREVIEW_CHANNEL, 'hosted_acceptance':'not-yet-tested', 'auth_domains_modified':False}
    def save():
        output.parent.mkdir(parents=True, exist_ok=True);output.write_text(json.dumps(receipt, indent=2) + '\n')
    save();previous = release_head(api);receipt['previous_live_release'] = previous;save()
    channels = api.request('GET', SITE_PATH + '/channels?pageSize=100')
    if channels.get('nextPageToken') or any(c.get('name') == PREVIEW_PATH for c in channels.get('channels', [])):
        raise ValueError('Channel already exists or channel inventory is incomplete; do not overwrite it')
    receipt['status'] = 'channel-create-outcome-pending';save()
    channel = api.request('POST', SITE_PATH + '/channels?channelId=' + PREVIEW_CHANNEL,
                          {'ttl':'86400s', 'labels':{'candidate_source':source_sha, 'packet_hash':manifest_sha[:32]}})
    origin = channel.get('url', '')
    receipt.update(status='channel-created-not-released', hosting_url=origin, expire_time=channel.get('expireTime'));save()
    created = datetime.fromisoformat(channel.get('createTime', '').replace('Z', '+00:00'))
    expires = datetime.fromisoformat(channel.get('expireTime', '').replace('Z', '+00:00'))
    if (channel.get('name') != PREVIEW_PATH or created.tzinfo is None or expires.tzinfo is None
            or not 86399 <= (expires - created).total_seconds() <= 86401
            or expires <= datetime.now(timezone.utc) or expires > datetime.now(timezone.utc) + timedelta(days=1, seconds=60)):
        raise ValueError('Unconfirmed exact one-day channel; stop without retry or deletion')
    target = output.parent / 'preview-bound-package'
    marker = bind_preview_packet(folder, target, manifest, origin)
    receipt['bound_manifest_sha256'] = digest(target / 'firebase-variant-manifest.json');save()
    shutil.copy2(target / 'firebase-variant-manifest.json', output.parent / 'preview-bound-manifest.json')
    wrapper_zip = output.parent / 'itch-wrapper.zip'
    with zipfile.ZipFile(wrapper_zip, 'w', zipfile.ZIP_DEFLATED) as archive:
        for path in sorted((target / 'itch-wrapper').rglob('*')):
            if path.is_file():archive.write(path, path.relative_to(target / 'itch-wrapper'))
    receipt.update(itch_wrapper_sha256=digest(wrapper_zip), itch_wrapper_bytes=wrapper_zip.stat().st_size);save()
    compressed, paths = {}, {}
    for path in sorted((target / 'public').rglob('*')):
        if path.is_file():
            payload = gzip.compress(path.read_bytes(), mtime=0);hash_value = hashlib.sha256(payload).hexdigest()
            compressed[hash_value] = payload;paths['/' + path.relative_to(target / 'public').as_posix()] = hash_value
    config = {'headers':CONFIG['headers'] + [{'glob':path, 'headers':{
        'Content-Security-Policy':FRAME_POLICY, 'Cache-Control':'no-store'}} for path in ['/', '/index.html']]}
    receipt['status'] = 'version-create-outcome-pending';save()
    version = api.request('POST', SITE_PATH + '/versions', {'config':config}).get('name', '')
    if not isinstance(version, str) or not VERSION_RE.fullmatch(version):raise ValueError('Unconfirmed preview version')
    receipt.update(status='staging-preview', hosting_version=version);save()
    result = api.request('POST', version + ':populateFiles', {'files':paths})
    upload_url = 'https://upload-firebasehosting.googleapis.com/upload/' + version + '/files'
    required = result.get('uploadRequiredHashes', [])
    if (result.get('uploadUrl') != upload_url or not isinstance(required, list)
            or len(set(required)) != len(required) or not set(required).issubset(compressed)):
        raise ValueError('Untrusted preview upload response')
    for hash_value in required:api.request('POST', upload_url + '/' + hash_value, compressed[hash_value], upload=True)
    finalized = api.request('PATCH', version + '?update_mask=status', {'status':'FINALIZED'})
    if finalized.get('name') != version or finalized.get('status') != 'FINALIZED':raise ValueError('Preview version not finalized')
    if release_head(api) != previous:raise RuntimeError('Live release changed concurrently; preview not released')
    receipt['status'] = 'preview-release-outcome-pending';save()
    release = api.request('POST', PREVIEW_PATH + '/releases?' + urlencode({'versionName':version}), {})
    if (not re.fullmatch(re.escape(PREVIEW_PATH) + r'/releases/[A-Za-z0-9_-]+', release.get('name', ''))
            or release.get('version', {}).get('name') != version or release.get('type') != 'DEPLOY'):
        raise RuntimeError('Preview release outcome uncertain; inspect receipt, do not retry')
    receipt.update(status='preview-published-pending-smoke', channel_release=release['name']);save()
    if not smoke(origin, marker):raise RuntimeError('Preview marker smoke failed; no live rollback or channel deletion')
    confirmed = api.request('GET', PREVIEW_PATH)
    if (confirmed.get('url') != origin or confirmed.get('expireTime') != channel['expireTime']
            or confirmed.get('release', {}).get('name') != release['name']
            or confirmed.get('release', {}).get('version', {}).get('name') != version):
        raise RuntimeError('Preview URL/expiry/release changed')
    if release_head(api) != previous:raise RuntimeError('Live release changed during preview; inspect before continuing')
    receipt.update(status='preview-published-pending-auth-acceptance', live_release_unchanged=True,
                   exact_hostname=urlsplit(origin).hostname);save()
    return receipt


def preview_smoke(origin, expected):
    opener = build_opener(NoRedirect())
    with opener.open(Request(origin + '/hosting-release.json', headers={'Cache-Control':'no-cache'}), timeout=30) as response:
        return json.load(response) == expected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--variant', required=True, type=Path)
    parser.add_argument('--sha', required=True)
    parser.add_argument('--manifest-sha256', required=True)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--verify-only', action='store_true')
    parser.add_argument('--itch-preview', action='store_true')
    args = parser.parse_args()
    if args.verify_only:
        (verify_preview_package if args.itch_preview else verify_package)(args.variant, args.sha, args.manifest_sha256)
        print('Exact selected package verified locally; no Hosting change or hosted acceptance claimed')
        return
    if args.itch_preview:
        result = deploy_preview(args.variant, args.sha, args.manifest_sha256, args.output,
                                Transport(os.environ.get('FIREBASE_HOSTING_ACCESS_TOKEN')), preview_smoke)
        print('Published one-day preview at ' + result['hosting_url'] + '; exact auth hostname approval remains pending')
    else:
        result = deploy(args.variant, args.sha, args.manifest_sha256, args.output,
                        Transport(os.environ.get('FIREBASE_HOSTING_ACCESS_TOKEN')), live_smoke)
        print('Published selected test build at ' + result['hosting_url'] + '; account/device acceptance remains pending')


if __name__ == '__main__':
    main()
