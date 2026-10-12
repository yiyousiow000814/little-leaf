"""Typed independent Firebase qualification from a common tag; no credentials."""
import argparse
import base64
import json
import os
from pathlib import Path
import re
import shutil
import sys
from urllib.request import Request, build_opener, HTTPRedirectHandler

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from release.firebase_release_event import artifact_for, download
from release.firebase_release_gate import require, trusted_run, REPOSITORY
from qualification.artifacts import sha256
from qualification.reuse_main_ci import GitHub
from release.common_tag import authenticate, chronology, git, valid_order

STATUS='common-tag-firebase-qualified'
WORKFLOW='.github/workflows/release-firebase.yml'
ROOT=Path(__file__).resolve().parents[2]
COORDINATOR_FILES=['tools/release/common_tag.py','tools/release/common_firebase.py',
    'tools/release/stage_released_firebase.py','tools/build/build_firebase.py','tools/qualification/run_firebase_focused.py',
    '.github/workflows/ci.yml','.github/workflows/release-firebase.yml',
    '.github/workflows/stage-firebase.yml','.github/workflows/deploy-firebase.yml']


def common_context(selection,env,run,attempt):
    require(selection.get('kind') == 'common-tag-qualified'
        and env.get('GITHUB_REPOSITORY') == REPOSITORY
        and env.get('GITHUB_EVENT_NAME') == 'workflow_run'
        and env.get('GITHUB_REF') == 'refs/heads/main'
        and env.get('GITHUB_WORKFLOW') == 'Qualify Firebase release'
        and str(run) == env.get('GITHUB_RUN_ID')
        and str(attempt) == env.get('GITHUB_RUN_ATTEMPT')
        and re.fullmatch('[1-9][0-9]*',str(run)) and re.fullmatch('[1-9][0-9]*',str(attempt))
        and re.fullmatch('[0-9a-f]{40}',env.get('GITHUB_SHA','')),
        'Independent default-main common-tag qualification required')
    event=json.loads(Path(env['GITHUB_EVENT_PATH']).read_text())
    require(event.get('workflow_run',{}).get('id') == selection['common']['common_run_id'],
            'Event must identify the pinned original common run')
    return {'workflow':WORKFLOW,'event':'workflow_run','ref':'refs/heads/main',
        'staging_run_id':int(run),'staging_attempt':int(attempt),
        'coordinator_source_commit':env['GITHUB_SHA']}


def seal(root,coordinator,output,manifest,selection,context,inputs,records,flow,evidence,reuse):
    from build.build_firebase import BROWSER_GATES
    require(git(coordinator,'rev-parse','HEAD') == context['coordinator_source_commit'],
            'Exact staging coordinator required')
    target=output/'evidence'
    for name,(relative,_,_) in BROWSER_GATES.items():
        if name != 'firebase-fullflow':
            destination=target/'original-browser'/f'{name}.json'
            destination.parent.mkdir(exist_ok=True)
            shutil.copy2(evidence/'web-build/evidence'/relative,destination)
    shutil.copy2(root/'platform/firebase/public-config.json',target/'public-config.json')
    shutil.copy2(reuse/'web/release-manifest.json',target/'base-web-manifest.json')
    proof={'schema_version':1,'context':{**context,'coordinator_source_tree':git(coordinator,'rev-parse','HEAD^{tree}')},
        'common':selection['common'],'common_origin':selection['common_origin'],
        'qualification':selection['qualification'],'ordinary_inputs':inputs,
        'fresh_firebase_gate_sha256':records,'compiled_source_sha256':flow['source_sha256'],
        'public_config_sha256':sha256(target/'public-config.json'),
        'released_transformer_sha256':sha256(root/'tools/build/build_firebase.py'),
        'coordinator_sha256':{name:sha256(coordinator/name) for name in COORDINATOR_FILES},
        'runtime_sha256':{name:sha256(output/'public'/name) for name in ['index.js','index.wasm','index.pck']},
        'ordinary_browser_sha256':{name:sha256(target/'original-browser'/f'{name}.json') for name in BROWSER_GATES if name!='firebase-fullflow'},
        'new_engine_suite_run':False,'new_ordinary_browser_matrix_run':False,
        'production_security_changes':False,'hosted_acceptance':False}
    manifest['common_tag_reuse']=proof
    (target/'common-tag-reuse.json').write_text(json.dumps(proof,indent=2)+'\n')


def validate_packet(folder,manifest,marker):
    from build.build_firebase import BROWSER_GATES
    from release.stage_released_firebase import validate_focused
    proof=manifest['common_tag_reuse']; common=proof['common']; q=common['qualification']; context=proof['context']
    require(manifest.get('status') == STATUS and common.get('status') == 'common-tag-qualified'
        and proof.get('schema_version') == 1 and proof.get('qualification') == q
        and proof.get('new_engine_suite_run') is False and proof.get('new_ordinary_browser_matrix_run') is False
        and proof.get('production_security_changes') is False and proof.get('hosted_acceptance') is False
        and valid_order(common.get('release_order')), 'Separate complete common-tag proof required')
    require(json.loads((folder/'evidence/common-tag-reuse.json').read_text()) == proof
        and {k:marker.get(k) for k in ['source_commit','source_tree','version']} ==
            {k:common[k] for k in ['source_commit','source_tree','version']}
        and marker.get('tag') == common['release_tag'] and marker.get('release_order') == common['release_order']
        and manifest.get('source_commit') == common['source_commit'] and manifest.get('source_tree') == common['source_tree'],
        'Packet/source/marker chronology differs')
    base_path=folder/'evidence/base-web-manifest.json'; base=json.loads(base_path.read_text())
    require(base == manifest['base_web_manifest'] and sha256(base_path) == common['web_manifest_sha256']
        and base.get('release_reuse') == q and proof['ordinary_inputs']['qualification'] == q
        and q.get('mandatory_gate_success') is True and q.get('packed_startup') == 'passed'
        and q.get('qualified_payload_unchanged') is True, 'Common qualified runtime manifest differs')
    native_path=folder/'evidence/base-native-summary.json'; native=json.loads(native_path.read_text())
    export=json.loads((folder/'evidence/base-export-report.json').read_text()); original=dict(base)
    original.pop('release_reuse');original['tag']=''
    require(export.get('manifest') == original and export.get('stages') and all(s.get('exit_code') == 0 for s in export['stages'])
        and sha256(native_path) == base['test_report_sha256'] and native.get('status') == 'passed'
        and native.get('player_save_used') is False and native.get('source_commit') == common['source_commit']
        and native.get('total_checks') == base['engine_checks'] and native.get('test_processes') == base['test_processes'],
        'Original native/export evidence differs')
    for name,(relative,key,expected) in BROWSER_GATES.items():
        if name=='firebase-fullflow':continue
        path=folder/'evidence/original-browser'/f'{name}.json'; report=json.loads(path.read_text())
        require(sha256(path) == proof['ordinary_browser_sha256'][name] and report.get(key) == expected
                and (key!='passed' or report[key] is True), 'Original ordinary browser gate differs: '+name)
    records=validate_focused(ROOT,folder/'evidence',common['source_commit'],common['source_tree'],
                             context['staging_run_id'],context['staging_attempt'])
    flow_path=folder/'evidence/firebase-fullflow.json';flow=json.loads(flow_path.read_text())
    records['firebase-fullflow.json']=sha256(flow_path)
    expected={'passed':True,'source_commit':common['source_commit'],'source_tree':common['source_tree'],
        'export_manifest_sha256':common['web_manifest_sha256'],'native_report_sha256':sha256(native_path),
        'real_compiled_ui':True,'real_firestore_rules':True,'synthetic_only':True,'browser_sandbox':True,
        'real_google_sign_in':False,'diagnostic_only':False}
    require(records == proof['fresh_firebase_gate_sha256'] and flow.get('checks')
        and all(type(flow.get(k)) is type(v) and flow[k] == v for k,v in expected.items())
        and flow.get('source_sha256') == proof['compiled_source_sha256'], 'Fresh exact Firebase gates required')
    config_path=folder/'evidence/public-config.json';config=json.loads(config_path.read_text())
    require(sha256(config_path) == proof['public_config_sha256'] and config.get('projectId')=='little-leaf-41e5d'
        and config.get('authDomain')=='little-leaf-41e5d.firebaseapp.com', 'Exact public project required')
    for name,digest in proof['runtime_sha256'].items():
        require(name in ['index.js','index.wasm','index.pck'] and sha256(folder/'public'/name)==digest==base['files'][name]['sha256'],
                'Common runtime bytes changed')
    require(set(proof['runtime_sha256']) == {'index.js','index.wasm','index.pck'}, 'Complete runtime proof required')
    require((folder/'public/index.html').read_text().count('window.__littleLeafRelease='+json.dumps(marker).replace('<','\\u003c')+';')==1,
            'Exact immutable loaded-page marker required')
    return proof


def authenticate_packet(api,folder,manifest,origin,root):
    marker=json.loads((folder/'public/hosting-release.json').read_text());proof=validate_packet(folder,manifest,marker)
    context=proof['context']; run=api.read(f"actions/runs/{context['staging_run_id']}/attempts/{context['staging_attempt']}")
    trusted_run(run,WORKFLOW,('workflow_run',))
    require(run == origin['run'] and run['run_attempt'] == context['staging_attempt']
        and run['head_sha'] == context['coordinator_source_commit'] and run.get('head_branch') == 'main', 'Staging origin differs')
    jobs=api.pages(f"actions/runs/{run['id']}/attempts/{run['run_attempt']}/jobs",'jobs')
    require(any(job.get('name') == 'common / released' and job.get('conclusion') == 'success' for job in jobs)
        and all(job.get('status') == 'completed' and job.get('conclusion') in {'success','skipped'} for job in jobs),
        'Independent Firebase qualification did not succeed')
    artifact=api.read(f"actions/artifacts/{origin['artifact']['id']}")
    require(artifact == origin['artifact'] and artifact.get('expired') is False
        and artifact.get('name') == f"little-leaf-firebase-{manifest['source_commit']}-{context['staging_attempt']}"
        and artifact.get('workflow_run',{}).get('id') == run['id']
        and artifact['workflow_run'].get('head_sha') == run['head_sha'], 'Immutable Firebase archive differs')
    # Re-read the immutable common archive, rather than trusting a packet's
    # self-asserted copy of its manifest/qualification receipt.
    import tempfile
    from release.common_tag import consume
    with tempfile.TemporaryDirectory() as temporary:
        selected=consume(api,proof['common']['common_run_id'],Path(temporary)/'common')
        require(selected['common'] == proof['common'] and selected['common_origin'] == proof['common_origin'],
                'Packet differs from actual immutable common receipt')
    common_origin=proof['common_origin'];common_artifact=api.read(f"actions/artifacts/{common_origin['artifact']['id']}")
    require(common_artifact == common_origin['artifact'] and common_artifact.get('expired') is False
        and common_artifact.get('name') == 'little-leaf-common-release-'+manifest['source_commit']+'-1'
        and common_artifact.get('workflow_run',{}).get('id') == proof['common']['common_run_id'], 'Common archive differs')
    require(chronology(root,manifest['source_commit']) == proof['common']['release_order'], 'Immutable source chronology differs')
    def content_hash(path,commit):
        value=api.read(f'contents/{path}?ref={commit}')
        require(value.get('encoding') == 'base64', 'Exact source content required')
        import hashlib
        return hashlib.sha256(base64.b64decode(value['content'])).hexdigest()
    from release.stage_released_firebase import FULLFLOW_SOURCES
    require(proof['compiled_source_sha256'] == {name:content_hash('platform/'+name if name.startswith(('web/','firebase/')) else name,manifest['source_commit']) for name in FULLFLOW_SOURCES}
        and proof['public_config_sha256'] == content_hash('platform/firebase/public-config.json',manifest['source_commit'])
        and proof['released_transformer_sha256'] == content_hash('tools/build/build_firebase.py',manifest['source_commit'])
        and proof['coordinator_sha256'] == {name:content_hash(name,run['head_sha']) for name in COORDINATOR_FILES}
        and api.read('git/commits/'+run['head_sha'])['tree']['sha'] == context['coordinator_source_tree'],
        'Fresh authenticated source/coordinator evidence differs')
    return {**origin,'common_authenticated':True,'common_proof_sha256':sha256(folder/'evidence/common-tag-reuse.json')}


def require_origin(folder,manifest,origin):
    require(isinstance(origin,dict) and origin.get('common_authenticated') is True
        and origin.get('common_proof_sha256') == sha256(folder/'evidence/common-tag-reuse.json'),
        'Fresh authenticated independent Firebase origin required')
    context=manifest['common_tag_reuse']['context'];run=origin['run'];artifact=origin['artifact']
    trusted_run(run,WORKFLOW,('workflow_run',))
    require(run['id'] == context['staging_run_id'] and run['run_attempt'] == context['staging_attempt']
        and run['head_sha'] == context['coordinator_source_commit'] and run.get('head_branch')=='main'
        and artifact.get('expired') is False and artifact.get('workflow_run',{}).get('id')==run['id']
        and artifact['workflow_run'].get('head_sha')==run['head_sha']
        and re.fullmatch('sha256:[0-9a-f]{64}',artifact.get('digest','')),
        'Qualified independent staging origin differs')


def forward(current,candidate,api):
    from release.release_metadata import RELEASE,release_key
    require(current.get('schema_version')==1 and re.fullmatch('[0-9a-f]{40}',current.get('source_commit',''))
        and re.fullmatch(RELEASE,current.get('version','')) and current.get('tag')=='v'+current['version'],
        'Known current-live source/version required')
    def key(marker):return release_key(marker['version'].split('-pre.')[0])
    require(key(candidate)>=key(current) and not
        (key(candidate)==key(current) and '-pre.' in candidate['version'] and '-pre.' not in current['version']),
        'Refusing older platform release version')
    if current == candidate:return 'already-current'
    require(current['source_commit']!=candidate['source_commit'] and
        api.read(f"compare/{current['source_commit']}...{candidate['source_commit']}").get('status')=='ahead',
        'Refusing duplicate, uncertain, unrelated or older platform source')
    return 'forward-qualified'


def current_marker():
    class NoRedirect(HTTPRedirectHandler):
        def redirect_request(self,*args):raise ValueError('Unexpected public marker redirect')
    request=Request('https://little-leaf-41e5d.firebaseapp.com/hosting-release.json',headers={'Cache-Control':'no-cache'})
    with build_opener(NoRedirect()).open(request,timeout=15) as response:
        data=response.read(65537)
    require(len(data)<=65536,'Public marker exceeds finite bound')
    return json.loads(data)


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--run',type=int,required=True)
    parser.add_argument('--output',type=Path,required=True);args=parser.parse_args()
    api=GitHub(os.environ.get('GH_TOKEN','')); run=api.read(f'actions/runs/{args.run}')
    trusted_run(run,WORKFLOW,('workflow_run',))
    artifacts=[a for a in api.pages(f'actions/runs/{args.run}/artifacts','artifacts') if re.fullmatch('little-leaf-firebase-[0-9a-f]{40}-'+str(run['run_attempt']),a.get('name',''))]
    require(len(artifacts)==1,'Exact current-attempt Firebase artifact required')
    artifact=artifact_for(api,run,artifacts[0]['name']);download(api,artifact,args.output/'variant')
    folder=args.output/'variant'; manifest=json.loads((folder/'firebase-variant-manifest.json').read_text())
    origin=authenticate_packet(api,folder,manifest,{'run':run,'artifact':artifact},ROOT)
    current=current_marker();marker=json.loads((folder/'public/hosting-release.json').read_text())
    status=forward(current,marker,api);origin['live_baseline']=current
    (args.output/'origin.json').write_text(json.dumps(origin,indent=2)+'\n')
    (args.output/'status.json').write_text(json.dumps({'status':status,'source_commit':manifest['source_commit'],
        'variant_manifest_sha256':sha256(folder/'firebase-variant-manifest.json'),
        'mutation_performed':False,'hosted_acceptance':False},indent=2)+'\n')
    with open(os.environ['GITHUB_OUTPUT'],'a') as stream:
        stream.write(f"source_sha={manifest['source_commit']}\nmanifest_sha256={sha256(folder/'firebase-variant-manifest.json')}\nalready_current={'true' if status=='already-current' else 'false'}\n")
    print('Independent common-tag Firebase origin verified; no Hosting mutation')


if __name__=='__main__':main()
