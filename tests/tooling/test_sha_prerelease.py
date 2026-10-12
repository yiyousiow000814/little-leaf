"""Exact-source prerelease tests: no network, account, save or publication."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from types import SimpleNamespace

from qualification import artifacts
from build import build_firebase
from release import publish_itch
from release.release_metadata import version, projected_metadata, release_key
from tests.tooling import test_github_release_workflow as release_workflow
from tests.tooling.test_release import status


class ShaPrereleaseTests(unittest.TestCase):
    def test_fullflow_actual_injection_binds_loaded_identity_before_updater(self):
        root=Path(__file__).resolve().parents[2]
        script=r'''
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const root=process.argv[1],fixture=fs.readFileSync(path.join(root,'platform/firebase/fullflow.test.mjs'),'utf8');
const loaded=fixture.match(/^const loadedRelease=.*;$/m),mutable=fixture.match(/^let release=\{\.\.\.loadedRelease\};$/m);
assert(loaded&&mutable,'fixture must separate loaded identity from mutable endpoint');
const context=vm.createContext({manifest:{version:'0.1.11-pre.aaaaaaaa',source_commit:'a'.repeat(40)},config:{projectId:'synthetic'},itchVariant:null});
vm.runInContext(loaded[0]+'\n'+mutable[0]+"\nrelease.version='99.0.0';",context);
const expression=fixture.match(/^const injection=(.*);$/m);assert(expression,'actual fixture injection required');
const injection=vm.runInContext(expression[1],context);
const assignment=injection.match(/<script>(window\.__littleLeafRelease=.*?;)(?=window\.__littleLeafFirebaseReady)/);
assert(assignment,'loaded marker must be emitted before boot');
const page={};vm.runInNewContext(assignment[1],{window:page});
assert.equal(JSON.stringify(page.__littleLeafRelease),JSON.stringify(vm.runInContext('loadedRelease',context)));
assert.equal(page.__littleLeafRelease.version,'0.1.11-pre.aaaaaaaa','mutable endpoint must not redefine loaded page');
const updateSource=fs.readFileSync(path.join(root,'platform/web/little_leaf_update.js'),'utf8');
async function observe(marker){
 const window={setTimeout,clearTimeout};vm.runInNewContext(updateSource,{window});let fetches=0;
 const updater=window.LittleLeafUpdates.create({currentRelease:marker,
  fetch:async()=>{fetches++;return{ok:true,json:async()=>({schema_version:1,version:'9.0.0',source_commit:'b'.repeat(40)})};},
  checkUpdateReady:async()=>({}),canReloadUpdate:()=>true,setInterval:()=>1,clearInterval:()=>{}});
 updater.start('0.1.11-pre.aaaaaaaa');await updater.poll();const state=JSON.parse(updater.snapshot());updater.close();
 return{fetches,state};
}
(async()=>{const missing=await observe(undefined);assert.equal(missing.fetches,0);assert.equal(missing.state.available,false);
const bound=await observe(page.__littleLeafRelease);assert.equal(bound.fetches,1);assert.equal(bound.state.available,true);assert.equal(bound.state.version,'9.0.0');})().catch(e=>{console.error(e);process.exitCode=1;});
'''
        subprocess.run(['node','-e',script,str(root)],capture_output=True,text=True,check=True,timeout=30)

    def metadata(self, root):
        (root/'data').mkdir()
        (root/'project.godot').write_text('config/version="0.1.11-pre"\n')
        (root/'data/release_notes.json').write_text(json.dumps({'schema_version':1,
            'version':'0.1.11-pre','prerelease':True,'status':'released','date':'2000-01-01',
            'new':[],'fixed':['Camera repair.']}))

    def test_source_projection_and_numeric_hash_are_exact(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);self.metadata(root)
            original=(root/'project.godot').read_bytes()
            for sha in ['a'*40,'01234567'+'a'*32,'12345678'+'b'*32]:
                value='0.1.11-pre.'+sha[:8]
                self.assertEqual(version(root,'v'+value,source_commit=sha),value)
                projected=projected_metadata(root,sha)
                self.assertIn(value.encode(),projected['project.godot'])
                self.assertEqual(json.loads(projected['data/release_notes.json'])['version'],value)
                self.assertEqual((root/'project.godot').read_bytes(),original)
                with self.assertRaises(ValueError):version(root,'v0.1.11-pre.deadbeef',source_commit=sha)
                with self.assertRaises(ValueError):release_key(value)
            notes=json.loads((root/'data/release_notes.json').read_text());notes['prerelease']=False
            (root/'data/release_notes.json').write_text(json.dumps(notes))
            with self.assertRaises(ValueError):version(root,source_commit='a'*40)

    def test_export_projection_cannot_hide_other_mutations(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)/'source';root.mkdir();self.metadata(root)
            build=Path(d)/'build';(build/'project/data').mkdir(parents=True);(build/'web').mkdir()
            sha='a'*40;projected=projected_metadata(root,sha)
            hashes={}
            for name,content in projected.items():
                hashes[name]=hashlib.sha256((root/name).read_bytes()).hexdigest()
                (build/'project'/name).write_bytes(content)
            manifest={'version':'0.1.11-pre.aaaaaaaa','source_commit':sha,'source_tree':'b'*40,
                'packed_smoke':'passed','engine_checks':1,'test_processes':1,
                'toolchain_verification':'checksum-pinned-official-archives','production_sha256':hashes,
                'projected_metadata_sha256':{n:hashlib.sha256(b).hexdigest() for n,b in projected.items()}}
            (build/'web/index.html').write_text('synthetic')
            path=build/'web/release-manifest.json';path.write_text(json.dumps(manifest))
            artifacts.validate_web_gate(build,sha,'b'*40,source_root=root)
            (build/'project/project.godot').write_bytes(projected['project.godot']+b'\nextra=1')
            with self.assertRaises(RuntimeError):artifacts.validate_web_gate(build,sha,'b'*40,source_root=root)

    def test_compatibility_accepts_only_exact_projected_metadata(self):
        from qualification import prepare_browser_qa as qa
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)/'source';root.mkdir();self.metadata(root)
            build=Path(d)/'build';(build/'project/data').mkdir(parents=True);(build/'web').mkdir()
            commit='01234567'+'a'*32
            projection=projected_metadata(root,commit)
            hashes={name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in projection}
            for name,content in projection.items():(build/'project'/name).write_bytes(content)
            manifest={'version':'0.1.11-pre.01234567','source_commit':commit,
                'toolchain_verification':'checksum-pinned-official-archives','production_sha256':hashes,
                'projected_metadata_sha256':{n:hashlib.sha256(b).hexdigest() for n,b in projection.items()},'files':{}}
            path=build/'web/release-manifest.json';path.write_text(json.dumps(manifest))
            with patch.object(qa.subprocess,'check_output',side_effect=lambda command,**kwargs: '' if 'status' in command else commit), patch.dict(qa.CONTRACT,{'candidate_required_sources':list(projection)}):
                qa.validate_export(build,root)
                manifest['projected_metadata_sha256']['scripts/main.gd']='a'*64
                path.write_text(json.dumps(manifest))
                with self.assertRaises(RuntimeError):qa.validate_export(build,root)
                del manifest['projected_metadata_sha256']['scripts/main.gd'];path.write_text(json.dumps(manifest))
                (build/'project/data/release_notes.json').write_bytes(projection['data/release_notes.json']+b' ')
                with self.assertRaises(RuntimeError):qa.validate_export(build,root)
                (build/'project/data/release_notes.json').write_bytes(projection['data/release_notes.json'])
                (root/'data/release_notes.json').write_bytes((root/'data/release_notes.json').read_bytes()+b' ')
                with self.assertRaises(RuntimeError):qa.validate_export(build,root)

    def test_browser_expected_version_uses_full_export_source(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);self.metadata(root)
            script="const {sourceVersion}=require('./tests/source_paths');const assert=require('node:assert/strict');const r=process.argv[1];assert.equal(sourceVersion(r,'01234567'+'a'.repeat(32)),'0.1.11-pre.01234567');assert.throws(()=>sourceVersion(r,'01234567'));"
            subprocess.run(['node','-e',script,str(root)],check=True)

    def test_upload_uses_ancestry_not_hash_order(self):
        older='ffffffff'+'a'*32;newer='01234567'+'b'*32
        with patch.object(publish_itch.subprocess,'check_output',return_value=older), patch.object(publish_itch.subprocess,'run',return_value=subprocess.CompletedProcess([],0)):
            self.assertEqual(publish_itch.check_previous(status('0.1.11-pre.ffffffff'),'0.1.11-pre.01234567',newer),55)
        with patch.object(publish_itch.subprocess,'check_output',return_value=older), patch.object(publish_itch.subprocess,'run',return_value=subprocess.CompletedProcess([],1)):
            with self.assertRaises(ValueError):publish_itch.check_previous(status('0.1.11-pre.ffffffff'),'0.1.11-pre.01234567',newer)
        with self.assertRaises(ValueError):publish_itch.check_previous(status('0.1.11'),'0.1.11-pre.01234567',newer)
        self.assertEqual(publish_itch.check_previous(status('0.1.11-pre.01234567'),'0.1.11'),55)

    def test_repeated_prerelease_uses_real_retained_tag_history(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)
            def git(*args):return subprocess.check_output(['git','-C',str(root),*args],stderr=subprocess.DEVNULL,text=True).strip()
            git('init');git('config','user.name','Synthetic test');git('config','user.email','fixture@example.invalid')
            git('commit','--allow-empty','-m','older');old=git('rev-parse','HEAD')
            old_version='0.1.11-pre.'+old[:8];git('tag','v'+old_version)
            git('commit','--allow-empty','-m','newer');new=git('rev-parse','HEAD')
            previous=os.getcwd()
            try:
                os.chdir(root)
                self.assertEqual(publish_itch.check_previous(status(old_version),'0.1.11-pre.'+new[:8],new),55)
                git('tag','-d','v'+old_version)
                with self.assertRaises(subprocess.CalledProcessError):
                    publish_itch.check_previous(status(old_version),'0.1.11-pre.'+new[:8],new)
            finally:os.chdir(previous)
        workflow=(Path(__file__).resolve().parents[2]/'.github/workflows/release-itch.yml').read_text()
        publish_checkout=workflow.split('  publish:',1)[1].split('      - name:',1)[0]
        self.assertIn('fetch-depth: 0',publish_checkout,'publisher needs prior immutable tags and ancestor history')

    def test_github_workflow_opaque_hash_binding_and_flag(self):
        gate=release_workflow.MetadataGateTests()
        result=gate.run_prepare({'prerelease':True},tag='v0.1.11-pre.aaaaaaaa',version='0.1.11-pre')
        self.assertEqual(result['prerelease'],'true')
        with self.assertRaises(ValueError):gate.run_prepare({'prerelease':True},tag='v0.1.11-pre.bbbbbbbb',version='0.1.11-pre')
        with self.assertRaises(ValueError):gate.run_prepare(tag='v0.1.11-pre.aaaaaaaa',version='0.1.11-pre')
        with patch.object(release_workflow,'SHA','01234567'+'a'*32):
            result=gate.run_prepare({'prerelease':True},tag='v0.1.11-pre.01234567',version='0.1.11-pre')
            self.assertEqual(result['prerelease'],'true')

    def test_upload_receipt_records_only_confirmed_channel_order(self):
        from tests.tooling import test_release as fixtures
        fixture=fixtures.ArtifactTests();fixture.setUp()
        try:
            fixture.manifest.update(tag='v0.1.11-pre.aaaaaaaa',version='0.1.11-pre.aaaaaaaa');fixture.save()
            receipt=fixture.web/'publication/receipt.json'
            args=SimpleNamespace(web=fixture.web,tag=fixture.manifest['tag'],sha='a'*40,receipt=receipt)
            for sequence in [12,None,True]:
                observed=status(fixture.manifest['version']);head=observed['channels'][0]['head'];head.update(id=56,version=sequence)
                with patch.dict(publish_itch.os.environ,{'BUTLER_API_KEY':'synthetic'},clear=True), patch.object(publish_itch.argparse.ArgumentParser,'parse_args',return_value=args), patch.object(publish_itch,'butler',side_effect=[status(),{'buildId':56,'channel':'html5'},observed]):
                    if sequence==12:
                        publish_itch.main();self.assertEqual(json.loads(receipt.read_text())['itch_channel_version'],12);receipt.unlink()
                    else:
                        with self.assertRaises(RuntimeError):publish_itch.main()
                        self.assertFalse(receipt.exists())
        finally:fixture.doCleanups()

    def test_firebase_stage_binds_same_version_source_and_completed_order(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);build=root/'build';web=build/'web';web.mkdir(parents=True)
            (web/'index.html').write_text('<script src="index.js"></script><script>window.__littleLeafVault.boot()</script>')
            for name in ['index.js','index.wasm','index.pck']:(web/name).write_bytes(b'synthetic runtime')
            base={'source_commit':'a'*40,'source_tree':'b'*40,'workflow_run':'10',
                  'version':'0.1.11-pre.aaaaaaaa','packed_smoke':'passed','engine_checks':1,'test_processes':1,
                  'test_report_sha256':'a'*64,'toolchain_verification':'checksum-pinned-official-archives',
                  'files':{p.name:{'bytes':p.stat().st_size,'sha256':artifacts.sha256(p)} for p in web.iterdir()}}
            (web/'release-manifest.json').write_text(json.dumps(base))
            config={'apiKey':'synthetic','authDomain':'little-leaf-41e5d.firebaseapp.com','projectId':'little-leaf-41e5d','appId':'synthetic'}
            publication={'target':'siowyiyou/little-leaf:html5','state':'completed','source_commit':'a'*40,
                'version':base['version'],'tag':'v'+base['version'],'itch_build_id':40,'itch_channel_version':12}
            output=root/'variant';build_firebase.stage(build,output,config,publication=publication)
            marker=json.loads((output/'public/hosting-release.json').read_text())
            self.assertEqual(marker['release_order'],{'target':publication['target'],'channel_version':12})
            self.assertIn('window.__littleLeafRelease='+json.dumps(marker)+';', (output/'public/index.html').read_text())
            for name in ['index.js','index.wasm','index.pck']:self.assertEqual((output/'public'/name).read_bytes(),(web/name).read_bytes())
            self.assertEqual(json.loads((output/'firebase-variant-manifest.json').read_text())['publication'],publication)
            # Exercise the real fresh producer sequence, including its final
            # engine_source_commit mutation; stage-only coverage missed this.
            engine=root/'engine.json';engine.write_text('{"synthetic_only":true}')
            (build/'evidence').mkdir();(build/'evidence/export-report.json').write_text('{}')
            for relative,_,_ in build_firebase.BROWSER_GATES.values():
                path=build/'evidence'/relative;path.parent.mkdir(parents=True,exist_ok=True);path.write_text('{}')
            focused=root/'focused';focused.mkdir()
            for name in build_firebase.FOCUSED_LOGS:
                for suffix in ['', '.json']:(focused/(name+suffix)).write_text('synthetic fixture')
            build_firebase.add_fresh_evidence(build,output,engine,focused,{'synthetic_only':True})
            final_marker=json.loads((output/'public/hosting-release.json').read_text())
            self.assertEqual(final_marker['engine_source_commit'],base['source_commit'])
            final_html=(output/'public/index.html').read_text()
            self.assertIn('window.__littleLeafRelease='+json.dumps(final_marker)+';',final_html)
            from release import deploy_firebase_hosting as hosting
            path=output/'firebase-variant-manifest.json'
            hosting.verify_live_package(output,base['source_commit'],artifacts.sha256(path))
            # Rehashing a stale inline marker cannot conceal the discrepancy.
            (output/'public/index.html').write_text(final_html.replace(json.dumps(final_marker),json.dumps(marker)))
            manifest=json.loads(path.read_text());manifest['files']['public/index.html']=artifacts.sha256(output/'public/index.html');path.write_text(json.dumps(manifest))
            with self.assertRaises(ValueError):hosting.verify_live_package(output,base['source_commit'],artifacts.sha256(path))
            for key,value in [('source_commit','c'*40),('state','pending'),('itch_channel_version',True),('target','wrong')]:
                with self.subTest(key=key), self.assertRaises(ValueError):
                    build_firebase.stage(build,root/key,config,publication={**publication,key:value})

    def test_live_prerelease_requires_bound_order_before_any_network(self):
        from tests.tooling import test_firebase_hosting_deploy as fixtures
        from release import deploy_firebase_hosting as hosting
        fixture=fixtures.HostingTests();fixture.setUp()
        try:
            fixture.marker.update(version='0.1.11-pre.aaaaaaaa',tag='v0.1.11-pre.aaaaaaaa',
                release_order={'target':'siowyiyou/little-leaf:html5','channel_version':12})
            fixture.base['version']=fixture.marker['version']
            fixture.manifest['publication']={'version':fixture.marker['version'],'tag':fixture.marker['tag'],
                'source_commit':fixtures.SHA,'state':'completed','target':'siowyiyou/little-leaf:html5','itch_channel_version':12,'itch_build_id':40}
            (fixture.package/'public/hosting-release.json').write_text(json.dumps(fixture.marker))
            (fixture.package/'public/index.html').write_text('<script src="index.js"></script><script>window.__littleLeafRelease='+json.dumps(fixture.marker)+';</script>')
            fixture.rewrite_manifest();hosting.verify_live_package(fixture.package,fixtures.SHA,fixture.hash)
            fixture.manifest['publication']['itch_channel_version']=11;fixture.rewrite_manifest()
            api=fixtures.FakeAPI()
            with self.assertRaises(ValueError):fixture.deploy(api)
            self.assertEqual(api.calls,[])
            fixture.manifest['publication']['itch_channel_version']=12
            fixture.marker['version']='0.1.10d'
            (fixture.package/'public/hosting-release.json').write_text(json.dumps(fixture.marker))
            fixture.rewrite_manifest()
            with self.assertRaises(ValueError):fixture.deploy(api)
            self.assertEqual(api.calls,[],'removing SHA marker cannot bypass SHA base gate')
        finally:fixture.doCleanups()


if __name__=='__main__':unittest.main()
