"""Typed independent Firebase qualification from a common tag; no credentials."""
import argparse
import base64
import json
import os
from pathlib import Path
import re
import shutil
import sys
from html.parser import HTMLParser
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
ANCESTORS=['https://html-classic.itch.zone', 'https://siowyiyou.itch.io']
PROJECTION_FILES=['public/index.html','public/hosting-release.json',
    'public/itch/index.html','public/itch/hosting-release.json']
ORIGINAL='evidence/common-delivery-original/'


def qualified_path(folder,projection,name):
    return folder/(ORIGINAL+name if projection and name in PROJECTION_FILES else name)


def surface_inventory(folder, surface, projection=None):
    root=folder/surface
    require(root.is_dir() and not any(p.is_symlink() for p in root.rglob('*')), 'Complete same-page surface required')
    return {p.relative_to(root).as_posix():sha256(qualified_path(folder,projection,p.relative_to(folder).as_posix()))
        for p in sorted(root.rglob('*')) if p.is_file()}


def validate_same_page(folder,manifest,proof,flow,projection=None):
    same=proof.get('same_page',{})
    require(same.get('compiled_entry_sha256') == flow.get('itch_entry_sha256')
        and re.fullmatch('[0-9a-f]{64}',same.get('compiled_entry_sha256',''))
        and flow.get('itch_test_entry') is True and flow.get('itch_ancestor_origins') == ANCESTORS
        and same.get('embedded_sha256') == surface_inventory(folder,'public/itch',projection)
        and same.get('wrapper_sha256') == surface_inventory(folder,'itch-wrapper'),
        'Exact compiled same-page entry and complete delivery surfaces required')
    base=manifest['base_web_manifest'];common=proof['common']
    for surface in ['public/itch','itch-wrapper']:
        for name in ['index.js','index.wasm','index.pck']:
            require(sha256(folder/surface/name) == base['files'][name]['sha256'], 'Same-page runtime bytes changed')
    marker=json.loads(qualified_path(folder,projection,'public/itch/hosting-release.json').read_text())
    require(marker.get('source_commit') == common['source_commit'] and marker.get('source_tree') == common['source_tree']
        and marker.get('version') == common['version'] and marker.get('tag') == common['release_tag']
        and marker.get('release_order') == common['release_order']
        and marker.get('runtime_origin') == 'https://little-leaf-41e5d.firebaseapp.com'
        and marker.get('runtime_path') == '/itch/' and marker.get('test_surface') == 'trusted-itch-frame',
        'Exact common same-page loaded marker required')
    require(qualified_path(folder,projection,'public/itch/index.html').read_text().count('window.__littleLeafRelease='+json.dumps(marker).replace('<','\\u003c')+';') == 1,
        'Embedded loaded marker differs')
    require('release-manifest.json' not in same['wrapper_sha256']
        and set(same['wrapper_sha256']) == set(base['files'])
        and all(same['wrapper_sha256'][name] == value['sha256'] for name,value in base['files'].items() if name!='index.html'),
        'Wrapper must retain every original member except the derived entry')
    policy='frame-ancestors https://html-classic.itch.zone https://siowyiyou.itch.io'
    additions=[{'source':'/itch/','headers':[{'key':'Content-Security-Policy','value':policy},{'key':'Cache-Control','value':'no-cache'}]},
        {'source':'/itch/index.html','headers':[{'key':'Content-Security-Policy','value':policy}]},
        {'source':'/itch/hosting-release.json','headers':[{'key':'Cache-Control','value':'no-store'}]}]
    headers=json.loads((folder/'firebase.json').read_text())['hosting']['headers']
    require(manifest.get('hosting_header_additions') == additions
        and all(headers.count(value)==1 for value in additions), 'Reviewed same-page header additions required')
    return same


class _OrdinaryAccountEntry(HTMLParser):
    def __init__(self):
        super().__init__();self.links=[]

    def handle_starttag(self,tag,attrs):
        attributes=dict(attrs)
        if attributes.get('id')=='itch-release-account':
            self.links.append((tag,attributes))


def validate_ordinary_itch(folder,manifest,proof):
    ordinary=proof.get('ordinary_itch',{});common=proof['common'];base=manifest['base_web_manifest']
    require(ordinary.get('surface')=='ordinary-root-new-tab'
        and ordinary.get('files_sha256')==surface_inventory(folder,'itch-ordinary')
        and set(ordinary['files_sha256'])==set(base['files'])|{'release-manifest.json'}
        and ordinary['files_sha256']['release-manifest.json']==common['web_manifest_sha256']
        and json.loads((folder/'itch-ordinary/release-manifest.json').read_bytes())==base
        and all(ordinary['files_sha256'][name]==record['sha256'] for name,record in base['files'].items()),
        'Exact separately bound ordinary source/tag export required')
    entry=_OrdinaryAccountEntry();entry.feed((folder/'itch-ordinary/index.html').read_text(encoding='utf-8'))
    require(len(entry.links)==1 and entry.links[0][0]=='a'
        and entry.links[0][1].get('href')=='https://little-leaf-41e5d.firebaseapp.com/'
        and entry.links[0][1].get('target')=='_blank'
        and set(entry.links[0][1].get('rel','').split())=={'noopener','noreferrer'},
        'Preserved ordinary Root account entry must open a new tab')
    return ordinary


def publication_matches(publication,manifest, *, allow_processing=False):
    proof=manifest['common_tag_reuse'];common=proof['common'];context=proof['context']
    linked=publication.get('same_page_staging_origin',{})
    state=publication.get('state')
    processing=publication.get('provider_observation',{})
    completed=(state=='completed' and type(publication.get('itch_channel_version')) is int
        and 0<publication['itch_channel_version']<=9007199254740991)
    queued=(allow_processing and state=='accepted-processing'
        and processing.get('state') in {'queued','processing'}
        and type(processing.get('build_id')) is int
        and processing=={'build_id':publication.get('itch_build_id'), 'state':processing.get('state'),
                        'version':common['version']}
        and 'itch_channel_version' not in publication)
    require(publication.get('delivery_surface')=='qualified-root-new-tab-entry'
        and publication.get('target')=='siowyiyou/little-leaf:html5'
        and (completed or queued) and type(publication.get('itch_build_id')) is int
        and publication['itch_build_id']>0
        and publication.get('source_commit')==common['source_commit']
        and publication.get('version')==common['version'] and publication.get('tag')==common['release_tag']
        and publication.get('common_qualification')==common
        and publication.get('ordinary_itch_sha256')==proof['ordinary_itch']['files_sha256']
        and publication.get('qualification')==proof['qualification']
        and publication.get('release_manifest_sha256')==common['web_manifest_sha256']
        and linked.get('run_id')==context['staging_run_id'] and linked.get('attempt')==context['staging_attempt']
        and linked.get('coordinator_source_commit')==context['coordinator_source_commit'],
        'Exact-source authenticated upload acceptance required; completed order remains separate')
    return linked


def project_delivery(folder,publication_path,origin):
    """The only post-qualification change is actual completed channel chronology."""
    path=folder/'firebase-variant-manifest.json';raw=path.read_bytes();manifest=json.loads(raw)
    require('delivery_projection' not in manifest,'No repeated metadata projection')
    publication=json.loads(publication_path.read_bytes());linked=publication_matches(publication,manifest)
    require(linked.get('artifact_id')==origin['artifact']['id'] and linked.get('artifact_digest')==origin['artifact']['digest']
        and publication.get('firebase_variant_manifest_sha256')==sha256(path), 'Publication refers to another qualified archive')
    target=folder/ORIGINAL;target.mkdir(parents=True,exist_ok=False)
    (target/'firebase-variant-manifest.json').write_bytes(raw)
    for name in PROJECTION_FILES:
        destination=target/name;destination.parent.mkdir(parents=True,exist_ok=True);destination.write_bytes((folder/name).read_bytes())
    shutil.copy2(publication_path,folder/'evidence/completed-itch-publication.json')
    for surface in ['public','public/itch']:
        marker_path=folder/surface/'hosting-release.json';html_path=folder/surface/'index.html'
        marker=json.loads(marker_path.read_bytes())
        old=('window.__littleLeafRelease='+json.dumps(marker).replace('<','\\u003c')+';').encode('utf-8')
        marker['release_order']={**marker['release_order'],'target':publication['target'],
                                 'channel_version':publication['itch_channel_version']}
        new=('window.__littleLeafRelease='+json.dumps(marker).replace('<','\\u003c')+';').encode('utf-8')
        html=html_path.read_bytes();require(html.count(old)==1,'Exact original inline marker required')
        html_path.write_bytes(html.replace(old,new))
        marker_path.write_bytes((json.dumps(marker,indent=2)+'\n').encode('utf-8'))
    manifest['delivery_projection']={'schema_version':1,'status':'completed-wrapper-order-only',
        'original_manifest_sha256':__import__('hashlib').sha256(raw).hexdigest(),
        'publication_sha256':sha256(folder/'evidence/completed-itch-publication.json')}
    manifest['files']={p.relative_to(folder).as_posix():sha256(p) for p in sorted(folder.rglob('*')) if p.is_file() and p!=path}
    path.write_text(json.dumps(manifest,indent=2)+'\n')
    validate_delivery_projection(folder,manifest)
    origin.update(publication_authenticated=True,publication_sha256=manifest['delivery_projection']['publication_sha256'],
        qualified_original_manifest_sha256=manifest['delivery_projection']['original_manifest_sha256'])
    return manifest


def validate_delivery_projection(folder,manifest):
    projection=manifest['delivery_projection'];original_path=folder/(ORIGINAL+'firebase-variant-manifest.json')
    require(type(projection.get('schema_version')) is int and projection['schema_version']==1 and projection.get('status')=='completed-wrapper-order-only'
        and sha256(original_path)==projection.get('original_manifest_sha256'), 'Exact original qualified manifest required')
    original=json.loads(original_path.read_bytes());unchanged=dict(manifest)
    unchanged.pop('delivery_projection');unchanged['files']=original['files']
    require(unchanged==original and 'delivery_projection' not in original, 'Only the declared delivery projection is permitted')
    publication_path=folder/'evidence/completed-itch-publication.json';publication=json.loads(publication_path.read_bytes())
    publication_matches(publication,original)
    require(sha256(publication_path)==projection['publication_sha256']
        and publication.get('firebase_variant_manifest_sha256')==projection['original_manifest_sha256'], 'Completed receipt changed')
    added={ORIGINAL+'firebase-variant-manifest.json','evidence/completed-itch-publication.json'}|{ORIGINAL+name for name in PROJECTION_FILES}
    require(set(manifest['files'])==set(original['files'])|added, 'Projection inventory differs')
    for name,digest in original['files'].items():
        require(sha256(qualified_path(folder,projection,name))==digest, 'Qualified original member changed: '+name)
    for surface in ['public','public/itch']:
        marker_name=surface+'/hosting-release.json';html_name=surface+'/index.html'
        before=json.loads(qualified_path(folder,projection,marker_name).read_bytes())
        after={**before,'release_order':{**before['release_order'],'target':publication['target'],
            'channel_version':publication['itch_channel_version']}}
        require(valid_order(before['release_order']), 'Original common chronology required')
        expected_marker=(json.dumps(after,indent=2)+'\n').encode()
        old=('window.__littleLeafRelease='+json.dumps(before).replace('<','\\u003c')+';').encode('utf-8')
        new=('window.__littleLeafRelease='+json.dumps(after).replace('<','\\u003c')+';').encode('utf-8')
        html=qualified_path(folder,projection,html_name).read_bytes()
        require(html.count(old)==1 and (folder/marker_name).read_bytes()==expected_marker
            and (folder/html_name).read_bytes()==html.replace(old,new), 'Only exact inline/marker chronology may change')
    require(all(sha256(folder/name)==digest for name,digest in manifest['files'].items()), 'Projected delivery member changed')
    return original


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
        'released_same_page_transformer_sha256':sha256(root/'tools/build/build_itch_trusted_preview.py'),
        'coordinator_sha256':{name:sha256(coordinator/name) for name in COORDINATOR_FILES},
        'runtime_sha256':{name:sha256(output/'public'/name) for name in ['index.js','index.wasm','index.pck']},
        'ordinary_browser_sha256':{name:sha256(target/'original-browser'/f'{name}.json') for name in BROWSER_GATES if name!='firebase-fullflow'},
        'new_engine_suite_run':False,'new_ordinary_browser_matrix_run':False,
        'production_security_changes':False,'hosted_acceptance':False,
        'same_page':{'compiled_entry_sha256':flow['itch_entry_sha256'],
            'embedded_sha256':surface_inventory(output,'public/itch'),
            'wrapper_sha256':surface_inventory(output,'itch-wrapper')},
        'ordinary_itch':{'surface':'ordinary-root-new-tab',
            'files_sha256':surface_inventory(output,'itch-ordinary')}}
    manifest['common_tag_reuse']=proof
    (target/'common-tag-reuse.json').write_text(json.dumps(proof,indent=2)+'\n')


def validate_packet(folder,manifest,marker):
    from build.build_firebase import BROWSER_GATES
    from release.stage_released_firebase import validate_focused
    projection=manifest.get('delivery_projection')
    if projection:
        manifest=validate_delivery_projection(folder,manifest)
        marker=json.loads(qualified_path(folder,projection,'public/hosting-release.json').read_bytes())
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
    validate_same_page(folder,manifest,proof,flow,projection)
    validate_ordinary_itch(folder,manifest,proof)
    config_path=folder/'evidence/public-config.json';config=json.loads(config_path.read_text())
    require(sha256(config_path) == proof['public_config_sha256'] and config.get('projectId')=='little-leaf-41e5d'
        and config.get('authDomain')=='little-leaf-41e5d.firebaseapp.com', 'Exact public project required')
    for name,digest in proof['runtime_sha256'].items():
        require(name in ['index.js','index.wasm','index.pck'] and sha256(folder/'public'/name)==digest==base['files'][name]['sha256'],
                'Common runtime bytes changed')
    require(set(proof['runtime_sha256']) == {'index.js','index.wasm','index.pck'}, 'Complete runtime proof required')
    require(qualified_path(folder,projection,'public/index.html').read_text().count('window.__littleLeafRelease='+json.dumps(marker).replace('<','\\u003c')+';')==1,
            'Exact immutable loaded-page marker required')
    return proof


def authenticate_packet(api,folder,manifest,origin,root):
    require('delivery_projection' not in manifest,'Authenticate the unchanged original archive before deriving delivery metadata')
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
        and proof['released_same_page_transformer_sha256'] == content_hash('tools/build/build_itch_trusted_preview.py',manifest['source_commit'])
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
    if manifest.get('delivery_projection'):
        validate_delivery_projection(folder,manifest)
        projection=manifest['delivery_projection']
        require(origin.get('publication_authenticated') is True
            and origin.get('publication_sha256')==projection['publication_sha256']
            and origin.get('qualified_original_manifest_sha256')==projection['original_manifest_sha256'],
            'Fresh authenticated completed wrapper publication required before Hosting')


def consume_publication(api,run_id,output):
    """Consume authenticated upload acceptance, including a named retry."""
    from release.firebase_release_gate import ITCH_WORKFLOW
    run=api.read(f'actions/runs/{run_id}');trusted_run(run,ITCH_WORKFLOW,('workflow_run','workflow_dispatch'))
    retry=None
    if run['event']=='workflow_dispatch':
        retry=re.fullmatch(r'Retry qualified itch ([1-9][0-9]*)',run.get('display_title',''))
        require(retry is not None and run['run_attempt']==1,'Only a named first-attempt qualified platform retry is allowed')
    require(run.get('head_branch')=='main','Default-main automatic wrapper publisher required')
    workflow=api.read('actions/workflows/release-itch.yml')
    require(workflow.get('state')=='active' and workflow.get('path')==ITCH_WORKFLOW
        and run.get('workflow_id')==workflow.get('id'), 'Exact active wrapper workflow required')
    jobs=api.pages(f"actions/runs/{run_id}/attempts/{run['run_attempt']}/jobs",'jobs')
    publishes=[job for job in jobs if job.get('name')=='publish']
    require(len(publishes)==1 and publishes[0].get('conclusion')=='success'
        and publishes[0].get('run_id')==run_id and publishes[0].get('run_attempt')==run['run_attempt']
        and all(job.get('status')=='completed' and job.get('conclusion') in {'success','skipped'} for job in jobs),
        'Exact successful wrapper publication attempt required')
    candidates=[a for a in api.pages(f'actions/runs/{run_id}/artifacts','artifacts')
        if re.fullmatch('little-leaf-itch-publication-[0-9a-f]{40}-'+str(run['run_attempt']),a.get('name',''))]
    require(len(candidates)==1,'One exact wrapper publication artifact required')
    artifact=artifact_for(api,run,candidates[0]['name']);download(api,artifact,output)
    receipt_path=output/'receipt.json';receipt=json.loads(receipt_path.read_bytes())
    require({p.relative_to(output).as_posix() for p in output.rglob('*') if p.is_file()}=={'receipt.json'}
        and str(receipt.get('workflow_run'))==str(run_id)
        and str(receipt.get('workflow_attempt'))==str(run['run_attempt'])
        and artifact['name']==f"little-leaf-itch-publication-{receipt.get('source_commit')}-{run['run_attempt']}",
        'Exact immutable wrapper receipt identity required')
    if retry:
        qualified_run=receipt.get('same_page_staging_origin',{}).get('run_id')
        require(type(qualified_run) is int and qualified_run==int(retry[1]),
                'Platform retry must retain its named qualified run')
    return receipt_path,{'run':run,'artifact':artifact}


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
    parser=argparse.ArgumentParser(description=__doc__)
    selected=parser.add_mutually_exclusive_group(required=True)
    selected.add_argument('--run',type=int);selected.add_argument('--itch-run',type=int)
    parser.add_argument('--platform',choices=['firebase','itch'],default='firebase')
    parser.add_argument('--output',type=Path,required=True);args=parser.parse_args()
    api=GitHub(os.environ.get('GH_TOKEN',''))
    publication_path=None
    if args.itch_run:
        require(args.platform=='firebase','Completed publication is only the Hosting metadata bridge')
        publication_path,publication_origin=consume_publication(api,args.itch_run,args.output/'publication')
        publication=json.loads(publication_path.read_bytes())
        selected_run=publication.get('same_page_staging_origin',{}).get('run_id')
        require(type(selected_run) is int and selected_run>0,'Exact qualified Firebase origin required')
    else:selected_run=args.run
    latest=api.read(f'actions/runs/{selected_run}')
    trusted_run(latest,WORKFLOW,('workflow_run',))
    # The latest-run and attempt endpoints use different jobs/logs URLs.
    # Construct origin from the same canonical view used by authentication;
    # never rewrite API objects or relax its strict equality comparison.
    run=api.read(f"actions/runs/{selected_run}/attempts/{latest['run_attempt']}")
    trusted_run(run,WORKFLOW,('workflow_run',))
    require(run['id']==selected_run and run['run_attempt']==latest['run_attempt']
            and run['head_sha']==latest['head_sha'] and run['head_branch']==latest['head_branch'],
            'Pinned qualification attempt differs from latest run')
    artifacts=[a for a in api.pages(f'actions/runs/{selected_run}/artifacts','artifacts') if re.fullmatch('little-leaf-firebase-[0-9a-f]{40}-'+str(run['run_attempt']),a.get('name',''))]
    require(len(artifacts)==1,'Exact current-attempt Firebase artifact required')
    artifact=artifact_for(api,run,artifacts[0]['name'])
    original=args.output/('variant-original' if publication_path else 'variant');download(api,artifact,original)
    folder=original;manifest=json.loads((folder/'firebase-variant-manifest.json').read_text())
    origin=authenticate_packet(api,folder,manifest,{'run':run,'artifact':artifact},ROOT)
    if publication_path:
        linked=publication_matches(publication,manifest,allow_processing=True)
        require(linked.get('artifact_id')==artifact['id'] and linked.get('artifact_digest')==artifact['digest']
            and linked.get('attempt')==run['run_attempt']
            and publication.get('firebase_variant_manifest_sha256')==sha256(folder/'firebase-variant-manifest.json'),
            'Publication must bind the freshly authenticated original archive')
        folder=args.output/'variant';shutil.copytree(original,folder)
        if publication.get('state')=='completed':
            manifest=project_delivery(folder,publication_path,origin)
        origin['publication_origin']=publication_origin
    marker=json.loads((folder/'public/hosting-release.json').read_text())
    if args.platform=='firebase':
        current=current_marker();status=forward(current,marker,api);origin['live_baseline']=current
    else:
        status='itch-qualified' # Butler's independent current channel is checked by its publisher.
    (args.output/'origin.json').write_text(json.dumps(origin,indent=2)+'\n')
    (args.output/'status.json').write_text(json.dumps({'status':status,'source_commit':manifest['source_commit'],
        'variant_manifest_sha256':sha256(folder/'firebase-variant-manifest.json'),
        'mutation_performed':False,'hosted_acceptance':False},indent=2)+'\n')
    with open(os.environ['GITHUB_OUTPUT'],'a') as stream:
        stream.write(f"source_sha={manifest['source_commit']}\nrelease_tag={marker['tag']}\nmanifest_sha256={sha256(folder/'firebase-variant-manifest.json')}\nalready_current={'true' if status=='already-current' else 'false'}\n")
    print('Independent common-tag Firebase origin verified; no Hosting mutation')


if __name__=='__main__':main()
