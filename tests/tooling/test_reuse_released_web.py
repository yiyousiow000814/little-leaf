"""Original publication identity stays pinned even if newer CI exists."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import reuse_released_web as pinned
from tests.tooling.test_firebase_release_event import archive, API as EventAPI


class API(EventAPI):
    def __init__(self):
        super().__init__()
        self.original = {'source_commit': 'a' * 40, 'source_tree': 'b' * 40,
                         'version': '0.1.10b', 'tag': '', 'files': {}}
        self.bytes = json.dumps(self.original).encode()
        self.package = archive({'release-manifest.json': self.bytes})
        self.receipt['qualified_manifest_sha256'] = hashlib.sha256(self.bytes).hexdigest()
        self.receipt['artifact_digest'] = 'sha256:' + hashlib.sha256(self.package).hexdigest()
        self.queries = []
        self.artifact = {'id': 30, 'name': 'little-leaf-web-' + 'a' * 40 + '-1', 'expired': False,
            'workflow_run': {'id': 20, 'head_sha': 'a' * 40}, 'digest': self.receipt['artifact_digest']}

    def read(self, path, binary=False):
        self.queries.append(path)
        if path == 'actions/artifacts/30/zip': return self.package
        return super().read(path, binary)

    def pages(self, path, key):
        self.queries.append(path)
        if key == 'artifacts': return [self.artifact]
        return super().pages(path, key)


class PinnedReuseTests(unittest.TestCase):
    def selection(self, api):
        return {'source_commit': 'a' * 40, 'source_tree': 'b' * 40, 'qualification': api.receipt}

    def test_reuses_original_run_and_artifact_without_searching_newer_ci(self):
        api = API()
        with tempfile.TemporaryDirectory() as d, patch.object(pinned, 'source_identity'), \
                patch.object(pinned.reuse, 'bind_package', return_value=api.original), \
                patch.object(pinned.reuse, 'packed_smoke') as startup, \
                patch.object(pinned.reuse, 'validate_export_inventory'):
            receipt = pinned.prepare(api, Path(d), self.selection(api), Path(d) / 'output')
            self.assertEqual(receipt['qualification_run_id'], 20)
            self.assertEqual(receipt['artifact_id'], 30)
            self.assertEqual(receipt['tag'], '')
            startup.assert_called_once()
            self.assertNotIn('actions/runs', api.queries)
            self.assertIn('actions/runs/20/attempts/1/jobs', api.queries)

    def test_refuses_original_artifact_change_expiry_or_run_rerun(self):
        for mode in ['expired', 'changed', 'attempt']:
            api = API()
            if mode == 'expired': api.artifact['expired'] = True
            elif mode == 'changed': api.artifact['id'] = 31
            else: api.qualification['run_attempt'] = 2
            with tempfile.TemporaryDirectory() as d, patch.object(pinned, 'source_identity'), \
                    self.subTest(mode=mode), self.assertRaises(ValueError):
                pinned.prepare(api, Path(d), self.selection(api), Path(d) / 'output')


if __name__ == '__main__':
    unittest.main()
