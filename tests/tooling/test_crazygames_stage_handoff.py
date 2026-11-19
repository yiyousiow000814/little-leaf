"""Only synthetic source, runner identities and disposable staged data."""
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

from build import crazygames_stage_handoff as handoff


class CrazyGamesStageHandoffTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = root = Path(temporary.name)
        self.source = root / "checkout"
        self.build = root / "web-build"
        self.project = self.build / "project"
        self.packet = root / "stage.json"
        self.template = root / "template"
        binary = root / "godot"
        self.template.write_bytes(b"fixture template")
        binary.write_bytes(b"fixture Godot")
        self.files = {"project.godot": b"raw", "scripts/Visible.gd": b"script",
                      "assets/.kept": b"hidden tracked bytes", "assets/叶.ogg": b"music"}
        self.projected = {"project.godot": b"projected"}
        for name, value in self.files.items():
            path = self.source / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(value)
        shutil.copytree(self.source, self.project)
        for name, value in {**self.projected, handoff.TEMPLATE: self.template.read_bytes(),
                            "scripts/Visible.gd.uid": b"uid://truly-original",
                            "assets/叶.ogg.import": b"exact metadata", ".godot/ignore": b"cache",
                            "assets/.godot/ignore": b"nested cache"}.items():
            path = self.project / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(value)
        (self.build / "web").mkdir()
        (self.build / "web/index.html").write_text("<html>ordinary</html>")
        self.commit, self.tree = "a" * 40, "b" * 40
        self.ver = "1.2.3-pre.aaaaaaaa"
        self.manifest = {
            "source_commit": self.commit, "source_tree": self.tree,
            "workflow_run": "42", "workflow_attempt": "2", "version": self.ver, "tag": "",
            "toolchain_verification": "checksum-pinned-official-archives", "toolchain_receipt": {},
            "web_template_sha256": handoff.sha256(self.template), "packed_smoke": "passed",
            "engine_checks": 17, "test_processes": 2,
            "files": {"index.html": {"sha256": handoff.sha256(self.build / "web/index.html"),
                                     "bytes": (self.build / "web/index.html").stat().st_size}},
            "production_sha256": {n: handoff.digest(b) for n, b in self.files.items()},
            "projected_metadata_sha256": {n: handoff.digest(b) for n, b in self.projected.items()}
        }
        self.write_manifest()
        self.fake_e = {
            "GITHUB_SHA": self.commit, "GITHUB_RUN_ID": "42", "GITHUB_RUN_ATTEMPT": "2",
            "GITHUB_EVENT_NAME": "pull_request", "GODOT_TEMPLATE": str(self.template),
            "GODOT_BIN": str(binary), "GODOT_TOOLCHAIN_RECEIPT": str(root / "synthetic"),
        }
        for patcher in (
            patch.object(handoff, "ROOT", self.source), patch.object(handoff, "git", self.git),
            patch.object(handoff, "version", return_value=self.ver),
            patch.object(handoff, "projected_metadata", return_value=self.projected),
            patch("qualification.artifacts.projected_metadata", return_value=self.projected),
            patch.object(handoff, "verify_installer_receipt", return_value={}),
            patch.dict("os.environ", self.fake_e, clear=True),
        ):
            patcher.start()
            self.addCleanup(patcher.stop)

    def git(self, *args):
        return {
            ("status", "--porcelain", "--untracked-files=no"): "",
            ("rev-parse", "HEAD"): self.commit, ("rev-parse", "HEAD^{tree}"): self.tree,
            ("ls-files", "-z"): "\0".join(self.files) + "\0",
        }[args]

    def write_manifest(self):
        (self.build / "web/release-manifest.json").write_text(json.dumps(self.manifest))

    def prepare(self):
        original = handoff.scan(self.project)
        handoff.pack(self.build, self.packet)
        shutil.rmtree(self.project)
        return original

    def test_exact_stage_reproduces_hidden_and_generated_bytes_except_cache(self):
        expected = self.prepare()
        body = json.loads(self.packet.read_bytes())
        self.assertEqual(set(body["extras"]), {"scripts/Visible.gd.uid", "assets/叶.ogg.import"})
        handoff.restore(self.build, self.packet)
        self.assertEqual(handoff.scan(self.project), expected)
        self.assertFalse((self.project / ".godot").exists())
        self.assertEqual((self.project / "scripts/Visible.gd.uid").read_bytes(), b"uid://truly-original")
        self.assertEqual((self.project / "project.godot").read_bytes(), b"projected")
        self.assertEqual(handoff.sha256(self.project / handoff.TEMPLATE), handoff.sha256(self.template))
        with self.assertRaises(FileExistsError):
            handoff.restore(self.build, self.packet)

    def test_rejects_foreign_receipts_and_ordinary_bytes(self):
        self.prepare()
        for key, value in {"GITHUB_RUN_ID": "43", "GITHUB_RUN_ATTEMPT": "1",
                           "GITHUB_EVENT_NAME": "push", "GITHUB_SHA": "c" * 40}.items():
            with self.subTest(key=key), patch.dict("os.environ", {key: value}):
                with self.assertRaises(ValueError):
                    handoff.restore(self.build, self.packet)
                self.assertFalse(self.project.exists())
        self.manifest["change_unrelated_to_build"] = True
        self.write_manifest()
        with self.assertRaisesRegex(ValueError, "proof is not"):
            handoff.restore(self.build, self.packet)

    def test_packet_cannot_add_replace_or_modify_staged_inputs(self):
        self.prepare()
        frozen = self.packet.read_bytes()
        for modify in (lambda p: p["extras"].update({"../../foreign.gd.uid": "YQ=="}),
                       lambda p: p["extras"].update({"scripts/Visible.gd.uid": "YQ=="}),
                       lambda p: p["extras"].update({"project.godot": "YQ=="}),
                       lambda p: p["inventory"]["directories"].append("extra")):
            body = json.loads(frozen)
            modify(body)
            self.packet.write_text(json.dumps(body))
            with self.assertRaises(ValueError):
                handoff.restore(self.build, self.packet)
            self.assertFalse(self.project.exists())

    def test_rejects_untracked_side_effect_and_symlink_in_producer(self):
        odd = self.project / "assets/unexpected.dat"
        odd.write_bytes(b"not ordinary staged metadata")
        with self.assertRaisesRegex(ValueError, "Only generated"):
            handoff.pack(self.build, self.packet)
        odd.unlink()
        odd.symlink_to(self.source / "assets/.kept")
        with self.assertRaisesRegex(ValueError, "Symlink"):
            handoff.pack(self.build, self.packet)

    def test_template_and_ordinary_payload_are_verified(self):
        self.prepare()
        initial = self.template.read_bytes()
        self.template.write_bytes(b"not the original template")
        with self.assertRaisesRegex(ValueError, "template/toolchain"):
            handoff.restore(self.build, self.packet)
        self.template.write_bytes(initial)
        (self.build / "web/index.html").write_text("changed Web payload")
        with self.assertRaisesRegex(ValueError, "inventory hash/size"):
            handoff.restore(self.build, self.packet)
        self.assertFalse(self.project.exists())
