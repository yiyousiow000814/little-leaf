import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import verify_prebaked_atlases as guard

class AtlasSourceGuard(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.addCleanup(patch.stopall)
        patch.object(guard,'ROOT',self.root).start()
        patch.object(guard,'MANIFEST',self.root/'data/prebaked_atlas_manifest.json').start()
        (self.root/'scripts').mkdir();(self.root/'data').mkdir();(self.root/'assets/cache').mkdir(parents=True)
        for name in guard.SEEDS:(self.root/name).write_text('extends RefCounted\n')
        for name in guard.NAMES:
            image = self.root/f'assets/cache/{name}-atlas.png'
            # Structural fixture only: actual imported-pixel integrity is tested in Godot.
            image.write_bytes(b'\x89PNG\r\n\x1a\n'+b'\0'*8+(1).to_bytes(4,'big')*2)
            Path(str(image)+'.import').write_text('compress/mode=0\nmipmaps/generate=false\nprocess/fix_alpha_border=false\nprocess/premult_alpha=false\nprocess/size_limit=0\n')
        self.receipt = self.root/'receipt.json'
        self.receipt.write_text(json.dumps({'checks':3,'failures':[],'baseline_sha256':['a']*3,'candidate_sha256':['a']*3}))
        self.run_guard('--write-manifest',str(self.receipt),'--provenance','synthetic unit fixture')
    def run_guard(self,*args):
        with patch('sys.argv',['verify',*args]),contextlib.redirect_stdout(io.StringIO()):guard.main()
    def test_current_sources_pass(self):self.run_guard()
    def test_changed_art_is_rejected(self):
        (self.root/guard.SEEDS[0]).write_text('extends RefCounted\n# changed art\n')
        with self.assertRaises(AssertionError):self.run_guard()
    def test_new_dependency_is_rejected(self):
        (self.root/'scripts/new.gd').write_text('extends RefCounted\n')
        (self.root/guard.SEEDS[0]).write_text('extends "res://scripts/new.gd"\n')
        with self.assertRaises(AssertionError):self.run_guard()
    def test_changed_image_is_rejected(self):
        image=self.root/'assets/cache/heads-atlas.png';image.write_bytes(image.read_bytes()+b'changed')
        with self.assertRaises(AssertionError):self.run_guard()
    def test_quality_reduction_is_rejected(self):
        p=self.root/'assets/cache/heads-atlas.png.import';p.write_text(p.read_text().replace('compress/mode=0','compress/mode=1'))
        with self.assertRaises(AssertionError):self.run_guard()
    def test_failed_parity_cannot_write_manifest(self):
        self.receipt.write_text(json.dumps({'checks':3,'failures':['different pixels'],'baseline_sha256':['a']*3,'candidate_sha256':['b']*3}))
        with self.assertRaises(AssertionError):self.run_guard('--write-manifest',str(self.receipt),'--provenance','fixture')

if __name__=='__main__':unittest.main()
