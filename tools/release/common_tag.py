"""One immutable tag qualification consumed independently by both platforms.

Read-only GitHub/Git access; no platform credential, upload, dispatch or deploy.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from release.firebase_release_event import artifact_for, download, peel
from release.firebase_release_gate import require, trusted_run, REPOSITORY
from qualification.artifacts import sha256, validate_export_inventory
from qualification.reuse_main_ci import GitHub, bind_package, require_jobs
from release.release_metadata import RELEASE, version

WORKFLOW = '.github/workflows/ci.yml'
STATUS = 'common-tag-qualified'
ROOT = Path(__file__).resolve().parents[2]


def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args], text=True).strip()


def chronology(root, source, main='FETCH_HEAD'):
    require(re.fullmatch('[0-9a-f]{40}', source or ''), 'Full source identity required')
    require(git(root, 'rev-parse', '--is-shallow-repository') == 'false', 'Complete source history required')
    require(source in git(root, 'rev-list', '--first-parent', main).splitlines(),
            'Tagged source must be on main first-parent history')
    chain = list(reversed(git(root, 'rev-list', '--first-parent', source).splitlines()))
    require(chain and chain[-1] == source and len(chain) <= 9007199254740991,
            'Complete immutable source chain required')
    return {'kind': 'main-first-parent', 'repository': REPOSITORY, 'anchor': chain[0],
            'sequence': len(chain), 'chain_sha256': hashlib.sha256(('\n'.join(chain)+'\n').encode()).hexdigest()}


def valid_order(order):
    return (isinstance(order, dict) and set(order) == {'kind','repository','anchor','sequence','chain_sha256'}
            and order['kind'] == 'main-first-parent' and order['repository'] == REPOSITORY
            and type(order['sequence']) is int and 0 < order['sequence'] <= 9007199254740991
            and isinstance(order['anchor'],str) and re.fullmatch('[0-9a-f]{40}', order['anchor'])
            and isinstance(order['chain_sha256'],str) and re.fullmatch('[0-9a-f]{64}', order['chain_sha256']))


def require_common_jobs(jobs, run, attempt):
    matches = [job for job in jobs if job.get('name') == 'common_tag']
    require(len(matches) == 1 and matches[0].get('conclusion') == 'success'
            and matches[0].get('status') == 'completed'
            and matches[0].get('run_id') == run and matches[0].get('run_attempt') == attempt,
            'Exact common qualification job must pass')
    require(all(job.get('status') == 'completed' and
                (job is matches[0] or job.get('conclusion') == 'skipped') for job in jobs),
            'Common qualification must be independent of platform jobs')


def create(folder, root, tag, environment):
    source = git(root, 'rev-parse', 'HEAD'); tree = git(root, 'rev-parse', 'HEAD^{tree}')
    require(environment.get('GITHUB_REPOSITORY') == REPOSITORY
            and environment.get('GITHUB_EVENT_NAME') == 'push'
            and environment.get('GITHUB_REF') == 'refs/tags/'+tag
            and environment.get('GITHUB_SHA') == source
            and environment.get('GITHUB_RUN_ATTEMPT') == '1'
            and environment.get('RELEASE_TAG_CREATED') == 'true'
            and re.fullmatch('[1-9][0-9]*', environment.get('GITHUB_RUN_ID','')),
            'Only the original immutable tag creation may qualify')
    require(not (folder/'common.json').exists(), 'Existing common receipt cannot be replaced')
    q = json.loads((folder/'qualification.json').read_text())
    manifest = validate_export_inventory(folder/'web')
    require(q == manifest.get('release_reuse') and q.get('tag') == tag
            and q.get('source_commit') == source and q.get('source_tree') == tree
            and q.get('version') == version(root, tag, source_commit=source)
            and q.get('mandatory_gate_success') is True and q.get('packed_startup') == 'passed'
            and q.get('qualified_payload_unchanged') is True and (folder/'packed-startup.log').is_file(),
            'Complete exact-main qualification and final startup required')
    receipt = {'schema_version':1, 'status':STATUS, 'repository':REPOSITORY, 'workflow':WORKFLOW,
        'common_run_id':int(environment['GITHUB_RUN_ID']), 'common_attempt':1,
        'release_tag':tag, 'source_commit':source, 'source_tree':tree, 'version':q['version'],
        'release_order':chronology(root, source), 'qualification':q,
        'web_manifest_sha256':sha256(folder/'web/release-manifest.json'),
        'packed_startup_log_sha256':sha256(folder/'packed-startup.log'),
        'tag_creation_event':True, 'platform_publication_required':False}
    (folder/'common.json').write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')
    return receipt


def authenticate(api, receipt, run_id):
    require(type(receipt.get('schema_version')) is int and receipt['schema_version'] == 1 and receipt.get('status') == STATUS
            and receipt.get('repository') == REPOSITORY and receipt.get('workflow') == WORKFLOW
            and receipt.get('common_run_id') == run_id and type(run_id) is int and run_id > 0
            and type(receipt.get('common_attempt')) is int and receipt['common_attempt'] == 1 and receipt.get('tag_creation_event') is True
            and receipt.get('platform_publication_required') is False and valid_order(receipt.get('release_order')),
            'Unsupported common qualification receipt')
    tag = receipt['release_tag']; source = receipt['source_commit']
    require(isinstance(tag,str) and re.fullmatch('v'+RELEASE,tag)
            and tag == 'v'+receipt.get('version','') and re.fullmatch('[0-9a-f]{40}',source or '')
            and ('-pre.' not in tag or tag.rsplit('.',1)[1] == source[:8]), 'Tag/source/version binding differs')
    run = api.read(f'actions/runs/{run_id}/attempts/1')
    trusted_run(run, WORKFLOW, ('push',))
    workflow=api.read('actions/workflows/ci.yml')
    require(workflow.get('path')==WORKFLOW and workflow.get('state')=='active'
            and run.get('workflow_id')==workflow.get('id'), 'Common workflow identity differs')
    require(run['id'] == run_id and run['run_attempt'] == 1 and run.get('head_branch') == tag
            and run['head_sha'] == source and peel(api,tag) == source
            and api.read('git/commits/'+source)['tree']['sha'] == receipt['source_tree'],
            'Immutable tag/common attempt source differs')
    require_common_jobs(api.pages(f'actions/runs/{run_id}/attempts/1/jobs','jobs'),run_id,1)
    require(api.read(f'compare/{source}...main').get('status') in {'ahead','identical'},
            'Common source no longer belongs to main history')
    q=receipt['qualification']
    require(type(q.get('schema_version')) is int and q['schema_version']==1 and q.get('repository')==REPOSITORY
        and q.get('workflow')==WORKFLOW and all(type(q.get(k)) is int and q[k]>0 for k in ['qualification_run_id','qualification_attempt','artifact_id'])
        and re.fullmatch('sha256:[0-9a-f]{64}',q.get('artifact_digest',''))
        and re.fullmatch('[0-9a-f]{64}',q.get('qualified_manifest_sha256','')),
        'Complete immutable original qualification identity required')
    original=api.read(f"actions/runs/{q['qualification_run_id']}/attempts/{q['qualification_attempt']}")
    trusted_run(original,WORKFLOW,('push','workflow_dispatch'))
    require(original.get('head_branch') == 'main' and original['head_sha'] == source
            and original['run_attempt'] == q['qualification_attempt']
            and q.get('source_commit') == source and q.get('source_tree') == receipt['source_tree']
            and q.get('version') == receipt['version'] and q.get('tag') == tag
            and q.get('mandatory_gate_success') is True and q.get('packed_startup') == 'passed'
            and q.get('qualified_payload_unchanged') is True, 'Original exact-main qualification differs')
    require_jobs(api.pages(f"actions/runs/{original['id']}/attempts/{original['run_attempt']}/jobs",'jobs'))
    artifact=api.read(f"actions/artifacts/{q['artifact_id']}")
    require(artifact.get('expired') is False and artifact.get('digest') == q['artifact_digest']
            and artifact.get('name') == f"little-leaf-web-{source}-{q['qualification_attempt']}"
            and artifact.get('workflow_run',{}).get('id') == original['id']
            and artifact['workflow_run'].get('head_sha') == source,
            'Original immutable qualification archive differs or expired')
    return run, original


def consume(api, run_id, output):
    # The event identifies ONE original run. No newest-run or artifact-name fallback.
    require(type(run_id) is int and run_id > 0, 'Exact common run required')
    run=api.read(f'actions/runs/{run_id}/attempts/1')
    trusted_run(run,WORKFLOW,('push',))
    artifact=artifact_for(api,run,'little-leaf-common-release-'+run['head_sha']+'-1')
    download(api,artifact,output)
    receipt=json.loads((output/'common.json').read_text())
    _, original=authenticate(api,receipt,run_id)
    manifest=validate_export_inventory(output/'web')
    require(sha256(output/'web/release-manifest.json') == receipt['web_manifest_sha256']
            and sha256(output/'packed-startup.log') == receipt['packed_startup_log_sha256']
            and json.loads((output/'qualification.json').read_text()) == receipt['qualification']
            and manifest.get('release_reuse') == receipt['qualification'], 'Common package payload differs')
    expected={'common.json','qualification.json','packed-startup.log'}|{'web/'+name for name in manifest['files']}|{'web/release-manifest.json'}
    require({p.relative_to(output).as_posix() for p in output.rglob('*') if p.is_file()} == expected,
            'Unexpected common package files')
    selection={'kind':STATUS, 'source_commit':receipt['source_commit'], 'source_tree':receipt['source_tree'],
        'release_tag':receipt['release_tag'], 'qualification':receipt['qualification'],
        'common':receipt, 'common_origin':{'run':run,'artifact':artifact},
        'release_run_id':run_id}
    (output/'selection.json').write_text(json.dumps(selection,indent=2)+'\n',encoding='utf-8')
    return selection


def verify_local(root, folder, selection, api):
    receipt=selection['common']; _,run=authenticate(api,receipt,receipt['common_run_id'])
    require(git(root,'rev-parse','HEAD') == receipt['source_commit']
            and git(root,'rev-parse','HEAD^{tree}') == receipt['source_tree']
            and not git(root,'status','--porcelain','--untracked-files=no'), 'Exact unchanged source checkout required')
    require(chronology(root,receipt['source_commit']) == receipt['release_order'], 'Source chronology differs')
    require(sha256(folder/'web/release-manifest.json') == receipt['web_manifest_sha256'], 'Common manifest changed')
    return bind_package(folder/'web',root,receipt['source_commit'],receipt['source_tree'],run,receipt['release_tag'])


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode',choices=['create','consume','verify'])
    parser.add_argument('--folder',type=Path,required=True)
    parser.add_argument('--tag',default='');parser.add_argument('--run',type=int)
    parser.add_argument('--source-root',type=Path,default=ROOT)
    args=parser.parse_args()
    if args.mode == 'create':result=create(args.folder,args.source_root,args.tag,os.environ)
    else:
        api=GitHub(os.environ.get('GH_TOKEN',''))
        if args.mode == 'consume':result=consume(api,args.run,args.folder)
        else:result=verify_local(args.source_root,args.folder,json.loads((args.folder/'selection.json').read_text()),api)
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'],'a') as stream:
            for key,value in {'source_sha':result['source_commit'],'release_tag':result.get('release_tag',args.tag)}.items():stream.write(f'{key}={value}\n')
    print('Exact common qualification verified; no platform operation performed')


if __name__ == '__main__':main()
