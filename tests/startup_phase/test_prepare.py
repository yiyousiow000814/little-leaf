"""Offline diagnostic overlay/source-isolation contracts. No engine or browser."""
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("phase_prepare", ROOT / "qa/startup_phase/prepare.py")
prepare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare)


class PhasePreparationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="startup-phase-offline-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.root = self.base / "source"
        self.root.mkdir()
        (self.root / "scripts").mkdir()
        (self.root / "scripts/main.gd").write_text("extends Node3D\nfunc _ready():\n\tpass\n")
        for name in ["main.tscn", "project.godot", "export_presets.cfg"]:
            (self.root / name).write_bytes((ROOT / name).read_bytes())
        (self.root / "qa").mkdir()
        shutil.copytree(ROOT / "qa/startup_phase", self.root / "qa/startup_phase", ignore=shutil.ignore_patterns("__pycache__"))
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        self.git("add", ".")
        self.git("-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-qm", "synthetic fixture")
        self.head = self.git("rev-parse", "HEAD").strip()

    def git(self, *args):
        return prepare.git(self.root, *args).decode()

    def test_exact_source_pair_only_differs_in_script(self):
        before = self.git("status", "--porcelain")
        out = self.base / "pair"
        manifests = prepare.prepare(self.root, out, self.head)
        self.assertEqual(before, self.git("status", "--porcelain"))
        control, instrumented = [manifests[mode] for mode in prepare.MODES]
        self.assertEqual(control["pair_id"], instrumented["pair_id"])
        self.assertNotEqual(control["overlay_id"], instrumented["overlay_id"])
        self.assertEqual(json.loads((out / "pair.json").read_text())["project_differences"], [prepare.OVERLAY_PATH])
        for mode, manifest in manifests.items():
            self.assertFalse(manifest["release_qualified"])
            self.assertTrue(manifest["release_qualification_prohibited"])
            self.assertEqual(manifest["browser_status"], "not_run_actual_browser_pending")
            self.assertFalse((out / mode / "release-manifest.json").exists())
            for name, digest in manifest["diagnostic_project_sha256"].items():
                self.assertEqual(prepare.digest((out / mode / "project" / name).read_bytes()), digest)
            for name, digest in manifest["base_production_sha256"].items():
                self.assertEqual(prepare.digest((self.root / name).read_bytes()), digest)
        self.assertEqual((out / "control/project/project.godot").read_bytes(), (self.root / "project.godot").read_bytes())
        self.assertIn('run/main_scene="res://main.tscn"', (out / "instrumented/project/project.godot").read_text())

    def test_wrong_head_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "HEAD differs"):
            prepare.prepare(self.root, self.base / "pair", "f" * 40)

    def test_changed_production_rejected(self):
        (self.root / "scripts/main.gd").write_text("changed")
        with self.assertRaisesRegex(RuntimeError, "Production source differs"):
            prepare.prepare(self.root, self.base / "pair", self.head)

    def test_untracked_production_rejected(self):
        (self.root / "scripts/extra.gd").write_text("extra")
        with self.assertRaisesRegex(RuntimeError, "Untracked production"):
            prepare.prepare(self.root, self.base / "pair", self.head)

    def test_checkout_output_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "outside"):
            prepare.prepare(self.root, self.root / "output", self.head)

    def test_overlay_change_changes_identity(self):
        first = prepare.prepare(self.root, self.base / "a", self.head)
        with (self.root / "qa/startup_phase/control.gd").open("a") as file:
            file.write("# changed helper\n")
        second = prepare.prepare(self.root, self.base / "b", self.head)
        self.assertNotEqual(first["control"]["pair_id"], second["control"]["pair_id"])
        self.assertEqual(first["control"]["base_production_sha256"], second["control"]["base_production_sha256"])

    def test_export_validator_binds_source_overlay_and_artifact(self):
        out = self.base / "pair"
        manifests = prepare.prepare(self.root, out, self.head)
        for mode, manifest in manifests.items():
            web = out / mode / "web"
            web.mkdir()
            # Clearly synthetic artifact bytes: validates identity plumbing only.
            contents = {"index.html": b"synthetic offline fixture", "index.wasm": b"\\0asmfixture", "index.pck": b"GDPCfixture"}
            for name, data in contents.items():
                (web / name).write_bytes(data)
            manifest.update(export_status="passed", files={name: {"sha256": prepare.digest(data), "bytes": len(data)} for name, data in contents.items()})
            prepare.write_json(web / "diagnostic-manifest.json", manifest)
            command = ["node", "-e", "require(process.argv[1]).verifyManifest(process.argv[2],process.argv[3])", str(ROOT / "qa/startup_phase/validate.js"), str(web), str(self.root)]
            subprocess.run(command, check=True, capture_output=True)
            (web / "index.html").write_text("changed artifact")
            self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)
            (web / "index.html").write_bytes(contents["index.html"])
            (web / "release-manifest.json").write_text("{}")
            self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)

    def test_runtime_wrappers_call_real_super_without_io(self):
        text = (ROOT / "qa/startup_phase/instrumented.gd").read_text()
        methods = ["_ready", "_load_startup", "_setup_world", "_build_ui", "_setup_music", "_rebuild_room", "_rebuild_furniture", "_restore_service_runtime"]
        for method in methods:
            body = text.split("func " + method + "():\n", 1)[1].split("\nfunc ", 1)[0]
            self.assertEqual(body.count("super()"), 1, method)
            self.assertNotIn("JavaScriptBridge", body)
            self.assertNotIn("print(", body)
        for forbidden in ["MinimalStart", "save_writes_suppressed", "--fresh-review", "func _save(", "func _autosave("]:
            self.assertNotIn(forbidden, text)
        self.assertEqual(text.count("JavaScriptBridge.eval("), 1)
        self.assertEqual(text.count('print("STARTUP_PHASE_PACKET'), 1)
        self.assertIn("_phase_emit.call_deferred()", text)
        control = (ROOT / "qa/startup_phase/control.gd").read_text()
        self.assertNotIn("func ", control)
        self.assertNotIn("Time.get_ticks", control)


if __name__ == "__main__":
    unittest.main()
