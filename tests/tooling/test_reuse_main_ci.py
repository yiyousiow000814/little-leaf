"""Synthetic provenance/ZIP/package contracts; no account, game or upload."""
import copy
import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import urllib.request
import zipfile

import reuse_main_ci as reuse

SHA, TREE = 'a' * 40, 'b' * 40


def run():
    return dict(id=7, run_attempt=2, head_sha=SHA, workflow_id=3, event='push', head_branch='main',
        repository={'full_name': reuse.REPOSITORY}, head_repository={'full_name': reuse.REPOSITORY},
        status='completed', conclusion='success')


class API:
    def __init__(self):
        self.runs = [run()]
        self.jobs = [dict(name=n, status='completed', conclusion='success') for n in reuse.REQUIRED_JOBS]
        self.jobs.append(dict(name='web / firebase', status='completed', conclusion='skipped'))
        self.artifacts = [dict(id=11, name=f'little-leaf-web-{SHA}-2', expired=False,
            digest='sha256:' + 'c' * 64, workflow_run={'id': 7, 'head_sha': SHA})]

    def read(self, path):
        return dict(id=3, path=reuse.WORKFLOW, state='active')

    def pages(self, path, key):
        return {'workflow_runs': self.runs, 'jobs': self.jobs, 'artifacts': self.artifacts}[key]


class QualificationTests(unittest.TestCase):
    def test_exact_main_qualification(self):
        self.assertEqual(reuse.resolve(API(), SHA, 0)[1]['id'], 11)

    def test_rejects_other_commit_pr_fork_branch_or_workflow(self):
        for field, value in [('head_sha', 'd' * 40), ('event', 'pull_request'),
            ('head_branch', 'candidate'), ('workflow_id', 4),
            ('head_repository', {'full_name': 'fork/little-leaf'})]:
            api = API(); api.runs[0][field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                reuse.resolve(api, SHA, 0)

    def test_rejects_failed_or_incomplete_qualification(self):
        for mutate in [lambda a: a.runs[0].update(conclusion='failure'),
                       lambda a: a.jobs.pop(),
                       lambda a: a.jobs[0].update(conclusion='cancelled'),
                       lambda a: a.jobs.append(copy.deepcopy(a.jobs[0]))]:
            api = API(); mutate(api)
            # Removing the optional Firebase job is harmless; remove a required one.
            if len(api.jobs) == len(reuse.REQUIRED_JOBS): api.jobs.pop(0)
            with self.assertRaises(ValueError): reuse.resolve(api, SHA, 0)

    def test_rejects_missing_expired_undigested_or_other_run_artifact(self):
        for mutate in [lambda a: a.artifacts.clear(), lambda a: a.artifacts[0].update(expired=True),
            lambda a: a.artifacts[0].update(digest=''),
            lambda a: a.artifacts[0]['workflow_run'].update(id=8),
            lambda a: a.artifacts.append(copy.deepcopy(a.artifacts[0]))]:
            api = API(); mutate(api)
            with self.assertRaises(ValueError): reuse.resolve(api, SHA, 0)

    def test_waits_existing_run_without_starting_matrix(self):
        api = API(); api.runs[0].update(status='in_progress', conclusion=None)
        elapsed = [0]
        def sleep(seconds):
            elapsed[0] += seconds; api.runs[0].update(status='completed', conclusion='success')
        with patch('builtins.print'):
            self.assertEqual(reuse.resolve(api, SHA, 30, clock=lambda: elapsed[0], sleep=sleep)[0]['id'], 7)
        self.assertEqual(elapsed[0], 15)

    def test_latest_failed_run_does_not_fall_back_to_old_green(self):
        api = API(); failed = run(); failed.update(id=8, conclusion='failure'); api.runs.append(failed)
        with self.assertRaises(ValueError): reuse.resolve(api, SHA, 0)

    def test_redirect_never_forwards_github_authorization(self):
        request = urllib.request.Request('https://api.github.com/artifact', headers={'Authorization': 'Bearer fake'})
        redirected = reuse.NoAuthorizationRedirect().redirect_request(request, None, 302, '', {},
            'https://artifact.example.invalid/file')
        self.assertIsNone(redirected.get_header('Authorization'))
        with self.assertRaises(ValueError):
            reuse.NoAuthorizationRedirect().redirect_request(request, None, 302, '', {}, 'http://unsafe/file')


class ArchiveTests(unittest.TestCase):
    def archive(self, names):
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, 'w') as z:
            for name in names: z.writestr(name, b'synthetic')
        return buf.getvalue()

    def test_digest_and_flat_inventory(self):
        data = self.archive(['index.html'])
        with tempfile.TemporaryDirectory() as folder:
            out = Path(folder) / 'web'
            with self.assertRaises(ValueError): reuse.extract(data, '0' * 64, out)
            self.assertFalse(out.exists())
            reuse.extract(data, hashlib.sha256(data).hexdigest(), out)
            self.assertEqual((out / 'index.html').read_bytes(), b'synthetic')

    def test_rejects_unsafe_case_collisions_and_symlink(self):
        for names in [['../escape'], ['/absolute'], ['a/b'], ['C:bad'], ['a\\b'],
                      ['index.html', 'INDEX.HTML']]:
            data = self.archive(names)
            with tempfile.TemporaryDirectory() as folder, self.assertRaises(ValueError):
                reuse.extract(data, hashlib.sha256(data).hexdigest(), Path(folder) / 'web')
        member = zipfile.ZipInfo('link'); member.external_attr = 0o120777 << 16
        data = self.archive([member])
        with tempfile.TemporaryDirectory() as folder, self.assertRaises(ValueError):
            reuse.extract(data, hashlib.sha256(data).hexdigest(), Path(folder) / 'web')


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name); self.web = self.root / 'web'; self.web.mkdir()
        (self.root / 'game/data').mkdir(parents=True)
        (self.root / 'game/project.godot').write_text('config/version="0.1.10c"\n')
        (self.root / 'game/data/release_notes.json').write_text(json.dumps(dict(version='0.1.10c',
            status='released', date='2026-10-10', fixed=['Synthetic fixture'])))
        (self.root / 'notice.txt').write_bytes(b'notice')
        payload = {'index.html': b'ordinary', 'index.js': b'engine', 'index.wasm': b'\0asm',
                   'index.pck': b'GDPC', 'NOTICE.txt': b'notice'}
        for name, data in payload.items(): (self.web / name).write_bytes(data)
        self.manifest = dict(source_commit=SHA, source_tree=TREE, version='0.1.10c', tag='',
            workflow_run='7', workflow_attempt='2', packed_smoke='passed', engine_checks=1,
            test_processes=1, toolchain_verification='checksum-pinned-official-archives',
            production_sha256={name: reuse.sha256(self.root / 'game' / name)
                               for name in ['project.godot', 'data/release_notes.json']},
            files={n: dict(sha256=hashlib.sha256(d).hexdigest(), bytes=len(d)) for n, d in payload.items()})

    def bind(self):
        (self.web / 'release-manifest.json').write_text(json.dumps(self.manifest))
        with patch.object(reuse, 'REQUIRED_NOTICES', {'notice.txt': 'NOTICE.txt'}), \
             patch.object(reuse.subprocess, 'check_output', return_value=
                          b'game/project.godot\0game/data/release_notes.json\0'):
            return reuse.bind_package(self.web, self.root, SHA, TREE, run(), 'v0.1.10c')

    def test_exact_package_before_release_tag_metadata(self):
        self.assertEqual(self.bind()['tag'], '')

    def test_rejects_pr_synthetic_sha_tree_version_run_or_local_tools(self):
        for field, value in [('source_commit', 'd' * 40), ('source_tree', 'e' * 40),
            ('version', '0.1.10b'), ('workflow_run', '8'), ('workflow_attempt', '1'),
            ('toolchain_verification', 'local-tools-unverified-for-release')]:
            original = self.manifest[field]; self.manifest[field] = value
            with self.subTest(field=field), self.assertRaises(ValueError): self.bind()
            self.manifest[field] = original

    def test_rejects_changed_payload_source_or_missing_inventory(self):
        (self.web / 'index.js').write_bytes(b'changed')
        with self.assertRaises(ValueError): self.bind()
        (self.web / 'index.js').write_bytes(b'engine')
        self.manifest['production_sha256'].pop('project.godot')
        with self.assertRaises(ValueError): self.bind()


class WorkflowTests(unittest.TestCase):
    def test_release_removes_duplicate_matrix_retains_final_checks_and_publishing(self):
        root = Path(__file__).resolve().parents[2]
        text = (root / '.github/workflows/release-itch.yml').read_text()
        self.assertNotIn('uses: ./.github/workflows/build-web.yml', text)
        for required in ['tools/reuse_main_ci.py', 'tools/verify_prebaked_atlases.py',
            '--require-main-ancestor', 'digest-mismatch: error', 'tools/publish_itch.py',
            'little-leaf-itch-publication-', 'actions: read']:
            self.assertIn(required, text)
        self.assertNotIn('actions: write', text)
        self.assertNotIn('id-token:', text)
        self.assertEqual(text.count('BUTLER_API_KEY: ${{ secrets.BUTLER_API_KEY }}'), 2)


if __name__ == '__main__':
    unittest.main()
