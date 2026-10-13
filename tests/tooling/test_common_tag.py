"""Independent platform qualification fences; synthetic Git/API, no runtime."""
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import shutil
import tempfile
import unittest
from unittest.mock import Mock,patch

import yaml
from release import common_tag as common
from release import common_firebase as firebase
from qualification.reuse_main_ci import REQUIRED_JOBS


def run(number,source,branch,event='push',workflow=common.WORKFLOW):
    return {'id':number,'run_attempt':1,'head_sha':source,'head_branch':branch,'event':event,
        'path':workflow,'workflow_id':9,'status':'completed','conclusion':'success',
        'repository':{'full_name':common.REPOSITORY},'head_repository':{'full_name':common.REPOSITORY}}


class CommonTagTests(unittest.TestCase):
    def api_fixture(self):
        source='a'*40;tree='b'*40;tag='v0.1.11-pre.aaaaaaaa'
        q={'qualification_run_id':10,'qualification_attempt':1,'artifact_id':20,'artifact_digest':'sha256:'+'c'*64,
            'schema_version':1,'repository':common.REPOSITORY,'workflow':common.WORKFLOW,'qualified_manifest_sha256':'f'*64,
            'source_commit':source,'source_tree':tree,'version':tag[1:],'tag':tag,
            'mandatory_gate_success':True,'packed_startup':'passed','qualified_payload_unchanged':True}
        receipt={'schema_version':1,'status':common.STATUS,'repository':common.REPOSITORY,'workflow':common.WORKFLOW,
            'common_run_id':30,'common_attempt':1,'tag_creation_event':True,'platform_publication_required':False,
            'source_commit':source,'source_tree':tree,'release_tag':tag,'version':tag[1:],'qualification':q,
            'release_order':{'kind':'main-first-parent','repository':common.REPOSITORY,'anchor':'d'*40,'sequence':7,'chain_sha256':'e'*64}}
        rows={'actions/runs/30/attempts/1':run(30,source,tag),
            'actions/runs/10/attempts/1':run(10,source,'main'),
            'actions/workflows/ci.yml':{'id':9,'path':common.WORKFLOW,'state':'active'},
            'git/ref/tags/'+tag:{'object':{'type':'commit','sha':source}},
            'git/commits/'+source:{'tree':{'sha':tree}},'compare/'+source+'...main':{'status':'ahead'},
            'actions/artifacts/20':{'id':20,'expired':False,'digest':q['artifact_digest'],
                'name':'little-leaf-web-'+source+'-1','workflow_run':{'id':10,'head_sha':source}}}
        jobs={'actions/runs/30/attempts/1/jobs':[{'name':'common_tag','run_id':30,'run_attempt':1,'status':'completed','conclusion':'success'}],
            'actions/runs/10/attempts/1/jobs':[{'name':name,'status':'completed','conclusion':'success'} for name in REQUIRED_JOBS]}
        api=Mock();api.read.side_effect=lambda path:copy.deepcopy(rows[path]);api.pages.side_effect=lambda path,key:copy.deepcopy(jobs[path])
        return api,receipt,rows,jobs

    def test_pinned_original_attempt_accepted_without_publication(self):
        api,receipt,rows,jobs=self.api_fixture()
        common.authenticate(api,receipt,30)
        self.assertTrue(all('release-itch' not in call.args[0] for call in api.read.call_args_list))
        self.assertTrue(all('/attempts/1' in call.args[0] for call in api.read.call_args_list if call.args[0].startswith('actions/runs/')))

    def test_untrusted_or_changed_common_origin_refused(self):
        mutations=[('event','pull_request'),('path','.github/workflows/release-itch.yml'),('head_branch','main'),
            ('head_sha','f'*40),('run_attempt',2),('conclusion','failure'),('workflow_id',99)]
        for key,value in mutations:
            api,receipt,rows,jobs=self.api_fixture();rows['actions/runs/30/attempts/1'][key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):common.authenticate(api,receipt,30)
        api,receipt,rows,jobs=self.api_fixture();rows['actions/runs/30/attempts/1']['head_repository']['full_name']='attacker/fork'
        with self.assertRaises(ValueError):common.authenticate(api,receipt,30)

    def test_moved_tag_wrong_tree_missing_gate_or_expired_archive_refused(self):
        for case in ['tag','tree','job','digest','expired','wrong-main']:
            api,receipt,rows,jobs=self.api_fixture();source=receipt['source_commit']
            if case=='tag':rows['git/ref/tags/'+receipt['release_tag']]['object']['sha']='f'*40
            if case=='tree':rows['git/commits/'+source]['tree']['sha']='f'*40
            if case=='job':jobs['actions/runs/10/attempts/1/jobs'].pop()
            if case=='digest':rows['actions/artifacts/20']['digest']='sha256:'+'f'*64
            if case=='expired':rows['actions/artifacts/20']['expired']=True
            if case=='wrong-main':rows['actions/runs/10/attempts/1']['head_branch']='feature'
            with self.subTest(case=case),self.assertRaises(ValueError):common.authenticate(api,receipt,30)

    def test_platform_job_cannot_join_common_success_predicate(self):
        api,receipt,rows,jobs=self.api_fixture()
        jobs['actions/runs/30/attempts/1/jobs'].append({'name':'itch-publish','status':'completed','conclusion':'success'})
        with self.assertRaises(ValueError):common.authenticate(api,receipt,30)

    def test_order_rejects_boolean_zero_unknown_domains(self):
        _,receipt,_,_=self.api_fixture();order=receipt['release_order']
        self.assertTrue(common.valid_order(order))
        for patch_value in [{'sequence':True},{'sequence':0},{'sequence':9007199254740992},
                            {'repository':'fork'},{'anchor':'bad'},{'kind':'itch-channel'},{'unknown':'secret'}]:
            with self.subTest(patch=patch_value):self.assertFalse(common.valid_order({**order,**patch_value}))

    def test_first_parent_chain_stable_after_main_advance_and_rejects_side_branch(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary)
            command=lambda *args:subprocess.check_output(['git','-C',str(root),*args],stderr=subprocess.DEVNULL,text=True).strip()
            command('init','-q');command('config','user.name','Synthetic');command('config','user.email','synthetic@example.invalid')
            for number in range(2):
                (root/'fixture').write_text(str(number));command('add','fixture');command('commit','-qm','synthetic')
            source=command('rev-parse','HEAD');before=common.chronology(root,source,'HEAD')
            command('checkout','-qb','side');(root/'side').write_text('x');command('add','side');command('commit','-qm','side');side=command('rev-parse','HEAD')
            command('checkout','-q','-');(root/'main').write_text('x');command('add','main');command('commit','-qm','main');command('merge','--no-ff','-qm','merge','side')
            self.assertEqual(common.chronology(root,source,'HEAD'),before)
            self.assertEqual(before['sequence'],2)
            with self.assertRaises(ValueError):common.chronology(root,side,'HEAD')


class PlatformTests(unittest.TestCase):
    def marker(self,source='a',version='0.1.11-pre.aaaaaaaa'):
        return {'schema_version':1,'source_commit':source*40,'version':version,'tag':'v'+version}

    def test_forward_ancestry_and_idempotency_without_other_platform(self):
        api=Mock();api.read.return_value={'status':'ahead'}
        old=self.marker();new=self.marker('b','0.1.11-pre.bbbbbbbb')
        self.assertEqual(firebase.forward(old,new,api),'forward-qualified')
        self.assertEqual(firebase.forward(new,new,api),'already-current')
        self.assertEqual(api.read.call_count,1)
        self.assertNotIn('itch',api.read.call_args.args[0])

    def test_rollback_unrelated_unknown_or_uncertain_equal_source_refused(self):
        for state in ['behind','diverged','identical']:
            api=Mock();api.read.return_value={'status':state}
            with self.subTest(state=state),self.assertRaises(ValueError):firebase.forward(self.marker(),self.marker('b','0.1.11-pre.bbbbbbbb'),api)
        api=Mock()
        with self.assertRaises(ValueError):firebase.forward(self.marker('a','0.1.11'),self.marker('b','0.1.11-pre.bbbbbbbb'),api)
        with self.assertRaises(ValueError):firebase.forward(self.marker(),{**self.marker(),'unknown':'changed'},api)
        with self.assertRaises(ValueError):firebase.forward({'schema_version':1},self.marker(),api)
        api.read.assert_not_called()

    def test_itch_common_rejects_higher_version_on_older_source(self):
        from release import publish_itch
        from tests.tooling.test_release import status
        from types import SimpleNamespace
        old=status('0.1.10d')
        with patch.object(publish_itch.subprocess,'check_output',return_value='a'*40),patch.object(publish_itch.subprocess,'run',return_value=SimpleNamespace(returncode=1)):
            with self.assertRaises(ValueError):publish_itch.check_common_previous(old,'0.2.0','b'*40)
        with patch.object(publish_itch.subprocess,'check_output',return_value='a'*40),patch.object(publish_itch.subprocess,'run',return_value=SimpleNamespace(returncode=0)):
            self.assertEqual(publish_itch.check_common_previous(old,'0.2.0','b'*40),old['channels'][0]['head']['id'])

    def test_common_workflow_and_platform_credentials_stay_separate(self):
        root=Path(__file__).resolve().parents[2]
        workflow=lambda name:yaml.safe_load((root/'.github/workflows'/name).read_text())
        ci=workflow('ci.yml');itch=workflow('release-itch.yml');fb=workflow('release-firebase.yml');deploy=workflow('deploy-firebase.yml')
        trigger=lambda value:value.get('on',value.get(True))
        self.assertIn('tags',trigger(ci)['push']);self.assertIn("github.ref_type != 'tag'",ci['jobs']['web']['if'])
        self.assertNotIn('secrets',json.dumps(ci));self.assertNotIn('id-token',json.dumps(ci))
        self.assertEqual(trigger(fb)['workflow_run']['workflows'],['Check and build Web'])
        self.assertEqual(trigger(itch)['workflow_run']['workflows'],['Qualify Firebase release'])
        self.assertEqual(trigger(itch)['workflow_dispatch']['inputs']['qualified_run_id']['default'],'')
        self.assertIn("inputs.qualified_run_id == ''",itch['jobs']['diagnose_status']['if'])
        self.assertIn("inputs.qualified_run_id != ''",itch['jobs']['publish']['if'])
        self.assertNotIn('Release Web to itch.io',json.dumps(fb))
        self.assertNotIn('needs',itch['jobs']['publish'])
        self.assertNotIn('needs',fb['jobs']['common'])
        self.assertIn('common_firebase.py',json.dumps(itch))
        self.assertIn('--firebase-variant',json.dumps(itch))
        self.assertNotIn('common-release/web',json.dumps(itch))
        self.assertEqual(trigger(deploy)['workflow_run']['workflows'],['Release Web to itch.io'])
        self.assertIn("startsWith(github.event.workflow_run.display_title, 'Retry qualified itch ')",deploy['jobs']['common-tag']['if'])
        self.assertIn('--itch-run',json.dumps(deploy['jobs']['common-tag']))
        steps=deploy['jobs']['common-tag']['steps'];index=next(i for i,s in enumerate(steps) if 'google-github-actions/auth@' in s.get('uses',''))
        self.assertTrue(any('common_firebase.py' in s.get('run','') for s in steps[:index]))
        self.assertTrue(any('--verify-only' in s.get('run','') for s in steps[:index]))
        auth=steps[index]['with'];self.assertEqual(auth['access_token_lifetime'],'900s')
        self.assertEqual(auth['access_token_scopes'],'https://www.googleapis.com/auth/firebase.hosting')
        self.assertFalse(auth['create_credentials_file']);self.assertFalse(auth['export_environment_variables'])

    def test_updater_keeps_order_authorities_separate_and_hashes_opaque(self):
        root=Path(__file__).resolve().parents[2]
        script=r'''
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync(process.argv[1],'utf8');
const order=sequence=>({kind:'main-first-parent',repository:'yiyousiow000814/little-leaf',anchor:'a'.repeat(40),sequence,chain_sha256:'b'.repeat(64)});
const marker=(commit,release_order)=>({schema_version:1,source_commit:commit.repeat(40),version:'0.1.11-pre.'+commit.repeat(8),release_order});
async function observe(current,next){
 const window={setTimeout,clearTimeout};vm.runInNewContext(source,{window});
 const updater=window.LittleLeafUpdates.create({currentRelease:current,fetch:async()=>({ok:true,json:async()=>next}),
  checkUpdateReady:async()=>({}),canReloadUpdate:()=>true,setInterval:()=>1,clearInterval:()=>{}});
 updater.start(current.version);await updater.poll();const available=JSON.parse(updater.snapshot()).available;updater.close();return available;
}
(async()=>{
 assert.equal(await observe(marker('f',order(10)),marker('0',order(11))),true,'source ordinal, never lexical/numeric SHA');
 assert.equal(await observe(marker('a',order(10)),marker('b',order(9))),false);
 assert.equal(await observe(marker('a',order(10)),marker('b',{...order(11),anchor:'c'.repeat(40)})),false);
 const legacy={target:'siowyiyou/little-leaf:html5',channel_version:999};
 assert.equal(await observe(marker('a',legacy),marker('b',order(1000))),false,'no Butler/common cross-ordering');
 assert.equal(await observe(marker('a',order(10)),marker('b',legacy)),false);
 assert.equal(await observe(marker('a',{...order(10),sequence:true}),marker('b',order(11))),false);
})().catch(error=>{console.error(error);process.exitCode=1;});
'''
        subprocess.run(['node','-e',script,str(root/'platform/web/little_leaf_update.js')],check=True,capture_output=True,text=True,timeout=30)

    def packet(self,folder):
        from release import stage_released_firebase as stage
        from qualification.artifacts import sha256
        root=Path(__file__).resolve().parents[2];reuse=folder/'reuse';web=reuse/'web';web.mkdir(parents=True)
        from build.build_itch_entry import ordinary_entry_html
        shell=(root/'platform/web/little_leaf_shell.html').read_text().replace('$GODOT_URL','index.js')
        (web/'index.html').write_text(ordinary_entry_html(shell),encoding='utf-8')
        for name,value in [('index.js',b'fixture'),('index.wasm',b'\0asmfixture'),('index.pck',b'GDPCfixture')]: (web/name).write_bytes(value)
        evidence=folder/'evidence';(evidence/'engine-evidence').mkdir(parents=True);native=evidence/'engine-evidence/summary.json'
        native.write_text(json.dumps({'source_commit':'a'*40,'status':'passed','player_save_used':False,'total_checks':1,'test_processes':1}))
        q={'source_commit':'a'*40,'source_tree':'b'*40,'version':'0.1.11-pre.aaaaaaaa','tag':'v0.1.11-pre.aaaaaaaa',
            'qualification_run_id':10,'qualification_attempt':1,'artifact_id':20,'artifact_digest':'sha256:'+'c'*64,
            'qualified_manifest_sha256':'d'*64,'mandatory_gate_success':True,'packed_startup':'passed','qualified_payload_unchanged':True}
        base={'source_commit':'a'*40,'source_tree':'b'*40,'version':q['version'],'tag':q['tag'],'workflow_run':'10',
            'packed_smoke':'passed','toolchain_verification':'checksum-pinned-official-archives','engine_checks':1,'test_processes':1,
            'test_report_sha256':sha256(native),'release_reuse':q,
            'production_sha256':{'web/little_leaf_firebase_boot.mjs':sha256(root/'platform/web/little_leaf_firebase_boot.mjs')},
            'files':{p.name:{'sha256':sha256(p),'bytes':p.stat().st_size} for p in web.iterdir()}}
        (web/'release-manifest.json').write_text(json.dumps(base));(reuse/'qualification.json').write_text(json.dumps(q))
        (evidence/'reuse-inputs.json').write_text(json.dumps({'qualification':q,'original_native_summary_sha256':sha256(native),'new_engine_suite_run':False}))
        original=dict(base);original.pop('release_reuse');original['tag']=''
        (evidence/'web-build/evidence').mkdir(parents=True)
        (evidence/'web-build/evidence/export-report.json').write_text(json.dumps({'manifest':original,'stages':[{'exit_code':0}]}))
        for name,(relative,key,expected) in stage.build_firebase.BROWSER_GATES.items():
            if name=='firebase-fullflow':continue
            p=evidence/'web-build/evidence'/relative;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps({key:expected}))
        focused=folder/'focused';focused.mkdir()
        from tests.tooling.test_stage_released_firebase import ReleasedStagingTests
        ReleasedStagingTests().fixtures(focused)
        # Existing fixture helper uses run10; the current platform attempt is901.
        for p in focused.glob('*.json'):
            data=json.loads(p.read_text());data['workflow_run']='901';p.write_text(json.dumps(data))
        flow=folder/'flow';flow.mkdir()
        report={'passed':True,'source_commit':'a'*40,'source_tree':'b'*40,'export_manifest_sha256':sha256(web/'release-manifest.json'),
            'native_report_sha256':sha256(native),'real_compiled_ui':True,'real_firestore_rules':True,'synthetic_only':True,
            'browser_sandbox':True,'real_google_sign_in':False,'diagnostic_only':False,'checks':['synthetic'],
            'source_sha256':{name:sha256(stage.source_path(root,name)) for name in stage.FULLFLOW_SOURCES}}
        common_receipt={'schema_version':1,'status':common.STATUS,'source_commit':'a'*40,'source_tree':'b'*40,'version':q['version'],
            'release_tag':q['tag'],'common_run_id':30,'qualification':q,'web_manifest_sha256':sha256(web/'release-manifest.json'),
            'release_order':{'kind':'main-first-parent','repository':common.REPOSITORY,'anchor':'d'*40,'sequence':1,'chain_sha256':'e'*64}}
        selection={'kind':common.STATUS,'source_commit':'a'*40,'source_tree':'b'*40,'release_tag':q['tag'],'release_run_id':30,
            'qualification':q,'common':common_receipt,'common_origin':{'synthetic':True}}
        context={'workflow':firebase.WORKFLOW,'event':'workflow_run','ref':'refs/heads/main','staging_run_id':901,'staging_attempt':1,
            'coordinator_source_commit':common.git(root,'rev-parse','HEAD')}
        output=folder/'variant'
        with patch.object(stage,'source_identity'),patch.object(firebase,'common_context',return_value=context):
            prepared=folder/'same-page'
            stage.prepare_common_surface(root,reuse,selection,prepared)
            report.update(itch_test_entry=True,itch_ancestor_origins=firebase.ANCESTORS,
                itch_entry_sha256=sha256(prepared/'public/itch/index.html'))
            (flow/'firebase-fullflow.json').write_text(json.dumps(report))
            stage.stage(root,reuse,selection,evidence,focused,flow,output,'901','1',common_tag=True,itch_variant=prepared)
        manifest=json.loads((output/'firebase-variant-manifest.json').read_text());marker=json.loads((output/'public/hosting-release.json').read_text())
        return output,manifest,marker

    def test_incompatible_producer_packet_never_emits_upload_handoff(self):
        import os
        from release import firebase_release_event as event
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / 'github-output'
            with patch.dict(os.environ, {'GITHUB_OUTPUT': str(output)}), \
                    patch.object(event, 'check_firebase_packet_budget', side_effect=ValueError('over budget')):
                with self.assertRaisesRegex(ValueError, 'over budget'):
                    self.packet(Path(temporary))
            self.assertFalse(output.exists())

    def test_complete_typed_packet_preserves_runtime_without_butler_receipt(self):
        from release.deploy_firebase_hosting import verify_package,verify_live_package
        from qualification.artifacts import sha256
        from release import firebase_release_event as event
        with tempfile.TemporaryDirectory() as temporary, \
                patch.object(event,'check_firebase_packet_budget',wraps=event.check_firebase_packet_budget) as budget:
            folder,manifest,marker=self.packet(Path(temporary))
            budget.assert_called_once_with(folder)
            firebase.validate_packet(folder,manifest,marker)
            self.assertNotIn('publication',manifest);self.assertNotIn('manual_live_reuse',manifest)
            self.assertEqual(manifest['status'],firebase.STATUS)
            self.assertEqual(marker['release_order']['kind'],'main-first-parent')
            verify_package(folder,'a'*40,sha256(folder/'firebase-variant-manifest.json'))
            with self.assertRaises(ValueError):verify_live_package(folder,'a'*40,sha256(folder/'firebase-variant-manifest.json'))
            self.assertFalse(manifest['common_tag_reuse']['new_engine_suite_run'])
            self.assertFalse(manifest['common_tag_reuse']['new_ordinary_browser_matrix_run'])

    def test_missing_focus_compiled_failure_and_mutated_runtime_refused(self):
        for mode in ['missing-rules','failed-flow','changed-runtime','bad-marker','changed-embedded','changed-wrapper','missing-same-page-flow','bad-ancestors']:
            with self.subTest(mode=mode),tempfile.TemporaryDirectory() as temporary:
                folder,manifest,marker=self.packet(Path(temporary))
                if mode=='missing-rules':(folder/'evidence/rules.log').unlink()
                if mode=='changed-runtime':(folder/'public/index.js').write_bytes(b'changed')
                if mode=='changed-embedded':(folder/'public/itch/index.js').write_bytes(b'changed')
                if mode=='changed-wrapper':(folder/'itch-wrapper/index.html').write_text('ordinary Root outbound')
                if mode=='bad-marker':marker['release_order']['sequence']+=1
                if mode=='failed-flow':
                    path=folder/'evidence/firebase-fullflow.json';flow=json.loads(path.read_text());flow['passed']=False;path.write_text(json.dumps(flow))
                if mode in ['missing-same-page-flow','bad-ancestors']:
                    path=folder/'evidence/firebase-fullflow.json';flow=json.loads(path.read_text())
                    if mode=='missing-same-page-flow':flow.pop('itch_test_entry')
                    else:flow['itch_ancestor_origins']=['https://other.example']
                    path.write_text(json.dumps(flow))
                with self.assertRaises((ValueError,FileNotFoundError)):firebase.validate_packet(folder,manifest,marker)

    def test_publisher_requires_separate_ordinary_entry_and_authenticated_origin(self):
        from release import publish_itch
        with tempfile.TemporaryDirectory() as temporary:
            folder,manifest,marker=self.packet(Path(temporary))
            origin={'fixture':'authenticated by caller'}
            with patch.object(firebase,'require_origin') as fence:
                base,common_receipt,digest=publish_itch.verify_qualified_ordinary_entry(
                    folder/'itch-ordinary',folder,origin,marker['tag'],marker['source_commit'])
                fence.assert_called_once_with(folder,manifest,origin)
                self.assertEqual(base,manifest['base_web_manifest'])
                self.assertEqual(common_receipt,manifest['common_tag_reuse']['common'])
                self.assertEqual(len(digest),64)
                with self.assertRaises(ValueError):publish_itch.verify_qualified_ordinary_entry(
                    folder/'public',folder,origin,marker['tag'],marker['source_commit'])
                with self.assertRaises(ValueError):publish_itch.verify_qualified_ordinary_entry(
                    folder/'itch-wrapper',folder,origin,marker['tag'],marker['source_commit'])
            with self.assertRaises(ValueError):publish_itch.verify_qualified_ordinary_entry(
                folder/'itch-ordinary',folder,{},marker['tag'],marker['source_commit'])

    def test_staging_refuses_candidate_changed_since_compiled_flow(self):
        from release import stage_released_firebase as stage
        with tempfile.TemporaryDirectory() as temporary:
            folder,manifest,marker=self.packet(Path(temporary))
            candidate=Path(temporary)/'same-page'
            selection={'source_commit':'a'*40,'source_tree':'b'*40}
            flow=json.loads((folder/'evidence/firebase-fullflow.json').read_text())
            stage.validate_common_surface(candidate,selection,manifest['base_web_manifest'],flow)
            (candidate/'itch-wrapper/index.html').write_text('unqualified entry')
            with self.assertRaisesRegex(ValueError,'inventory changed'):
                stage.validate_common_surface(candidate,selection,manifest['base_web_manifest'],flow)

    def publication(self,folder,manifest):
        proof=manifest['common_tag_reuse'];common_receipt=proof['common'];context=proof['context']
        publication={'target':'siowyiyou/little-leaf:html5','state':'completed','itch_build_id':44,'itch_channel_version':17,
            'delivery_surface':'qualified-root-new-tab-entry','source_commit':common_receipt['source_commit'],
            'version':common_receipt['version'],'tag':common_receipt['release_tag'],
            'common_qualification':common_receipt,'qualification':proof['qualification'],
            'release_manifest_sha256':common_receipt['web_manifest_sha256'],
            'ordinary_itch_sha256':proof['ordinary_itch']['files_sha256'],
            'firebase_variant_manifest_sha256':firebase.sha256(folder/'firebase-variant-manifest.json'),
            'same_page_staging_origin':{'run_id':context['staging_run_id'],'attempt':context['staging_attempt'],
                'coordinator_source_commit':context['coordinator_source_commit'],'artifact_id':701,'artifact_digest':'sha256:'+'f'*64}}
        origin={'common_authenticated':True,'common_proof_sha256':firebase.sha256(folder/'evidence/common-tag-reuse.json'),
            'run':run(901,context['coordinator_source_commit'],'main','workflow_run',firebase.WORKFLOW),
            'artifact':{'id':701,'digest':'sha256:'+'f'*64,'expired':False,
                'workflow_run':{'id':901,'head_sha':context['coordinator_source_commit']}}}
        path=folder.parent/'publication.json';path.write_text(json.dumps(publication)+'\n')
        return path,publication,origin

    def test_completed_wrapper_order_projection_preserves_original_gate_and_runtime(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder,original,before=self.packet(Path(temporary))
            path,publication,origin=self.publication(folder,original)
            after=firebase.project_delivery(folder,path,origin)
            restored=firebase.validate_delivery_projection(folder,after)
            self.assertEqual(restored,original)
            marker=json.loads((folder/'public/hosting-release.json').read_bytes())
            self.assertEqual(marker['release_order'],{**before['release_order'],'target':publication['target'],'channel_version':17})
            firebase.validate_packet(folder,after,marker)
            firebase.require_origin(folder,after,origin)
            origin['publication_authenticated']=False
            with self.assertRaisesRegex(ValueError,'completed wrapper'):
                firebase.require_origin(folder,after,origin)

    def test_projection_refuses_fake_order_origin_source_or_other_byte_changes(self):
        for mode in ['zero-order','bool-order','wrong-source','other-artifact','uncompleted','runtime','marker','original-evidence']:
            with self.subTest(mode=mode),tempfile.TemporaryDirectory() as temporary:
                folder,original,before=self.packet(Path(temporary));path,publication,origin=self.publication(folder,original)
                if mode in ['zero-order','bool-order','wrong-source','other-artifact','uncompleted']:
                    if mode=='zero-order':publication['itch_channel_version']=0
                    if mode=='bool-order':publication['itch_channel_version']=True
                    if mode=='wrong-source':publication['source_commit']='f'*40
                    if mode=='other-artifact':publication['same_page_staging_origin']['artifact_id']=702
                    if mode=='uncompleted':publication['state']='processing'
                    path.write_text(json.dumps(publication))
                    with self.assertRaises(ValueError):firebase.project_delivery(folder,path,origin)
                    self.assertFalse((folder/firebase.ORIGINAL).exists())
                else:
                    after=firebase.project_delivery(folder,path,origin)
                    if mode=='runtime':(folder/'public/itch/index.js').write_bytes(b'changed')
                    if mode=='marker':(folder/'public/hosting-release.json').write_text('{}')
                    if mode=='original-evidence':(folder/(firebase.ORIGINAL+'public/index.html')).write_text('changed')
                    with self.assertRaises(ValueError):firebase.validate_packet(folder,after,before)

    def test_publication_consumer_requires_successful_exact_workflow_attempt_and_archive(self):
        published=run(990,'c'*40,'main','workflow_run','.github/workflows/release-itch.yml')
        artifact={'id':700,'name':'little-leaf-itch-publication-'+'a'*40+'-1','expired':False,
            'digest':'sha256:'+'d'*64,'workflow_run':{'id':990,'head_sha':'c'*40}}
        job={'name':'publish','run_id':990,'run_attempt':1,'status':'completed','conclusion':'success'}
        receipt={'source_commit':'a'*40,'workflow_run':'990','workflow_attempt':'1',
                 'same_page_staging_origin':{'run_id':901}}
        def extracted(api,value,output):
            output.mkdir();(output/'receipt.json').write_text(json.dumps(receipt))
        for mode in ['valid','named-retry','manual','retry-other-run','retry-malformed-title','retry-second-attempt',
                     'wrong-repository','failed-publish','stale-job-attempt','expired','wrong-receipt-attempt']:
            selected=copy.deepcopy(published);selected_job=dict(job);selected_artifact=copy.deepcopy(artifact)
            receipt['workflow_attempt']='1'
            if mode=='manual':selected['event']='workflow_dispatch'
            if mode.startswith('retry-') or mode=='named-retry':
                selected.update(event='workflow_dispatch',display_title='Retry qualified itch 901')
                if mode=='retry-other-run':selected['display_title']='Retry qualified itch 902'
                if mode=='retry-malformed-title':selected['display_title']='Retry qualified itch 0901'
                if mode=='retry-second-attempt':selected['run_attempt']=2
            if mode=='wrong-repository':selected['repository']={'full_name':'other/repository'}
            if mode=='failed-publish':selected_job['conclusion']='failure'
            if mode=='stale-job-attempt':selected_job['run_attempt']=2
            if mode=='expired':selected_artifact['expired']=True
            if mode=='wrong-receipt-attempt':receipt['workflow_attempt']='2'
            api=Mock();api.read.side_effect=lambda name:selected if name=='actions/runs/990' else {
                'state':'active','id':9,'path':'.github/workflows/release-itch.yml'}
            api.pages.side_effect=lambda name,key:[selected_job] if key=='jobs' else [selected_artifact]
            with self.subTest(mode=mode),tempfile.TemporaryDirectory() as temporary,patch.object(firebase,'download',side_effect=extracted):
                if mode in {'valid','named-retry'}:
                    path,origin=firebase.consume_publication(api,990,Path(temporary)/'publication')
                    self.assertEqual(origin['artifact'],artifact);self.assertEqual(json.loads(path.read_bytes()),receipt)
                else:
                    with self.assertRaises(ValueError):firebase.consume_publication(api,990,Path(temporary)/'publication')

    def test_canonical_attempt_drift_is_refused_before_artifact_access(self):
        import os,sys
        latest=run(901,'a'*40,'main','workflow_run',firebase.WORKFLOW)
        for field,value in [('id',902),('run_attempt',2),('head_sha','b'*40),
                            ('head_branch','other'),('conclusion','failure'),
                            ('repository',{'full_name':'fork/repository'})]:
            selected={**latest,field:value};api=Mock()
            api.read.side_effect=lambda path:latest if path=='actions/runs/901' else selected
            with self.subTest(field=field),tempfile.TemporaryDirectory() as temporary, \
                    patch.object(firebase,'GitHub',return_value=api), \
                    patch.dict(os.environ,{'GH_TOKEN':'synthetic'}), \
                    patch.object(sys,'argv',['common_firebase','--run','901','--platform','itch','--output',temporary]):
                with self.assertRaises(ValueError):firebase.main()
                api.pages.assert_not_called()

    def test_itch_run_cli_enumerates_selected_firebase_run_and_projects_real_packet(self):
        import os,sys
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);fixture=root/'fixture';fixture.mkdir()
            folder,manifest,marker=self.packet(fixture)
            receipt_path,receipt,origin=self.publication(folder,manifest)
            receipt.update(workflow_run='990',workflow_attempt='1');receipt_path.write_text(json.dumps(receipt))
            publication_run=run(990,'c'*40,'main','workflow_run','.github/workflows/release-itch.yml')
            publication_artifact={'id':700,'name':'little-leaf-itch-publication-'+'a'*40+'-1','expired':False,
                'digest':'sha256:'+'d'*64,'workflow_run':{'id':990,'head_sha':'c'*40}}
            selected_artifact={**origin['artifact'],'name':'little-leaf-firebase-'+'a'*40+'-1'}
            api=Mock();enumerated=[]
            def read(name):
                if name=='actions/runs/990':return publication_run
                if name=='actions/runs/901':
                    return {**origin['run'],'jobs_url':'https://api.github.com/repos/'+common.REPOSITORY+'/actions/runs/901/jobs',
                            'logs_url':'https://api.github.com/repos/'+common.REPOSITORY+'/actions/runs/901/logs'}
                if name=='actions/runs/901/attempts/1':
                    return {**origin['run'],'jobs_url':'https://api.github.com/repos/'+common.REPOSITORY+'/actions/runs/901/attempts/1/jobs',
                            'logs_url':'https://api.github.com/repos/'+common.REPOSITORY+'/actions/runs/901/attempts/1/logs'}
                if name=='actions/workflows/release-itch.yml':return {'id':9,'state':'active','path':'.github/workflows/release-itch.yml'}
                if name.startswith('compare/'):return {'status':'ahead'}
                raise AssertionError('Unexpected CLI endpoint: '+name)
            def pages(name,key):
                if name=='actions/runs/990/attempts/1/jobs':return [{'name':'publish','run_id':990,'run_attempt':1,'status':'completed','conclusion':'success'}]
                if key=='artifacts':
                    enumerated.append(name)
                    if name=='actions/runs/990/artifacts':return [publication_artifact]
                    if name=='actions/runs/901/artifacts':return [selected_artifact]
                raise AssertionError('Wrong selected artifact endpoint: '+name)
            def downloaded(unused,artifact,output):
                if artifact['id']==700:
                    output.mkdir(parents=True);(output/'receipt.json').write_bytes(receipt_path.read_bytes())
                elif artifact['id']==701:shutil.copytree(folder,output)
                else:raise AssertionError('Wrong artifact downloaded')
            def authenticated(unused,packet,data,selected,unused_root):
                firebase.validate_packet(packet,data,json.loads((packet/'public/hosting-release.json').read_bytes()))
                self.assertEqual(selected['run']['id'],901);self.assertEqual(selected['artifact'],selected_artifact)
                self.assertEqual(selected['run'],read('actions/runs/901/attempts/1'))
                return {**selected,'common_authenticated':True,'common_proof_sha256':firebase.sha256(packet/'evidence/common-tag-reuse.json')}
            api.read.side_effect=read;api.pages.side_effect=pages;output=root/'result'
            baseline={'schema_version':1,'source_commit':'9'*40,'version':'0.1.11-pre.99999999','tag':'v0.1.11-pre.99999999'}
            with patch.object(sys,'argv',['common_firebase.py','--itch-run','990','--output',str(output)]),\
                patch.dict(os.environ,{'GITHUB_OUTPUT':str(root/'github-output')}),\
                patch.object(firebase,'GitHub',return_value=api),patch.object(firebase,'download',side_effect=downloaded),\
                patch.object(firebase,'authenticate_packet',side_effect=authenticated),patch.object(firebase,'current_marker',return_value=baseline):
                firebase.main()
            self.assertNotIn('actions/runs/None/artifacts',enumerated)
            self.assertIn('actions/runs/901/artifacts',enumerated)
            projected=json.loads((output/'variant/firebase-variant-manifest.json').read_bytes())
            projected_origin=json.loads((output/'origin.json').read_bytes())
            firebase.require_origin(output/'variant',projected,projected_origin)
            self.assertEqual(firebase.validate_delivery_projection(output/'variant',projected),manifest)
            self.assertEqual((output/'variant-original/firebase-variant-manifest.json').read_bytes(),(folder/'firebase-variant-manifest.json').read_bytes())

    def test_selected_ordinary_entry_keeps_source_bytes_root_new_tab_and_separate_same_page_proof(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder,manifest,marker=self.packet(Path(temporary));proof=manifest['common_tag_reuse']
            ordinary=firebase.validate_ordinary_itch(folder,manifest,proof)
            for name in ordinary['files_sha256']:
                self.assertEqual((folder/'itch-ordinary'/name).read_bytes(),(Path(temporary)/'reuse/web'/name).read_bytes())
            html=(folder/'itch-ordinary/index.html').read_text(encoding='utf-8')
            self.assertIn('href="https://little-leaf-41e5d.firebaseapp.com/" target="_blank"',html)
            self.assertNotIn('id="itch-account"',html)
            self.assertIn('id="itch-account"',(folder/'itch-wrapper/index.html').read_text(encoding='utf-8'))
            self.assertNotEqual(ordinary['files_sha256']['index.html'],proof['same_page']['wrapper_sha256']['index.html'])
            self.assertTrue(json.loads((folder/'evidence/firebase-fullflow.json').read_bytes())['itch_test_entry'])
            workflow=(Path(__file__).resolve().parents[2]/'.github/workflows/release-itch.yml').read_text()
            self.assertIn('--web "$RUNNER_TEMP/common-firebase/variant/itch-ordinary"',workflow)
            self.assertNotIn('--web "$RUNNER_TEMP/common-firebase/variant/itch-wrapper"',workflow)

    def test_ordinary_member_or_same_page_receipt_alias_is_refused(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder,manifest,marker=self.packet(Path(temporary));path,receipt,origin=self.publication(folder,manifest)
            receipt['delivery_surface']='qualified-same-page-wrapper'
            with self.assertRaises(ValueError):firebase.publication_matches(receipt,manifest)
            (folder/'itch-ordinary/index.html').write_bytes((folder/'itch-wrapper/index.html').read_bytes())
            with self.assertRaises(ValueError):firebase.validate_packet(folder,manifest,marker)


if __name__=='__main__':unittest.main()
