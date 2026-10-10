"""Offline API fixtures only; no dispatch, renderer, browser or credential use."""
import copy
import unittest
from firebase_release_gate import plan_release, REPOSITORY, ITCH_WORKFLOW, QUALIFICATION_WORKFLOW


class FirebaseReleaseGateTests(unittest.TestCase):
    def setUp(self):
        def run(identity, workflow):
            return {"id": identity, "run_attempt": 1, "repository": {"full_name": REPOSITORY},
                    "head_repository": {"full_name": REPOSITORY}, "path": workflow,
                    "event": "push", "head_branch": "main", "head_sha": "a" * 40,
                    "status": "completed", "conclusion": "success"}
        release = run(10, ITCH_WORKFLOW); release["head_branch"] = "v0.1.10b"
        self.args = dict(release_run=release,
                         publish_jobs=[{"name": "publish", "run_id": 10, "run_attempt": 1,
                                        "status": "completed", "conclusion": "success"}],
                         tag="v0.1.10b", tag_commit="a" * 40, tag_tree="b" * 40,
                         project_version="0.1.10b", qualification_run=run(20, QUALIFICATION_WORKFLOW),
                         qualification_receipt={"schema_version": 1, "repository": REPOSITORY,
                            "workflow": QUALIFICATION_WORKFLOW, "qualification_run_id": 20,
                            "qualification_attempt": 1, "source_commit": "a" * 40,
                            "source_tree": "b" * 40, "version": "0.1.10b", "artifact_id": 30,
                            "artifact_digest": "sha256:" + "c" * 64,
                            "mandatory_gate_success": True, "qualified_manifest_sha256": "d" * 64,
                            "packed_startup": "passed"},
                         qualification_artifact={"id": 30, "workflow_run": {"id": 20},
                                                 "expired": False, "digest": "sha256:" + "c" * 64})
        names = ["source_sha", "release_tag", "qualification_run_id", "qualification_attempt",
                 "qualification_artifact_id", "qualification_artifact_digest", "qualified_manifest_sha256"]
        self.contract = {"schema_version": 1, "workflow": "stage-firebase.yml", "ref": "main",
                         "workflow_blob_sha": "e" * 40, "reuse_qualified_only": True,
                         "checks_out_exact_source": True, "input_names": {n: "reuse_" + n for n in names}}

    def test_missing_interface_is_blocked_and_inputs_are_not_guessed(self):
        before = copy.deepcopy(self.args)
        plan = plan_release(**self.args)
        self.assertEqual(plan["status"], "interface-pending")
        self.assertIs(plan["dispatch_allowed"], False)
        self.assertEqual(plan["inputs"], {})
        self.assertEqual(plan["live_status"], "security-cutover-blocked")
        self.assertEqual(before, self.args)

    def test_reviewed_contract_maps_exact_source_without_live_permission(self):
        plan = plan_release(**self.args, stage_contract=self.contract)
        self.assertIs(plan["dispatch_allowed"], True)
        self.assertEqual(plan["ref"], "main")
        self.assertEqual(plan["inputs"]["reuse_source_sha"], "a" * 40)
        self.assertEqual(plan["inputs"]["reuse_release_tag"], "v0.1.10b")
        self.assertEqual(plan["live_status"], "security-cutover-blocked")

    def test_rejects_failed_skipped_missing_ambiguous_or_wrong_attempt_publish(self):
        for jobs in [[], self.args["publish_jobs"] * 2,
                     [{**self.args["publish_jobs"][0], "conclusion": "skipped"}],
                     [{**self.args["publish_jobs"][0], "conclusion": "failure"}],
                     [{**self.args["publish_jobs"][0], "run_attempt": 2}]]:
            with self.subTest(jobs=jobs), self.assertRaises(ValueError):
                plan_release(**{**self.args, "publish_jobs": jobs})

    def test_rejects_release_tag_source_and_version_mismatch(self):
        for key, value in [("tag", "v0.1.10bb"), ("tag", "v0.1.10a"),
                           ("tag_commit", "f" * 40), ("project_version", "0.1.11"),
                           ("tag_tree", "f" * 40)]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                plan_release(**{**self.args, key: value})

    def test_rejects_untrusted_and_pr_qualification_runs(self):
        for key, value in [("event", "pull_request"), ("head_branch", "feature"),
                           ("path", ITCH_WORKFLOW), ("conclusion", "failure"),
                           ("head_sha", "f" * 40), ("head_repository", {"full_name": "other/repo"})]:
            args = copy.deepcopy(self.args); args["qualification_run"][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError): plan_release(**args)

    def test_accepts_main_manual_qualification_but_not_manual_release(self):
        args = copy.deepcopy(self.args); args["qualification_run"]["event"] = "workflow_dispatch"
        self.assertEqual(plan_release(**args)["status"], "interface-pending")
        args["release_run"]["event"] = "workflow_dispatch"
        with self.assertRaises(ValueError): plan_release(**args)

    def test_release_main_branch_and_old_attempt_alias_are_rejected(self):
        args = copy.deepcopy(self.args); args["release_run"]["head_branch"] = "main"
        with self.assertRaises(ValueError): plan_release(**args)
        args = copy.deepcopy(self.args)
        args["qualification_receipt"]["qualification_run_attempt"] = args["qualification_receipt"].pop("qualification_attempt")
        with self.assertRaises(ValueError): plan_release(**args)

    def test_rejects_invalid_receipt_and_artifact_binding(self):
        for key, value in [("schema_version", True), ("mandatory_gate_success", "true"),
                           ("packed_startup", "skipped"), ("artifact_digest", "c" * 64),
                           ("qualified_manifest_sha256", "d" * 63), ("qualification_attempt", 2),
                           ("version", "0.1.10a"), ("artifact_id", 31)]:
            args = copy.deepcopy(self.args); args["qualification_receipt"][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError): plan_release(**args)
        for key, value in [("expired", True), ("digest", "sha256:" + "f" * 64),
                           ("workflow_run", {"id": 99})]:
            args = copy.deepcopy(self.args); args["qualification_artifact"][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError): plan_release(**args)

    def test_ledger_blocks_reruns_same_tag_source_and_uncertain_requests(self):
        for ledger in [[{}], [{"release_run_id": 10, "release_run_attempt": 2, "release_tag": "v0.1.9", "source_commit": "f" * 40}],
                       [{"release_run_id": 9, "release_run_attempt": 1, "release_tag": "v0.1.10b", "source_commit": "f" * 40}],
                       [{"release_run_id": 9, "release_run_attempt": 1, "release_tag": "v0.1.9", "source_commit": "a" * 40}]]:
            with self.subTest(ledger=ledger), self.assertRaises(ValueError):
                plan_release(**self.args, prior_requests=ledger)

    def test_contract_cannot_fall_back_to_fresh_build_or_tag_workflow(self):
        for key, value in [("reuse_qualified_only", False), ("checks_out_exact_source", False),
                           ("ref", "v0.1.10b"), ("input_names", {}), ("workflow_blob_sha", "bad")]:
            contract = {**self.contract, key: value}
            with self.subTest(key=key), self.assertRaises(ValueError):
                plan_release(**self.args, stage_contract=contract)
