"""Presentation contracts against the retained, reviewed auth-only v2 source."""
import json
import re
import subprocess
import tempfile
import unittest
from pathlib import Path
from build_firebase import auth_verification_html
from build_itch_trusted_preview import wrapper_html
from build_web import ROOT


class EntryPresentationTests(unittest.TestCase):
    def test_reviewed_auth_handler_and_game_path_are_unchanged(self):
        baseline=(ROOT/'tools/auth_preview_pause/update/public/little_leaf_firebase_boot.mjs').read_text(encoding='utf-8')
        candidate=(ROOT/'platform/web/little_leaf_firebase_boot.mjs').read_text(encoding='utf-8')
        # Refused-save recovery may change presentation; Google and session setup
        # still follow the exact reviewed path before the adapter is created.
        def login_path(text):
            begin=text.index('  button.onclick=async()=>{')
            return text[begin:text.index('  const remote=',begin)]
        self.assertEqual(login_path(candidate),login_path(baseline))
        handler=lambda text:text[text.index('  button.onclick=async()=>{',text.index('async function verifyAuthOnly')):]
        self.assertEqual(handler(candidate),handler(baseline))

    def test_real_generated_pages_with_synthetic_auth_and_local_boundaries(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder=Path(temporary)
            origin='https://little-leaf-41e5d--itch-embed-test-0b0pnaf7.web.app'
            shell=(ROOT/'platform/web/little_leaf_shell.html').read_text(encoding='utf-8').replace('$GODOT_URL','index.js')
            config=json.loads((ROOT/'platform/firebase/public-config.json').read_text())
            auth=folder/'auth.html';auth.write_text(auth_verification_html(shell,config,origin),encoding='utf-8')
            manifest=folder/'manifest.json';manifest.write_text(json.dumps({'runtime_origin':origin}))
            html=auth.read_text(encoding='utf-8')
            self.assertIn('Nunito',html);self.assertIn('SIL OPEN FONT LICENSE',html)
            self.assertIn('Game and saves remain paused.',html)
            self.assertEqual(len(re.findall(r'<script\b',html)),1)
            subprocess.run(['node','tests/firebase_auth_verification_pause.js',str(auth),str(manifest)],cwd=ROOT,check=True,timeout=30)
            wrapper=folder/'wrapper.html';wrapper.write_text(wrapper_html(shell,origin),encoding='utf-8')
            subprocess.run(['node','tests/itch_trusted_preview_entry.js',str(wrapper)],cwd=ROOT,check=True,timeout=30)


if __name__=='__main__':unittest.main()
