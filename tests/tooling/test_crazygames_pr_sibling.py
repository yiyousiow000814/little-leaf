"""Proof for the ordinary CI sibling boundary, not a hosted export result."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import yaml

from tools.ci import crazygames_pr_evidence as proof

ROOT = Path(__file__).resolve().parents[2]


class SiblingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.jobs = yaml.safe_load((ROOT/'.github/workflows/build-web.yml').read_bytes())['jobs']

    def test_routes_and_exact_evidence_before_outputs(self):
        j = self.jobs
        steps = lambda n: j[n]['steps']
        def step(n, phrase):
            return next(s for s in steps(n) if phrase in s.get('name',''))
        s = step('guard','Select ordinary PR')
        self.assertEqual(s['env']['ORDINARY_PR'],j['play']['env']['ORDINARY_PR'])
        self.assertIn("ordinary_pr=%s",s['run'])
        self.assertEqual(j['crazygames']['if'], "${{ !cancelled() && needs.guard.result == 'success' && needs.build.result == 'success' && needs.guard.outputs.scope == 'full' && needs.guard.outputs.locked_browser == 'true' }}")
        lock = s['env']['LOCKED_BROWSER']
        self.assertIn("github.event_name == 'push' && github.ref == 'refs/heads/main'", lock)
        for required in ("inputs.release_tag == ''", "!inputs.firebase_preview", "!inputs.itch_preview",
                         "!inputs.itch_test_entry", "inputs.publication_receipt == ''"):
            self.assertIn(required, lock)
        self.assertEqual(step('gate','Verify the sibling receipt')['if'],
                         "needs.guard.outputs.locked_browser == 'true' && needs.guard.outputs.scope == 'full'")
        self.assertEqual(step('gate','Require every mandatory gate')['env']['SIBLING_REQUIRED'],
                         "${{ needs.guard.outputs.locked_browser }}")
        self.assertEqual(j['crazygames']['name'],
                         "${{ needs.guard.outputs.ordinary_pr == 'false' && needs.guard.outputs.locked_browser == 'true' && 'crazygames (main CI)' || 'crazygames' }}")
        self.assertEqual(j['crazygames']['needs'],['guard','build'])
        self.assertEqual(step('build','Export separate CrazyGames')['if'],"needs.guard.outputs.locked_browser == 'false'")
        self.assertEqual(step('build','Retain separate CrazyGames')['if'],"needs.guard.outputs.locked_browser == 'false'")
        self.assertEqual(step('build','Bind exact post-import')['if'],"needs.guard.outputs.locked_browser == 'true'")
        command=step('build','Export separate CrazyGames')['run']
        self.assertEqual(step('crazygames','independent CI variant')['run'],command)
        self.assertEqual(j['play']['needs'],'build')
        self.assertNotIn('crazygames',j['firebase']['needs'])
        get=next(s for s in steps('crazygames') if 'download-artifact@' in s.get('uses',''))
        self.assertEqual(get['with']['artifact-ids'],'${{ needs.build.outputs.inputs_id }}')
        self.assertEqual(get['with']['digest-mismatch'],'error')
        self.assertNotIn('name',get['with'])
        get=step('gate','Collect the exact sibling')
        self.assertEqual(get['with']['artifact-ids'],'${{ needs.crazygames.outputs.evidence_id }}')
        self.assertEqual(get['with']['digest-mismatch'],'error')
        ids=[s.get('id') for s in steps('gate')]
        self.assertLess(ids.index('sibling_verify'),ids.index('gate_evidence'))
        self.assertLess(ids.index('gate_evidence'),ids.index('accept'))
        self.assertIn('crazygames-build/evidence/',step('gate','Keep test and export evidence')['with']['path'])

    def test_actual_accept_shell_fails_closed_for_missing_stage_or_evidence(self):
        accept=next(s for s in self.jobs['gate']['steps'] if s.get('id')=='accept')['run']
        env={**dict.fromkeys('GUARD ENGINE HISTORICAL BUILD PLAY BROWSER COMPATIBILITY SIBLING_VERIFIED CRAZYGAMES'.split(),'success'),
             'FIREBASE_REQUIRED':'false','FIREBASE':'skipped','FIREBASE_ARTIFACT':'','FIREBASE_MANIFEST':'','WEB_ARTIFACT':'100',
             'SIBLING_REQUIRED':'true','CRAZYGAMES_ARTIFACT':'101','CRAZYGAMES_EVIDENCE':'102','GATE_EVIDENCE':'103'}
        def attempt(update, passed):
            with tempfile.TemporaryDirectory() as td:
                out=Path(td)/'outputs'
                r=subprocess.run(['bash','-e','-c',accept],env={**os.environ,**env,**update,'GITHUB_OUTPUT':str(out)})
                self.assertEqual(r.returncode==0,passed)
                self.assertEqual(out.exists(),passed)
        attempt({},True)
        for k in ('CRAZYGAMES_ARTIFACT','CRAZYGAMES_EVIDENCE','GATE_EVIDENCE','SIBLING_REQUIRED','SIBLING_VERIFIED'):
            attempt({k:''},False)
        for val in ('skipped','cancelled','failure'):
            attempt({'CRAZYGAMES':val},False)
        attempt({'SIBLING_REQUIRED':'false'},False)
        attempt({'SIBLING_REQUIRED':'false','CRAZYGAMES':'skipped','CRAZYGAMES_ARTIFACT':'','CRAZYGAMES_EVIDENCE':'','SIBLING_VERIFIED':'skipped'},True)

    def test_real_receipt_cross_artifact_and_stage_mutations(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td); ev=root/'crazygames-build/evidence';ev.mkdir(parents=True)
            wm=root/'web-build/web/release-manifest.json';wm.parent.mkdir(parents=True)
            sf=root/'engine-evidence/summary.json';sf.parent.mkdir();sf.write_text('full suite')
            packet=root/'crazygames-stage.json';packet.write_text('fixed packet')
            a=root/'crazygames-build/web/crazygames-manifest.json';a.parent.mkdir()
            rev=lambda ref:subprocess.check_output(['git','-C',str(ROOT),'rev-parse',ref],text=True).strip()
            commit=rev('HEAD');tree=rev('HEAD^{tree}');env={'GITHUB_SHA':commit,'GITHUB_EVENT_NAME':'pull_request','GITHUB_RUN_ID':'99','GITHUB_RUN_ATTEMPT':'2','CI_INPUTS_ID':'57','VARIANT_ID':'58'}
            base={'source_tree':tree,'source_commit':commit,'toolchain_verification':'checksum-pinned-official-archives'}
            wm.write_text(json.dumps({**base,'workflow_run':'99','workflow_attempt':'2','packed_smoke':'passed','tag':'','engine_checks':17,'test_report_sha256':proof.sha(sf)}))
            report={'platform':'crazygames','existing_web_gate_checks':17,**base,'save_variant':{'name':'production'},'stages':[{'stage':n,'exit_code':0} for n in proof.STAGES]}
            data=json.dumps(report);(ev/'export-report.json').write_text(data)
            for n in proof.STAGES:(ev/(n+'.log')).write_text('SCENE_READY furniture=1' if n=='packed-smoke' else 'good')
            a.write_text('different variant');self.assertRaises(ValueError,proof.bind,root,env,'record');a.write_text(data)

            proof.bind(root,env,'record');proof.bind(root,env,'verify')
            (ev/proof.NAME).unlink()
            main={**env,'GITHUB_EVENT_NAME':'push','GITHUB_REF':'refs/heads/main','CI_ORDINARY_MAIN_VARIANT':'true'}
            proof.bind(root,main,'record');proof.bind(root,main,'verify')
            for update in ({'GITHUB_REF':'refs/tags/v0.1.11'}, {'GITHUB_REF':'refs/heads/qa'},
                           {'GITHUB_EVENT_NAME':'workflow_dispatch'}, {'CI_ORDINARY_MAIN_VARIANT':'false'}):
                self.assertRaises(ValueError,proof.bind,root,{**main,**update},'verify')
            tag_manifest=wm.read_bytes(); tagged=json.loads(tag_manifest); tagged['tag']='v0.1.11'
            wm.write_text(json.dumps(tagged));self.assertRaises(ValueError,proof.bind,root,main,'verify')
            wm.write_bytes(tag_manifest)
            for k,v in [('VARIANT_ID','9'),('CI_INPUTS_ID','9'),('GITHUB_RUN_ATTEMPT','3'),('GITHUB_SHA','0'*40)]:
                self.assertRaises(ValueError,proof.bind,root,{**env,k:v},'verify')
            for path in [wm,sf,ev/'export.log',ev/'packed-smoke.log',packet]:
                old=path.read_bytes();path.write_bytes(old+b' ');self.assertRaises(ValueError,proof.bind,root,env,'verify');path.write_bytes(old)
            (ev/'ack.log').unlink();self.assertRaises(ValueError,proof.bind,root,env,'verify')
