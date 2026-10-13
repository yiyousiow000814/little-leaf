import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from qualification import verify_prebaked_atlases as guard

class AtlasSourceGuard(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.addCleanup(patch.stopall)
        patch.object(guard,'ROOT',self.root).start()
        patch.object(guard,'MANIFEST',self.root/'data/prebaked_atlas_manifest.json').start()
        (self.root/'scripts').mkdir();(self.root/'data').mkdir();(self.root/'assets/cache').mkdir(parents=True)
        for name in guard.SEEDS:
            source = self.root/name
            source.parent.mkdir(parents=True,exist_ok=True)
            source.write_text('extends RefCounted\n',encoding='utf-8')
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
    def add_main(self,source):
        main=self.root/'scripts/main.gd';main.write_text('extends RefCounted\n',encoding='utf-8')
        (self.root/guard.SEEDS[0]).write_text(source,encoding='utf-8')
        return guard.sources()
    def test_resource_identity_comparisons_do_not_load_main(self):
        sources=self.add_main('if script.resource_path == "res://scripts/main.gd": pass\n'
                              'if "res://scripts/main.gd" != game.get_script().resource_path: pass\n')
        self.assertNotIn('scripts/main.gd',sources)
    def test_real_main_load_is_retained_beside_identity_comparison(self):
        sources=self.add_main('if script.resource_path == "res://scripts/main.gd": pass\n'
                              'var loaded=load("res://scripts/main.gd")\n')
        self.assertIn('scripts/main.gd',sources)
        with self.assertRaises(AssertionError):self.run_guard()
    def test_preload_and_inherited_main_still_require_parity(self):
        for source in ['const Main=preload("res://scripts/main.gd")\n','extends "res://scripts/main.gd"\n']:
            with self.subTest(source=source):
                self.assertIn('scripts/main.gd',self.add_main(source))
                with self.assertRaises(AssertionError):self.run_guard()
    def test_dynamic_load_constants_and_cycles_are_retained(self):
        sources=self.add_main('const PATH="res://scripts/main.gd"\nvar loaded=load(PATH)\n')
        (self.root/'scripts/main.gd').write_text('extends "res://'+guard.SEEDS[0]+'"\n',encoding='utf-8')
        self.assertIn('scripts/main.gd',sources)
        self.assertEqual(sources.keys(),guard.sources().keys())
    def test_comment_references_are_not_dependencies(self):
        sources=self.add_main('# preload("res://scripts/main.gd")\n'
                              '# script.resource_path ==\nvar unused="unrelated"\n')
        self.assertNotIn('scripts/main.gd',sources)
    def test_resource_name_hash_is_not_a_comment(self):
        (self.root/'scripts/art#detail.gd').write_text('extends RefCounted\n',encoding='utf-8')
        (self.root/guard.SEEDS[0]).write_text('const Art=preload("res://scripts/art#detail.gd")\n',encoding='utf-8')
        self.assertIn('scripts/art#detail.gd',guard.sources())
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
