"""Single embedded chooser packaging and local/account isolation."""
import subprocess
import tempfile
import unittest
from pathlib import Path
from build.build_web import ROOT
from build.build_itch_trusted_preview import wrapper_html, STABLE_ORIGIN, STABLE_PATH


class ItchReleaseEntryTests(unittest.TestCase):
    def setUp(self):
        self.shell = (ROOT / 'platform/web/little_leaf_shell.html').read_text(encoding='utf-8').replace('$GODOT_URL', 'index.js')
        self.origin = STABLE_ORIGIN + STABLE_PATH.rstrip('/')

    def test_generated_wrapper_boundaries(self):
        html = wrapper_html(self.shell, self.origin, stable=True)
        self.assertIn('SIL OPEN FONT LICENSE', html)
        self.assertIn('Local and Google-account progress are separate.', html)
        self.assertIn('aria-describedby="itch-account-detail itch-progress-separation"', html)
        self.assertIn('aria-describedby="itch-local-detail itch-progress-separation"', html)
        self.assertEqual(html.count('window.__littleLeafVault.boot()'), 1)
        self.assertNotIn('target="_blank"', html)
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'index.html'
            path.write_text(html, encoding='utf-8')
            subprocess.run(['node', 'tests/tooling/itch_trusted_preview_entry.js', str(path), self.origin+'/'], cwd=ROOT, check=True, timeout=30)

    def test_changed_or_duplicate_shell_is_refused(self):
        for html in [self.shell.replace('window.__littleLeafVault.boot()', 'otherBoot()'),
                     self.shell + 'window.__littleLeafVault.boot()',
                     self.shell.replace('<body>', '<body><body>'),
                     wrapper_html(self.shell, self.origin, stable=True)]:
            with self.subTest(), self.assertRaises(ValueError):
                wrapper_html(html, self.origin, stable=True)

    def test_preview_and_stable_share_the_same_chooser(self):
        stable = wrapper_html(self.shell, self.origin, stable=True)
        preview_origin = 'https://little-leaf-41e5d--itch-embed-test-fixture.web.app'
        preview = wrapper_html(self.shell, preview_origin)
        self.assertEqual(preview.replace(preview_origin, self.origin), stable)
