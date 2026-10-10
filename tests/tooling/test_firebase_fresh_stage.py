"""Synthetic fresh-run guard tests; no retained CI reports or engine artifacts."""
import copy,json,tempfile,unittest
from unittest.mock import patch
from types import SimpleNamespace
from pathlib import Path
from build_firebase import BROWSER_GATES, FOCUSED_LOGS, validate_fresh_ci, validate_export_inventory
from run_firebase_focused import COMMANDS
from build_web import sha256
from project_layout import source_path

ROOT=Path(__file__).resolve().parents[2]
SOURCE='a'*40
TREE='b'*40


class FreshStageTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name);self.build=self.root/'build';(self.build/'web').mkdir(parents=True)
        self.logs=self.root/'focused';self.logs.mkdir()
        for name in FOCUSED_LOGS:(self.logs/name).write_text('Synthetic successful process output')
        self.native=self.root/'native.json'
        self.native.write_text(json.dumps({'status':'passed','source_commit':SOURCE,'player_save_used':False,'total_checks':123,'test_processes':7}))
        self.base={'source_commit':SOURCE,'source_tree':TREE,'workflow_run':'1','workflow_attempt':'1',
            'toolchain_verification':'checksum-pinned-official-archives','packed_smoke':'passed',
            'test_report_sha256':sha256(self.native),'engine_checks':123,'test_processes':7}
        files={}
        for name in ['index.html','index.js','index.wasm','index.pck']:
            p=self.build/'web'/name;p.write_text('synthetic '+name);files[name]={'sha256':sha256(p),'bytes':p.stat().st_size}
        self.base.update(files=files,web_template_sha256='synthetic-template')
        self.write_base()
        for name in FOCUSED_LOGS:
            (self.logs/(name+'.json')).write_text(json.dumps({'schema_version':1,'status':'passed','exit_code':0,'command':COMMANDS[name],
                'source_commit':SOURCE,'source_tree':TREE,'workflow_run':'1','workflow_attempt':'1','log_sha256':sha256(self.logs/name)}))
        for name,(relative,key,expected) in BROWSER_GATES.items():
            p=self.build/'evidence'/relative;p.parent.mkdir(parents=True,exist_ok=True)
            report={key:expected,'browser_verified':True,'binding':{'source_commit':SOURCE,'export_manifest_sha256':sha256(self.build/'web/release-manifest.json'),'engine_report_sha256':sha256(self.native)}}
            if name=='firebase-fullflow':report.update(source_commit=SOURCE,source_tree=TREE,export_manifest_sha256=sha256(self.build/'web/release-manifest.json'),native_report_sha256=sha256(self.native),real_compiled_ui=True,real_firestore_rules=True,synthetic_only=True,browser_sandbox=True,real_google_sign_in=False,diagnostic_only=False,checks=['synthetic guard receipt'],source_sha256={n:sha256(source_path(ROOT,n)) for n in ['firebase/fullflow.test.mjs','firebase/fullflow_fixtures.mjs','firebase/fullflow_network.mjs','tests/probe_cloud_recovery_geometry.gd','tools/prepare_browser_qa.py','web/little_leaf_firebase.js','web/little_leaf_firebase_session.js','web/little_leaf_firebase_boot.mjs','web/little_leaf_update.js','firebase/firestore.rules']})
            if name=='webkit-recovery':report.update(source_commit=SOURCE,source_tree=TREE,export_manifest_sha256=sha256(self.build/'web/release-manifest.json'),native_report_sha256=sha256(self.native),export_files=files)
            if name=='compatibility':report['inputs']={'new_commit':SOURCE,'export_files':{'new':files}}
            if name=='save-log':report['export_sha256']={k:v['sha256'] for k,v in files.items()}
            if name=='inbox':report.update(export_manifest_sha256=sha256(self.build/'web/release-manifest.json'),export_js_sha256=files['index.js']['sha256'],web_template_sha256=self.base['web_template_sha256'],source_sha256={n:sha256(source_path(ROOT,n)) for n in ['tests/engine_launch_hook.js','tests/fixtures/inbox-vault-018.js','web/little_leaf_vault.js','web/little_leaf_inbox.js','tests/compensation_inbox_suite.js']})
            p.write_text(json.dumps(report))

    def write_base(self):
        (self.build/'web/release-manifest.json').write_text(json.dumps(self.base))
        (self.build/'evidence').mkdir(exist_ok=True)
        (self.build/'evidence/export-report.json').write_text(json.dumps({'manifest':self.base,'stages':[{'stage':'packed-smoke','exit_code':0}]}))
    def verify(self):return validate_fresh_ci(self.build,self.native,self.logs,SOURCE,TREE,'1','1')

    def test_retained_compiled_diagnostic_cannot_qualify_release(self):
        p=self.build/'evidence/firebase-fullflow/firebase-fullflow.json'
        report=json.loads(p.read_text());report['diagnostic_only']=True;p.write_text(json.dumps(report))
        with self.assertRaises(ValueError):self.verify()

    def test_complete_fresh_evidence_is_distinct_from_hosted_acceptance(self):
        result=self.verify();self.assertEqual(result['status'],'fresh-gates-passed')
        self.assertTrue(result['new_engine_run']);self.assertFalse(result['hosted_acceptance'])
        self.assertEqual(result['source_commit'],SOURCE)
        self.assertEqual(set(result['gate_evidence_sha256']),{'native','export',*BROWSER_GATES,*('firebase-'+x+s for x in FOCUSED_LOGS for s in ['', '.json'])})

    def test_wrong_source_tree_run_attempt_or_toolchain_rejected(self):
        for key,value in [('source_commit','c'*40),('source_tree','c'*40),('workflow_run','2'),('workflow_attempt','2'),
                          ('test_report_sha256','c'*64),('toolchain_verification','local-tools-unverified-for-release'),('packed_smoke','failed')]:
            original=copy.deepcopy(self.base);self.base[key]=value;self.write_base()
            with self.subTest(key=key),self.assertRaises(ValueError):self.verify()
            self.base=original;self.write_base()

    def test_each_browser_gate_is_required(self):
        for name,(relative,key,_) in BROWSER_GATES.items():
            p=self.build/'evidence'/relative;old=p.read_text();report=json.loads(old);report[key]=False;p.write_text(json.dumps(report))
            with self.subTest(name=name),self.assertRaises(ValueError):self.verify()
            p.unlink()
            with self.subTest(missing=name),self.assertRaises(FileNotFoundError):self.verify()
            p.write_text(old)

    def test_diagnostic_tutorial_cannot_qualify_fresh_run(self):
        p=self.build/'evidence'/BROWSER_GATES['tutorial'][0];x=json.loads(p.read_text());x['binding']['diagnostic_only']=True;p.write_text(json.dumps(x))
        with self.assertRaisesRegex(ValueError,'diagnostic'):self.verify()

    def test_missing_focused_or_changed_native_evidence_rejected(self):
        p=self.logs/'rules.log';p.write_text('')
        with self.assertRaisesRegex(ValueError,'focused'):self.verify()
        p.write_text('fixture');self.native.write_text('{}')
        with self.assertRaises(ValueError):self.verify()

    def test_recovery_gates_are_required_same_source_evidence(self):
        for name in ['recovery.log', 'recovery-presentation.log', 'recovery-browser.log']:
            self.assertIn(name, FOCUSED_LOGS)
            path=self.logs/name;old=path.read_text();path.unlink()
            with self.subTest(name=name),self.assertRaisesRegex(ValueError, 'focused'):self.verify()
            path.write_text(old)
        self.assertEqual(COMMANDS['recovery-browser.log'], ['node', 'tests/firebase_recovery_browser.js'])

    def test_browser_binding_mismatches_rejected(self):
        for name in BROWSER_GATES:
            p=self.build/'evidence'/BROWSER_GATES[name][0];old=p.read_text();r=json.loads(old)
            if name=='tutorial':r['binding']['export_manifest_sha256']='wrong'
            elif name in {'webkit-recovery','firebase-fullflow'}:r['source_tree']='wrong'
            elif name=='compatibility':r['inputs']['export_files']['new']={}
            elif name=='save-log':r['export_sha256']['index.pck']='wrong'
            else:r['export_js_sha256']='wrong'
            p.write_text(json.dumps(r))
            with self.subTest(name=name),self.assertRaises(ValueError):self.verify()
            p.write_text(old)

    def test_structured_focused_receipts_fail_closed(self):
        p=self.logs/'rules.log.json';old=p.read_text()
        for key,value in [('status','failed'),('exit_code',1),('source_commit','wrong'),('source_tree','wrong'),('workflow_run','2'),('workflow_attempt','2'),('log_sha256','wrong'),('command',['true'])]:
            r=json.loads(old);r[key]=value;p.write_text(json.dumps(r))
            with self.subTest(key=key),self.assertRaises(ValueError):self.verify()
        p.unlink()
        with self.assertRaises(FileNotFoundError):self.verify()

    def test_export_inventory_rejects_extra_symlink_hash_size_and_missing(self):
        web=self.build/'web';extra=web/'extra.js';extra.write_text('extra')
        with self.assertRaises(ValueError):self.verify()
        extra.unlink();target=web/'index.js';original=target.read_bytes();target.unlink();target.symlink_to(web/'index.html')
        with self.assertRaises(ValueError):self.verify()
        target.unlink();target.write_bytes(original+b'changed')
        with self.assertRaises(ValueError):self.verify()
        target.write_bytes(original);self.base['files']['index.js']['bytes']+=1;self.write_base()
        with self.assertRaises(ValueError):self.verify()
        target.unlink()
        with self.assertRaises(ValueError):self.verify()


class FocusedRunnerTests(unittest.TestCase):
    def test_failed_process_cannot_leave_success_receipt(self):
        from run_firebase_focused import run
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);receipt=root/'adapter.log.json';receipt.write_text('stale success')
            with patch('run_firebase_focused.subprocess.run',return_value=SimpleNamespace(returncode=1)):
                with self.assertRaises(SystemExit):run('adapter.log',root)
            self.assertFalse(receipt.exists())

    def test_success_receipt_binds_command_source_run_and_log(self):
        from run_firebase_focused import run
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)
            with patch('run_firebase_focused.subprocess.run',return_value=SimpleNamespace(returncode=0)), patch('run_firebase_focused.subprocess.check_output',side_effect=[SOURCE,TREE]), patch.dict('os.environ',{'GITHUB_RUN_ID':'1','GITHUB_RUN_ATTEMPT':'2'}):
                run('adapter.log',root)
            receipt=json.loads((root/'adapter.log.json').read_text())
            self.assertEqual(receipt['source_commit'],SOURCE);self.assertEqual(receipt['source_tree'],TREE)
            self.assertEqual(receipt['workflow_attempt'],'2');self.assertEqual(receipt['exit_code'],0)
            self.assertEqual(receipt['command'],COMMANDS['adapter.log']);self.assertEqual(receipt['log_sha256'],sha256(root/'adapter.log'))

class WorkflowTests(unittest.TestCase):
    def test_wrapper_has_no_historical_artifact_input_or_access(self):
        text=(ROOT/'.github/workflows/stage-firebase.yml').read_text()
        self.assertIn('uses: ./.github/workflows/build-web.yml',text)
        self.assertIn('firebase_preview: true',text)
        self.assertIn('itch_preview: ${{ inputs.itch_preview || false }}',text)
        self.assertEqual(text.count('type: boolean'),1)
        self.assertEqual(text.count('default: false'),1)
        for forbidden in ['actions: read','id-token: write','secrets.','download-artifact','gh api','run-id','artifact-ids']:
            self.assertNotIn(forbidden,text)

    def test_existing_full_gate_commands_retained_before_firebase(self):
        text=(ROOT/'.github/workflows/build-web.yml').read_text();first=text.index('      - name: Check Firebase adapter')
        for command in ['python3 tools/engine_shards.py run','python3 tools/engine_shards.py merge','python3 tools/build_web.py','python3 tools/build_crazygames.py',
                        'python3 .compatibility-old/tests/run_integration_candidate.py','python3 tools/prepare_browser_qa.py wall',
                        'node tests/compensation_inbox_browser.js','node tests/fresh_tutorial_browser.js','node tests/wall_compatibility_browser.js',
                        'node tests/save_log_browser.js','node tests/connection_recovery_browser.js']:
            self.assertLess(text.index(command),first,command)
        self.assertIn('node tests/fresh_tutorial_browser_test.js --ocr-fixtures',text)
        self.assertIn('firebase_preview:\n        description:',text)
        self.assertIn('        default: false',text)
        self.assertNotIn('continue-on-error',text)
        self.assertIn('needs: [build, browser]',text)
        self.assertIn('needs: [guard, engine, historical, build, browser, firebase]',text)
        self.assertIn('jobs.gate.outputs.artifact_id',text)
        self.assertIn('digest-mismatch: error',text)
        self.assertNotIn('run-id:',text)
        self.assertNotIn('repository:',text)
        self.assertIn('little-leaf-candidate-project-${{ github.sha }}-${{ github.run_attempt }}',text)
        self.assertIn('little-leaf-historical-project-${{ github.sha }}-${{ github.run_attempt }}',text)
        self.assertIn('include-hidden-files: true',text)
        self.assertNotIn('secrets.',text)
        tail=text[first:text.index('      - name: Keep test and export evidence')]
        self.assertEqual(tail.count('        if: inputs.firebase_preview'),7)
        self.assertIn('python3 tools/prepare_browser_qa.py cloud',tail)
        self.assertNotIn('always()',tail)
        self.assertLess(tail.index('--require-fresh-ci'),tail.index('id: firebase_upload'))

    def test_recovery_browser_gate_is_bounded_and_not_skippable(self):
        text=(ROOT/'.github/workflows/build-web.yml').read_text()
        section=text[text.index('      - name: Verify cloud recovery in real IndexedDB before merge'):text.index('      - name: Verify compensation history')]
        self.assertLess(text.index('      - name: Install shared pinned browser tools'),text.index(section))
        self.assertIn("        if: matrix.lane == 'recovery'",section)
        self.assertIn('lane: [play, compatibility, recovery]',text)
        self.assertIn('"$BROWSER"; do test "$result" = success || exit 1',text)
        self.assertNotIn('continue-on-error',section)
        self.assertIn('PLAYWRIGHT_MODULE="$RUNNER_TEMP/inbox-browser-tools/node_modules/playwright"',section)
        self.assertIn('${{ runner.temp }}/firebase-focused/',text)
        for gate in ['adapter.log','delayed-network.log','recovery.log','choice.log','session.log','update-notice.log','recovery-presentation.log','recovery-browser.log']:
            self.assertEqual(text.count('--gate '+gate+' --output'),1)
            self.assertIn('--gate '+gate,section)
        self.assertIn('timeout-minutes: 4', section)
        self.assertIn('PLAYWRIGHT_CHROMIUM_CHANNEL: chrome', section)
        for gate in ['recovery.log', 'recovery-presentation.log', 'recovery-browser.log']:
            self.assertIn('--gate '+gate, section)
        runner=(ROOT/'tools/run_firebase_focused.py').read_text()
        self.assertIn("timeout=120 if name=='recovery-browser.log' else None", runner)

    def test_public_config_contains_only_approved_public_app_fields(self):
        x=json.loads((ROOT/'platform/firebase/public-config.json').read_text())
        self.assertEqual(set(x),{'apiKey','authDomain','projectId','appId'})
        self.assertEqual(x['projectId'],'little-leaf-41e5d')
        self.assertEqual(x['authDomain'],'little-leaf-41e5d.firebaseapp.com')

if __name__=='__main__':unittest.main()
