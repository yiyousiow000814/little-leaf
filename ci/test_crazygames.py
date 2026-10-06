"""Guard the separate platform export without replacing the existing Web gates."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import build_crazygames as cg


class CrazyGamesExportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.build = self.root / "build"
        (self.build / "web").mkdir(parents=True)
        (self.build / "project").mkdir()
        self.source = self.root / "main.tscn"
        self.source.write_text("synthetic scene")
        (self.build / "project/main.tscn").write_text("synthetic scene")
        (self.build / "web/index.html").write_text("normal Web shell")
        self.manifest = {"source_commit": "a" * 40, "source_tree": "b" * 40,
                         "packed_smoke": "passed", "engine_checks": 10, "test_processes": 3,
                         "toolchain_verification": "checksum-pinned-official-archives",
                         "production_sha256": {"main.tscn": hashlib.sha256(b"synthetic scene").hexdigest()}}
        self.save()

    def save(self):
        (self.build / "web/release-manifest.json").write_text(json.dumps(self.manifest))

    def validate(self, local=False):
        with patch.object(cg, "ROOT", self.root):
            return cg.validate_web_gate(self.build, "a" * 40, "b" * 40, local)

    def test_requires_passed_exact_source_gate(self):
        self.validate()
        for key, bad in [("source_commit", "c" * 40), ("source_tree", "c" * 40),
                         ("packed_smoke", "failed"), ("engine_checks", 0), ("test_processes", 0)]:
            with self.subTest(key=key):
                old = self.manifest[key]; self.manifest[key] = bad; self.save()
                with self.assertRaises(RuntimeError): self.validate()
                self.manifest[key] = old

    def test_ci_rejects_local_tools(self):
        self.manifest["toolchain_verification"] = "local-tools-unverified-for-release"; self.save()
        with self.assertRaises(RuntimeError): self.validate()
        self.validate(local=True)

    def test_source_or_staged_mutation_rejected(self):
        self.source.write_text("changed source")
        with self.assertRaises(RuntimeError): self.validate()
        self.source.write_text("synthetic scene")
        (self.build / "project/main.tscn").write_text("changed staging")
        with self.assertRaises(RuntimeError): self.validate()

    def test_sdk_cannot_leak_into_normal_web(self):
        (self.build / "web/index.html").write_text('<script src="https://sdk.crazygames.com/crazygames-sdk-v3.js"></script>')
        with self.assertRaises(RuntimeError): self.validate()

    def test_separate_presets_keep_original_web_selection(self):
        config = (Path(__file__).resolve().parents[1] / "export_presets.cfg").read_text(encoding="utf-8")
        sections = config.split("[preset.")
        self.assertIn('name="Web"', sections[1])
        self.assertIn('custom_features=""', sections[1])
        self.assertIn('html/custom_html_shell="res://web/little_leaf_shell.html"', config)
        self.assertIn('name="CrazyGames"', config)
        self.assertIn('name="CrazyGamesMusic"', config)
        self.assertIn('html/custom_html_shell="res://web/little_leaf_crazygames_shell.html"', config)


if __name__ == "__main__":
    unittest.main()
