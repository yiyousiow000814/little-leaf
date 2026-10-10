"""Offline release safety checks. These tests cannot authenticate or publish."""
import copy
from datetime import date, timedelta
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import install_tools
from build_web import copy_notices, verify_installer_receipt
import publish_itch as publisher
import subprocess
from types import SimpleNamespace
from publish_itch import check_previous, completed, parse_result, verify_artifact
from release_metadata import version, require_main_ancestor, release_key

SHA = "a" * 40


def status(v="0.1.5", state="completed", pending=None):
    result = {"target": "siowyiyou/little-leaf", "channels": [
        {"name": "html5", "uploadId": 123, "head": {"id": 55, "state": state, "userVersion": v}}]}
    if pending:
        result["channels"][0]["pending"] = pending
    return result


class MetadataTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "data").mkdir()
        (self.root / "project.godot").write_text('config/version="0.1.6"\n')
        self.notes = {"version": "0.1.6", "status": "released", "date": "2026-01-01", "fixed": ["Test"]}
        self.save()

    def save(self):
        (self.root / "data/release_notes.json").write_text(json.dumps(self.notes))

    def test_match(self):
        self.assertEqual(version(self.root, "v0.1.6"), "0.1.6")

    def test_hotfix_metadata_matches_exactly(self):
        for suffix in "abcz":
            value = "0.1.10" + suffix
            (self.root / "project.godot").write_text('config/version="' + value + '"\n')
            self.notes["version"] = value; self.save()
            self.assertEqual(version(self.root, "v" + value), value)
            for tag in ["v0.1.10", "v0.1.10aa", "v0.1.11"]:
                with self.subTest(tag=tag), self.assertRaises(ValueError): version(self.root, tag)
            self.notes["status"] = "draft"; self.save()
            with self.assertRaises(ValueError): version(self.root, "v" + value)
            self.notes["status"] = "released"

    def test_invalid_hotfix_metadata(self):
        for value in ["0.1.10A", "0.1.10aa", "0.1.10a1", "0.1.10-a", "0.1.10a-dev.1", "0.1.10a+build.1", "00.1.10a"]:
            (self.root / "project.godot").write_text('config/version="' + value + '"\n')
            self.notes["version"] = value; self.save()
            with self.subTest(value=value), self.assertRaises(ValueError): version(self.root, "v" + value)

    def test_ci_does_not_require_release_status(self):
        self.notes["status"] = "draft"; self.save()
        self.assertEqual(version(self.root), "0.1.6")

    def test_wrong_tag(self):
        for tag in ["0.1.6", "v0.1.5", "v0.1.6-rc1", "v01.1.6", "v0.1.6\n"]:
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                version(self.root, tag)

    def test_mismatched_notes(self):
        self.notes["version"] = "0.1.5"; self.save()
        with self.assertRaises(ValueError): version(self.root)

    def test_release_not_ready(self):
        for field, value in [("status", "draft"), ("date", str(date.today() + timedelta(days=1))), ("fixed", [])]:
            with self.subTest(field=field):
                original = copy.deepcopy(self.notes)
                self.notes[field] = value; self.save()
                with self.assertRaises(ValueError): version(self.root, "v0.1.6")
                self.notes = original

    def test_project_version_strict(self):
        for text in ['config/version="0.01.6"', 'config/version="0.1.6-dev.1"', '',
                     'config/version="0.1.6"\nconfig/version="0.1.6"']:
            (self.root / "project.godot").write_text(text)
            with self.assertRaises(ValueError): version(self.root)

    def test_stable_019_metadata_never_accepts_diagnostic_tags(self):
        (self.root / "project.godot").write_text('config/version="0.1.9"\n')
        self.notes["version"] = "0.1.9"; self.save()
        self.assertEqual(version(self.root, "v0.1.9"), "0.1.9")
        for tag in ["v0.1.9-alpha-1", "v0.1.9-alpha-2", "v0.1.9-alpha-3", "v0.1.8", "v0.1.10"]:
            with self.subTest(tag=tag), self.assertRaises(ValueError): version(self.root, tag)
        for value in ["0.1.9-alpha-1", "0.1.9-alpha-2"]:
            (self.root / "project.godot").write_text('config/version="' + value + '"\n')
            self.notes["version"] = value; self.save()
            with self.subTest(value=value), self.assertRaises(ValueError): version(self.root, "v" + value)


class ReleaseNotesContractTests(unittest.TestCase):
    """Guard the checked-in draft contract without adding CI dependencies."""
    root = Path(__file__).resolve().parents[2]

    def test_checked_in_document_uses_declared_schema_fields_and_status(self):
        notes = json.loads((self.root / "data/release_notes.json").read_text())
        schema = json.loads((self.root / "data/release_notes.schema.json").read_text())
        self.assertFalse(schema["additionalProperties"])
        self.assertTrue(set(schema["required"]).issubset(notes))
        self.assertTrue(set(notes).issubset(schema["properties"]))
        self.assertIn(notes["status"], schema["properties"]["status"]["enum"])
        self.assertEqual(schema["properties"]["schema_version"]["const"], notes["schema_version"])
        self.assertIn("draft", schema["properties"]["status"]["enum"])
        review = schema["properties"]["review_pending"]
        self.assertEqual(review["type"], "array")
        self.assertEqual(review["items"], {"type": "string", "minLength": 1, "pattern": r"\S"})
        for item in notes.get("review_pending", []):
            self.assertIsInstance(item, str)
            self.assertTrue(item.strip())

    def test_hotfix_keeps_exact_major_update_history(self):
        import hashlib
        notes=json.loads((self.root / "data/release_notes.json").read_text())
        self.assertEqual(notes["version"],"0.1.10a")
        self.assertEqual(len(notes["history"]),1)
        previous=notes["history"][0]
        self.assertEqual(previous["version"],"0.1.10")
        self.assertNotIn("history",previous)
        digest=hashlib.sha256(json.dumps(previous,sort_keys=True,separators=(",",":"),ensure_ascii=False).encode()).hexdigest()
        self.assertEqual(digest,"97d1d9f9ae3d93c809476611d5cc26d57782f12a44fa37cc46cb875158e1348d")
        schema=json.loads((self.root / "data/release_notes.schema.json").read_text())
        self.assertNotIn("history",schema["$defs"]["historicalRelease"]["properties"])

    def test_draft_with_populated_review_metadata_is_never_publishable(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "data").mkdir()
            (root / "project.godot").write_text('config/version="0.1.10"\n')
            notes = {"schema_version": 1, "status": "draft", "version": "0.1.10",
                     "date": "2026-01-01", "label": "Candidate", "new": ["Candidate change"],
                     "fixed": [], "review_pending": ["Visual acceptance still open"]}
            (root / "data/release_notes.json").write_text(json.dumps(notes))
            self.assertEqual(version(root), "0.1.10")
            with self.assertRaisesRegex(ValueError, "marked released"):
                version(root, "v0.1.10")


class MainHistoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.git("init", "--initial-branch=main")
        (self.root / "example.txt").write_text("reviewed")
        self.git("add", "example.txt")
        self.git("commit", "-m", "reviewed baseline")
        self.base = self.git("rev-parse", "HEAD")

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.root), "-c", "user.name=CI fixture",
                                        "-c", "user.email=ci@example.invalid", *args],
                                       text=True, stderr=subprocess.DEVNULL).strip()

    def test_current_main_accepted(self):
        self.git("fetch", ".", "main")
        require_main_ancestor(self.root)

    def test_main_advance_does_not_block_fixed_tag(self):
        self.git("commit", "--allow-empty", "-m", "later reviewed work")
        self.git("fetch", ".", "main")
        self.git("checkout", "--detach", self.base)
        require_main_ancestor(self.root)

    def test_unmerged_branch_rejected(self):
        self.git("checkout", "-b", "unmerged")
        self.git("commit", "--allow-empty", "-m", "unreviewed work")
        self.git("fetch", ".", "main")
        with self.assertRaises(ValueError): require_main_ancestor(self.root)


class ItchGuardTests(unittest.TestCase):
    def test_completed_alpha2_can_promote_to_stable_019(self):
        self.assertEqual(check_previous(status("0.1.9-alpha-2"), "0.1.9"), 55)

    def test_stable_019_still_rejects_duplicate_or_newer_baselines(self):
        for value in ["0.1.9", "v0.1.9", "0.1.9+build.2", "0.1.10-alpha-2", "0.1.10", "0.2.0"]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                check_previous(status(value), "0.1.9")

    def test_alpha2_promotion_requires_completed_idle_channel(self):
        for state in ["failed", "started", "processing", "queued", "canceled"]:
            with self.subTest(state=state), self.assertRaises(ValueError):
                check_previous(status("0.1.9-alpha-2", state=state), "0.1.9")
        with self.assertRaises(ValueError):
            check_previous(status("0.1.9-alpha-2", pending={"id": 56, "state": "processing"}), "0.1.9")

    def test_alpha2_promotion_still_rejects_malformed_baselines(self):
        for value in ["0.1.9-alpha-2.", "0.1.9-alpha-2+", "0.1.9-alpha-2.01", "0.1.9-alpha-2\n"]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                check_previous(status(value), "0.1.9")

    def test_all_hotfix_ordering_pairs(self):
        versions = ["0.1.9", "0.1.10"] + ["0.1.10" + chr(c) for c in range(ord("a"), ord("z") + 1)] + ["0.1.11", "0.2.0", "1.0.0"]
        self.assertEqual(sorted(reversed(versions), key=release_key), versions)
        for old_index, old in enumerate(versions):
            for new_index, new in enumerate(versions):
                with self.subTest(old=old, new=new):
                    if old_index < new_index:
                        self.assertEqual(check_previous(status(old), new), 55)
                    else:
                        with self.assertRaises(ValueError): check_previous(status(old), new)

    def test_hotfix_legacy_and_prefixed_baselines(self):
        for old in ["0.1.5-dev.1", "v0.1.10-dev.1+build.2", "0.1.10+build.1", "v0.1.10a", "v0.1.10a+build.2"]:
            with self.subTest(old=old): self.assertEqual(check_previous(status(old), "0.1.10b"), 55)
        for old in ["v0.1.10b", "0.1.10b+build.2", "0.1.11-dev.1", "0.1.10aa", "0.1.10A", "0.1.10a-dev.1", "0.1.10a\n"]:
            with self.subTest(old=old), self.assertRaises(ValueError): check_previous(status(old), "0.1.10b")

    def test_invalid_new_release_never_orders(self):
        for new in ["0.1.10aa", "0.1.10A", "0.1.10-dev.1", "0.1.10+build.1", "v0.1.10a", "0.01.10a", "0.1.10a\n"]:
            with self.subTest(new=new), self.assertRaises(ValueError): check_previous(status(), new)

    def test_upgrade(self):
        self.assertEqual(check_previous(status(), "0.1.6"), 55)

    def test_legacy_dev_version(self):
        self.assertEqual(check_previous(status("0.1.5-dev.1"), "0.1.6"), 55)

    def test_same_base_prerelease_upgrade(self):
        self.assertEqual(check_previous(status("0.1.6-rc.1"), "0.1.6"), 55)

    def test_build_metadata_and_prefixed_version(self):
        self.assertEqual(check_previous(status("v0.1.5-dev.1+build.02"), "0.1.6"), 55)

    def test_status_and_push_timeouts(self):
        output = json.dumps({"type": "result", "value": {}})
        with patch.object(publisher.subprocess, "run", return_value=SimpleNamespace(returncode=0, stdout=output)) as run:
            publisher.butler("status", publisher.TARGET)
            self.assertEqual(run.call_args.kwargs["timeout"], 60)
            publisher.butler("push", "synthetic", publisher.TARGET)
            self.assertEqual(run.call_args.kwargs["timeout"], 600)
            publisher.butler("status", publisher.TARGET, timeout=7)
            self.assertEqual(run.call_args.kwargs["timeout"], 7)

    def test_error_output_is_not_logged(self):
        with patch.object(publisher.subprocess, "run", return_value=SimpleNamespace(returncode=1, stdout="private diagnostic", stderr="private diagnostic")):
            with self.assertRaises(RuntimeError) as error: publisher.butler("status", publisher.TARGET)
            self.assertNotIn("private diagnostic", str(error.exception))

    def test_timeout_does_not_retry(self):
        with patch.object(publisher.subprocess, "run", side_effect=subprocess.TimeoutExpired("butler", 600)) as run:
            with self.assertRaises(subprocess.TimeoutExpired): publisher.butler("push", "synthetic", publisher.TARGET)
            self.assertEqual(run.call_count, 1)

    def test_semantic_numeric_order(self):
        self.assertEqual(check_previous(status("0.1.9"), "0.1.10"), 55)

    def test_duplicate_and_rollback(self):
        for v in ["0.1.6", "v0.1.6", "0.1.7", "1.0.0", "0.1.6+build.12"]:
            with self.subTest(v=v), self.assertRaises(ValueError): check_previous(status(v), "0.1.6")

    def test_pending_prevents_concurrency(self):
        with self.assertRaises(ValueError): check_previous(status(pending={"id": 56, "state": "processing"}), "0.1.6")

    def test_unknown_baseline_blocked(self):
        for v in ["", "latest", "01.1.5", "0.1", "0.1.5-..", "0.1.5-dev.", "0.1.5-01", "0.1.5+", "0.1.5+.."]:
            with self.subTest(v=v), self.assertRaises(ValueError): check_previous(status(v), "0.1.6")

    def test_noncompleted_baseline_blocked(self):
        for state in ["failed", "started", "processing", "queued"]:
            with self.subTest(state=state), self.assertRaises(ValueError): check_previous(status(state=state), "0.1.6")

    def test_wrong_or_missing_channel(self):
        for result in [{"target": "other/project", "channels": []}, {"target": "siowyiyou/little-leaf", "channels": []}]:
            with self.assertRaises(ValueError): check_previous(result, "0.1.6")

    def test_structured_result(self):
        text = json.dumps({"type": "log", "message": "processing"}) + "\n" + json.dumps({"type": "result", "value": status()})
        self.assertEqual(parse_result(text), status())

    def test_malformed_results(self):
        record = json.dumps({"type": "result", "value": {}})
        for text in ["", "not json", record + "\n" + record, '{"type":"error"}', '{"type":"result","value":null}']:
            with self.subTest(text=text), self.assertRaises(ValueError): parse_result(text)

    def test_completion_identity(self):
        self.assertTrue(completed(status("0.1.6"), 55, "0.1.6"))
        self.assertFalse(completed(status("0.1.6"), 56, "0.1.6"))
        self.assertFalse(completed(status("0.1.5"), 55, "0.1.6"))
        self.assertFalse(completed(status("0.1.6", "processing"), 55, "0.1.6"))

    def test_processing_failure(self):
        with self.assertRaises(RuntimeError): completed(status("0.1.6", "failed"), 55, "0.1.6")


class DistributionNoticeTests(unittest.TestCase):
    def test_notice_is_in_export_and_hash_bound(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            path = root / "docs/art-audio/third-party/GODOT-AA-LICENSE.txt"
            path.parent.mkdir(parents=True)
            path.write_text("Synthetic notice fixture")
            web = root / "web"
            web.mkdir()
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            source = "docs/art-audio/third-party/GODOT-AA-LICENSE.txt"
            result = copy_notices(root, web, {source: digest})
            self.assertEqual((web / "GODOT-AA-LICENSE.txt").read_bytes(), path.read_bytes())
            self.assertEqual(result[source]["sha256"], digest)
            with self.assertRaises(RuntimeError): copy_notices(root, web, {source: "different"})

    def test_missing_notice_blocks_export(self):
        with tempfile.TemporaryDirectory() as temp:
            with self.assertRaisesRegex(RuntimeError, "Required distribution notice"):
                copy_notices(Path(temp), Path(temp), {})


class ArtifactTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.web = Path(self.temp.name)
        files = {}
        for name in ["index.html", "index.js", "index.wasm", "index.pck"]:
            data = (name + " test bytes").encode()
            (self.web / name).write_bytes(data)
            files[name] = {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
        self.manifest = {"source_commit": SHA, "tag": "v0.1.6", "version": "0.1.6", "packed_smoke": "passed", "engine_checks": 1, "toolchain_verification": "checksum-pinned-official-archives", "files": files}
        self.save()

    def save(self):
        (self.web / "release-manifest.json").write_text(json.dumps(self.manifest))

    def verify(self):
        return verify_artifact(self.web, "v0.1.6", SHA)

    def test_valid(self): self.assertEqual(self.verify(), self.manifest)

    def test_hotfix_artifact_is_exact_and_fail_closed(self):
        self.manifest.update(tag="v0.1.10a", version="0.1.10a"); self.save()
        self.assertEqual(verify_artifact(self.web, "v0.1.10a", SHA), self.manifest)
        for tag in ["v0.1.10", "v0.1.10b", "v0.1.10aa", "v0.1.10A", "v0.1.10a\n"]:
            with self.subTest(tag=tag), self.assertRaises(ValueError): verify_artifact(self.web, tag, SHA)
        with self.assertRaises(ValueError): verify_artifact(self.web, "v0.1.10a", "b" * 40)
        (self.web / "index.js").write_text("tampered")
        with self.assertRaises(ValueError): verify_artifact(self.web, "v0.1.10a", SHA)

    def test_stable_019_requires_exact_stable_artifact(self):
        self.manifest.update(tag="v0.1.9", version="0.1.9"); self.save()
        self.assertEqual(verify_artifact(self.web, "v0.1.9", SHA), self.manifest)
        self.manifest.update(tag="v0.1.9-alpha-2", version="0.1.9-alpha-2"); self.save()
        with self.assertRaises(ValueError): verify_artifact(self.web, "v0.1.9", SHA)

    def test_diagnostic_artifacts_remain_ineligible_for_stable_publisher(self):
        for value in ["0.1.9-alpha-1", "0.1.9-alpha-2", "0.1.9-alpha-3"]:
            self.manifest.update(tag="v" + value, version=value); self.save()
            with self.subTest(value=value), self.assertRaises(ValueError):
                verify_artifact(self.web, "v" + value, SHA)

    def test_wrong_commit(self):
        self.manifest["source_commit"] = "b" * 40; self.save()
        with self.assertRaises(ValueError): self.verify()

    def test_not_release_build(self):
        self.manifest["tag"] = ""; self.save()
        with self.assertRaises(ValueError): self.verify()

    def test_changed_bytes(self):
        (self.web / "index.js").write_text("tampered")
        with self.assertRaises(ValueError): self.verify()

    def test_extra_file(self):
        (self.web / "unexpected.txt").write_text("no")
        with self.assertRaises(ValueError): self.verify()

    def test_missing_file(self):
        (self.web / "index.pck").unlink()
        with self.assertRaises(ValueError): self.verify()

    def test_no_checks(self):
        self.manifest["engine_checks"] = 0; self.save()
        with self.assertRaises(ValueError): self.verify()

    def test_local_tools_artifact_cannot_publish(self):
        self.manifest["toolchain_verification"] = "local-tools-unverified-for-release"; self.save()
        with self.assertRaises(ValueError): self.verify()

    def test_installer_receipt_binds_extracted_files(self):
        receipt = {}
        for name in ["godot", "templates"]:
            path = self.web / name
            path.write_text("synthetic fixture bytes for " + name)
            spec = install_tools.LOCK[name]
            receipt[name] = {"url": spec["url"], "archive_sha256": spec["sha256"], "member": spec["member"],
                             "member_sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
        receipt_path = self.web / "receipt.json"
        receipt_path.write_text(json.dumps(receipt))
        self.assertEqual(verify_installer_receipt(self.web / "godot", self.web / "templates", receipt_path), receipt)
        (self.web / "templates").write_text("changed after installation")
        with self.assertRaises(RuntimeError): verify_installer_receipt(self.web / "godot", self.web / "templates", receipt_path)

    def test_unsafe_ref(self):
        with self.assertRaises(ValueError): verify_artifact(self.web, "v0.1.6; echo bad", SHA)

    def test_symlink(self):
        (self.web / "index.js").unlink()
        (self.web / "index.js").symlink_to(self.web / "index.html")
        with self.assertRaises(ValueError): self.verify()

    def test_official_nested_archive_member(self):
        import io
        import zipfile
        archive = io.BytesIO()
        member = install_tools.LOCK["butler"]["member"]
        self.assertEqual(member, "linux-amd64/butler")
        with zipfile.ZipFile(archive, "w") as z:
            z.writestr(member, b"synthetic executable bytes, never executed")
            z.writestr("../unwanted.txt", b"must not extract")
        data = archive.getvalue()
        spec = {**install_tools.LOCK["butler"], "sha256": hashlib.sha256(data).hexdigest()}
        with patch.dict(install_tools.LOCK, {"butler": spec}):
            with patch.object(install_tools.urllib.request, "urlopen", return_value=io.BytesIO(data)):
                install_tools.install("butler", self.web / "butler")
        self.assertEqual((self.web / "butler").read_bytes(), b"synthetic executable bytes, never executed")
        self.assertFalse((self.web.parent / "unwanted.txt").exists())

    def test_missing_secret_never_calls_butler(self):
        with patch.dict(publisher.os.environ, {}, clear=True):
            with patch.object(publisher.argparse.ArgumentParser, "parse_args", return_value=SimpleNamespace(web=self.web, tag="v0.1.6", sha=SHA)):
                with patch.object(publisher, "butler") as command:
                    with self.assertRaisesRegex(RuntimeError, "Missing BUTLER_API_KEY"): publisher.main()
                    command.assert_not_called()

    def test_corrupt_tool_archive(self):
        import io
        with patch.object(install_tools.urllib.request, "urlopen", return_value=io.BytesIO(b"corrupt")):
            with self.assertRaises(RuntimeError): install_tools.install("butler", self.web / "butler")
        self.assertFalse((self.web / "butler").exists())


if __name__ == "__main__":
    unittest.main()
