"""Fast generated-save archive failures; real IndexedDB has a separate fixture."""
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]


class PreGridArchive(unittest.TestCase):
    def test_exact_bytes_and_authority_fences(self):
        subprocess.run(['node', 'tests/persistence/pre_grid_archive.js'],
                       cwd=ROOT, check=True, timeout=30)

    def test_embedded_authorities_match_standalone(self):
        for module, shells in [
            ('little_leaf_vault', ['little_leaf_shell', 'little_leaf_crazygames_shell']),
            ('little_leaf_crazygames', ['little_leaf_crazygames_shell']),
        ]:
            source = (ROOT / 'platform/web' / (module + '.js')).read_bytes().strip()
            for shell in shells:
                self.assertEqual((ROOT / 'platform/web' / (shell + '.html')).read_bytes().count(source), 1)

    def test_firebase_pending_upload_keeps_archive_requirement(self):
        subprocess.run(['node', 'tests/persistence/firebase_pre_grid_upload.js'],
                       cwd=ROOT, check=True, timeout=30)


if __name__ == '__main__':
    unittest.main()
