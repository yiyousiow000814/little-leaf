"""Popup help and copy-link fallback contract; no browser, game or player data."""
from pathlib import Path
import subprocess
import unittest

class ItchPopupHelp(unittest.TestCase):
    def test_source_and_exported_shell_contract(self):
        subprocess.run(['node','tests/itch_popup_help.js'],
                       cwd=Path(__file__).resolve().parents[1],check=True,timeout=30)

if __name__=='__main__':
    unittest.main()
