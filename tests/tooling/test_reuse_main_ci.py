"""Synthetic provenance/ZIP/package contracts; no account, game or upload."""
import copy
import hashlib
import io
import json
from pathlib import Path
import tempfile
import subprocess
import sys
import unittest
from unittest.mock import patch
import urllib.request
import zipfile

from qualification import reuse_main_ci as reuse

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
    def test_main_download_uses_exact_authenticated_size_above_legacy_default(self):
        # Reproduce the failed release size without allocating another 100-MiB fixture.
        class Payload:
            def __init__(self, size): self.size = size
            def __len__(self): return self.size
        class API:
            def read(self, path, binary=False, *, artifact_bytes=None):
                self.request = (path, binary, artifact_bytes)
                return Payload(artifact_bytes)
        self.assertEqual(reuse.MAX_MAIN_ARTIFACT_BYTES, 512 * 1024 * 1024)
        for size in [106071069, reuse.MAX_MAIN_ARTIFACT_BYTES]:
            api = API()
            result = reuse.download_main_artifact(api, dict(id=11, size_in_bytes=size))
            self.assertEqual(len(result), size)
            self.assertEqual(api.request, ('actions/artifacts/11/zip', True, size))
        self.assertEqual(reuse.DEFAULT_RESPONSE_BYTES, 100 * 1024 * 1024)

    def test_main_download_rejects_unbounded_metadata_and_length_mismatch(self):
        api = reuse.GitHub('synthetic')
        for size in [None, True, 0, -1, 3.0, '3', reuse.MAX_MAIN_ARTIFACT_BYTES + 1]:
            with self.subTest(size=size), patch.object(api.opener, 'open') as opened:
                with self.assertRaisesRegex(ValueError, 'finite ZIP budget'):
                    reuse.download_main_artifact(api, dict(id=11, size_in_bytes=size))
                opened.assert_not_called()
        for payload in [b'xx', b'xxxx']:
            with patch.object(api, 'read', return_value=payload), self.assertRaisesRegex(ValueError, 'authenticated size'):
                reuse.download_main_artifact(api, dict(id=11, size_in_bytes=3))

    def test_main_download_keeps_response_overrun_guard(self):
        class Response:
            def __enter__(self): return self
            def __exit__(self, *unused): pass
            def read(self, size): return b'x' * size
        api = reuse.GitHub('synthetic')
        with patch.object(api.opener, 'open', return_value=Response()):
            with self.assertRaisesRegex(ValueError, 'Response exceeds'):
                reuse.download_main_artifact(api, dict(id=11, size_in_bytes=3))

    def test_future_packet_headroom_remains_exact_and_finite(self):
        class Response:
            def __enter__(self): return self
            def __exit__(self, *unused): pass
            def read(self, size):
                self.requested = size
                return b'synthetic'
        response = Response(); api = reuse.GitHub('synthetic')
        with patch.object(api.opener, 'open', return_value=response):
            api.read('actions/artifacts/1/zip', binary=True, artifact_bytes=512 * 1024 * 1024)
        self.assertEqual(response.requested, 512 * 1024 * 1024 + 1)
        # Exercise metadata headroom without allocating a half-GiB fixture.
        with patch.object(api.opener, 'open') as opened, self.assertRaises(ValueError):
            api.read('actions/artifacts/1/zip', binary=True, artifact_bytes=512 * 1024 * 1024 + 1)
        opened.assert_not_called()

    def test_real_firebase_response_size_has_explicit_finite_zip_budget(self):
        # Actual PR263 qualified archive: 119110054 bytes, larger than the
        # unchanged ordinary reader. Generate only the requested response chunk.
        class Response:
            def __enter__(self): return self
            def __exit__(self, *unused): pass
            def read(self, size): return b'0' * min(size, 119110054)
        api = reuse.GitHub('synthetic')
        with patch.object(api.opener, 'open', return_value=Response()):
            with self.assertRaisesRegex(ValueError, 'Response exceeds'):
                api.read('actions/artifacts/1/zip', binary=True)
            data = api.read('actions/artifacts/1/zip', binary=True, artifact_bytes=119110054)
            self.assertEqual(len(data), 119110054)
            del data
            with self.assertRaisesRegex(ValueError, 'Response exceeds'):
                api.read('actions/artifacts/1/zip', binary=True, artifact_bytes=119110053)

    def test_zip_budget_cannot_expand_json_wrong_paths_or_unbounded_responses(self):
        api = reuse.GitHub('synthetic')
        for path, binary, size in [('actions/runs/1', True, 119110054),
                ('actions/artifacts/1/zip', False, 119110054),
                ('actions/artifacts/01/zip', True, 119110054),
                ('actions/artifacts/1/zip?other=1', True, 119110054),
                ('actions/artifacts/1/zip', True, True),
                ('actions/artifacts/1/zip', True, 0),
                ('actions/artifacts/1/zip', True, reuse.MAX_FIREBASE_ARTIFACT_BYTES + 1)]:
            with self.subTest(path=path, size=size), patch.object(api.opener, 'open') as opened:
                with self.assertRaises(ValueError): api.read(path, binary=binary, artifact_bytes=size)
                opened.assert_not_called()

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

    def test_main_extraction_budget_is_finite_and_crc_still_checked(self):
        data = self.archive(['index.html'])
        digest = hashlib.sha256(data).hexdigest()
        with tempfile.TemporaryDirectory() as folder:
            with patch.object(reuse, 'MAX_MAIN_EXTRACTED_BYTES', 8), self.assertRaisesRegex(ValueError, 'extraction bounds'):
                reuse.extract(data, digest, Path(folder) / 'over')
            with patch.object(reuse, 'MAX_MAIN_EXTRACTED_BYTES', 9):
                reuse.extract(data, digest, Path(folder) / 'at-bound')
            corrupted = bytearray(data)
            with zipfile.ZipFile(io.BytesIO(data)) as archive:
                member = archive.infolist()[0]
                start = member.header_offset + 30 + len(member.filename.encode()) + len(member.extra)
            corrupted[start] ^= 1
            with self.assertRaises(zipfile.BadZipFile):
                reuse.extract(corrupted, hashlib.sha256(corrupted).hexdigest(), Path(folder) / 'bad-crc')
        many = self.archive([str(i) for i in range(501)])
        with tempfile.TemporaryDirectory() as folder, self.assertRaisesRegex(ValueError, 'extraction bounds'):
            reuse.extract(many, hashlib.sha256(many).hexdigest(), Path(folder) / 'many')

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
    def test_direct_entrypoints_resolve_tools_outside_repository_cwd(self):
        root = Path(__file__).resolve().parents[2]
        commands = {
            'reuse_main_ci.py': ['--sha', '--tag', '--output', '--wait-seconds'],
            'reuse_released_web.py': ['--source-root', '--selection', '--output'],
            'reuse_welcome_web.py': ['--phase', '--repository', '--run-id', '--artifact-id'],
        }
        with tempfile.TemporaryDirectory() as folder:
            for name, flags in commands.items():
                with self.subTest(command=name):
                    result = subprocess.run([sys.executable,
                        str(root / 'tools/qualification' / name), '--help'],
                        cwd=folder, capture_output=True, text=True, timeout=10)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    for flag in flags:
                        self.assertIn(flag, result.stdout)

    def test_release_removes_duplicate_matrix_retains_final_checks_and_publishing(self):
        root = Path(__file__).resolve().parents[2]
        text = (root / '.github/workflows/release-itch.yml').read_text()
        self.assertNotIn('uses: ./.github/workflows/build-web.yml', text)
        for required in ['workflows: [Qualify Firebase release]',
            'coordinator/tools/release/common_firebase.py --run "$FIREBASE_RUN" --platform itch',
            'tools/release/publish_itch.py',
            '--web "$RUNNER_TEMP/common-firebase/variant/itch-wrapper"',
            '--firebase-variant "$RUNNER_TEMP/common-firebase/variant"',
            '--staging-origin "$RUNNER_TEMP/common-firebase/origin.json"',
            'little-leaf-itch-publication-', 'actions: read']:
            self.assertIn(required, text)
        self.assertNotIn('actions: write', text)
        self.assertNotIn('id-token:', text)
        diagnostic, publishing = text.split('  publish:', 1)
        self.assertEqual(publishing.count('BUTLER_API_KEY: ${{ secrets.BUTLER_API_KEY }}'), 1)
        self.assertEqual(diagnostic.count('BUTLER_API_KEY: ${{ secrets.BUTLER_API_KEY }}'), 1)
        self.assertIn("github.event_name == 'workflow_dispatch'", diagnostic)
        self.assertIn("github.ref == 'refs/heads/main'", diagnostic)
        self.assertNotIn('publish_itch.py', diagnostic)
        common = (root / '.github/workflows/ci.yml').read_text().split('  common_tag:',1)[1]
        for required in ['tools/qualification/reuse_main_ci.py', 'tools/qualification/verify_prebaked_atlases.py',
                         '--require-main-ancestor','github.event.created && !github.event.deleted']:
            self.assertIn(required,common)
        self.assertIn("github.event_name == 'workflow_run'",publishing)
        self.assertIn("github.event.workflow_run.conclusion == 'success'",publishing)
        self.assertIn("FIREBASE_RUN: ${{ github.event_name == 'workflow_dispatch' && inputs.qualified_run_id || github.event.workflow_run.id }}",publishing)
        self.assertIn("inputs.qualified_run_id != ''",publishing)
        # A rerun must be refused by the job before Butler credentials or upload.
        publish_condition = publishing.split('    runs-on:', 1)[0]
        self.assertIn("github.event_name == 'workflow_dispatch' && github.ref == 'refs/heads/main' && inputs.qualified_run_id != '' && github.run_attempt == 1", publish_condition)
        self.assertIn("inputs.qualified_run_id == ''",diagnostic)
        self.assertIn('ref: ${{ steps.common.outputs.source_sha }}',publishing)
        self.assertLess(publishing.index('git -C coordinator fetch --no-tags origin main'),
                        publishing.index('coordinator/tools/release/common_firebase.py'))
        self.assertLess(publishing.index('--platform itch'),publishing.index('ref: ${{ steps.common.outputs.source_sha }}'))
        self.assertLess(publishing.index('ref: ${{ steps.common.outputs.source_sha }}'),publishing.index('BUTLER_API_KEY:'))
        self.assertNotIn('common_tag.py consume',publishing)
        self.assertNotIn('reuse_main_ci.py',publishing)


if __name__ == '__main__':
    unittest.main()
