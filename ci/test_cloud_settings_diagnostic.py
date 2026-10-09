"""Offline negative guards for browser-only artifact reuse; no engine/browser invoked."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from verify_cloud_settings_diagnostic import validate, digest, validate_selection

SHA='a'*40
TREE='b'*40


class DiagnosticTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)/'source';self.root.mkdir()
        self.git('init','--initial-branch=main')
        for name,text in {'project.godot':'fixture version','scripts/cafe.gd':'fixture production',
                          'web/shell.html':'fixture Web shell','ci/toolchain.json':'fixture pinned tools',
                          'tests/run_integration_candidate.py':'fixture native runner',
                          'tests/test_save_log.gd':'fixture native test',
                          'tests/cloud_settings_browser.js':'fixture browser harness',
                          'tests/cloud_settings_browser_helpers.js':'fixture OCR guard'}.items():
            p=self.root/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text)
        self.git('add','.');self.git('commit','-m','fixture')
        self.evidence=Path(self.temp.name)/'evidence';(self.evidence/'engine-evidence').mkdir(parents=True)
        layout=self.evidence/'engine-evidence/test_save_log-result.json';layout.write_text('{"checks":3}')
        self.summary={'source_commit':SHA,'status':'passed','player_save_used':False,'total_checks':123,'test_processes':10,
            'records':[{'test':'test_save_log','exit_code':0,'failures':[],'result_sha256':digest(layout)}],
            'source_sha256':{name:digest(self.root/name) for name in self.git('ls-files').splitlines()}}
        summary=self.evidence/'engine-evidence/summary.json';summary.write_text(json.dumps(self.summary))
        self.web=Path(self.temp.name)/'web';self.web.mkdir()
        for name in ['index.html','index.js','index.wasm','index.pck']:(self.web/name).write_text(name)
        self.manifest={'source_commit':SHA,'source_tree':TREE,'workflow_run':'17',
            'toolchain_verification':'checksum-pinned-official-archives','packed_smoke':'passed',
            'test_report_sha256':digest(summary),'engine_checks':123,'test_processes':10,
            'files':{p.name:{'bytes':p.stat().st_size,'sha256':digest(p)} for p in self.web.iterdir()},
            'production_sha256':{name:digest(self.root/name) for name in ['project.godot','scripts/cafe.gd','web/shell.html']}}
        self.save()

    def git(self,*args):
        return subprocess.check_output(['git','-C',str(self.root),'-c','user.name=Fixture','-c','user.email=fixture@example.invalid',*args],text=True,stderr=subprocess.DEVNULL).strip()
    def save(self):(self.web/'release-manifest.json').write_text(json.dumps(self.manifest))
    def check(self):return validate(self.web,self.evidence,SHA,TREE,'17',self.root)

    def test_unchanged_production_allows_new_harness_without_qualifying_release(self):
        (self.root/'tests/cloud_settings_browser.js').write_text('new diagnostic harness')
        result=self.check()
        self.assertFalse(result['release_qualified'])
        self.assertEqual(result['export_source_commit'],SHA)
        self.assertNotEqual(result['harness_commit'],SHA)

    def test_changed_production_or_inventory_refused(self):
        (self.root/'scripts/cafe.gd').write_text('changed game')
        with self.assertRaisesRegex(ValueError,'Production changed'):self.check()
        (self.root/'scripts/cafe.gd').write_text('fixture production')
        (self.root/'web/new.js').write_text('new production');self.git('add','web/new.js')
        with self.assertRaisesRegex(ValueError,'inventory changed'):self.check()

    def test_wrong_source_tree_run_and_native_report_hash_refused(self):
        for key,value in [('source_commit','c'*40),('source_tree','c'*40),('workflow_run','18'),
                          ('test_report_sha256','d'*64),('packed_smoke','failed'),('engine_checks',122),
                          ('toolchain_verification','local-tools-unverified-for-release')]:
            old=self.manifest[key];self.manifest[key]=value;self.save()
            with self.subTest(key=key),self.assertRaises(ValueError):self.check()
            self.manifest[key]=old

    def test_native_test_or_runner_or_toolchain_change_refused(self):
        for name in ['tests/test_save_log.gd','tests/run_integration_candidate.py','ci/toolchain.json']:
            p=self.root/name;old=p.read_text();p.write_text('changed')
            with self.subTest(name=name),self.assertRaisesRegex(ValueError,'Native tests/runner/toolchain'):self.check()
            p.write_text(old)

    def test_tampered_export_layout_and_extra_file_refused(self):
        (self.web/'index.pck').write_text('bad binary')
        with self.assertRaises(ValueError):self.check()
        (self.web/'index.pck').write_text('index.pck')
        p=self.evidence/'engine-evidence/test_save_log-result.json';old=p.read_text();p.write_text('{}')
        with self.assertRaises(ValueError):self.check()
        p.write_text(old);(self.web/'extra.js').write_text('unexpected')
        with self.assertRaises(ValueError):self.check()

    def test_symlinked_production_refused_even_for_identical_bytes(self):
        p=self.root/'scripts/cafe.gd';p.rename(p.with_suffix('.copy'));p.symlink_to(p.with_suffix('.copy'))
        with self.assertRaises(ValueError):self.check()



class SelectionTests(unittest.TestCase):
    def test_wrong_artifact_source_and_run_are_refused(self):
        run={'id':17,'run_attempt':1,'repository':{'full_name':'yiyousiow000814/little-leaf'},'head_repository':{'full_name':'yiyousiow000814/little-leaf'},'path':'.github/workflows/ci.yml','status':'completed','conclusion':'success'}
        web={'id':21,'expired':False,'workflow_run':{'id':17},'name':'little-leaf-web-'+SHA+'-1'}
        evidence={'id':22,'expired':False,'workflow_run':{'id':17},'name':'little-leaf-evidence-'+SHA+'-1'}
        validate_selection(run,web,evidence,17,21,22,SHA)
        for bad in [{**web,'id':23},{**web,'expired':True},{**web,'workflow_run':{'id':18}},{**web,'name':'little-leaf-crazygames-'+SHA+'-1'}]:
            with self.assertRaises(ValueError):validate_selection(run,bad,evidence,17,21,22,SHA)
        with self.assertRaises(ValueError):validate_selection(run,web,evidence,17,21,22,'c'*40)
        with self.assertRaises(ValueError):validate_selection({**run,'conclusion':'failure'},web,evidence,17,21,22,SHA)
    def test_automatic_gate_preserved_and_diagnostic_read_only(self):
        text=(Path(__file__).resolve().parents[1]/'.github/workflows/ci.yml').read_text()
        self.assertIn("if: github.event_name != 'workflow_dispatch' || inputs.diagnostic_run_id == ''",text)
        diagnostic=text.split('  diagnostic:\n')[1]
        self.assertIn("github.event_name == 'workflow_dispatch'",diagnostic)
        for forbidden in ['secrets.','id-token: write','contents: write','ci/build_web.py --output','run_integration_candidate.py --output']:
            self.assertNotIn(forbidden,diagnostic)
        self.assertEqual(diagnostic.count('digest-mismatch: error'),2)
        self.assertIn('No full CI qualification, release, merge or deployment is implied.',diagnostic)

if __name__=='__main__':unittest.main()
