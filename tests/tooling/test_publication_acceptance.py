"""Upload acceptance is separate from provider completion; no external actions."""
import copy
import unittest
from pathlib import Path
import yaml
from release import common_firebase as common


class AcceptanceBridgeTests(unittest.TestCase):
    def setUp(self):
        c = {'source_commit': 'a'*40, 'version': '0.1.11-pre.aaaaaaaa',
             'release_tag': 'v0.1.11-pre.aaaaaaaa', 'web_manifest_sha256': 'b'*64}
        self.context = {'staging_run_id': 901, 'staging_attempt': 1, 'coordinator_source_commit': 'c'*40}
        self.manifest = {'common_tag_reuse': {'common': c, 'qualification': {'exact': True},
            'context': self.context, 'same_page': {'wrapper_sha256': {'index.html':'d'*64}}}}
        self.receipt = {'delivery_surface':'qualified-same-page-wrapper', 'target':'siowyiyou/little-leaf:html5',
            'state':'accepted-processing', 'itch_build_id':2120517, 'source_commit':c['source_commit'],
            'version':c['version'], 'tag':c['release_tag'], 'common_qualification':c,
            'itch_wrapper_sha256':{'index.html':'d'*64}, 'qualification':{'exact':True},
            'release_manifest_sha256':'b'*64, 'same_page_staging_origin':{'run_id':901,'attempt':1,'coordinator_source_commit':'c'*40},
            'provider_observation':{'build_id':2120517,'state':'queued','version':c['version']}}

    def test_verified_queue_can_link_independent_qualification_without_live_order(self):
        self.assertEqual(common.publication_matches(self.receipt,self.manifest,allow_processing=True), self.receipt['same_page_staging_origin'])
        with self.assertRaises(ValueError):
            common.publication_matches(self.receipt,self.manifest)

    def test_failed_unknown_wrong_build_and_fabricated_order_do_not_pass(self):
        cases = [('state','failed'),('state','unknown'),('build_id',1),('build_id',True),('version','0.1.10')]
        for field,value in cases:
            bad=copy.deepcopy(self.receipt);bad['provider_observation'][field]=value
            with self.subTest(field=field,value=value), self.assertRaises(ValueError):
                common.publication_matches(bad,self.manifest,allow_processing=True)
        bad=copy.deepcopy(self.receipt);bad['itch_channel_version']=16
        with self.assertRaises(ValueError):common.publication_matches(bad,self.manifest,allow_processing=True)

    def test_independent_workflow_reuses_precredential_gate_and_original_WIF_scope(self):
        root=Path(__file__).resolve().parents[2]
        workflow=yaml.safe_load((root/'.github/workflows/deploy-firebase.yml').read_text())
        job=workflow['jobs']['common-tag'];steps=job['steps']
        self.assertIn('qualified-firebase-live',job['if']);self.assertIn('github.run_attempt == 1',job['if'])
        auth=next(i for i,s in enumerate(steps) if s.get('id')=='auth')
        before='\n'.join(s.get('run','') for s in steps[:auth])
        for text in ['common_firebase.py --run', 'SELECTED_ARTIFACT', 'SELECTED_MANIFEST', 'approved_previous', '--verify-only']:
            self.assertIn(text,before)
        self.assertEqual(steps[auth]['with']['access_token_scopes'],'https://www.googleapis.com/auth/firebase.hosting')
        self.assertEqual(workflow['concurrency']['group'],'firebase-static-little-leaf-41e5d')
        self.assertFalse(workflow['concurrency']['cancel-in-progress'])


if __name__=='__main__':unittest.main()
