"""Bounded /itch test contract and mocked Hosting protocol; no provider calls."""
import copy
import gzip
import json
from pathlib import Path
import tempfile
import io
from email.message import Message
import unittest
from unittest.mock import patch
from urllib.parse import parse_qs, urlsplit
import deploy_firebase_hosting as h
from build_firebase import BROWSER_GATES, FOCUSED_LOGS
from project_layout import source_path
from run_firebase_focused import COMMANDS

ROOT = Path(__file__).resolve().parents[2]
SHA, TREE = 'a'*40, 'b'*40
NEW = h.SITE_PATH + '/versions/approved-test'
CONFIG = {'headers': [
    {'glob': '**/*.html', 'headers': {'Cache-Control': 'no-cache'}},
    {'glob': '/hosting-release.json', 'headers': {'Cache-Control': 'no-store'}}],
    'unrecognizedPrivateField': {'fixtureSentinel': 'never-public-configuration'}}
FILES = {name: str(i)*64 for i, name in enumerate([
    '/index.html', '/index.js', '/index.wasm', '/index.pck', '/hosting-release.json', '/retained-private-path'], 1)}


class API:
    def __init__(self, fail=None):
        self.fail, self.calls, self.finalized = fail, [], False
        self.head = dict(h.ITCH_BASELINE)
        self.config = copy.deepcopy(CONFIG)
        self.old = dict(FILES)
        self.created, self.files, self.release_posts = None, None, 0

    def request(self, method, path, data=None, upload=False):
        self.calls.append((method, path, data, upload))
        if method == 'GET' and '/releases?' in path:
            if self.fail == 'head-drift' and self.finalized:
                return {'releases': [{'name': h.SITE_PATH+'/releases/concurrent', 'version': {'name': NEW}}]}
            return {'releases': [{'name': self.head['release'], 'version': {'name': self.head['version']}}]}
        if method == 'GET' and '/files?' in path:
            values = self.files if path.startswith(NEW+'/') else self.old
            if self.finalized and self.fail == 'map-drift' and path.startswith(NEW+'/'):
                values = {**values, '/index.html': '0'*64}
            return {'files': [{'path': k, 'hash': v, 'status': 'ACTIVE'} for k, v in values.items()]}
        if method == 'GET':
            config = self.created if path == NEW else self.config
            if self.finalized and self.fail == 'config-drift' and path == NEW:
                config = {**config, 'newUnexpectedKey': True}
            return {'name': path, 'status': 'FINALIZED', 'config': config}
        if path == h.SITE_PATH+'/versions':
            self.created = copy.deepcopy(data['config'])
            return {'name': NEW}
        if ':populateFiles' in path:
            self.files = data['files']
            wanted = sorted(set(self.files.values())-set(self.old.values()))
            if self.fail == 'old-upload': wanted.append(self.old['/index.html'])
            return {'uploadUrl': 'https://upload-firebasehosting.googleapis.com/upload/'+NEW+'/files',
                    'uploadRequiredHashes': wanted}
        if upload:
            self.assert_payload(data, path)
            if self.fail == 'upload': raise RuntimeError('mocked upload uncertainty')
            return {}
        if method == 'PATCH':
            self.finalized = True
            return {'name': NEW, 'status': 'CREATED' if self.fail == 'finalize' else 'FINALIZED'}
        if method == 'POST' and '/releases?' in path:
            self.release_posts += 1
            if self.fail == 'release': raise RuntimeError('mocked release uncertainty')
            self.head = {'release': h.SITE_PATH+'/releases/test',
                         'version': parse_qs(urlsplit(path).query)['versionName'][0]}
            return {'name': self.head['release'], 'type': 'DEPLOY', 'version': {'name': self.head['version']}}
        raise AssertionError('unexpected mocked API request')

    @staticmethod
    def assert_payload(data, path):
        import hashlib
        assert hashlib.sha256(data).hexdigest() == path.rsplit('/', 1)[1]
        gzip.decompress(data)


class ItchTestEntry(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name);self.folder = self.root/'variant'
        self.inner = self.folder/'public/itch';self.inner.mkdir(parents=True)
        evidence = self.folder/'evidence';evidence.mkdir()
        for name in ['index.js', 'index.wasm', 'index.pck']:
            (self.inner/name).write_bytes(('synthetic '+name).encode())
        (self.inner/'index.audio.position.worklet.js').write_bytes(b'synthetic official-template asset')
        native = {'status': 'passed', 'source_commit': SHA, 'player_save_used': False,
                  'total_checks': 123, 'test_processes': 7}
        (evidence/'native-summary.json').write_text(json.dumps(native))
        self.base = {'source_commit': SHA, 'source_tree': TREE, 'workflow_run': '1', 'workflow_attempt': '1',
                     'toolchain_verification': 'checksum-pinned-official-archives', 'packed_smoke': 'passed',
                     'engine_checks': 123, 'test_processes': 7, 'version': 'synthetic', 'tag': '',
                     'test_report_sha256': h.digest(evidence/'native-summary.json'),
                     'files': {name: {'sha256': h.digest(self.inner/name), 'bytes': (self.inner/name).stat().st_size}
                               for name in ['index.js', 'index.wasm', 'index.pck']}}
        self.base_hash = h.record_digest(self.base)
        (evidence/'export-report.json').write_text(json.dumps({'manifest': self.base, 'stages': [{'exit_code': 0}]}))
        self.marker = {'source_commit': SHA, 'source_tree': TREE, 'runtime_origin': h.ORIGIN.rstrip('/'),
                       'runtime_path': '/itch/', 'test_surface': 'trusted-itch-frame', 'ci_run_id': '1',
                       'base_web_manifest_sha256': self.base_hash, 'version': 'synthetic', 'tag': ''}
        (self.inner/'hosting-release.json').write_text(json.dumps(self.marker))
        (self.inner/'index.html').write_text('<script>window.__littleLeafRelease='+json.dumps(self.marker)+';</script>', encoding='utf-8')
        flow_sources = ['firebase/fullflow.test.mjs','firebase/fullflow_fixtures.mjs','firebase/fullflow_network.mjs',
            'tests/diagnostics/probe_cloud_recovery_geometry.gd','tools/prepare_browser_qa.py','web/little_leaf_firebase.js',
            'web/little_leaf_firebase_session.js','web/little_leaf_firebase_boot.mjs','web/little_leaf_update.js','firebase/firestore.rules']
        flow = {'passed': True, 'synthetic_only': True, 'real_google_sign_in': False, 'real_compiled_ui': True,
                'real_firestore_rules': True, 'diagnostic_only': False, 'browser_sandbox': True, 'itch_test_entry': True,
                'synthetic_public_config_substitution': True, 'itch_ancestor_origins': h.ANCESTORS,
                'checks': ['synthetic'], 'itch_entry_sha256': h.digest(self.inner/'index.html'),
                'source_commit': SHA, 'source_tree': TREE, 'export_manifest_sha256': self.base_hash,
                'native_report_sha256': self.base['test_report_sha256'],
                'source_sha256': {name: h.digest(source_path(ROOT,name)) for name in flow_sources}}
        for name in BROWSER_GATES:
            (evidence/(name+'.json')).write_text(json.dumps(flow if name == 'firebase-fullflow' else {'passed': True}))
        for name in FOCUSED_LOGS:
            log = evidence/('firebase-'+name);log.write_text('synthetic successful check')
            log.with_name(log.name+'.json').write_text(json.dumps({'schema_version': 1, 'status': 'passed', 'exit_code': 0,
                'command': COMMANDS[name], 'source_commit': SHA, 'source_tree': TREE,
                'workflow_run': '1', 'workflow_attempt': '1', 'log_sha256': h.digest(log)}))
        labels = {'native': 'native-summary.json','export': 'export-report.json',
                  **{name:name+'.json' for name in BROWSER_GATES},
                  **{'firebase-'+name+s:'firebase-'+name+s for name in FOCUSED_LOGS for s in ['', '.json']}}
        self.manifest = {'status': h.ITCH_TEST_STATUS, 'source_commit': SHA, 'source_tree': TREE,
            'production_release_eligible': False, 'hosted_acceptance': False, 'auth_domains_modified': False,
            'hosting_config_proposal_only': True, 'runtime_origin': h.ORIGIN.rstrip('/'), 'runtime_path': '/itch/',
            'hosting_header_additions': [{'source':row['glob'],'headers':[{'key':k,'value':v} for k,v in row['headers'].items()]} for row in h.ITCH_HEADERS],
            'base_web_manifest': self.base, 'base_web_manifest_sha256': self.base_hash,
            'fresh_ci': {'status': 'fresh-gates-passed','new_engine_run': True, 'source_commit': SHA,'source_tree': TREE,
                         'workflow_run': '1','workflow_attempt': '1',
                         'gate_evidence_sha256': {label:h.digest(evidence/name) for label,name in labels.items()}},
            'source_sha256': {name:h.digest(source_path(ROOT,name)) for name in ['tools/build_itch_entry.py',
                'tools/build_itch_trusted_preview.py','tools/build_firebase.py','web/little_leaf_firebase_boot.mjs',
                'web/little_leaf_firebase_session.js','web/little_leaf_update.js','web/little_leaf_entry.css']}}
        names = ['guard','historical','build','gate','firebase','browser (play)','browser (recovery)',
            'compatibility (compatibility, old_opened_after_new)','compatibility (compatibility, already_open_old)',
            *(f'engine ({i})' for i in range(5))]
        self.origin = {'run': {'id': 1,'run_attempt': 1,'repository': {'full_name':'yiyousiow000814/little-leaf'},
            'head_repository': {'full_name':'yiyousiow000814/little-leaf'},'path':'.github/workflows/stage-firebase.yml',
            'event':'workflow_dispatch','head_branch':'main','head_sha':SHA,'status':'completed','conclusion':'success'},
            'artifact': {'id':2,'workflow_run': {'id':1,'head_sha':SHA},'expired':False,
                         'name':'little-leaf-firebase-'+SHA+'-1','digest':'sha256:'+'d'*64},
            'commit': {'sha':SHA,'commit': {'tree': {'sha':TREE}}},
            'jobs':[{'name':name,'status':'completed','conclusion':'success'} for name in ['selection',*('fresh / '+n for n in names)]]}
        self.rewrite()
        self.output = self.root/'receipt.json'

    def rewrite(self):
        self.manifest['files'] = {p.relative_to(self.folder).as_posix():h.digest(p) for p in self.folder.rglob('*')
                                  if p.is_file() and p.name!='firebase-variant-manifest.json'}
        p=self.folder/'firebase-variant-manifest.json';p.write_text(json.dumps(self.manifest))
        self.hash=h.digest(p)

    def verify(self):
        return h.verify_itch_test_package(self.folder,SHA,self.hash,self.origin)

    def deploy(self,api,smoke=True):
        with patch.object(h,'ITCH_BASELINE_CONFIG',h.record_digest(CONFIG)):
            return h.deploy_itch_test_entry(self.folder,SHA,self.hash,self.output,api,
                lambda marker,before,targets: {'synthetic-baseline':True} if marker is None else smoke,staging_origin=self.origin)

    def test_exact_package_and_complete_baseline_preserved(self):
        self.verify();api=API();result=self.deploy(api)
        self.assertEqual(result['status'],'test-entry-public-verified-auth-pending')
        self.assertTrue(result['homepage_preserved']);self.assertFalse(result['real_google_acceptance'])
        self.assertEqual({key:api.files[key] for key in FILES},FILES)
        self.assertTrue(all(key.startswith('/itch/') for key in set(api.files)-set(FILES)))
        self.assertEqual(api.created,{**CONFIG,'headers':CONFIG['headers']+h.ITCH_HEADERS})
        self.assertEqual(api.release_posts,1)
        text=self.output.read_text();self.assertNotIn('never-public-configuration',text)
        self.assertNotIn('retained-private-path',text)
        self.assertNotIn('unrecognizedPrivateField',text)
        self.assertEqual(result['previous'],h.ITCH_BASELINE)
        self.assertEqual(result['previous_files_sha256'],h.record_digest(FILES))
        self.assertTrue(result['rollback_version_verified'])

    def test_every_proof_label_and_focused_receipt_is_mandatory(self):
        original=copy.deepcopy(self.manifest)
        for label in original['fresh_ci']['gate_evidence_sha256']:
            self.manifest=copy.deepcopy(original);del self.manifest['fresh_ci']['gate_evidence_sha256'][label];self.rewrite()
            with self.subTest(label=label),self.assertRaises(ValueError):self.verify()

    def test_origin_source_job_artifact_and_local_promotion_rejected(self):
        original=copy.deepcopy(self.origin)
        for group,key,value in [('run','event','pull_request'),('run','head_sha','c'*40),('run','run_attempt',2),
            ('artifact','expired',True),('artifact','digest',None),('commit','sha','c'*40),('jobs',None,[])]:
            self.origin=copy.deepcopy(original)
            if key:self.origin[group][key]=value
            else:self.origin[group]=value
            with self.subTest(group=group,key=key),self.assertRaises(ValueError):self.verify()
        self.origin=original
        for status in ['prepared-same-itch-local-candidate-not-deployable','staged-not-published','prepared-itch-preview-not-deployed']:
            self.manifest['status']=status;self.rewrite()
            with self.subTest(status=status),self.assertRaises(ValueError):self.verify()

    def test_corrupt_runtime_or_unlisted_extra_rejected_before_network(self):
        (self.inner/'index.js').write_bytes(b'changed');api=API()
        with self.assertRaises(ValueError):self.deploy(api)
        self.assertEqual(api.calls,[])

    def test_changed_evidence_with_rebound_inventory_still_rejected(self):
        p=self.folder/'evidence/firebase-fullflow.json';original=p.read_text()
        for key,value in [('browser_sandbox',False),('itch_ancestor_origins',[]),('native_report_sha256','e'*64),('source_sha256',{}),('real_google_sign_in',True)]:
            row=json.loads(original);row[key]=value;p.write_text(json.dumps(row))
            self.manifest['fresh_ci']['gate_evidence_sha256']['firebase-fullflow']=h.digest(p);self.rewrite()
            with self.subTest(key=key),self.assertRaises(ValueError):self.verify()

    def test_existing_namespace_and_config_drift_stop_before_create(self):
        for failure in ['namespace','config']:
            api=API()
            if failure=='namespace':api.old['/itch/index.html']='a'*64
            else:api.config['drift']=True
            with self.subTest(failure=failure),self.assertRaises(ValueError):self.deploy(api)
            self.assertFalse(any(method=='POST' for method,*_ in api.calls))
            self.output.unlink()

    def test_new_config_map_upload_or_head_drift_never_releases(self):
        for failure in ['old-upload','upload','finalize','map-drift','config-drift','head-drift']:
            api=API(failure)
            with self.subTest(failure=failure),self.assertRaises(RuntimeError):self.deploy(api)
            self.assertEqual(api.release_posts,0)
            self.assertEqual(sum(method=='POST' and path==h.SITE_PATH+'/versions' for method,path,*_ in api.calls),1)
            self.output.unlink()

    def test_uncertain_release_and_failed_public_checks_never_retry_or_rollback(self):
        for failure in ['release','smoke']:
            api=API('release' if failure=='release' else None)
            with self.subTest(failure=failure),self.assertRaises(RuntimeError):self.deploy(api,smoke=False)
            self.assertEqual(api.release_posts,1)
            self.assertFalse(any(method=='DELETE' for method,*_ in api.calls))
            before=len(api.calls)
            with self.assertRaisesRegex(ValueError,'retry'):self.deploy(api)
            self.assertEqual(len(api.calls),before);self.output.unlink()

    def test_routing_unknown_and_header_overlap_rejected_even_when_digest_matches(self):
        for extra in [{'rewrites':[{'glob':'/**','path':'/index.html'}]},
                      {'redirects':[{'regex':'unknown','location':'/'}]},
                      {'headers':CONFIG['headers']+[{'glob':'/itch/index.html','headers':{'Cache-Control':'no-store'}}]},
                      {'headers':CONFIG['headers']+[{'glob':'/itch/','headers':{'Content-Security-Policy':"frame-ancestors 'none'"}}]}]:
            config={**CONFIG,**extra}
            with patch.object(h,'ITCH_BASELINE_CONFIG',h.record_digest(config)),self.assertRaises(ValueError):h.itch_test_config(config)

    def test_complete_file_pagination_and_fail_closed_bad_records(self):
        class Pages:
            def __init__(self,duplicate=False):self.calls=0;self.duplicate=duplicate
            def request(self,method,path):
                self.calls+=1
                return {'files':[{'path':'/one' if self.calls==1 or self.duplicate else '/two','hash':'a'*64,'status':'ACTIVE'}],
                        **({'nextPageToken':'opaque-private-token'} if self.calls==1 else {})}
        api=Pages();self.assertEqual(h.active_files(api,h.ITCH_BASELINE['version']),{'/one':'a'*64,'/two':'a'*64})
        self.assertEqual(api.calls,2)
        with self.assertRaises(ValueError):h.active_files(Pages(True),h.ITCH_BASELINE['version'])

    def test_public_checks_require_root_parity_headers_and_all_exact_payloads(self):
        owner=self
        class Response(io.BytesIO):
            status=200
            def __init__(self,data,headers):super().__init__(data);self.headers=headers
        class Public:
            drift=None
            def open(self,request,timeout):
                path=urlsplit(request.full_url).path
                headers=Message()
                if path.startswith('/itch/'):
                    name=path.removeprefix('/itch/') or 'index.html'
                    data=(owner.inner/name).read_bytes()
                    headers['Cache-Control']='no-store' if name=='hosting-release.json' else 'no-cache'
                    if name=='index.html':headers['Content-Security-Policy']=h.FRAME_POLICY
                    if self.drift=='cache' and name=='index.html':headers.replace_header('Cache-Control','max-age=3600')
                    if self.drift=='payload' and name=='index.js':data+=b'corrupt'
                else:
                    data=b'unchanged homepage' if path in ['/', '/index.html'] else b'unchanged root marker'
                    if self.drift=='root' and path=='/':data+=b'changed'
                    headers['Cache-Control']='max-age=3600'
                return Response(data,headers)
        api=Public();targets={'/itch/'+p.name:{'sha256':h.digest(p),'bytes':p.stat().st_size} for p in self.inner.iterdir()}
        with patch.object(h,'build_opener',return_value=api):
            before=h.itch_test_smoke(None,None,None)
            self.assertTrue(h.itch_test_smoke(self.marker,before,targets))
            for drift in ['root','cache','payload']:
                api.drift=drift
                with self.subTest(drift=drift):self.assertFalse(h.itch_test_smoke(self.marker,before,targets))

    def test_workflow_separate_mode_is_guarded_before_token_and_keeps_existing_identity(self):
        text=(ROOT/'.github/workflows/deploy-firebase.yml').read_text()
        mode=text[text.index('  itch-test-entry:'):text.index('  auth-pause:')]
        for guard in ['test "$SOURCE_SHA" = "$GITHUB_SHA"','test "$GITHUB_RUN_ATTEMPT" = 1','digest-mismatch: error','--verify-only']:
            self.assertIn(guard,mode);self.assertLess(mode.index(guard),mode.index('id: auth'))
        for boundary in ['access_token_lifetime: 900s','create_credentials_file: false','export_environment_variables: false','retention-days: 1']:
            self.assertIn(boundary,mode)
        self.assertNotIn('--reserve',mode);self.assertNotIn('authDomain',mode)
        self.assertNotIn('continue-on-error',mode)
