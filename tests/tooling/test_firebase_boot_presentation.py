"""Signed-out Firebase startup remains explicit and account-gated."""
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]


class FirebaseBootPresentation(unittest.TestCase):
    def test_google_cloud_authoritative_startup(self):
        subprocess.run(['node', 'tests/persistence/firebase_cloud_startup.js'],
                       cwd=ROOT, check=True, timeout=30)

    def test_recovery_metadata_lifecycle_with_synthetic_owners(self):
        subprocess.run(['node', '--expose-gc', 'tests/persistence/firebase_choice.js'],
                       cwd=ROOT, check=True, timeout=30)

    def test_real_module_with_disposable_sdk_and_dom(self):
        subprocess.run(['node', 'tests/persistence/firebase_boot_presentation.js'],
                       cwd=ROOT, check=True, timeout=30)

    def test_ordinary_refresh_with_synthetic_sessions_and_locks(self):
        subprocess.run(['node', 'tests/persistence/firebase_session_refresh.js'],
                       cwd=ROOT, check=True, timeout=30)

    def test_recovery_bridge_with_disposable_account_and_dom(self):
        subprocess.run(['node', 'tests/persistence/firebase_recovery_presentation.js'],
                       cwd=ROOT, check=True, timeout=30)


if __name__ == '__main__':
    unittest.main()
