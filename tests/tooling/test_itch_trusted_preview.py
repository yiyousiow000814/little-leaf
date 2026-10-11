"""Targeted synthetic package and local/cloud entry boundary checks."""
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from build_itch_trusted_preview import prepare, prepare_stable, wrapper_html, STABLE_ORIGIN
from build_web import ROOT, sha256
from read_firebase_hosting_config import effective_diagnosis

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
            self.assertIn('>Play with Google</button>', wrapper)
            self.assertIn('>Continue local play</button>', wrapper)
            self.assertIn('then continue playing on this itch page.', wrapper)
            self.assertNotIn('opens a new tab', wrapper)
            self.assertNotIn('id="itch-release-account"', wrapper)
            self.assertIn('aria-describedby="itch-account-detail itch-progress-separation"', wrapper)
            self.assertIn('Local and Google-account progress are separate.', wrapper)
            self.assertEqual(manifest['source_sha256']['tools/build_itch_entry.py'],
                             sha256(ROOT / 'tools/build_itch_entry.py'))
            self.assertFalse(manifest['hosted_acceptance']); self.assertFalse(manifest['auth_domains_modified'])
            for name in ['index.js', 'index.wasm', 'index.pck']:
                self.assertEqual((output / 'public' / name).read_bytes(), (web / name).read_bytes())
            subprocess.run(['node', 'tests/tooling/itch_trusted_preview_entry.js', str(output / 'itch-wrapper/index.html')], cwd=ROOT, check=True, timeout=30)
            stable = root / 'stable'
            record = prepare_stable(build, stable, config, 'a'*40, 'b'*40)
            self.assertFalse(record['production_release_eligible'])
            self.assertEqual(record['status'], 'prepared-same-itch-local-candidate-not-deployable')
            stable_html = (stable/'public/itch/index.html').read_text()
            self.assertIn('"runtimePath": "/itch/"', stable_html)
            self.assertNotIn('trusted-itch-frame', (stable/'public/index.html').read_text())
            stable_marker = json.loads((stable/'public/itch/hosting-release.json').read_text())
            self.assertIn('window.__littleLeafRelease='+json.dumps(stable_marker), stable_html)
            self.assertEqual(stable_marker['source_commit'], 'a'*40)
            headers = json.loads((stable/'firebase.json').read_text())
            self.assertEqual(set(headers), {'hosting'})
            framed = [row['source'] for row in headers['hosting']['headers']
                      if any(x['key']=='Content-Security-Policy' for x in row['headers'])]
            self.assertEqual(framed, ['/itch/', '/itch/index.html'])
            baseline_headers = json.loads((ROOT/'platform/firebase/firebase.json').read_text())['hosting']['headers']
            proposed_headers = headers['hosting']['headers']
            self.assertEqual(proposed_headers[:len(baseline_headers)], baseline_headers)
            self.assertEqual(record['hosting_header_additions'], proposed_headers[len(baseline_headers):])
            self.assertTrue(record['hosting_config_proposal_only'])
            index_rule = next(row for row in proposed_headers if row['source']=='/itch/index.html')
            self.assertEqual([value['key'] for value in index_rule['headers']], ['Content-Security-Policy'])
            classified = effective_diagnosis({'headers':[
                {'glob':row['source'], 'headers':{value['key']:value['value'] for value in row['headers']}}
                for row in proposed_headers]})['scenarios']['baseline']
            self.assertEqual(classified['/itch/index.html']['applicable_tokens']['CACHE_CONTROL'],
                             ['CACHE_NO_CACHE_EXACT'])
            self.assertTrue(all(not path['hold_categories'] for path in classified.values()))
            for name in ['index.js','index.wasm','index.pck']:
                self.assertEqual((stable/'public/itch'/name).read_bytes(), (web/name).read_bytes())
            subprocess.run(['node','tests/tooling/itch_trusted_preview_entry.js',str(stable/'itch-wrapper/index.html'),
                            STABLE_ORIGIN+'/itch/'],cwd=ROOT,check=True,timeout=30)
            with self.assertRaisesRegex(ValueError, 'Exact-source'):
                prepare_stable(build, root/'wrong-source',config,'c'*40,'b'*40)
            self.assertFalse((root/'wrong-source').exists())

    def test_arbitrary_shared_and_lookalike_origins_are_rejected(self):
        shell = (ROOT / 'platform/web/little_leaf_shell.html').read_text()
        for origin in ['https://html-classic.itch.zone', 'https://evil.example', ORIGIN+'/', ORIGIN+'.evil.example', ORIGIN.replace('https:', 'http:')]:
            with self.subTest(origin=origin), self.assertRaises(ValueError):
                wrapper_html(shell, origin)
        for origin in [STABLE_ORIGIN, STABLE_ORIGIN+'/itch/', STABLE_ORIGIN+'/other', STABLE_ORIGIN+'.evil.example/itch']:
            with self.subTest(stable_origin=origin), self.assertRaises(ValueError):
                wrapper_html(shell, origin, stable=True)


if __name__ == '__main__':
    unittest.main()
