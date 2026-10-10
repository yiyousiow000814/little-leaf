"""One digest-bound auth-only preview update and exact rollback; never live release.

Uses the existing Hosting-only WIF workflow. No channel creation/expiry edits,
credentials files, Auth/Firestore APIs, arbitrary artifacts or automatic retry.
"""
import argparse
from datetime import datetime, timezone
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys
from urllib.parse import urlencode
from urllib.request import Request, build_opener
import zipfile
import zlib
import deploy_firebase_hosting as hosting

BUNDLE = Path(__file__).parent / 'auth_preview_pause'
RECIPE_SHA = '2d43c41cf71d85a6b0003afdd0ba9fb53cd4eec1a57ab2b991fc4a24574b21a6'
ORIGIN = 'https://little-leaf-41e5d--itch-embed-test-0b0pnaf7.web.app'
EXPIRY = '2026-10-11T07:18:58.475792680Z'
ARCHIVE_SHA = {
    'update': 'f5aaf81d27500e5d82ac9bb2951852e67e7c56cf094adff68e7a1c7eb7c32778',
    'rollback': '98b033b91535b63c7818d7f12bca17c567e97c41ba92473a67f832f7d4deb0e6',
}


def recipe():
    if hosting.digest(BUNDLE / 'recipe.json') != RECIPE_SHA:
        raise ValueError('Reviewed one-off recipe changed')
    return json.loads((BUNDLE / 'recipe.json').read_text())


def stage(base, output):
    """Recreate both exact ZIPs with the owner's runtime and 8 KiB writes."""
    plan = recipe()
    if sys.version_info[:3] != (3, 14, 2) or zlib.ZLIB_RUNTIME_VERSION != '1.3.1.zlib-ng':
        raise ValueError('Exact reviewed Windows Python 3.14.2 / zlib-ng runtime required')
    output.mkdir(parents=True, exist_ok=False)
    for mode, packet in plan['archives'].items():
        folder = output / mode; (folder / 'public').mkdir(parents=True)
        for name, expected in packet['files'].items():
            source = base / 'public' / name if name in plan['unchanged_qualified_files'] else BUNDLE / mode / 'public' / name
            if source.is_symlink() or hosting.digest(source) != expected:
                raise ValueError('Qualified or overlay byte mismatch: ' + name)
            shutil.copyfile(source, folder / 'public' / name)
        verify_packet(folder, mode)
        with zipfile.ZipFile(output / (mode + '.zip'), 'w') as z:
            for record in packet['entries']:
                name = record['filename']
                source = folder / name if name.startswith('public/') else BUNDLE / mode / name
                info = zipfile.ZipInfo(name, tuple(record['date_time']))
                for key in ['compress_type', 'create_system', 'create_version', 'extract_version', 'internal_attr', 'external_attr']:
                    setattr(info, key, record[key])
                info.extra = bytes.fromhex(record['extra']); info.comment = bytes.fromhex(record['comment'])
                with source.open('rb') as src, z.open(info, 'w') as dest:
                    shutil.copyfileobj(src, dest, length=8192)
        verify_archive(output / (mode + '.zip'), mode)
    return output


def verify_archive(path, mode):
    if mode not in ARCHIVE_SHA or hosting.digest(path) != ARCHIVE_SHA[mode]:
        raise ValueError('Only the reviewed update/rollback ZIP digest is accepted')
    plan = recipe()['archives'][mode]
    with zipfile.ZipFile(path) as z:
        if z.testzip() or z.namelist() != [e['filename'] for e in plan['entries']]:
            raise ValueError('ZIP inventory differs')
        return {name: z.read('public/' + name) for name in plan['files']}


def verify_packet(folder, mode):
    if mode not in ARCHIVE_SHA:
        raise ValueError('Only the reviewed update/rollback inventory is accepted')
    plan = recipe()['archives'][mode]
    if plan['sha256'] != ARCHIVE_SHA[mode]:
        raise ValueError('Reviewed ZIP provenance differs')
    paths = list(folder.rglob('*'))
    if any(p.is_symlink() for p in paths) or {p.relative_to(folder).as_posix() for p in paths if p.is_file()} != {'public/' + n for n in plan['files']}:
        raise ValueError('Packet inventory differs')
    if any(hosting.digest(folder / 'public' / name) != expected for name, expected in plan['files'].items()):
        raise ValueError('Approved public content differs')
    return {name: (folder / 'public' / name).read_bytes() for name in plan['files']}


def public_files(origin, inventory):
    """Unauthenticated read of the exact public files; no save or SDK activity."""
    if origin != ORIGIN:
        raise ValueError('Unapproved public host')
    opener = build_opener(hosting.NoRedirect())
    for name, expected in inventory.items():
        with opener.open(Request(origin + '/' + name, headers={'Cache-Control': 'no-cache'}), timeout=60) as response:
            if name == 'index.html' and response.headers.get('Content-Security-Policy') != hosting.FRAME_POLICY:
                raise ValueError('Preview ancestor policy changed')
            if hashlib.file_digest(response, 'sha256').hexdigest() != expected:
                raise ValueError('Public file hash differs: ' + name)


class UpdateAPI:
    """Only read the existing channel/live head, stage one version, release it here."""
    def __init__(self, api):
        self.api = api
        self.current = self.new = None
        self.config = None

    def request(self, method, path, data=None, upload=False):
        new = self.new
        allowed = (
            method == 'GET' and path in {hosting.SITE_PATH + '/releases?pageSize=1', hosting.PREVIEW_PATH, self.current}
            or method == 'POST' and path == hosting.SITE_PATH + '/versions' and data == {'config': self.config} and self.config is not None and new is None
            or new is not None and (
                method == 'POST' and path == new + ':populateFiles'
                or method == 'PATCH' and path == new + '?update_mask=status' and data == {'status': 'FINALIZED'}
                or method == 'POST' and path == hosting.PREVIEW_PATH + '/releases?' + urlencode({'versionName': new}) and data == {}
                or upload and method == 'POST' and re.fullmatch(re.escape('https://upload-firebasehosting.googleapis.com/upload/' + new + '/files/') + '[0-9a-f]{64}', path)
            )
        )
        if not allowed or upload != path.startswith('https://upload-firebasehosting.googleapis.com/'):
            raise ValueError('Request escaped the bounded existing-channel protocol')
        return self.api.request(method, path, data, upload=upload)


def checked_channel(api, now):
    channel = api.request('GET', hosting.PREVIEW_PATH)
    version = channel.get('release', {}).get('version', {}).get('name', '')
    release = channel.get('release', {}).get('name', '')
    if (channel.get('name') != hosting.PREVIEW_PATH or channel.get('url') != ORIGIN
            or channel.get('expireTime') != EXPIRY
            or datetime.fromisoformat(EXPIRY.replace('Z', '+00:00')) <= now
            or not hosting.VERSION_RE.fullmatch(version)
            or not re.fullmatch(re.escape(hosting.PREVIEW_PATH) + '/releases/[A-Za-z0-9_-]+', release)):
        raise ValueError('Existing channel host/expiry/release differs or has expired')
    return channel


def deploy(path, mode, output, transport, observe=public_files, now=None):
    if output.exists():
        raise ValueError('Existing receipt requires inspection; no automatic retry')
    files = verify_archive(path, mode)  # Before any authenticated request.
    plan = recipe(); previous_mode = 'rollback' if mode == 'update' else 'update'
    api = UpdateAPI(transport)
    channel = checked_channel(api, now or datetime.now(timezone.utc))
    live = hosting.release_head(api)
    observe(ORIGIN, plan['archives'][previous_mode]['files'])
    api.current = channel['release']['version']['name']
    current = api.request('GET', api.current)
    config = current.get('config')
    if current.get('name') != api.current or current.get('status') != 'FINALIZED' or not isinstance(config, dict):
        raise ValueError('Existing version/config not established')
    for glob in ['/', '/index.html']:
        entries = [h for h in config.get('headers', []) if h.get('glob') == glob]
        if len(entries) != 1 or entries[0].get('headers', {}).get('Content-Security-Policy') != hosting.FRAME_POLICY:
            raise ValueError('Existing frame policy not established')
    api.config = config  # Preserve the server's entire Hosting config, not just CSP.
    receipt = {'status': 'validated-existing-preview', 'mode': mode, 'archive_sha256': ARCHIVE_SHA[mode],
               'origin': ORIGIN, 'expire_time': EXPIRY, 'previous_channel_release': channel['release'],
               'previous_live_release': live, 'config_sha256': hashlib.sha256(json.dumps(config, sort_keys=True).encode()).hexdigest(),
               'auth_acceptance': 'not-tested', 'automatic_retry': False}
    def save(status):
        receipt['status'] = status; output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(receipt, indent=2) + '\n')
    compressed, paths = {}, {}
    for name, payload in files.items():
        payload = gzip.compress(payload, mtime=0); digest = hashlib.sha256(payload).hexdigest()
        compressed[digest] = payload; paths['/' + name] = digest
    save('version-create-outcome-pending')
    version = api.request('POST', hosting.SITE_PATH + '/versions', {'config': config}).get('name', '')
    if not hosting.VERSION_RE.fullmatch(version) or version == api.current:
        raise ValueError('Unconfirmed new version; inspect receipt before retrying')
    api.new = version; receipt['version'] = version; save('staging-existing-preview')
    upload_url = 'https://upload-firebasehosting.googleapis.com/upload/' + version + '/files'
    result = api.request('POST', version + ':populateFiles', {'files': paths})
    required = result.get('uploadRequiredHashes', [])
    if (result.get('uploadUrl') != upload_url or not isinstance(required, list)
            or len(set(required)) != len(required) or not set(required).issubset(compressed)):
        raise ValueError('Untrusted upload response')
    for digest in required:
        api.request('POST', upload_url + '/' + digest, compressed[digest], upload=True)
    finalized = api.request('PATCH', version + '?update_mask=status', {'status': 'FINALIZED'})
    if finalized.get('name') != version or finalized.get('status') != 'FINALIZED':
        raise ValueError('Version not finalized')
    if checked_channel(api, now or datetime.now(timezone.utc)) != channel or hosting.release_head(api) != live:
        raise ValueError('Channel/live state changed during staging; not released')
    save('preview-release-outcome-pending')
    release = api.request('POST', hosting.PREVIEW_PATH + '/releases?' + urlencode({'versionName': version}), {})
    if (not re.fullmatch(re.escape(hosting.PREVIEW_PATH) + '/releases/[A-Za-z0-9_-]+', release.get('name', ''))
            or release.get('type') != 'DEPLOY' or release.get('version', {}).get('name') != version):
        raise RuntimeError('Release outcome uncertain; do not retry or roll back automatically')
    receipt['channel_release'] = release['name']; save('preview-published-pending-public-check')
    observe(ORIGIN, plan['archives'][mode]['files'])
    confirmed = checked_channel(api, now or datetime.now(timezone.utc))
    if confirmed.get('release', {}).get('name') != release['name'] or confirmed['release']['version']['name'] != version or hosting.release_head(api) != live:
        raise RuntimeError('Post-release channel/live state differs; inspect receipt')
    save('preview-public-verified-auth-pending' if mode == 'update' else 'qualified-preview-restored')
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stage', type=Path)
    parser.add_argument('--archive', type=Path)
    parser.add_argument('--mode', choices=list(ARCHIVE_SHA))
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    if args.stage:
        stage(args.stage, args.output)
    elif args.archive and args.mode:
        if args.verify_only:
            verify_archive(args.archive, args.mode)
        else:
            deploy(args.archive, args.mode, args.output, hosting.Transport(os.environ.get('FIREBASE_HOSTING_ACCESS_TOKEN')))
    else:
        parser.error('Use --stage BASE or --archive ZIP --mode update|rollback')


if __name__ == '__main__':
    main()
