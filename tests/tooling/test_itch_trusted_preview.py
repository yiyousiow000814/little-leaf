"""Targeted synthetic package and local/cloud entry boundary checks."""
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from build_itch_trusted_preview import prepare, wrapper_html
from build_web import ROOT, sha256

ORIGIN = 'https://little-leaf-41e5d--itch-embed-test-abc123.web.app'


class TrustedPreviewTests(unittest.TestCase):
    def test_package_is_own_origin_and_hosting_only(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); build = root / 'build'; web = build / 'web'; web.mkdir(parents=True)
            shell = (ROOT / 'platform/web/little_leaf_shell.html').read_text().replace('$GODOT_URL', 'index.js')
            (web / 'index.html').write_text(shell)
            for name in ['index.js', 'index.wasm', 'index.pck']:
                (web / name).write_bytes(b'synthetic engine fixture')
            base = {'source_commit':'a'*40, 'source_tree':'b'*40, 'workflow_run':'1', 'version':'synthetic',
                    'packed_smoke':'passed', 'engine_checks':1, 'test_processes':1,
                    'production_sha256':{'project.godot':sha256(ROOT / 'game/project.godot')},
                    'files':{p.name:{'sha256':sha256(p),'bytes':p.stat().st_size} for p in web.iterdir()}}
            (web / 'release-manifest.json').write_text(json.dumps(base))
            config = json.loads((ROOT / 'platform/firebase/public-config.json').read_text())
            output = root / 'out'; manifest = prepare(build, output, config, ORIGIN, 'c'*40, 'd'*40)
            hosting = json.loads((output / 'firebase.json').read_text())
            self.assertEqual(set(hosting), {'hosting'})
            for path in ['/', '/index.html']:
                policy = next(x for x in hosting['hosting']['headers'] if x['source'] == path)
                self.assertIn({'key':'Content-Security-Policy','value':'frame-ancestors https://html-classic.itch.zone https://siowyiyou.itch.io'}, policy['headers'])
            html = (output / 'public/index.html').read_text()
            self.assertIn('trusted-itch-frame', html); self.assertIn(ORIGIN, html)
            wrapper = (output / 'itch-wrapper/index.html').read_text()
            self.assertNotIn('import("./little_leaf_firebase_boot.mjs")', wrapper)
            self.assertNotIn('src="little_leaf_firebase.js"', wrapper)
            self.assertIn('does not transfer automatically', wrapper)
            self.assertFalse(manifest['hosted_acceptance']); self.assertFalse(manifest['auth_domains_modified'])
            for name in ['index.js', 'index.wasm', 'index.pck']:
                self.assertEqual((output / 'public' / name).read_bytes(), (web / name).read_bytes())
            subprocess.run(['node', 'tests/itch_trusted_preview_entry.js', str(output / 'itch-wrapper/index.html')], cwd=ROOT, check=True, timeout=30)

    def test_arbitrary_shared_and_lookalike_origins_are_rejected(self):
        shell = (ROOT / 'platform/web/little_leaf_shell.html').read_text()
        for origin in ['https://html-classic.itch.zone', 'https://evil.example', ORIGIN+'/', ORIGIN+'.evil.example', ORIGIN.replace('https:', 'http:')]:
            with self.subTest(origin=origin), self.assertRaises(ValueError):
                wrapper_html(shell, origin)


if __name__ == '__main__':
    unittest.main()
