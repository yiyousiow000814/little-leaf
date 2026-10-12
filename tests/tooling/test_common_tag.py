"""Independent platform qualification fences; synthetic Git/API, no runtime."""
import copy
import hashlib
import json
from pathlib import Path
import subprocess
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
        import publish_itch
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
        for platform in [itch,fb]:self.assertEqual(trigger(platform)['workflow_run']['workflows'],['Check and build Web'])
        self.assertNotIn('Release Web to itch.io',json.dumps(fb))
        self.assertNotIn('needs',itch['jobs']['publish'])
        self.assertNotIn('needs',fb['jobs']['common'])
        self.assertEqual(trigger(deploy)['workflow_run']['workflows'],['Qualify Firebase release'])
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
        import stage_released_firebase as stage
        from qualification.artifacts import sha256
        root=Path(__file__).resolve().parents[2];reuse=folder/'reuse';web=reuse/'web';web.mkdir(parents=True)
        (web/'index.html').write_text((root/'platform/web/little_leaf_shell.html').read_text().replace('$GODOT_URL','index.js'),encoding='utf-8')
        for name,value in [('index.js',b'fixture'),('index.wasm',b'\0asmfixture'),('index.pck',b'GDPCfixture')]: (web/name).write_bytes(value)
        evidence=folder/'evidence';(evidence/'engine-evidence').mkdir(parents=True);native=evidence/'engine-evidence/summary.json'
        native.write_text(json.dumps({'source_commit':'a'*40,'status':'passed','player_save_used':False,'total_checks':1,'test_processes':1}))
        q={'source_commit':'a'*40,'source_tree':'b'*40,'version':'0.1.11-pre.aaaaaaaa','tag':'v0.1.11-pre.aaaaaaaa',
            'qualification_run_id':10,'qualification_attempt':1,'artifact_id':20,'artifact_digest':'sha256:'+'c'*64,
            'qualified_manifest_sha256':'d'*64,'mandatory_gate_success':True,'packed_startup':'passed','qualified_payload_unchanged':True}
        base={'source_commit':'a'*40,'source_tree':'b'*40,'version':q['version'],'tag':q['tag'],'workflow_run':'10',
            'packed_smoke':'passed','toolchain_verification':'checksum-pinned-official-archives','engine_checks':1,'test_processes':1,
            'test_report_sha256':sha256(native),'release_reuse':q,
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
        (flow/'firebase-fullflow.json').write_text(json.dumps(report))
        common_receipt={'schema_version':1,'status':common.STATUS,'source_commit':'a'*40,'source_tree':'b'*40,'version':q['version'],
            'release_tag':q['tag'],'common_run_id':30,'qualification':q,'web_manifest_sha256':sha256(web/'release-manifest.json'),
            'release_order':{'kind':'main-first-parent','repository':common.REPOSITORY,'anchor':'d'*40,'sequence':1,'chain_sha256':'e'*64}}
        selection={'kind':common.STATUS,'source_commit':'a'*40,'source_tree':'b'*40,'release_tag':q['tag'],'release_run_id':30,
            'qualification':q,'common':common_receipt,'common_origin':{'synthetic':True}}
        context={'workflow':firebase.WORKFLOW,'event':'workflow_run','ref':'refs/heads/main','staging_run_id':901,'staging_attempt':1,
            'coordinator_source_commit':common.git(root,'rev-parse','HEAD')}
        output=folder/'variant'
        with patch.object(stage,'source_identity'),patch.object(firebase,'common_context',return_value=context):
            stage.stage(root,reuse,selection,evidence,focused,flow,output,'901','1',common_tag=True)
        manifest=json.loads((output/'firebase-variant-manifest.json').read_text());marker=json.loads((output/'public/hosting-release.json').read_text())
        return output,manifest,marker

    def test_complete_typed_packet_preserves_runtime_without_butler_receipt(self):
        from deploy_firebase_hosting import verify_package,verify_live_package
        from qualification.artifacts import sha256
        with tempfile.TemporaryDirectory() as temporary:
            folder,manifest,marker=self.packet(Path(temporary))
            firebase.validate_packet(folder,manifest,marker)
            self.assertNotIn('publication',manifest);self.assertNotIn('manual_live_reuse',manifest)
            self.assertEqual(manifest['status'],firebase.STATUS)
            self.assertEqual(marker['release_order']['kind'],'main-first-parent')
            verify_package(folder,'a'*40,sha256(folder/'firebase-variant-manifest.json'))
            with self.assertRaises(ValueError):verify_live_package(folder,'a'*40,sha256(folder/'firebase-variant-manifest.json'))
            self.assertFalse(manifest['common_tag_reuse']['new_engine_suite_run'])
            self.assertFalse(manifest['common_tag_reuse']['new_ordinary_browser_matrix_run'])

    def test_missing_focus_compiled_failure_and_mutated_runtime_refused(self):
        for mode in ['missing-rules','failed-flow','changed-runtime','bad-marker']:
            with self.subTest(mode=mode),tempfile.TemporaryDirectory() as temporary:
                folder,manifest,marker=self.packet(Path(temporary))
                if mode=='missing-rules':(folder/'evidence/rules.log').unlink()
                if mode=='changed-runtime':(folder/'public/index.js').write_bytes(b'changed')
                if mode=='bad-marker':marker['release_order']['sequence']+=1
                if mode=='failed-flow':
                    path=folder/'evidence/firebase-fullflow.json';flow=json.loads(path.read_text());flow['passed']=False;path.write_text(json.dumps(flow))
                with self.assertRaises((ValueError,FileNotFoundError)):firebase.validate_packet(folder,manifest,marker)


if __name__=='__main__':unittest.main()
