"""Fast diagnostic/source guards; synthetic PNG headers are not pixel evidence."""
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("mail_review", ROOT / "tools/diagnostics/mail_native_review.py")
review = importlib.util.module_from_spec(spec)
spec.loader.exec_module(review)


class MailNativeReviewTests(unittest.TestCase):
    def test_exact_postimages_and_no_unreviewed_production(self):
        review.verify_postimages(review.REVIEWED_POSTIMAGES, ROOT)
        with self.assertRaisesRegex(RuntimeError, "paths"):
            review.verify_postimages([*review.REVIEWED_POSTIMAGES, "game/scripts/unreviewed.gd"], ROOT)
        for name in ("game/scripts/main.gd", "platform/firebase/support_mail_service.mjs", review.FIXTURE):
            original = review.sha
            with patch.object(review, "sha", side_effect=lambda p: "0" * 64 if p == ROOT / name else original(p)):
                with self.assertRaises(RuntimeError):
                    review.verify_postimages(review.REVIEWED_POSTIMAGES, ROOT)

    def test_fifteen_frames_are_structural_evidence_not_acceptance(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            for surface in review.SURFACES:
                for size in review.SIZES:
                    (folder / f"{surface}-{size}.png").write_bytes(b"\x89PNG\r\n\x1a\n" + b"\0" * 8
                        + struct.pack(">II", *map(int, size.split("x"))) + b"\0" * 1100)
            receipt = {"synthetic_only": True, "player_save_used": False, "rendered_pngs": True,
                       "display": "X11", "renderer": "gl_compatibility"}
            (folder / "capture-receipt.json").write_text(json.dumps(receipt))
            log = 'OpenGL API - Compatibility\nSUPPORT_MAIL_UI_RESULT {"checks":200,"failures":[]}\n'
            result = review.check_frames(folder, log)
            self.assertEqual(len(result["frames"]), 15)
            self.assertFalse(result["pixels_inspected"])
            for bad in (log.replace("OpenGL API", "headless"), log + log,
                        log.replace('"failures":[]', '"failures":["overflow"]')):
                with self.assertRaises(RuntimeError):
                    review.check_frames(folder, bad)
            receipt["player_save_used"] = True
            (folder / "capture-receipt.json").write_text(json.dumps(receipt))
            with self.assertRaisesRegex(RuntimeError, "isolated"):
                review.check_frames(folder, log)

    def test_workflow_is_same_repo_read_only_and_has_no_deployment_route(self):
        source = (ROOT / ".github/workflows/mail-native-review.yml").read_text()
        for required in ("number == 329", "codex/support-mail-gifts-item20-011", "contents: read",
                         "head.repo.full_name == github.repository", "persist-credentials: false",
                         "--native-only", "--verify-only", "if: always()", "--ignore-scripts",
                         "setup-node@249970729cb0ef3589644e2896645e5dc5ba9c38", "node-version: '22.20.0'",
                         "GOOGLE_APPLICATION_CREDENTIALS: ''", "FIREBASE_TOKEN: ''"):
            self.assertIn(required, source)
        for forbidden in ("workflow_dispatch", "pull_request_target", "secrets.", "write-manifest",
                          "firebase deploy", "contents: write", "id-token:", "rules deploy"):
            self.assertNotIn(forbidden, source)
        self.assertNotIn("functions", json.loads((ROOT / "platform/firebase/firebase.json").read_text()))

    def test_admin_emulator_fixtures_refuse_non_loopback_before_initialization(self):
        for name in ("support_mail.test.mjs", "support_mail_audience.emulator.test.mjs", "support_storage_routing.rules.test.mjs", "support_mail_rules.test.mjs"):
            source = (ROOT / "platform/firebase" / name).read_text()
            self.assertIn("FIRESTORE_EMULATOR_HOST||''", source)
            self.assertIn("127\\.0\\.0\\.1|localhost", source)
            self.assertLess(source.index("assert.match(process.env.FIRESTORE_EMULATOR_HOST"), source.index("initializeTestEnvironment({" if name=="support_mail_rules.test.mjs" else "initializeApp({"))
            self.assertIn("projectId:'demo-little-leaf", source)

    def test_reuses_retained_native_and_atlas_guards_without_regeneration(self):
        source = (ROOT / "tools/diagnostics/mail_native_review.py").read_text()
        for required in ("native.execute_native", "native.check_closure", "atlas.asset(name)", "stage_project",
                         '"atlas_regenerated": False', '"player_save_used": False', "OLD_PR_HEAD"):
            self.assertIn(required, source)
        self.assertNotIn("--write-manifest", source)
        self.assertNotIn('run("atlas-native"', source)
        self.assertEqual(review.BASE, "f6ebeccd9fb8d2ded28895dc2f134c2a491f1ced")


if __name__ == "__main__":
    unittest.main()
