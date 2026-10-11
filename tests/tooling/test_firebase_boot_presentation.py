"""Signed-out Firebase startup remains explicit and account-gated."""
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]


class FirebaseBootPresentation(unittest.TestCase):
    def test_explicit_local_google_transition(self):
        subprocess.run(['node', 'tests/google_binding.js'],
                       cwd=ROOT, check=True, timeout=30)

    def test_real_module_with_disposable_sdk_and_dom(self):
        subprocess.run(['node', 'tests/firebase_boot_presentation.js'],
                       cwd=ROOT, check=True, timeout=30)

    def test_recovery_bridge_with_disposable_account_and_dom(self):
        subprocess.run(['node', 'tests/firebase_recovery_presentation.js'],
                       cwd=ROOT, check=True, timeout=30)


if __name__ == '__main__':
    unittest.main()
