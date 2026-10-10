"""Guard the separate platform export without replacing the existing Web gates."""
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import build_crazygames as cg

REPO = Path(__file__).resolve().parents[1]


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


class CrazyGamesVariantTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.project = self.root / "project"
        shutil.copytree(REPO / "web", self.project / "web")
        self.before = {p.relative_to(self.project).as_posix(): p.read_bytes()
                       for p in self.project.rglob("*") if p.is_file()}

    def files(self):
        return {p.relative_to(self.project).as_posix(): p.read_bytes()
                for p in self.project.rglob("*") if p.is_file()}

    def test_default_is_byte_identical_and_records_production_keys(self):
        variant = cg.prepare_variant(self.project)
        self.assertEqual(self.before, self.files())
        self.assertEqual(variant, {"name": "production", "storage_keys": cg.PRODUCTION_KEYS,
                                   "transformed_inputs": {}})

    def test_preview_changes_only_staged_keys_and_notice_with_hash_receipt(self):
        variant = cg.prepare_variant(self.project, True)
        changed = {name for name, data in self.files().items() if data != self.before[name]}
        self.assertEqual(changed, {"web/little_leaf_crazygames.js", "web/little_leaf_crazygames_shell.html"})
        self.assertEqual(variant["name"], "developer-preview")
        self.assertEqual(variant["storage_keys"], cg.PREVIEW_KEYS)
        self.assertEqual(set(variant["transformed_inputs"]), changed)
        for name in changed:
            expected = self.before[name].decode().replace(cg.key_declaration(cg.PRODUCTION_KEYS),
                                                         cg.key_declaration(cg.PREVIEW_KEYS))
            if name.endswith(".html"):
                expected = expected.replace(cg.TITLE_MARKER, "<title>$GODOT_PROJECT_NAME" + cg.PREVIEW_TITLE_SUFFIX)
                expected = expected.replace(cg.LOADING_MARKER, "\t\t\t\t" + cg.PREVIEW_NOTICE + "\n" + cg.LOADING_MARKER)
            self.assertEqual((self.project / name).read_text(), expected)
            self.assertEqual((REPO / name).read_bytes(), self.before[name], "source never transformed")
            self.assertEqual(variant["transformed_inputs"][name], {
                "source_sha256": hashlib.sha256(self.before[name]).hexdigest(),
                "staged_sha256": cg.sha256(self.project / name)})

    def test_drift_or_repeat_transformation_fails_before_any_write(self):
        shell_path = self.project / "web/little_leaf_crazygames_shell.html"
        original = shell_path.read_text()
        for shell in [original.replace(cg.TITLE_MARKER, ""), original + cg.TITLE_MARKER,
                      original.replace(cg.LOADING_MARKER, ""), original + cg.LOADING_MARKER,
                      original.replace(cg.key_declaration(cg.PRODUCTION_KEYS), ""),
                      original + cg.key_declaration(cg.PRODUCTION_KEYS),
                      original + cg.PREVIEW_KEYS["profile"],
                      original.replace("const LIMIT =", "const CHANGED_LIMIT =")]:
            with self.subTest(shell_suffix=shell[-80:]):
                shell_path.write_text(shell)
                before = self.files()
                with self.assertRaises(RuntimeError): cg.prepare_variant(self.project, True)
                self.assertEqual(self.files(), before)
        shell_path.write_text(original)
        cg.prepare_variant(self.project, True)
        before = self.files()
        for preview in [True, False]:
            with self.assertRaises(RuntimeError): cg.prepare_variant(self.project, preview)
            self.assertEqual(self.files(), before)

    def test_export_validation_rejects_wrong_namespace_or_missing_notice(self):
        normal = (self.project / "web/little_leaf_crazygames_shell.html").read_text()
        cg.prepare_variant(self.project, True)
        preview = (self.project / "web/little_leaf_crazygames_shell.html").read_text()
        cg.validate_variant_html(normal)
        cg.validate_variant_html(preview, True)
        for html, mode in [(normal, True), (preview, False),
                           (preview.replace(cg.PREVIEW_NOTICE, ""), True),
                           (preview.replace(cg.PREVIEW_TITLE_SUFFIX, "</title>"), True),
                           (preview + cg.PRODUCTION_KEYS["profile"], True),
                           (preview + cg.PRODUCTION_KEYS["preferences"], True),
                           (preview + cg.key_declaration(cg.PREVIEW_KEYS), True)]:
            with self.subTest(mode=mode), self.assertRaises(RuntimeError):
                cg.validate_variant_html(html, mode)

    def test_preview_notice_is_inside_original_dismissible_boot_layer(self):
        class NoticeParser(HTMLParser):
            def __init__(self):
                super().__init__(); self.parents = []; self.notice_parents = []

            def handle_starttag(self, tag, attrs):
                attrs = dict(attrs)
                if attrs.get("id") == "developer-preview-notice":
                    self.notice_parents.append(list(self.parents))
                if tag not in {"meta", "img", "link", "br", "input"}:
                    self.parents.append((tag, attrs.get("id")))

            def handle_endtag(self, tag):
                if self.parents and self.parents[-1][0] == tag: self.parents.pop()

        cg.prepare_variant(self.project, True)
        parser = NoticeParser()
        parser.feed((self.project / "web/little_leaf_crazygames_shell.html").read_text())
        self.assertEqual(len(parser.notice_parents), 1)
        self.assertEqual(parser.notice_parents[0][-2:], [("div", "status"), ("div", "status-loading")])
        self.assertNotIn("position:fixed", cg.PREVIEW_NOTICE)
        self.assertIn("pointer-events:none", cg.PREVIEW_NOTICE)

    def test_platform_help_explains_submission_without_claiming_cloud_confirmation(self):
        ui = (REPO / "scripts/cafe_compact_ui.gd").read_text()
        body = ui.split("func _sync_help_content():", 1)[1].split("\nfunc ", 1)[0]
        expected = "Progress submitted to CrazyGames. Guest saves stay on this device; signed-in progress syncs through the platform and may take up to 30 seconds. Cloud sync is not confirmed here."
        self.assertIn(expected, body)
        self.assertIn("if game.web_save!=null and game.web_save.platform_managed:save_detail=", body)
        self.assertLess(body.index(expected), body.index("if game.save_recovery_blocked:"))
        self.assertLess(body.index(expected), body.index("elif game.progress_unsaved:"))

    def test_web_save_routes_have_no_native_or_persistent_pending_fallback(self):
        # Source contracts supplement the actual embedded-JS fixtures; this is
        # not an engine/runtime claim. Web branches return before native paths.
        main = (REPO / "scripts/main.gd").read_text()
        startup = main.split("func _load_startup():", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn('if OS.has_feature("web"):\n\t\tweb_save=WebSave.new(self)\n\t\tweb_save.load_startup()\n\t\treturn', startup)
        save = main.split("func _save():", 1)[1].split("\nfunc ", 1)[0]
        self.assertTrue(save.lstrip().startswith('if OS.has_feature("web"):return web_save.request_save() if web_save!=null else false'))
        controller = (REPO / "scripts/cafe_web_save.gd").read_text()
        self.assertIn('const STAGING_FILE="/tmp/little_leaf_vault_staging.json"', controller)
        for initial in ['var pending=false', 'var queued=false', 'var _confirmed_payload=""', 'var _inflight_payload=""']:
            self.assertIn(initial, controller)
        self.assertIn('api=JavaScriptBridge.get_interface("__littleLeafVault")', controller)
        self.assertIn('var result=JSON.parse_string(str(api.bootJson))', controller)
        self.assertIn('api.save(payload,revision,profile_id,_callback)', controller)
        self.assertNotIn('FileAccess.READ', controller)
        self.assertIn('if not game.model.save(STAGING_FILE):', controller)
        self.assertLess(controller.index('if not game.model.save(STAGING_FILE):'), controller.index('FileAccess.get_file_as_string(STAGING_FILE)'))
        settings = (REPO / "scripts/cafe_settings.gd").read_text()
        self.assertIn('web_preferences=WebPreferences.new()\n\t\tloaded=web_preferences.load_into(cfg)\n\t\tsource="browser-preferences:"+web_preferences.source\n\telse:', settings)
        self.assertIn('return saved\n\treturn cfg.save(config_path)==OK', settings)
        shell = (self.project / "web/little_leaf_crazygames_shell.html").read_text()
        self.assertIn('GODOT_CONFIG.persistentPaths = [];', shell)
        self.assertLess(shell.index('root.__littleLeafVault = client;'), shell.index('window.__littleLeafVault.boot()'))
        self.assertLess(shell.index('window.__littleLeafPreferences.boot()'), shell.index("return engine.startGame("))
        self.assertNotIn('LittleLeafPreferences =', shell, "ordinary Web preference adapter is absent")
        config = (REPO / "export_presets.cfg").read_text().split('[preset.1.options]', 1)[1].split('[preset.2]', 1)[0]
        self.assertIn('progressive_web_app/enabled=false', config)

    def test_both_variants_and_embedded_adapters_keep_full_sdk_contract(self):
        for preview in [False, True]:
            cg.prepare_variant(self.project, preview)
            for embedded in [False, True]:
                command = ["node", "tests/crazygames_storage.js", "--web-dir", str(self.project / "web")]
                if preview: command.append("--developer-preview")
                if embedded: command.append("--embedded")
                with self.subTest(preview=preview, embedded=embedded):
                    result = subprocess.run(command, cwd=REPO, capture_output=True, text=True, timeout=30)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    report = json.loads(result.stdout)
                    self.assertTrue(report["passed"])
                    self.assertEqual(report["save_variant"], "developer-preview" if preview else "production")
                    self.assertEqual(report["adapter"], "embedded" if embedded else "standalone")

    def test_flag_routes_only_copied_export_and_manifest_without_engine(self):
        # Synthetic exporter tests CLI plumbing only; no Godot/native process.
        build = self.root / "validated-build"
        shutil.copytree(self.project, build / "project")
        before = {p: p.read_bytes() for p in (build / "project").rglob("*") if p.is_file()}
        template = self.root / "template.zip"
        template.write_bytes(b"synthetic template")
        legacy = {"web_template_sha256": cg.sha256(template), "engine_checks": 10,
                  "toolchain_verification": "synthetic-test-only"}

        def output(command, **kwargs):
            if command[0] != "git": return cg.LOCK["godot"]["runtime_prefix"]
            if "status" in command: return ""
            return "b" * 40 if command[-1] == "HEAD^{tree}" else "a" * 40

        for preview in [False, True]:
            out = self.root / ("preview" if preview else "production")
            calls = []

            def run(command, **kwargs):
                calls.append(command)
                if "--export-release" in command:
                    html = Path(command[-1])
                    html.write_bytes((out / "project/web/little_leaf_crazygames_shell.html").read_bytes())
                    html.with_name("index.pck").write_bytes(b"GDPC")
                    html.with_name("music.pck").write_bytes(b"GDPC")
                    html.with_name("index.wasm").write_bytes(b"\0asm")
                    html.with_name("index.js").write_bytes(
                        b"blitOffscreenFramebuffer:context=>{var gl=context.GLctx;"
                        b"var prevScissorTest=gl.getParameter(3089);}")
                return SimpleNamespace(returncode=0, stdout=b"SCENE_READY furniture=synthetic")

            argv = ["build_crazygames.py", "--validated-web-build", str(build), "--output", str(out)]
            if preview: argv.append("--developer-preview")
            with patch.object(sys, "argv", argv), patch.object(cg, "validate_web_gate", return_value=legacy) as gate, \
                 patch.object(cg.subprocess, "check_output", side_effect=output), \
                 patch.object(cg.subprocess, "run", side_effect=run), \
                 patch.dict(cg.os.environ, {"GODOT_TEMPLATE": str(template)}):
                cg.main()
                self.assertEqual(gate.call_count, 2, "full source gate still validated before and after")
            manifest = json.loads((out / "web/crazygames-manifest.json").read_text())
            self.assertIn("gl.isEnabled(3089)", (out / "web/index.js").read_text())
            self.assertEqual(manifest["presentation_optimization"]["output_sha256"],
                             cg.sha256(out / "web/index.js"))
            self.assertEqual(manifest["save_variant"]["name"], "developer-preview" if preview else "production")
            self.assertEqual(manifest["save_variant"]["storage_keys"], cg.PREVIEW_KEYS if preview else cg.PRODUCTION_KEYS)
            self.assertIn(str(out / "project/web"), calls[0])
            self.assertEqual("--developer-preview" in calls[0], preview)
            cg.validate_variant_html((out / "web/index.html").read_text(), preview)
            self.assertEqual((out / "web/DEVELOPER-PREVIEW.txt").exists(), preview)
            if preview:
                self.assertEqual((out / "web/DEVELOPER-PREVIEW.txt").read_text(), cg.PREVIEW_README)
                self.assertIn("DEVELOPER-PREVIEW.txt", manifest["files"])
            for name, receipt in manifest["save_variant"]["transformed_inputs"].items():
                self.assertEqual(receipt["staged_sha256"], cg.sha256(out / "project" / name))
            self.assertEqual(before, {p: p.read_bytes() for p in before}, "validated Web staging stays untouched")
        self.assertEqual(self.before, self.files(), "input project stays untouched")


if __name__ == "__main__":
    unittest.main()
