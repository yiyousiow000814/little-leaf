"""Synthetic completed-publication and unsafe ZIP rejection; no deploy or credentials."""
import copy
import base64
import hashlib
import io
import json
import stat
import struct
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from release import firebase_release_event as event
from release import common_firebase
from tests.tooling import test_firebase_release_gate as gate_fixture
from qualification.reuse_main_ci import REQUIRED_JOBS
from unittest.mock import Mock


def archive(files):
    output = io.BytesIO()
    with zipfile.ZipFile(output, 'w') as z:
        for name, value in files.items():
            z.writestr(name, value)
    return output.getvalue()


class API:
    def __init__(self):
        fixture = gate_fixture.FirebaseReleaseGateTests(); fixture.setUp()
        self.args = fixture.args
        self.release = self.args['release_run']
        self.qualification = self.args['qualification_run']
        self.receipt = {**self.args['qualification_receipt'], 'tag': 'v0.1.10b',
                        'qualified_payload_unchanged': True}
        self.publication = {'qualification': self.receipt, 'state': 'completed', 'itch_build_id': 123,
            'source_commit': 'a' * 40, 'tag': 'v0.1.10b', 'version': '0.1.10b',
            'target': 'siowyiyou/little-leaf:html5', 'workflow_run': '10', 'workflow_attempt': '1',
            'release_manifest_sha256': 'f' * 64}
        self.status = 'ahead'
        self.project_version = '0.1.10b'

    def release_artifacts(self):
        return [dict(id=i, name=f'little-leaf-{kind}-' + 'a' * 40 + '-1', expired=False,
            workflow_run={'id': 10, 'head_sha': 'a' * 40},
            digest='sha256:' + hashlib.sha256(self.data(i)).hexdigest())
            for i, kind in [(40, 'itch-publication'), (41, 'release-qualification')]]

    def data(self, identity):
        value, name = (self.publication, 'receipt.json') if identity == 40 else (self.receipt, 'qualification.json')
        return archive({name: json.dumps(value)})

    def read(self, path, binary=False):
        if path == 'actions/runs/10': return self.release
        if path == 'actions/runs/20': return self.qualification
        if path.startswith('git/ref/'): return {'object': {'type': 'commit', 'sha': 'a' * 40}}
        if path.startswith('git/commits/'): return {'tree': {'sha': 'b' * 40}}
        if path.startswith('compare/'): return {'status': self.status}
        if path.startswith('contents/game/'):
            data = ('config/version="' + self.project_version + '"\n') if 'project.godot' in path else json.dumps(
                {'version': self.project_version, 'status': 'released', 'date': '2000-01-01', 'fixed': ['fixture']})
            return {'encoding': 'base64', 'content': base64.b64encode(data.encode()).decode()}
        if path == 'actions/artifacts/30':
            return {**self.args['qualification_artifact'],
                'name': 'little-leaf-web-' + 'a' * 40 + '-1', 'workflow_run': {'id': 20, 'head_sha': 'a' * 40}}
        if path.endswith('/zip'): return self.data(int(path.split('/')[2]))
        raise AssertionError(path)

    def pages(self, path, key):
        if key == 'jobs':
            return self.args['publish_jobs'] if '/10/' in path else [
                {'name': n, 'status': 'completed', 'conclusion': 'success'} for n in REQUIRED_JOBS]
        return self.release_artifacts()


class ReleaseEventTests(unittest.TestCase):
    def test_producer_budget_preserves_payload_and_checks_both_boundaries(self):
        with tempfile.TemporaryDirectory() as d:
            folder = Path(d); (folder / 'runtime').write_bytes(b'audio-fixture' * 4096)
            before = (folder / 'runtime').read_bytes()
            measured = event.check_firebase_packet_budget(folder)
            self.assertEqual(measured['expanded_bytes'], len(before))
            self.assertEqual(measured['member_count'], 1)
            self.assertEqual((folder / 'runtime').read_bytes(), before)
            for expanded, compressed, accepted in [
                    (len(before), measured['compressed_bytes_with_reserve'], True),
                    (len(before) - 1, measured['compressed_bytes_with_reserve'], False),
                    (len(before), measured['compressed_bytes_with_reserve'] - 1, False)]:
                with self.subTest(expanded=expanded, compressed=compressed), \
                        patch.object(event, 'FIREBASE_PACKET_EXPANDED_BYTES', expanded), \
                        patch.object(event, 'MAX_FIREBASE_ARTIFACT_BYTES', compressed):
                    if accepted: event.check_firebase_packet_budget(folder)
                    else:
                        with self.assertRaises(ValueError): event.check_firebase_packet_budget(folder)

    def test_producer_budget_refuses_member_count_and_symlinks_before_compression(self):
        folder = Mock(); item = Mock(); item.is_symlink.return_value = False
        item.is_file.return_value = True; item.stat.return_value.st_size = 1
        folder.rglob.return_value = [item] * 5001
        with patch.object(event.zipfile, 'ZipFile') as compressed, self.assertRaises(ValueError):
            event.check_firebase_packet_budget(folder)
        compressed.assert_not_called()
        item.is_symlink.return_value = True; folder.rglob.return_value = [item]
        with self.assertRaises(ValueError): event.check_firebase_packet_budget(folder)

    def firebase_artifact(self, data):
        return {'id': 7, 'name': 'little-leaf-firebase-' + 'a' * 40 + '-1',
            'expired': False, 'size_in_bytes': len(data),
            'digest': 'sha256:' + hashlib.sha256(data).hexdigest(),
            'workflow_run': {'id': 3, 'head_sha': 'a' * 40}}

    def coordinator_fixture(self):
        data = archive({'firebase-variant-manifest.json': json.dumps({'source_commit': 'a' * 40}),
                        'public/hosting-release.json': json.dumps({'tag': 'v0.1.11-pre.aaaaaaaa'})})
        artifact = self.firebase_artifact(data)
        artifact['workflow_run']['head_sha'] = 'c' * 40
        run = {'id': 3, 'run_attempt': 1, 'head_sha': 'c' * 40, 'head_branch': 'main',
               'repository': {'full_name': event.REPOSITORY},
               'head_repository': {'full_name': event.REPOSITORY},
               'path': common_firebase.WORKFLOW, 'event': 'workflow_run',
               'status': 'completed', 'conclusion': 'success'}
        return data, artifact, run

    def test_common_consumer_keeps_candidate_separate_from_qualified_coordinator(self):
        data, artifact, run = self.coordinator_fixture()
        before = copy.deepcopy((artifact, run))
        api = Mock()
        api.pages.return_value = [artifact]
        api.read.side_effect = lambda path, **kwargs: {
            'actions/runs/3': run, 'actions/runs/3/attempts/1': run,
            'actions/artifacts/7/zip': data}[path]
        with tempfile.TemporaryDirectory() as d:
            output = Path(d) / 'selected'
            with patch('sys.argv', ['common_firebase.py', '--run', '3', '--platform', 'itch',
                                   '--output', str(output)]), \
                    patch.dict(event.os.environ, {'GH_TOKEN': '', 'GITHUB_OUTPUT': str(Path(d) / 'outputs')}), \
                    patch.object(common_firebase, 'GitHub', return_value=api), \
                    patch.object(common_firebase, 'authenticate_packet', return_value={'run': run, 'artifact': artifact}):
                common_firebase.main()
            self.assertEqual(json.loads((output / 'status.json').read_text())['source_commit'], 'a' * 40)
            self.assertEqual(json.loads((output / 'origin.json').read_text())['run']['head_sha'], 'c' * 40)
            self.assertEqual((artifact, run), before)
            api.read.assert_any_call('actions/artifacts/7/zip', binary=True, artifact_bytes=len(data))

    def test_qualified_coordinator_context_refuses_wrong_run_attempt_workflow_and_repository(self):
        data, artifact, run = self.coordinator_fixture()
        changes = [('id', 4), ('head_sha', 'd' * 40), ('head_branch', 'another'), ('run_attempt', 2),
                   ('status', 'in_progress'), ('conclusion', 'failure'), ('event', 'push'),
                   ('path', '.github/workflows/another.yml'),
                   ('repository', {'full_name': 'another/repository'}),
                   ('head_repository', {'full_name': 'another/repository'})]
        for field, value in changes:
            api = Mock()
            with self.subTest(field=field), tempfile.TemporaryDirectory() as d:
                with self.assertRaises(ValueError):
                    event.download(api, artifact, Path(d) / 'out', qualified_run={**run, field: value})
                api.read.assert_not_called()
                self.assertFalse((Path(d) / 'out').exists())
        api = Mock()
        with tempfile.TemporaryDirectory() as d, self.assertRaises(ValueError):
            event.download(api, {**artifact, 'name': 'little-leaf-web-' + 'a' * 40 + '-1'},
                           Path(d) / 'out', qualified_run=run)
        api.read.assert_not_called()

    def test_firebase_profile_uses_exact_metadata_size_ordinary_profile_unchanged(self):
        data = archive({'firebase-variant-manifest.json': '{}'})
        api = Mock(); api.read.return_value = data
        with tempfile.TemporaryDirectory() as d:
            event.download(api, self.firebase_artifact(data), Path(d) / 'firebase')
            api.read.assert_called_once_with('actions/artifacts/7/zip', binary=True, artifact_bytes=len(data))
            api.read.reset_mock()
            ordinary = {**self.firebase_artifact(data), 'name': 'little-leaf-web-' + 'a' * 40 + '-1'}
            event.download(api, ordinary, Path(d) / 'ordinary')
            api.read.assert_called_once_with('actions/artifacts/7/zip', binary=True)

    def test_firebase_profile_refuses_bad_origin_digest_size_and_truncated_body(self):
        data = archive({'firebase-variant-manifest.json': '{}'})
        for field, value in [('id', True), ('expired', True), ('digest', 'unknown'),
                ('size_in_bytes', True), ('size_in_bytes', 0),
                ('size_in_bytes', event.MAX_FIREBASE_ARTIFACT_BYTES + 1),
                ('workflow_run', {'id': 3, 'head_sha': 'b' * 40})]:
            api = Mock(); api.read.return_value = data
            with self.subTest(field=field), tempfile.TemporaryDirectory() as d:
                with self.assertRaises(ValueError):
                    event.download(api, {**self.firebase_artifact(data), field: value}, Path(d) / 'out')
                api.read.assert_not_called()
        for body in [data[:-1], data + b'x', data[:-1] + bytes([data[-1] ^ 1])]:
            api = Mock(); api.read.return_value = body
            with self.subTest(size=len(body)), tempfile.TemporaryDirectory() as d:
                with self.assertRaises(ValueError): event.download(api, self.firebase_artifact(data), Path(d) / 'out')
                self.assertFalse((Path(d) / 'out').exists())

    def test_firebase_profile_retains_decompression_count_path_and_symlink_bounds(self):
        data = archive({'small': 'x'})
        central = data.index(b'PK\x01\x02')
        # Hostile ZIP directory declares a bomb; refusal occurs before writes.
        bomb = bytearray(data)
        struct.pack_into('<I', bomb, central + 24, event.FIREBASE_PACKET_EXPANDED_BYTES + 1)
        for hostile in [bytes(bomb), archive({'../outside': 'x'}), archive({'A': 'x', 'a': 'x'})]:
            with self.subTest(size=len(hostile)), tempfile.TemporaryDirectory() as d:
                with self.assertRaises(ValueError):
                    event.extract_tree(hostile, 'sha256:' + hashlib.sha256(hostile).hexdigest(), Path(d) / 'out', firebase_packet=True)
                self.assertFalse((Path(d) / 'out').exists())
        symlink = zipfile.ZipInfo('link'); symlink.external_attr = (stat.S_IFLNK | 0o777) << 16
        for hostile in [archive({symlink: 'target'}), archive({str(i): 'x' for i in range(5001)})]:
            with tempfile.TemporaryDirectory() as d, self.assertRaises(ValueError):
                event.extract_tree(hostile, 'sha256:' + hashlib.sha256(hostile).hexdigest(), Path(d) / 'out', firebase_packet=True)

    def test_reservation_queries_only_exact_name_and_rejects_expired_intent(self):
        api = API()
        name = 'little-leaf-firebase-request-10'
        with patch.dict(event.os.environ, {'GITHUB_RUN_ATTEMPT': '1'}):
            with patch.object(api, 'pages', return_value=[]) as pages:
                event.reserve(api, 10)
                pages.assert_called_once_with('actions/artifacts?name=' + name, 'artifacts')
            for expired in (False, True):
                with patch.object(api, 'pages', return_value=[{'name': name, 'expired': expired}]), self.assertRaises(ValueError):
                    event.reserve(api, 10)
        with patch.dict(event.os.environ, {'GITHUB_RUN_ATTEMPT': '2'}), self.assertRaises(ValueError):
            event.reserve(api, 10)

    def select(self, api):
        with tempfile.TemporaryDirectory() as d:
            return event.select(api, 10, Path(d))

    def test_completed_receipt_selects_same_source_with_no_live_permission(self):
        result = self.select(API())
        self.assertEqual(result['source_commit'], 'a' * 40)
        self.assertEqual(result['publication']['itch_build_id'], 123)
        self.assertFalse(result['dispatch_allowed'])
        self.assertEqual(result['live_status'], 'security-cutover-blocked')

    def test_rejects_pending_failed_unknown_or_wrong_publication(self):
        for key, value in [('state', 'processing'), ('itch_build_id', True), ('itch_build_id', 0),
            ('workflow_attempt', '2'), ('target', 'another/game:html5'), ('source_commit', 'e' * 40),
            ('tag', 'v0.1.11'), ('version', '0.1.10a'), ('release_manifest_sha256', 'unknown')]:
            api = API(); api.publication[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError): self.select(api)

    def test_rejects_tag_not_in_main_or_failed_release(self):
        api = API(); api.status = 'diverged'
        with self.assertRaises(ValueError): self.select(api)

    def test_reads_immutable_tagged_project_version(self):
        api = API(); api.project_version = '0.1.11'
        with self.assertRaises(ValueError): self.select(api)
        api = API(); api.release['conclusion'] = 'failure'
        with self.assertRaises(ValueError): self.select(api)

    def test_rejects_qualification_different_from_completed_publication(self):
        api = API(); api.publication['qualification'] = copy.deepcopy(api.receipt)
        api.publication['qualification']['artifact_id'] = 31
        with self.assertRaises(ValueError): self.select(api)

    def test_rejects_missing_or_expired_artifact(self):
        api = API()
        with patch.object(api, 'release_artifacts', return_value=[]), self.assertRaises(ValueError):
            self.select(api)
        artifacts = api.release_artifacts(); artifacts[0]['expired'] = True
        with patch.object(api, 'release_artifacts', return_value=artifacts), self.assertRaises(ValueError):
            self.select(api)

    def test_safe_nested_archive_and_digest(self):
        data = archive({'engine-evidence/summary.json': '{}'})
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / 'extract'
            event.extract_tree(data, 'sha256:' + hashlib.sha256(data).hexdigest(), path)
            self.assertEqual((path / 'engine-evidence/summary.json').read_text(), '{}')
            with self.assertRaises(ValueError): event.extract_tree(data, 'sha256:' + 'a' * 64, Path(d) / 'wrong')

    def test_rejects_traversal_absolute_alias_and_case_duplicate_zip(self):
        for name in ['../outside', '/absolute', 'a/../outside', './alias', 'a//alias',
                     'C:/outside', 'a\\outside', '.secret']:
            data = archive({name: 'x'})
            if '\\' in name:
                # Python on Windows normalizes write-time filenames. Model the
                # raw hostile ZIP bytes received from an external producer.
                data = data.replace(name.replace('\\', '/').encode(), name.encode())
            with tempfile.TemporaryDirectory() as d, self.subTest(name=name), self.assertRaises(ValueError):
                event.extract_tree(data, 'sha256:' + hashlib.sha256(data).hexdigest(), Path(d) / 'out')
        data = archive({'A.json': '{}', 'a.json': '{}'})
        with tempfile.TemporaryDirectory() as d, self.assertRaises(ValueError):
            event.extract_tree(data, 'sha256:' + hashlib.sha256(data).hexdigest(), Path(d) / 'out')


if __name__ == '__main__':
    unittest.main()
