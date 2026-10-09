"""Shell-only itch entry regression; discovered by the ordinary Web CI gate."""
from pathlib import Path
import subprocess
import unittest

class ItchEntry(unittest.TestCase):
    def test_shell_contract(self):
        subprocess.run(['node', 'tests/itch_entry.js'],
                       cwd=Path(__file__).resolve().parents[1], check=True, timeout=30)

if __name__ == '__main__':
    unittest.main()
