"""The full PR may overlap, but the original command and successful exact-attempt proof are mandatory."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

import yaml
from tools.ci.pr_ci_scope import preflight_join
from tools.qualification.reuse_main_ci import REQUIRED_JOBS, require_jobs

ROOT = Path(__file__).resolve().parents[2]
SHA = 'a' * 40


class PreflightOverlapTests(unittest.TestCase):
    def test_route_and_exact_attempt_join(self):
        bound = {'CI_SCOPE':'full', 'ORDINARY_PR':'true', 'GITHUB_EVENT_NAME':'pull_request', 'GITHUB_SHA':SHA,
                 'GITHUB_RUN_ID':'7', 'GITHUB_RUN_ATTEMPT':'2', 'INLINE_PREFLIGHT':'skipped', 'PREFLIGHT':'success',
                 'PREFLIGHT_BINDING':f'{SHA}:7:2'}
        self.assertTrue(preflight_join(bound))
        for k in bound:
            self.assertFalse(preflight_join({n:v for n,v in bound.items() if n!=k}), k)
        for k, bad in [('PREFLIGHT','failure'), ('PREFLIGHT','cancelled'), ('PREFLIGHT','skipped'),
                       ('INLINE_PREFLIGHT','success'), ('GITHUB_EVENT_NAME','push'), ('GITHUB_SHA','b'*40),
                       ('GITHUB_RUN_ID','8'), ('GITHUB_RUN_ATTEMPT','1'), ('PREFLIGHT_BINDING','')]:
            self.assertFalse(preflight_join(bound | {k:bad}), k)
        for scope, ordinary in [('lightweight','true'), ('full','false')]:
            inline=bound | {'CI_SCOPE':scope, 'ORDINARY_PR':ordinary, 'INLINE_PREFLIGHT':'success',
                           'PREFLIGHT':'skipped', 'PREFLIGHT_BINDING':''}
            self.assertTrue(preflight_join(inline))
            if scope == "lightweight":
                self.assertFalse(preflight_join(inline | {"ORDINARY_PR":"false"}))
                self.assertFalse(preflight_join(inline | {"GITHUB_EVENT_NAME":"push"}))
            for k,bad in [('PREFLIGHT','success'), ('PREFLIGHT','failure'), ('INLINE_PREFLIGHT','skipped'),
                          ('INLINE_PREFLIGHT','failure'), ('PREFLIGHT_BINDING','stale')]:
                self.assertFalse(preflight_join(inline | {k:bad}))

    def test_named_sibling_and_both_consumers_use_same_guard_before_outputs(self):
        jobs=yaml.safe_load((ROOT/'.github/workflows/build-web.yml').read_text())['jobs']
        sibling,guard=jobs['preflight'],jobs['guard']
        self.assertEqual(sibling['needs'], 'guard')
        self.assertEqual(sibling['if'], "needs.guard.outputs.scope == 'full' && needs.guard.outputs.ordinary_pr == 'true'")
        inline=next(s for s in guard['steps'] if s.get('id')=='inline_preflight')
        self.assertEqual(inline['if'], "steps.scope.outputs.scope != 'full' || steps.engine_plan.outputs.ordinary_pr != 'true'")
        self.assertEqual(guard['outputs']['inline_preflight'], '${{ steps.inline_preflight.outcome }}')
        self.assertEqual(sibling['steps'][0],guard['steps'][0])
        once=next(s for s in sibling['steps'] if s.get('run')=='python3 tools/ci/preflight.py')
        self.assertEqual(once,{k:v for k,v in inline.items() if k not in ('id','if')})
        self.assertEqual(sibling['steps'][-1]['id'],'bind')
        self.assertEqual(sibling['outputs']['binding'], '${{ steps.bind.outputs.binding }}')
        self.assertEqual(jobs['engine']['needs'], 'guard');self.assertEqual(jobs['historical']['needs'],'guard')
        self.assertEqual(jobs['build']['needs'],['guard','preflight','engine','browser_packages'])
        check=lambda job:next(s for s in job['steps'] if s.get('run')=='python3 tools/ci/pr_ci_scope.py --check-preflight-join')
        for name in ('build','gate'):
            job=jobs[name];self.assertIn('preflight',job['needs']);self.assertEqual(job['steps'].index(check(job)),1)
        self.assertEqual(check(jobs['build']),check(jobs['gate']))
        self.assertEqual(check(jobs['gate'])['env']['PREFLIGHT_BINDING'],'${{ needs.preflight.outputs.binding }}')

    def test_actual_binding_rejects_wrong_checkout_and_dirty_source(self):
        job=yaml.safe_load((ROOT/'.github/workflows/build-web.yml').read_text())['jobs']['preflight']
        with tempfile.TemporaryDirectory() as td:
            td=Path(td);g=lambda *a:subprocess.check_output(['git',*a],cwd=td,text=True).strip()
            g('init','-q');f=td/'source';f.write_text('baseline');g('add','source')
            g('-c','user.name=test','-c','user.email=test@example.invalid','commit','-qm','fixture')
            commit=g('rev-parse','HEAD');out=td/'receipt'
            def run(sha):
                return subprocess.run(['bash','-e','-c',job['steps'][-1]['run']],cwd=td,
                                      env={**os.environ,'GITHUB_OUTPUT':str(out),'GITHUB_SHA':sha,
                                           'GITHUB_RUN_ID':'7','GITHUB_RUN_ATTEMPT':'2'}).returncode
            self.assertNotEqual(run('0'*40),0);self.assertFalse(out.exists())
            self.assertEqual(run(commit),0);self.assertEqual(out.read_text().strip(),f'binding={commit}:7:2')
            out.unlink();f.write_text('modified');self.assertNotEqual(run(commit),0);self.assertFalse(out.exists())

    def test_optional_pr_preflight_does_not_skip_required_non_pr_consumers(self):
        workflow = yaml.safe_load((ROOT / ".github/workflows/build-web.yml").read_text())
        jobs = workflow["jobs"]
        lanes = {
            "play": ["build"],
            "browser": ["build"],
            "compatibility": ["build", "historical"],
            "firebase": ["build", "play", "browser", "compatibility"],
        }
        for name, required in lanes.items():
            with self.subTest(job=name):
                needs = jobs[name]["needs"]
                self.assertEqual([needs] if isinstance(needs, str) else needs, required)
                terms = ["!cancelled()"]
                if name == "firebase":
                    terms.append("inputs.firebase_preview")
                terms += [f"needs.{dep}.result == 'success'" for dep in required]
                self.assertEqual(jobs[name]["if"], "${{ " + " && ".join(terms) + " }}")
        self.assertEqual(jobs["gate"]["if"], "always()")
        self.assertIn("needs.guard.outputs.ordinary_pr == 'true'", jobs["preflight"]["if"])

    def test_trusted_main_only_recognizes_exact_skipped_optional_name(self):
        base=[{'name':n,'status':'completed','conclusion':'success'} for n in REQUIRED_JOBS]
        sibling={'name':'web / preflight','status':'completed','conclusion':'skipped'}
        require_jobs(base, event='push'); require_jobs(base+[sibling], event='push')
        for change in [{'status':'queued'},{'conclusion':'success'},{'conclusion':'failure'},
                       {'conclusion':'cancelled'},{'name':'web / other preflight'}]:
            self.assertRaises(ValueError,require_jobs,base+[sibling|change], event='push')
        self.assertRaises(ValueError,require_jobs,base+[sibling,sibling], event='push')
