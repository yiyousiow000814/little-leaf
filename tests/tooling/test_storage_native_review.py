"""Fast synthetic guards for the bounded diagnostic, not native qualification."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import struct
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("storage_native_review", ROOT / "tools/diagnostics/storage_native_review.py")
review = importlib.util.module_from_spec(spec)
spec.loader.exec_module(review)


class StorageNativeReviewTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="storage-diagnostic-contract-")
        self.folder = Path(self.temp.name)
        self.addCleanup(self.temp.cleanup)

    def atlas(self):
        value = {"source_commit": "a" * 40, "checks": 3, "failures": [],
                 "baseline_sha256": list(review.EXPECTED_RGBA), "candidate_sha256": list(review.EXPECTED_RGBA),
                 "engine": "4.6.3-stable (official)", "display_server": "X11", "renderer": "gl_compatibility",
                 "player_data_used": False, "game_instance_created": False,
                 "runtime_requests": [{"name": name, "state": "ready", "prebaked": True,
                                       "rgba_sha256": review.EXPECTED_RGBA[i]} for i, name in enumerate(review.NAMES)]}
        self.write("atlas-parity.json", value)
        for filename in ("saved-png-check.json", "source-png-check.json"):
            self.write(filename, {"source_commit": "a" * 40, "failures": [], "rows": [
                {"name": name, "passed": True, "source_rgba": review.EXPECTED_RGBA[i],
                 "regenerated_rgba": review.EXPECTED_RGBA[i], "imported_rgba": review.EXPECTED_RGBA[i]}
                for i, name in enumerate(review.NAMES)]})
        return value

    def write(self, name, value):
        (self.folder / name).write_text(json.dumps(value))

    def test_fixed_native_five_paths_pass(self):
        self.atlas()
        self.assertEqual(review.check_atlas(self.folder, "a" * 40)["checks"], 3)

    def test_matching_generated_and_imported_is_not_its_own_reference(self):
        value = self.atlas()
        value["baseline_sha256"][0] = value["candidate_sha256"][0] = "0" * 64
        self.write("atlas-parity.json", value)
        with self.assertRaisesRegex(RuntimeError, "fixed references"):
            review.check_atlas(self.folder, "a" * 40)

    def test_headless_and_unofficial_renderer_refused(self):
        for key, value in (("display_server", "headless"), ("renderer", "vulkan"), ("engine", "4.6.2")):
            with self.subTest(key=key):
                record = self.atlas(); record[key] = value; self.write("atlas-parity.json", record)
                with self.assertRaisesRegex(RuntimeError, "native GL"):
                    review.check_atlas(self.folder, "a" * 40)

    def test_stale_source_and_missing_receipt_refused(self):
        self.atlas()
        with self.assertRaises(RuntimeError):
            review.check_atlas(self.folder, "b" * 40)
        self.write("saved-png-check.json", {"source_commit": "a" * 40, "failures": [], "rows": []})
        with self.assertRaisesRegex(RuntimeError, "PNG decoding"):
            review.check_atlas(self.folder, "a" * 40)

    def test_runtime_fallback_and_wrong_saved_pixels_refused(self):
        value = self.atlas(); value["runtime_requests"][1]["prebaked"] = False
        self.write("atlas-parity.json", value)
        with self.assertRaisesRegex(RuntimeError, "READY"):
            review.check_atlas(self.folder, "a" * 40)
        self.atlas()
        value = json.loads((self.folder / "source-png-check.json").read_text())
        value["rows"][2]["source_rgba"] = "0" * 64; self.write("source-png-check.json", value)
        with self.assertRaisesRegex(RuntimeError, "PNG reference"):
            review.check_atlas(self.folder, "a" * 40)

    def test_closure_rejects_count_hash_and_reference_changes(self):
        current = {str(i): str(i) for i in range(83)}
        for i, name in enumerate(sorted(review.STALE)):
            current.pop(str(i)); current[name] = str(i)
        previous = current.copy()
        manifest = {"source_sha256": previous, "atlases": {
            n: {"rgba_sha256": review.EXPECTED_RGBA[i]} for i, n in enumerate(review.NAMES)}}
        expected = review.digest(json.dumps(current, sort_keys=True, separators=(",", ":")).encode())
        with patch.object(review, "CLOSURE_SHA", expected):
            review.check_closure(current, manifest)
            with self.assertRaisesRegex(RuntimeError, "83-input"):
                review.check_closure({}, manifest)
            wrong = copy.deepcopy(current); wrong["82"] = "changed"
            with self.assertRaisesRegex(RuntimeError, "differs"):
                review.check_closure(wrong, manifest)
            wrong = copy.deepcopy(manifest); wrong["source_sha256"]["82"] = "stale"
            with self.assertRaisesRegex(RuntimeError, "Qualified source"):
                review.check_closure(current, wrong)
            wrong = copy.deepcopy(manifest); wrong["atlases"]["heads"]["rgba_sha256"] = "0" * 64
            with self.assertRaisesRegex(RuntimeError, "Fixed"):
                review.check_closure(current, wrong)

    def frames(self):
        # Deliberately structural PNG headers, not real screenshot/pixel evidence.
        for state in ("parking-unowned", "parking-owned"):
            for size in ((566, 360),):
                (self.folder / f"{state}-{size[0]}x{size[1]}.png").write_bytes(
                    b"\x89PNG\r\n\x1a\n" + b"\0" * 8 + struct.pack(">II", *size) + b"\0" * 1100)
        return ('Godot Engine v4.6.3.stable.official.7d41c59c4\nOpenGL API - Compatibility\n'
                'PARKING_DECOR_UI_RESULT {"checks":160,"failures":[],"player_save_used":false}\n')

    def test_two_parking_frame_contract_never_accepts_pixels(self):
        result = review.check_frames(self.folder, self.frames())
        self.assertEqual(len(result["frames"]), 2)
        self.assertFalse(result["pixels_inspected"])

    def test_missing_wrong_size_failed_or_headless_ui_refused(self):
        log = self.frames()
        for bad in (log.replace('"checks":160', '"checks":99'), log.replace('"failures":[]', '"failures":["bad"]'),
                    log.replace("OpenGL API", "headless"), log + log):
            with self.assertRaises(RuntimeError):
                review.check_frames(self.folder, bad)
        (self.folder / "parking-owned-566x360.png").write_bytes(b"not a PNG")
        with self.assertRaisesRegex(RuntimeError, "Invalid"):
            review.check_frames(self.folder, log)
        (self.folder / "parking-owned-566x360.png").unlink()
        with self.assertRaisesRegex(RuntimeError, "Incomplete"):
            review.check_frames(self.folder, log)

    def test_historical_helpers_and_fixture_are_pinned(self):
        for name, sha in review.HELPERS.items():
            self.assertEqual(review.file_sha(ROOT / "tests/diagnostics/canonical_atlas" / name), sha)
        self.assertEqual(len(review.EXPECTED_RGBA), 3)
        self.assertEqual(len(review.STALE), 4)
        self.assertEqual(review.REVIEWED_SOURCE, "9127a53d31258c28eaa37e06cc1752e8bd48b9f4")

    def test_only_reviewed_ui_postimages_may_change(self):
        names = ("main.gd", "shop.gd", "fixture.gd")
        for name in names:
            (self.folder / name).write_text(name)
        expected = {name: review.file_sha(self.folder / name) for name in names}
        with patch.object(review, "REVIEWED_POSTIMAGES", expected):
            review.check_reviewed_postimages(names, self.folder)
            with self.assertRaisesRegex(RuntimeError, "Unreviewed"):
                review.check_reviewed_postimages((*names, "model.gd"), self.folder)
            with self.assertRaisesRegex(RuntimeError, "Unreviewed"):
                review.check_reviewed_postimages(names[:-1], self.folder)
            (self.folder / names[0]).write_text("changed")
            with self.assertRaisesRegex(RuntimeError, "postimage"):
                review.check_reviewed_postimages(names, self.folder)

    def test_atlas_reuse_stays_bound_to_original_receipt(self):
        self.assertEqual(review.PRIOR_ATLAS["source"], "207409f5f19187e13f005de0f8a832b69f430cb9")
        self.assertEqual(review.PRIOR_ATLAS["receipt_sha256"], "ea7452ab917c85ae36f261e0372471291d1941254717e3b9736716dff7a18133")
        self.assertEqual(set(review.REVIEWED_POSTIMAGES), {"game/scripts/main.gd", "game/scripts/ui/cafe_shop_ui.gd",
            "game/scripts/ui/cafe_hud.gd", "game/data/prebaked_atlas_manifest.json", review.FIXTURE,
            "tests/presentation/test_storage_ui.gd", "tests/presentation/test_intro_lifecycle_headless.gd",
            "tests/presentation/test_toolbar_help.gd",
            "tests/presentation/test_hud_layout.gd", "tests/audio/test_feedback_sfx.gd"})
        self.assertEqual(review.REVIEWED_PARENT, "654cb9a873f6813b7838daa155d559bfcaf66122")
        self.check_current_postimages()
        source = (ROOT / "tools/diagnostics/storage_native_review.py").read_text()
        self.assertNotIn('run("atlas-native"', source)
        self.assertNotIn('run(name, engine +', source)

    def check_current_postimages(self):
        # The retired 875d6df capture and its pins remain unchanged. This one
        # later, uncaptured subpixel alignment fix requires ordinary CI qualification,
        # not a new native visual receipt. PR329 adds only reviewed mail refresh hooks
        # to Main; these are uncaptured by the old Storage fixture and will be
        # independently bound by the mail capture. PR351 separately regenerated all
        # three atlases with exact original pixels and adopted two source hashes.
        # PR352 independently repeats original-three qualification for standby retention.
        # Neither successor manifest is evidence from the old Storage capture. Other pins stay.
        for name, captured_sha in review.REVIEWED_POSTIMAGES.items():
            expected = captured_sha
            if name == "game/scripts/ui/cafe_shop_ui.gd":
                self.assertEqual(captured_sha, "5d3590d6e715eb5f09c2d82a11eaa99e4ca6d1da31e0638acbdeb9eecb3da22f")
                expected = "5854f2deabb6d99781847c33497a3eb66fb0a1a99f40f755b2b51820a15e12e3"
            if name == "game/scripts/main.gd":
                self.assertEqual(captured_sha, "4c1fb1afcb0d1c72797bd42b07937bb5828f4c389f0e1607a57c1aa9a50192be")
                expected = "a585cfa764e893bb974343fe8dc77d5365ff8b8ac7ae17be5dbf6167bdf47b78"
            if name == "game/data/prebaked_atlas_manifest.json":
                self.assertEqual(captured_sha, "81724088c204877ce1f31d2620f8cd9db27aabffca12f2bc3d74d813c526b283")
                expected = "b1c1150d3690125045a85c2f3e8b3575efe11b4ecb10061e62a3b2248a8c36ac"
            self.assertEqual(review.file_sha(ROOT / name), expected, name)

    def test_post_capture_exceptions_accept_only_exact_qualified_postimages(self):
        expected = dict(review.REVIEWED_POSTIMAGES)
        expected["game/scripts/ui/cafe_shop_ui.gd"] = "5854f2deabb6d99781847c33497a3eb66fb0a1a99f40f755b2b51820a15e12e3"
        expected["game/scripts/main.gd"] = "a585cfa764e893bb974343fe8dc77d5365ff8b8ac7ae17be5dbf6167bdf47b78"
        expected["game/data/prebaked_atlas_manifest.json"] = "b1c1150d3690125045a85c2f3e8b3575efe11b4ecb10061e62a3b2248a8c36ac"
        def current(path):
            return expected[path.relative_to(ROOT).as_posix()]
        with patch.object(review, "file_sha", side_effect=current):
            self.check_current_postimages()
            for name in ("game/scripts/ui/cafe_shop_ui.gd", "game/scripts/main.gd", "game/data/prebaked_atlas_manifest.json"):
                exact = expected[name]
                expected[name] = "0" * 64
                with self.assertRaises(AssertionError):
                    self.check_current_postimages()
                expected[name] = exact

    def test_qualified_manifest_keeps_complete_old_provenance_and_new_receipt(self):
        manifest = json.loads((ROOT / "game/data/prebaked_atlas_manifest.json").read_text())
        old, separator, current = manifest["provenance"].partition("; PR351 wall-slice retention qualification ")
        self.assertTrue(separator)
        self.assertEqual(review.digest(old.encode()), "692ba2e9ec9079827a41275b7a57b055a356dfe4636b7a9000e3153b1f7f6091")
        self.assertIn("source cdcebf38d3a2b0f2f548fc6bd799bd53b08bbaa5 / tree ddf72dd27b78431a7e773ee65a1e56446ab528f0", current)
        self.assertIn("https://github.com/yiyousiow000814/little-leaf/actions/runs/39027499315", current)
        self.assertIn("92a7df57c6cbc61473e85518d2dfa8d19f734ac5190a0031852ede9e3d1e373b", current)
        self.assertIn("b23351e0973159c2033c8d8fbe169c6f31f596cef99a9d00b773bc61a9f1078b", current)
        self.assertEqual(tuple(manifest["atlases"][name]["rgba_sha256"] for name in review.NAMES), review.EXPECTED_RGBA)

    def test_standby_manifest_preserves_entire_prior_provenance(self):
        manifest = json.loads((ROOT / "game/data/prebaked_atlas_manifest.json").read_text())
        prior, separator, current = manifest["provenance"].partition("; PR352 standby retention qualification ")
        self.assertTrue(separator)
        self.assertEqual(review.digest(prior.encode()), "6272265281c71dd6c892e5b1b7d4047bd1d83669dd3ba7130cc8d92da7f5a243")
        self.assertIn("source 6b89414ced6240a277259e89dd215f5c9a09d0cd / tree 44f68461777f0637b8bc493c1f2ee0d0b54518b3", current)
        self.assertIn("https://github.com/yiyousiow000814/little-leaf/actions/runs/39037439249", current)
        self.assertIn("37d9904f066b111c8b7ece5b53f2339459760f52f1a04378f11ede1362fd28e2", current)
        self.assertIn("6117588144ac91122aadd90d6651fff158b07dd1647f6ba3b9ef992fff1dabde", current)
        self.assertEqual(manifest["source_sha256"]["scripts/rendering/cafe_native_draw_node.gd"], "485c298089fb735ccad3e99af0980b19eb4d44b5e434b1f1dc2c1a7c6baa60a3")
        self.assertEqual(manifest["source_sha256"]["scripts/rendering/illustrated_cafe.gd"], "11ff59969cf60918b5e2b48c1df7f436b76d48ee9798530d82d8caa7d178023e")

    def test_engine_error_is_retained_and_stops_before_timeout(self):
        log = self.folder / "early-error.log"
        started = time.monotonic()
        code, reason = review.execute_native(
            [sys.executable, "-c", 'import time; print("SCRIPT ERROR: synthetic", flush=True); time.sleep(60)'],
            os.environ.copy(), log, timeout=10)
        self.assertNotEqual(code, 0)
        self.assertEqual(reason, "engine reported an error")
        self.assertIn("SCRIPT ERROR: synthetic", log.read_text())
        self.assertLess(time.monotonic() - started, 5)

    def test_silent_owned_process_is_bounded(self):
        code, reason = review.execute_native([sys.executable, "-c", "import time; time.sleep(60)"],
                                            os.environ.copy(), self.folder / "timeout.log", timeout=.15)
        self.assertNotEqual(code, 0)
        self.assertEqual(reason, "native stage timed out")

    def test_workflow_is_read_only_pr349_and_not_a_deployment_route(self):
        text = (ROOT / ".github/workflows/storage-native-review.yml").read_text()
        for required in ("number == 349", "feat/decorate-storage", "contents: read", "persist-credentials: false",
                         "github.event.pull_request.head.sha == '875d6df54327ab410b659facfb544b0a61dc4ed6'",
                         "--native-only", "github.event.pull_request.head.sha", "if: always()"):
            self.assertIn(required, text)
        for forbidden in ("workflow_dispatch", "pull_request_target", "secrets.", "write-manifest", "build_web.py",
                          "firebase", "needs:", "contents: write", "id-token:"):
            self.assertNotIn(forbidden, text)


if __name__ == "__main__":
    unittest.main()
