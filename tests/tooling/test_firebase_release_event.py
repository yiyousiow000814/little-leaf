"""Synthetic completed-publication and unsafe ZIP rejection; no deploy or credentials."""
import copy
import base64
import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import firebase_release_event as event
from tests.tooling import test_firebase_release_gate as gate_fixture
from reuse_main_ci import REQUIRED_JOBS


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
