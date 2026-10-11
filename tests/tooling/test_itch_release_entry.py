"""Permanent account entry packaging and origin/storage boundaries."""
import subprocess
import tempfile
import unittest
from pathlib import Path
from build_web import ROOT
from build_itch_entry import ordinary_entry_html, remove_ordinary_entry
from build_itch_trusted_preview import wrapper_html


class ItchReleaseEntryTests(unittest.TestCase):
    def setUp(self):
        self.shell = (ROOT / 'platform/web/little_leaf_shell.html').read_text(encoding='utf-8').replace('$GODOT_URL', 'index.js')

    def test_generated_release_chooser_boundaries(self):
        html = ordinary_entry_html(self.shell)
        self.assertIn('SIL OPEN FONT LICENSE', html)
        self.assertIn('Local and Google-account progress are separate.', html)
        self.assertEqual(html.count('window.__littleLeafVault.boot()'), 1)
        self.assertEqual(remove_ordinary_entry(html), self.shell)
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'index.html'
            path.write_text(html, encoding='utf-8')
            subprocess.run(['node', 'tests/tooling/itch_release_entry.js', str(path)], cwd=ROOT, check=True, timeout=30)

    def test_changed_or_duplicate_shell_is_refused(self):
        for html in [self.shell.replace('window.__littleLeafVault.boot()', 'otherBoot()'),
                     self.shell + 'window.__littleLeafVault.boot()', ordinary_entry_html(self.shell)]:
            with self.subTest(), self.assertRaises(ValueError):
                ordinary_entry_html(html)

    def test_explicit_preview_has_only_its_existing_chooser(self):
        html = wrapper_html(ordinary_entry_html(self.shell), 'https://little-leaf-41e5d--itch-embed-test-fixture.web.app')
        self.assertNotIn('itch-release-entry', html)
        self.assertIn('id="itch-entry"', html)
        self.assertNotIn('LittleLeafItchReleaseEntryReady', html)

    def test_export_injects_before_inventory_and_does_not_rewrite_engine(self):
        code = (ROOT / 'tools/build_web.py').read_text(encoding='utf-8')
        self.assertLess(code.index('write_text(ordinary_entry_html(html)'), code.index('manifest = {'))
        self.assertIn('"files": {p.name:', code)
