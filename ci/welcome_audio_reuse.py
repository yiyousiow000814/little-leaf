"""Fail-closed preflight for one immutable ordinary-Web audio diagnostic artifact."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import stat
import subprocess
import zipfile

PINS = {
    'repository': 'yiyousiow000814/little-leaf',
    'artifact_id': 11618320268,
    'run_id': 37933440818,
    'run_head': '8d63f936245602628386026732a6dd030dce0fc9',
    'source_commit': 'a6b8a3de4fb0f39529886b426fd7820a2c3c2ddc',
    'source_tree': '08bd2d87c4969dce910c7907682f4653b0110b65',
    'archive_sha256': 'a70dde4aad2564f9fdfd9069019c2d16da4969a03d25d99a42dd380d069225df',
    'manifest_sha256': '5006f66ff1de43e712cc4b21fd3154d67dd0d5b2cad9d887b373c2a658571be7',
    'engine_checks': 1235410,
    'test_processes': 121,
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def validate_records(artifact, run):
    assert artifact['id'] == PINS['artifact_id'], 'Wrong artifact ID'
    assert artifact['expired'] is False, 'Artifact expired or unavailable'
    assert artifact['digest'] == 'sha256:' + PINS['archive_sha256'], 'Wrong artifact digest'
    assert artifact['workflow_run']['id'] == PINS['run_id'], 'Wrong artifact run'
    assert artifact['workflow_run']['head_sha'] == PINS['run_head'], 'Wrong artifact head'
    assert run['id'] == PINS['run_id'] and run['head_sha'] == PINS['run_head'], 'Wrong workflow run/head'
    assert run['repository']['full_name'] == PINS['repository'], 'Wrong repository'
    # In-progress/failed general CI is not promoted into release qualification.
    return {'status': run['status'], 'conclusion': run.get('conclusion'), 'diagnostic_only': True}


def unpack(archive, output):
    assert digest(archive.read_bytes()) == PINS['archive_sha256'], 'Exact artifact ZIP SHA256 mismatch'
    assert not output.exists(), 'Fresh artifact output directory required'
    with zipfile.ZipFile(archive) as z:
        names = set()
        assert len(z.infolist()) <= 1000 and sum(i.file_size for i in z.infolist()) <= 512 * 1024 * 1024, 'Unexpected archive bounds'
        for item in z.infolist():
            # ZipInfo normalizes backslashes on Windows. Validate retained raw
            # archive spelling before trusting the normalized filename.
            assert item.orig_filename == item.filename and '\\' not in item.orig_filename, 'Unsafe archive member'
            name = PurePosixPath(item.filename)
            assert item.filename and not name.is_absolute() and '..' not in name.parts and '\\' not in item.filename, 'Unsafe archive member'
            assert str(name) == item.filename.rstrip('/'), 'Noncanonical archive member'
            assert item.filename not in names, 'Duplicate archive member'
            assert not stat.S_ISLNK(item.external_attr >> 16) and not item.flag_bits & 1, 'Unsupported archive member'
            names.add(item.filename)
        output.mkdir(parents=True)
        z.extractall(output)


def source_snapshot(root):
    def git(*args):
        return subprocess.check_output(['git', '-C', str(root), *args]).decode().strip()
    assert not git('status', '--porcelain', '--untracked-files=no'), 'Clean tracked source required'
    production = {}
    for name in git('ls-files', '-z').split('\0'):
        if name and (name in {'project.godot', 'main.tscn', 'export_presets.cfg'} or name.split('/')[0] in {'assets', 'data', 'scripts', 'shaders', 'web'}):
            file = root / name
            assert not file.is_symlink(), 'Symlink production source rejected'
            production[name] = digest(file.read_bytes())
    assert production, 'Nonempty exact source map required'
    return {'commit': git('rev-parse', 'HEAD'), 'tree': git('rev-parse', 'HEAD^{tree}'), 'production': production}


def validate_export(web, source, qa):
    assert source['commit'] == PINS['source_commit'], 'Wrong immutable merge checkout'
    assert source['tree'] == PINS['source_tree'], 'Wrong immutable source tree'
    manifest_path = web / 'release-manifest.json'
    assert digest(manifest_path.read_bytes()) == PINS['manifest_sha256'], 'Exact export manifest SHA256 mismatch'
    manifest = json.loads(manifest_path.read_text())
    assert manifest['source_commit'] == PINS['source_commit'], 'Wrong exported source commit'
    assert manifest['source_tree'] == PINS['source_tree'], 'Wrong exported source tree'
    assert manifest['toolchain_verification'] == 'checksum-pinned-official-archives', 'Unchecked toolchain'
    assert manifest['workflow_run'] == str(PINS['run_id']), 'Wrong export workflow run'
    assert manifest['packed_smoke'] == 'passed' and manifest['engine_checks'] == PINS['engine_checks'] and manifest['test_processes'] == PINS['test_processes'], 'Missing exact checked export gate'
    assert manifest['production_sha256'] == source['production'] == qa['production'], 'Complete production byte maps must match export, immutable source and QA checkout'
    required = {'index.html', 'index.js', 'index.wasm', 'index.pck'}
    assert required <= set(manifest['files']), 'Incomplete ordinary-Web export manifest'
    files = {str(p.relative_to(web)) for p in web.rglob('*') if p.is_file()}
    assert files == set(manifest['files']) | {'release-manifest.json'}, 'Unbound or missing export files'
    for name, expected in manifest['files'].items():
        relative = PurePosixPath(name)
        assert not relative.is_absolute() and '..' not in relative.parts and '\\' not in name, 'Unsafe manifest member'
        data = (web / name).read_bytes()
        assert len(data) == expected['bytes'] and digest(data) == expected['sha256'], 'Export byte mismatch: ' + name
    return {'manifest_sha256': digest(manifest_path.read_bytes()), 'production_file_count': len(source['production']),
            'qa_commit': qa['commit'], 'qa_tree': qa['tree'], 'source_commit': source['commit'], 'source_tree': source['tree']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['artifact-metadata', 'run-metadata', 'archive', 'source-root', 'qa-root', 'output', 'receipt']:
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    record = {'status': 'failed', 'pins': PINS, 'diagnostic_only': True,
              'scope': 'Reused immutable engine-tested ordinary-Web export; cannot qualify release or replace current complete CI.'}
    try:
        record['origin_run'] = validate_records(json.loads(args.artifact_metadata.read_text()), json.loads(args.run_metadata.read_text()))
        unpack(args.archive, args.output)
        record.update(validate_export(args.output, source_snapshot(args.source_root), source_snapshot(args.qa_root)))
        record['status'] = 'passed-preflight'
    except Exception as error:
        record['error'] = str(error)
        raise
    finally:
        args.receipt.parent.mkdir(parents=True, exist_ok=True)
        args.receipt.write_text(json.dumps(record, indent=2) + '\n')


if __name__ == '__main__':
    main()
