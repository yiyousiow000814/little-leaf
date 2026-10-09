"""Allow a browser-harness diagnostic only when every production byte is unchanged.

A diagnostic is never a complete CI gate, a release qualification, or publication.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
from build_web import PRODUCTION_DIRS, PRODUCTION_FILES

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def validate_selection(run, web_artifact, evidence_artifact, run_id, web_id, evidence_id, source_sha):
    repo='yiyousiow000814/little-leaf'
    if (run.get('id')!=int(run_id) or run.get('repository',{}).get('full_name')!=repo
            or run.get('head_repository',{}).get('full_name')!=repo
            or run.get('path')!='.github/workflows/ci.yml'
            or run.get('status')!='completed' or run.get('conclusion')!='success'):
        raise ValueError('Selected run is not successful same-repository CI')
    for artifact, expected_id, kind in [(web_artifact,web_id,'web'),(evidence_artifact,evidence_id,'evidence')]:
        if (artifact.get('id')!=int(expected_id) or artifact.get('expired') is not False
                or artifact.get('workflow_run',{}).get('id')!=int(run_id)
                or artifact.get('name')!='little-leaf-'+kind+'-'+source_sha+'-'+str(run['run_attempt'])):
            raise ValueError('Selected artifact identity, kind or run differs')


def validate(web, evidence, source_sha, source_tree, run_id, root=ROOT):
    if not re.fullmatch(r'[0-9a-f]{40}', source_sha) or not re.fullmatch(r'[0-9a-f]{40}', source_tree):
        raise ValueError('Exact original export source SHA and tree required')
    manifest = json.loads((web / 'release-manifest.json').read_text())
    summary_path = evidence / 'engine-evidence/summary.json'
    summary = json.loads(summary_path.read_text())
    if (manifest.get('source_commit') != source_sha or manifest.get('source_tree') != source_tree
            or str(manifest.get('workflow_run')) != str(run_id)
            or manifest.get('toolchain_verification') != 'checksum-pinned-official-archives'
            or manifest.get('packed_smoke') != 'passed'
            or manifest.get('test_report_sha256') != digest(summary_path)
            or summary.get('source_commit') != source_sha or summary.get('status') != 'passed'
            or summary.get('player_save_used') is not False
            or summary.get('total_checks', 0) <= 0 or summary.get('test_processes', 0) <= 0
            or manifest.get('engine_checks') != summary.get('total_checks')
            or manifest.get('test_processes') != summary.get('test_processes')):
        raise ValueError('Original exported source/run and complete native evidence do not match')
    files = manifest.get('files', {})
    if (not {'index.html','index.js','index.wasm','index.pck'}.issubset(files)
            or any(p.is_symlink() for p in web.rglob('*'))
            or {p.relative_to(web).as_posix() for p in web.rglob('*') if p.is_file()} != set(files) | {'release-manifest.json'}):
        raise ValueError('Unexpected or missing diagnostic Web files')
    for name, spec in files.items():
        if (Path(name).name != name or name.startswith('.') or '\\' in name
                or (web / name).stat().st_size != spec.get('bytes') or digest(web / name) != spec.get('sha256')):
            raise ValueError('Diagnostic Web bytes differ from the source-bound export')
    tracked = set(subprocess.check_output(['git','-C',str(root),'ls-files','-z'], text=True).split('\0')) - {''}
    production = {name for name in tracked if name in PRODUCTION_FILES or Path(name).parts[0] in PRODUCTION_DIRS}
    if production != set(manifest.get('production_sha256', {})):
        raise ValueError('Production inventory changed; run the full engine/export gate')
    for name in production:
        path = root / name
        if path.is_symlink() or digest(path) != manifest['production_sha256'][name]:
            raise ValueError('Production changed; full engine/export gate required: ' + name)
    # Native evidence cannot be reused if engine tests, runner or toolchain changed.
    native = {name for name in tracked if name.startswith('tests/') and name.endswith('.gd')}
    old_native = {name for name in summary['source_sha256'] if name.startswith('tests/') and name.endswith('.gd')}
    if native != old_native:
        raise ValueError('Native suite inventory changed')
    for name in native | {'tests/run_integration_candidate.py', 'ci/toolchain.json'}:
        if (root / name).is_symlink() or digest(root / name) != summary['source_sha256'].get(name):
            raise ValueError('Native tests/runner/toolchain changed: ' + name)
    tutorial = [record for record in summary['records'] if record['test'] == 'test_save_log']
    if (len(tutorial) != 1 or tutorial[0].get('exit_code') or tutorial[0].get('failures')
            or digest(evidence / 'engine-evidence/test_save_log-result.json') != tutorial[0].get('result_sha256')):
        raise ValueError('Settings layout evidence differs from the complete native run')
    return {'schema_version': 1, 'purpose': 'browser-harness-diagnostic-only', 'release_qualified': False,
            'export_source_commit': source_sha, 'export_source_tree': source_tree, 'export_run_id': str(run_id),
            'current_production_sha256': manifest['production_sha256'],
            'export_manifest_sha256': digest(web / 'release-manifest.json'),
            'engine_report_sha256': digest(summary_path),
            'layout_sha256': digest(evidence / 'engine-evidence/test_save_log-result.json'),
            'harness_commit': subprocess.check_output(['git','-C',str(root),'rev-parse','HEAD'], text=True).strip(),
            'harness_sha256': {name: digest(root / name) for name in
                              ['tests/cloud_settings_browser.js','tests/cloud_settings_browser_helpers.js']}}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--web',required=True,type=Path)
    parser.add_argument('--evidence',required=True,type=Path)
    parser.add_argument('--source-sha',required=True)
    parser.add_argument('--source-tree',required=True)
    parser.add_argument('--run-id',required=True)
    parser.add_argument('--output',required=True,type=Path)
    args=parser.parse_args()
    result=validate(args.web,args.evidence,args.source_sha,args.source_tree,args.run_id)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,indent=2)+'\n')
    print('Exact production/native inputs verified. Browser diagnostic only; never a full gate or release qualification.')


if __name__=='__main__':main()
