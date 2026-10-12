"""Deploy an explicitly selected, hash-bound static test build with short-lived WIF auth.

Only classic Hosting in little-leaf-41e5d is reachable. No Firestore/Auth/IAM,
service creation, billing, personal credentials, or site/version deletion APIs.
Official protocol: https://firebase.google.com/docs/hosting/api-deploy
"""
import argparse
import copy
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import time
from datetime import datetime, timedelta, timezone
from html.parser import HTMLParser
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, urlencode, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener
import zipfile
if __name__ == "__main__":
    import sys
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from release.released_live_provenance import STATUS as RELEASED_LIVE_STATUS, validate_released_live, validate_origin

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
    if manifest.get('status') == RELEASED_LIVE_STATUS:
        validate_released_live(folder, manifest, json.loads((folder/'public/hosting-release.json').read_text()))
    elif manifest.get('status') == 'prepared-local-test-artifact-not-deployed':
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
    if manifest.get('status') not in {'prepared-local-test-artifact-not-deployed', 'staged-not-published', RELEASED_LIVE_STATUS}:
        raise ValueError('Unexpected Firebase package stage')
    if ('qualified_release_reuse' in manifest or 'manual_live_reuse' in manifest) and manifest.get('status') != RELEASED_LIVE_STATUS:
        raise ValueError('Released reuse cannot be relabelled as a legacy fresh/preview package')
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


class _EntryScripts(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=False)
        self.engine = False
        self.inline = []
        self.in_inline = False

    def handle_starttag(self, tag, attrs):
        if tag == 'script':
            src = dict(attrs).get('src')
            self.engine |= src in {'index.js', './index.js'}
            self.in_inline = src is None

    def handle_endtag(self, tag):
        if tag == 'script':
            self.in_inline = False

    def handle_data(self, data):
        if self.in_inline:
            self.inline.append(data)


def verify_live_package(folder, expected_sha, expected_manifest, *, staging_origin=None):
    """Keep reviewed previews/diagnostics out of the top-level live game route."""
    manifest, marker = verify_package(folder, expected_sha, expected_manifest)
    if manifest.get('status') == RELEASED_LIVE_STATUS:
        validate_origin(manifest, staging_origin)
    elif staging_origin is not None and staging_origin['run'].get('head_sha') != expected_sha:
        raise ValueError('Fresh package must match its exact staging source')
    if '-pre.' in marker.get('version','') or '-pre.' in manifest.get('base_web_manifest',{}).get('version',''):
        publication=manifest.get('publication',{})
        order=publication.get('itch_channel_version')
        expected={'source_commit':expected_sha,'version':marker['version'],'tag':'v'+marker['version'],
                  'target':'siowyiyou/little-leaf:html5','state':'completed'}
        if (marker.get('version')!=manifest.get('base_web_manifest',{}).get('version')
                or marker.get('tag')!=expected['tag']
                or marker['version'].rsplit('.',1)[-1]!=expected_sha[:8]
                or any(publication.get(k)!=v for k,v in expected.items())
                or type(publication.get('itch_build_id')) is not int or publication['itch_build_id']<=0
                or type(order) is not int or not 0<order<=9007199254740991
                or marker.get('release_order')!={'target':expected['target'],'channel_version':order}
                or ('window.__littleLeafRelease='+json.dumps(marker).replace('<','\\u003c')+';') not in (folder/'public/index.html').read_text()):
            raise ValueError('SHA prerelease needs exact completed publication and bound update chronology')
    if (manifest.get('production_release_eligible') is False
            or marker.get('diagnostic_only') is True
            or marker.get('auth_verification_only') is True
            or marker.get('game_start_allowed') is False
            or marker.get('test_surface') is not None
            or manifest.get('ancestor_origins') is not None):
        raise ValueError('Preview or diagnostic packets cannot replace the live game')
    for record in [manifest, marker]:
        origin = record.get('runtime_origin')
        if origin is not None and origin.rstrip('/') != ORIGIN.rstrip('/'):
            raise ValueError('Live game runtime origin differs')
    scripts = _EntryScripts()
    scripts.feed((folder / 'public/index.html').read_text(encoding='utf-8'))
    inline = '\n'.join(scripts.inline)
    if (not scripts.engine
            or re.search(r'[\"\']?authVerificationOnly[\"\']?\s*:\s*true\b', inline)
            or re.search(r'[\"\']?surface[\"\']?\s*:\s*[\"\']trusted-itch-frame[\"\']', inline)):
        raise ValueError('Live game entry must load the engine without an auth-only or preview bootstrap')
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


def deploy(folder, source_sha, manifest_sha, output, api, smoke, *, staging_origin=None):
    manifest, marker = verify_live_package(folder, source_sha, manifest_sha, staging_origin=staging_origin)
    receipt = {'schema_version': 1, 'status': 'validated', 'source_commit': source_sha,
               'source_tree': marker['source_tree'], 'variant_manifest_sha256': manifest_sha,
               'hosting_url': ORIGIN, 'live_marker': marker, 'hosted_acceptance': 'not-yet-tested',
               'automatic_rollback_allowed': False}
    def save():
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(receipt, indent=2) + '\n')
    save()
    previous = release_head(api)
    if not previous:
        raise ValueError('Existing finalized Hosting baseline required; no default config replacement')
    baseline = api.request('GET', previous['version'])
    if (baseline.get('name') != previous['version'] or baseline.get('status') != 'FINALIZED'
            or not isinstance(baseline.get('config'), dict)):
        raise ValueError('Complete current Hosting configuration could not be established')
    config = copy.deepcopy(baseline['config'])
    def config_digest(value):
        return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':'),
                                         ensure_ascii=False, allow_nan=False).encode()).hexdigest()
    config_hash = config_digest(config)
    receipt['preserved_hosting_config'] = config
    receipt['preserved_hosting_config_sha256'] = config_hash
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
    version = api.request('POST', SITE_PATH + '/versions', {'config': config}).get('name', '')
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
    candidate = api.request('GET', version)
    if (candidate.get('name') != version or candidate.get('status') != 'FINALIZED'
            or config_digest(candidate.get('config')) != config_hash):
        raise RuntimeError('Finalized candidate configuration differs; live release untouched')
    current = api.request('GET', previous['version'])
    if (release_head(api) != previous or current.get('name') != previous['version']
            or current.get('status') != 'FINALIZED'
            or config_digest(current.get('config')) != config_hash):
        raise RuntimeError('Another release changed during staging; live release untouched')
    receipt['status'] = 'release-outcome-pending';save()
    release = api.request('POST', SITE_PATH + '/releases?' + urlencode({'versionName': version}), {})
    if (not RELEASE_RE.fullmatch(release.get('name', ''))
            or release.get('version', {}).get('name') != version or release.get('type') != 'DEPLOY'):
        raise RuntimeError('Hosting release outcome uncertain; inspect before retrying')
    receipt.update({'status': 'published-pending-smoke', 'hosting_release': release['name']});save()
    if not smoke(marker):
        receipt['status'] = 'smoke-failed-inspection-required';save()
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
    if any(FIXTURE_ORIGIN.encode() in p.read_bytes() for p in (target / 'public').rglob('*') if p.is_file()):
        raise ValueError('Bootstrap fixture origin remained in upload; refusing publication')
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


ITCH_TEST_STATUS = 'fresh-itch-test-entry-not-live-eligible'
ITCH_BASELINE = {'release': SITE_PATH + '/releases/1791701963370000',
                 'version': SITE_PATH + '/versions/5c3b69acc18fdc94'}
ITCH_BASELINE_CONFIG = '09113ff8616e7f0d7dd26032952d4932d728f19c8014f2eb2cd54dcf093a53a7'
ITCH_HEADERS = [
    {'glob': '/itch/', 'headers': {'Content-Security-Policy': FRAME_POLICY, 'Cache-Control': 'no-cache'}},
    {'glob': '/itch/index.html', 'headers': {'Content-Security-Policy': FRAME_POLICY}},
    {'glob': '/itch/hosting-release.json', 'headers': {'Cache-Control': 'no-store'}},
]


def record_digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':'),
                                    ensure_ascii=False, allow_nan=False).encode()).hexdigest()


def verify_itch_test_package(folder, source_sha, manifest_sha, origin):
    """A separate fresh test contract; never promote local, preview or release packets."""
    path = folder / 'firebase-variant-manifest.json'
    if (not re.fullmatch(r'[0-9a-f]{40}', source_sha)
            or not re.fullmatch(r'[0-9a-f]{64}', manifest_sha)
            or path.is_symlink() or digest(path) != manifest_sha):
        raise ValueError('Exact reviewed test source and manifest required')
    manifest = json.loads(path.read_text(encoding='utf-8'))
    base, proof = manifest.get('base_web_manifest', {}), manifest.get('fresh_ci', {})
    run, artifact, jobs = origin.get('run', {}), origin.get('artifact', {}), origin.get('jobs', [])
    sha, tree = manifest.get('source_commit'), manifest.get('source_tree')
    run_id, attempt = str(run.get('id')), str(run.get('run_attempt'))
    if (manifest.get('status') != ITCH_TEST_STATUS or sha != source_sha
            or not re.fullmatch(r'[0-9a-f]{40}', tree or '')
            or manifest.get('production_release_eligible') is not False
            or manifest.get('hosted_acceptance') is not False
            or manifest.get('auth_domains_modified') is not False
            or manifest.get('hosting_config_proposal_only') is not True
            or manifest.get('runtime_origin') != ORIGIN.rstrip('/') or manifest.get('runtime_path') != '/itch/'
            or manifest.get('hosting_header_additions') != [
                {'source': row['glob'], 'headers': [{'key': k, 'value': v} for k, v in row['headers'].items()]}
                for row in ITCH_HEADERS]
            or 'publication' in manifest or 'manual_live_reuse' in manifest or 'engine_reuse' in manifest
            or base.get('source_commit') != sha or base.get('source_tree') != tree
            or base.get('toolchain_verification') != 'checksum-pinned-official-archives'
            or base.get('packed_smoke') != 'passed' or base.get('engine_checks', 0) <= 0
            or base.get('test_processes', 0) <= 0
            or proof.get('status') != 'fresh-gates-passed' or proof.get('new_engine_run') is not True
            or proof.get('source_commit') != sha or proof.get('source_tree') != tree
            or proof.get('workflow_run') != run_id or proof.get('workflow_attempt') != attempt
            or str(base.get('workflow_run')) != run_id or str(base.get('workflow_attempt')) != attempt):
        raise ValueError('Fresh exact-source official test qualification required')
    repository = 'yiyousiow000814/little-leaf'
    if (run.get('repository', {}).get('full_name') != repository
            or run.get('head_repository', {}).get('full_name') != repository
            or run.get('path') != '.github/workflows/stage-firebase.yml'
            or run.get('event') != 'workflow_dispatch' or run.get('head_branch') != 'main'
            or run.get('head_sha') != sha or run.get('status') != 'completed'
            or run.get('conclusion') != 'success' or attempt != '1'
            or not re.fullmatch(r'[1-9][0-9]*', run_id)
            or type(artifact.get('id')) is not int or artifact['id'] <= 0
            or artifact.get('workflow_run', {}).get('id') != run.get('id')
            or artifact.get('workflow_run', {}).get('head_sha') != sha
            or artifact.get('expired') is not False
            or artifact.get('name') != 'little-leaf-firebase-' + sha + '-' + attempt
            or not isinstance(artifact.get('digest'), str)
            or not re.fullmatch(r'sha256:[0-9a-f]{64}', artifact['digest'])
            or origin.get('commit', {}).get('sha') != sha
            or origin.get('commit', {}).get('commit', {}).get('tree', {}).get('sha') != tree):
        raise ValueError('Fresh authenticated staging artifact origin required')
    required = {'guard', 'historical', 'build', 'gate', 'firebase',
                'browser (play)', 'browser (recovery)',
                'compatibility (compatibility, old_opened_after_new)',
                'compatibility (compatibility, already_open_old)', *(f'engine ({i})' for i in range(5))}
    required = {'fresh / ' + name for name in required} | {'selection'}
    names = [job.get('name') for job in jobs]
    if (len(names) != len(set(names)) or not required.issubset(names)
            or any(job.get('status') != 'completed' or job.get('conclusion') != 'success'
                   for job in jobs if job.get('name') in required)):
        raise ValueError('Every fresh mandatory staging gate must pass')
    files = manifest.get('files', {})
    actual = {p.relative_to(folder).as_posix(): p for p in folder.rglob('*') if p.is_file()}
    if (not files or set(actual) != set(files) | {'firebase-variant-manifest.json'}
            or any(p.is_symlink() for p in folder.rglob('*'))):
        raise ValueError('Exact test inventory required')
    for name, expected in files.items():
        if (not isinstance(name, str) or Path(name).is_absolute() or '..' in Path(name).parts or '\\' in name
                or not re.fullmatch(r'[0-9a-f]{64}', expected) or digest(actual[name]) != expected):
            raise ValueError('Test file path or hash differs')
    from build.build_firebase import BROWSER_GATES, FOCUSED_LOGS
    evidence = proof.get('gate_evidence_sha256', {})
    expected_labels = {'native', 'export', *BROWSER_GATES,
                       *('firebase-' + label + suffix for label in FOCUSED_LOGS for suffix in ['', '.json'])}
    if set(evidence) != expected_labels:
        raise ValueError('Complete fresh evidence label set required')
    for label, expected in evidence.items():
        filename = {'native': 'native-summary.json', 'export': 'export-report.json'}.get(label, label + '.json')
        if label.startswith('firebase-') and label.endswith('.log'):
            filename = label
        elif label.startswith('firebase-') and label.endswith('.log.json'):
            filename = label
        if digest(folder / 'evidence' / filename) != expected:
            raise ValueError('Fresh gate evidence changed')
    native = json.loads((folder / 'evidence/native-summary.json').read_text())
    export = json.loads((folder / 'evidence/export-report.json').read_text())
    if (native.get('status') != 'passed' or native.get('source_commit') != sha
            or native.get('player_save_used') is not False
            or type(native.get('total_checks')) is not int or native['total_checks'] <= 0
            or native['total_checks'] != base.get('engine_checks')
            or type(native.get('test_processes')) is not int or native['test_processes'] <= 0
            or native['test_processes'] != base.get('test_processes')
            or evidence['native'] != base.get('test_report_sha256')
            or export.get('manifest') != base or not export.get('stages')
            or any(row.get('exit_code') != 0 for row in export['stages'])):
        raise ValueError('Complete native/export evidence binding required')
    from qualification.run_firebase_focused import COMMANDS
    for name in FOCUSED_LOGS:
        log = folder / 'evidence' / ('firebase-' + name)
        recorded = json.loads(log.with_name(log.name + '.json').read_text())
        expected = {'schema_version': 1, 'status': 'passed', 'exit_code': 0, 'command': COMMANDS[name],
                    'source_commit': sha, 'source_tree': tree, 'workflow_run': run_id,
                    'workflow_attempt': attempt, 'log_sha256': digest(log)}
        if recorded != expected or not log.stat().st_size:
            raise ValueError('Exact focused process success receipt required')
    flow = json.loads((folder / 'evidence/firebase-fullflow.json').read_text())
    inner = folder / 'public/itch'
    marker = json.loads((inner / 'hosting-release.json').read_text())
    entry = (inner / 'index.html').read_text(encoding='utf-8')
    if (marker.get('source_commit') != sha or marker.get('source_tree') != tree
            or marker.get('runtime_origin') != ORIGIN.rstrip('/') or marker.get('runtime_path') != '/itch/'
            or marker.get('test_surface') != 'trusted-itch-frame' or 'release_order' in marker
            or marker.get('ci_run_id') != run_id
            or marker.get('base_web_manifest_sha256') != manifest.get('base_web_manifest_sha256')
            or marker.get('version') != base.get('version') or marker.get('tag') != base.get('tag', '')
            or entry.count('window.__littleLeafRelease=' + json.dumps(marker).replace('<', '\\u003c') + ';') != 1
            or flow.get('passed') is not True or flow.get('synthetic_only') is not True
            or flow.get('real_google_sign_in') is not False or flow.get('real_compiled_ui') is not True
            or flow.get('real_firestore_rules') is not True or flow.get('diagnostic_only') is not False
            or flow.get('itch_test_entry') is not True or flow.get('browser_sandbox') is not True
            or flow.get('synthetic_public_config_substitution') is not True or not flow.get('checks')
            or flow.get('itch_ancestor_origins') != ANCESTORS
            or flow.get('export_manifest_sha256') != manifest.get('base_web_manifest_sha256')
            or flow.get('native_report_sha256') != evidence['native']
            or flow.get('itch_entry_sha256') != digest(inner / 'index.html')
            or flow.get('source_commit') != sha or flow.get('source_tree') != tree):
        raise ValueError('Exact compiled iframe and marker qualification required')
    from build.project_layout import source_path
    root = Path(__file__).resolve().parents[2]
    flow_sources = ['firebase/fullflow.test.mjs', 'firebase/fullflow_fixtures.mjs', 'firebase/fullflow_network.mjs',
                    'tests/diagnostics/probe_cloud_recovery_geometry.gd', 'tools/qualification/prepare_browser_qa.py',
                    'web/little_leaf_firebase.js', 'web/little_leaf_firebase_session.js', 'web/little_leaf_firebase_boot.mjs',
                    'web/little_leaf_update.js', 'firebase/firestore.rules']
    entry_sources = ['tools/build/build_itch_entry.py', 'tools/build/build_itch_trusted_preview.py', 'tools/build/build_firebase.py',
                     'web/little_leaf_firebase_boot.mjs', 'web/little_leaf_firebase_session.js',
                     'web/little_leaf_update.js', 'web/little_leaf_entry.css']
    if (flow.get('source_sha256') != {name: digest(source_path(root, name)) for name in flow_sources}
            or manifest.get('source_sha256') != {name: digest(source_path(root, name)) for name in entry_sources}):
        raise ValueError('Final source modules changed since qualification')
    for name in ['index.js', 'index.wasm', 'index.pck']:
        record = base.get('files', {}).get(name, {})
        if (digest(inner / name) != record.get('sha256')
                or (inner / name).stat().st_size != record.get('bytes')):
            raise ValueError('Qualified runtime bytes changed')
    additions = {'/' + p.relative_to(folder / 'public').as_posix(): p
                 for p in inner.iterdir() if p.is_file()}
    if (any(not p.is_file() or p.is_symlink() for p in inner.iterdir())
            or not {'/itch/index.html', '/itch/hosting-release.json', '/itch/index.js', '/itch/index.wasm', '/itch/index.pck'}.issubset(additions)
            or any(not re.fullmatch(r'/itch/[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)+', name) for name in additions)):
        raise ValueError('Flat exact /itch file inventory required')
    return manifest, marker, additions


def active_files(api, version):
    """Exhaust the finalized version inventory; keep unknown path values in memory only."""
    files, seen, token = {}, set(), None
    for _ in range(20):
        query = {'status': 'ACTIVE', 'pageSize': 1000}
        if token is not None:
            query['pageToken'] = token
        response = api.request('GET', version + '/files?' + urlencode(query))
        rows = response.get('files')
        if not isinstance(rows, list):
            raise ValueError('Complete ACTIVE Hosting inventory required')
        for row in rows:
            path, value = row.get('path'), row.get('hash')
            if (not isinstance(path, str) or not path.startswith('/') or path.startswith('//')
                    or any(part in {'.', '..'} for part in path.split('/')) or '\\' in path or '?' in path or '#' in path
                    or row.get('status') != 'ACTIVE' or not re.fullmatch(r'[0-9a-f]{64}', value or '') or path in files):
                raise ValueError('Invalid or duplicate ACTIVE file record')
            files[path] = value
        token = response.get('nextPageToken')
        if not token:
            if not files:
                raise ValueError('Empty baseline inventory forbidden')
            return files
        if not isinstance(token, str) or token in seen or len(token) > 4096:
            raise ValueError('Invalid Hosting pagination')
        seen.add(token)
    raise ValueError('Hosting inventory exceeded bounded pagination')


def itch_test_config(config):
    from release.read_firebase_hosting_config import effective_diagnosis, path_match
    if record_digest(config) != ITCH_BASELINE_CONFIG:
        raise ValueError('Approved Hosting configuration baseline changed')
    for family in ['redirects', 'rewrites']:
        rows = config.get(family, [])
        if not isinstance(rows, list):
            raise ValueError('Unknown routing shape')
        for row in rows:
            if any(path_match(row, path)[1] != 'no' for path in ['/itch/', '/itch/index.html', '/itch/hosting-release.json']):
                raise ValueError('Existing routing may intercept the test entry')
    paths = effective_diagnosis(config)['scenarios']['baseline']
    for path in ['/itch/', '/itch/index.html', '/itch/hosting-release.json']:
        row = paths[path]
        tokens = row['applicable_tokens']
        expected_cache = ['CACHE_NO_CACHE_EXACT'] if path.endswith('index.html') else []
        if (row['hold_categories'] or any(tokens.get(key) for key in ['CSP', 'CSP_REPORT_ONLY', 'XFO'])
                or tokens.get('CACHE_CONTROL', []) != expected_cache):
            raise ValueError('Approved effective header assumptions changed')
    result = copy.deepcopy(config)
    result['headers'] = copy.deepcopy(config.get('headers', [])) + copy.deepcopy(ITCH_HEADERS)
    return result


def deploy_itch_test_entry(folder, source_sha, manifest_sha, output, api, smoke, *, staging_origin):
    if output.exists():
        raise ValueError('Existing receipt forbids an automatic retry')
    manifest, marker, additions = verify_itch_test_package(folder, source_sha, manifest_sha, staging_origin)
    receipt = {'schema_version': 1, 'status': 'validated-itch-test-entry', 'source_commit': source_sha,
               'source_tree': manifest['source_tree'], 'variant_manifest_sha256': manifest_sha,
               'hosting_url': ORIGIN + 'itch/', 'approved_header_additions': ITCH_HEADERS,
               'approval_reference': 'Sentinel_a5f561e9ac4881918febbacb871d259c',
               'production_release_eligible': False, 'real_google_acceptance': False,
               'homepage_preserved': False, 'itch_publication_performed': False,
               'automatic_rollback_allowed': False, 'previous': ITCH_BASELINE,
               'previous_config_sha256': ITCH_BASELINE_CONFIG, 'target_files_sha256': {
                   name: digest(path) for name, path in additions.items()}, 'target_files_bytes': {
                   name: path.stat().st_size for name, path in additions.items()}}
    def save():
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
    save()
    if release_head(api) != ITCH_BASELINE:
        raise ValueError('Approved release/version baseline changed')
    baseline = api.request('GET', ITCH_BASELINE['version'])
    if baseline.get('name') != ITCH_BASELINE['version'] or baseline.get('status') != 'FINALIZED':
        raise ValueError('Existing finalized baseline required')
    config = itch_test_config(baseline.get('config'))
    original = active_files(api, ITCH_BASELINE['version'])
    if (any(path == '/itch' or path.startswith('/itch/') for path in original)
            or not {'/index.html', '/hosting-release.json', '/index.js', '/index.wasm', '/index.pck'}.issubset(original)):
        raise ValueError('Existing test namespace or incomplete homepage baseline')
    compressed = {}
    paths = dict(original)
    for name, path in additions.items():
        payload = gzip.compress(path.read_bytes(), mtime=0)
        value = hashlib.sha256(payload).hexdigest()
        compressed[value] = payload
        paths[name] = value
    receipt.update(previous_files_sha256=record_digest(original), previous_file_count=len(original),
                   candidate_files_sha256=record_digest(paths), candidate_file_count=len(paths),
                   candidate_config_sha256=record_digest(config), rollback_version_verified=True)
    save()
    before = smoke(None, None, None)
    receipt.update(status='version-create-outcome-pending');save()
    version = api.request('POST', SITE_PATH + '/versions', {'config': config}).get('name')
    if not isinstance(version, str) or not VERSION_RE.fullmatch(version) or version == ITCH_BASELINE['version']:
        raise RuntimeError('Version creation uncertain; no retry')
    receipt.update(status='staging-test-entry', hosting_version=version);save()
    populated = api.request('POST', version + ':populateFiles', {'files': paths})
    upload_url = 'https://upload-firebasehosting.googleapis.com/upload/' + version + '/files'
    needed = populated.get('uploadRequiredHashes')
    if (populated.get('uploadUrl') != upload_url or not isinstance(needed, list)
            or len(needed) != len(set(needed)) or not set(needed).issubset(compressed)):
        raise RuntimeError('Unexpected upload response; baseline files will never be fetched or replaced')
    for value in needed:
        api.request('POST', upload_url + '/' + value, compressed[value], upload=True)
    finalized = api.request('PATCH', version + '?update_mask=status', {'status': 'FINALIZED'})
    if finalized.get('name') != version or finalized.get('status') != 'FINALIZED':
        raise RuntimeError('New test version not finalized; live unchanged')
    candidate = api.request('GET', version)
    current = api.request('GET', ITCH_BASELINE['version'])
    if (candidate.get('name') != version or candidate.get('status') != 'FINALIZED'
            or record_digest(candidate.get('config')) != record_digest(config)
            or active_files(api, version) != paths
            or current.get('name') != ITCH_BASELINE['version'] or current.get('status') != 'FINALIZED'
            or record_digest(current.get('config')) != ITCH_BASELINE_CONFIG
            or active_files(api, ITCH_BASELINE['version']) != original or release_head(api) != ITCH_BASELINE):
        raise RuntimeError('Finalized candidate or baseline drifted; live unchanged')
    receipt.update(status='release-outcome-pending', candidate_preserves_homepage_files=True);save()
    release = api.request('POST', SITE_PATH + '/releases?' + urlencode({'versionName': version}), {})
    if (not RELEASE_RE.fullmatch(release.get('name', '')) or release.get('type') != 'DEPLOY'
            or release.get('version', {}).get('name') != version):
        raise RuntimeError('Release outcome uncertain; inspect receipt, no retry')
    receipt.update(status='published-pending-public-check', hosting_release=release['name']);save()
    targets = {name: {'sha256': receipt['target_files_sha256'][name], 'bytes': receipt['target_files_bytes'][name]}
               for name in additions}
    try:
        public_ok = smoke(marker, before, targets)
    except Exception:
        receipt.update(status='public-check-failed-inspection-required');save()
        raise RuntimeError('Public checks could not complete; no automatic rollback') from None
    if not public_ok:
        receipt.update(status='public-check-failed-inspection-required');save()
        raise RuntimeError('Public checks failed; no automatic rollback')
    if release_head(api) != {'release': release['name'], 'version': version}:
        raise RuntimeError('Concurrent release after publication; inspect before rollback')
    receipt.update(status='test-entry-public-verified-auth-pending', homepage_preserved=True,
                   hosted_headers_verified=True, target_http_payloads_verified=True);save()
    return receipt


def itch_test_smoke(expected, before, targets):
    opener = build_opener(NoRedirect())
    def read(path):
        with opener.open(Request(ORIGIN + path, headers={'Cache-Control': 'no-cache'}), timeout=30) as response:
            data = response.read(4 * 1024 * 1024 + 1)
            if response.status != 200 or len(data) > 4 * 1024 * 1024:
                raise ValueError('Bounded public response required')
            headers = {key: response.headers.get_all(key, []) for key in [
                'Content-Security-Policy', 'Content-Security-Policy-Report-Only', 'X-Frame-Options', 'Cache-Control']}
            return hashlib.sha256(data).hexdigest(), headers, data
    root = {path: read(path)[:2] for path in ['', 'index.html', 'hosting-release.json']}
    if expected is None:
        return root
    if root != before:
        return False
    for path, cache in [('itch/', 'no-cache'), ('itch/index.html', 'no-cache'), ('itch/hosting-release.json', 'no-store')]:
        _, headers, data = read(path)
        if headers['Cache-Control'] != [cache]:
            return False
        if path.endswith('.json'):
            if json.loads(data) != expected:
                return False
        elif (headers['Content-Security-Policy'] != [FRAME_POLICY]
              or headers['Content-Security-Policy-Report-Only'] or headers['X-Frame-Options']):
            return False
    # Hash each newly served payload without retaining engine or account data in the receipt.
    for path, record in targets.items():
        if (not re.fullmatch(r'/itch/[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)+', path)
                or type(record.get('bytes')) is not int or not 0 < record['bytes'] <= 256*1024*1024):
            raise ValueError('Bounded exact public payload expected')
        with opener.open(Request(ORIGIN+path.lstrip('/'), headers={'Cache-Control': 'no-cache'}), timeout=30) as response:
            if response.status != 200:
                return False
            digest_value, count = hashlib.sha256(), 0
            while chunk := response.read(min(1024*1024, record['bytes']-count+1)):
                count += len(chunk)
                if count > record['bytes']:
                    return False
                digest_value.update(chunk)
            if count != record['bytes'] or digest_value.hexdigest() != record['sha256']:
                return False
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--variant', required=True, type=Path)
    parser.add_argument('--sha', required=True)
    parser.add_argument('--manifest-sha256', required=True)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--verify-only', action='store_true')
    parser.add_argument('--itch-preview', action='store_true')
    parser.add_argument('--itch-test-entry', action='store_true')
    parser.add_argument('--staging-origin', type=Path, help='Fresh authenticated run/artifact metadata, required for manual released-live reuse')
    args = parser.parse_args()
    origin = json.loads(args.staging_origin.read_text()) if args.staging_origin else None
    if args.itch_test_entry:
        if args.itch_preview or origin is None:
            raise ValueError('Separate explicit test selection and fresh origin required')
        try:
            if args.verify_only:
                verify_itch_test_package(args.variant, args.sha, args.manifest_sha256, origin)
                print('Fresh bounded test package verified; no Hosting mutation')
            else:
                deploy_itch_test_entry(args.variant, args.sha, args.manifest_sha256, args.output,
                                      Transport(os.environ.get('FIREBASE_HOSTING_ACCESS_TOKEN')),
                                      itch_test_smoke, staging_origin=origin)
                print('Bounded test entry published; real Google acceptance remains pending')
        except Exception:
            raise SystemExit('Bounded test request stopped; inspect its sanitized receipt. No automatic retry.') from None
        return
    if args.verify_only:
        if args.itch_preview:
            verify_preview_package(args.variant, args.sha, args.manifest_sha256)
        else:
            verify_live_package(args.variant, args.sha, args.manifest_sha256, staging_origin=origin)
        print('Exact selected package verified locally; no Hosting change or hosted acceptance claimed')
        return
    if args.itch_preview:
        result = deploy_preview(args.variant, args.sha, args.manifest_sha256, args.output,
                                Transport(os.environ.get('FIREBASE_HOSTING_ACCESS_TOKEN')), preview_smoke)
        print('Published one-day preview at ' + result['hosting_url'] + '; exact auth hostname approval remains pending')
    else:
        result = deploy(args.variant, args.sha, args.manifest_sha256, args.output,
                        Transport(os.environ.get('FIREBASE_HOSTING_ACCESS_TOKEN')), live_smoke, staging_origin=origin)
        print('Published selected test build at ' + result['hosting_url'] + '; account/device acceptance remains pending')


if __name__ == '__main__':
    main()
