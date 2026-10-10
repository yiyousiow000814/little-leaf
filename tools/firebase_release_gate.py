"""Pure release-to-staging selection. Never dispatches or obtains credentials."""
import re

REPOSITORY = "yiyousiow000814/little-leaf"
ITCH_WORKFLOW = ".github/workflows/release-itch.yml"
QUALIFICATION_WORKFLOW = ".github/workflows/ci.yml"
STAGE_WORKFLOW = "stage-firebase.yml"
TAG = r"v(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)[a-z]?"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def positive(value):
    return type(value) is int and value > 0


def hash_value(value, length):
    return isinstance(value, str) and re.fullmatch(r"[0-9a-f]{%d}" % length, value) is not None


def trusted_run(run, workflow, events=("push",)):
    require(run.get("repository", {}).get("full_name") == REPOSITORY
            and run.get("head_repository", {}).get("full_name") == REPOSITORY,
            "Run must originate in the exact repository")
    require(run.get("path") == workflow and run.get("event") in events
            and run.get("status") == "completed" and run.get("conclusion") == "success",
            "Expected a successful completed trusted workflow event")
    require(positive(run.get("id")) and positive(run.get("run_attempt")), "Invalid run identity")
    require(hash_value(run.get("head_sha"), 40), "Invalid run source")


def plan_release(*, release_run, publish_jobs, tag, tag_commit, tag_tree,
                 project_version, qualification_run, qualification_receipt,
                 qualification_artifact, prior_requests=(), stage_contract=None):
    """Validate caller-fetched API objects and immutable tagged metadata.

    Caller must fetch *all* jobs for the selected release attempt, peel the tag,
    read project metadata at that commit, and retain a serialized request ledger.
    A returned plan is not proof that a dispatch or deployment happened.
    """
    trusted_run(release_run, ITCH_WORKFLOW)
    require(isinstance(tag, str) and re.fullmatch(TAG, tag), "Invalid immutable release tag")
    require(release_run.get("head_branch") == tag, "Release run must originate at the exact tag")
    require(hash_value(tag_commit, 40) and hash_value(tag_tree, 40), "Invalid tag source binding")
    require(release_run["head_sha"] == tag_commit and tag == "v" + project_version,
            "Release/tag/project version mismatch")
    publishes = [job for job in publish_jobs if job.get("name") == "publish"]
    require(len(publishes) == 1, "Missing or ambiguous publish job")
    job = publishes[0]
    require(job.get("run_id") == release_run["id"]
            and job.get("run_attempt") == release_run["run_attempt"]
            and job.get("status") == "completed" and job.get("conclusion") == "success",
            "Exact release attempt did not publish successfully")

    trusted_run(qualification_run, QUALIFICATION_WORKFLOW, ("push", "workflow_dispatch"))
    require(qualification_run.get("head_branch") == "main", "Qualification must be a main push")
    receipt = qualification_receipt
    require(type(receipt.get("schema_version")) is int and receipt["schema_version"] == 1,
            "Unsupported qualification schema")
    require(positive(receipt.get("qualification_run_id"))
            and positive(receipt.get("qualification_attempt")), "Invalid receipt run identity")
    expected = {"repository": REPOSITORY, "workflow": QUALIFICATION_WORKFLOW,
                "qualification_run_id": qualification_run["id"],
                "qualification_attempt": qualification_run["run_attempt"],
                "source_commit": tag_commit, "source_tree": tag_tree,
                "version": project_version, "packed_startup": "passed"}
    require(all(receipt.get(key) == value for key, value in expected.items()),
            "Qualification receipt identity mismatch")
    require(qualification_run["head_sha"] == tag_commit,
            "Qualification source differs from release")
    require(receipt.get("mandatory_gate_success") is True,
            "Every mandatory qualification gate must pass")
    require(hash_value(receipt.get("qualified_manifest_sha256"), 64), "Invalid qualified manifest hash")
    artifact = qualification_artifact
    require(positive(receipt.get("artifact_id")) and artifact.get("id") == receipt["artifact_id"]
            and artifact.get("workflow_run", {}).get("id") == qualification_run["id"]
            and artifact.get("expired") is False, "Invalid qualification artifact origin")
    digest = receipt.get("artifact_digest")
    require(isinstance(digest, str) and re.fullmatch(r"sha256:[0-9a-f]{64}", digest)
            and artifact.get("digest") == digest, "Invalid qualification artifact digest")

    require(isinstance(prior_requests, (list, tuple)), "Request ledger must be complete")
    for previous in prior_requests:
        require(isinstance(previous, dict) and positive(previous.get("release_run_id"))
                and positive(previous.get("release_run_attempt"))
                and isinstance(previous.get("release_tag"), str)
                and re.fullmatch(TAG, previous["release_tag"])
                and hash_value(previous.get("source_commit"), 40), "Malformed request ledger")
        require(previous["release_run_id"] != release_run["id"]
                and previous["release_tag"] != tag and previous["source_commit"] != tag_commit,
                "Duplicate or uncertain release request; inspect before retrying")
    plan = {"schema_version": 1, "status": "interface-pending", "dispatch_allowed": False,
            "repository": REPOSITORY,
            "release_run_id": release_run["id"], "release_run_attempt": release_run["run_attempt"],
            "release_tag": tag, "source_commit": tag_commit, "source_tree": tag_tree,
            "version": project_version, "workflow": STAGE_WORKFLOW, "ref": "main",
            "inputs": {},
            "live_status": "security-cutover-blocked"}
    if stage_contract is None:
        return plan
    values = {"source_sha": tag_commit, "release_tag": tag,
              "qualification_run_id": str(qualification_run["id"]),
              "qualification_attempt": str(qualification_run["run_attempt"]),
              "qualification_artifact_id": str(receipt["artifact_id"]),
              "qualification_artifact_digest": digest,
              "qualified_manifest_sha256": receipt["qualified_manifest_sha256"]}
    require(type(stage_contract.get("schema_version")) is int and stage_contract["schema_version"] == 1
            and stage_contract.get("workflow") == STAGE_WORKFLOW
            and stage_contract.get("ref") == "main"
            and stage_contract.get("reuse_qualified_only") is True
            and stage_contract.get("checks_out_exact_source") is True
            and hash_value(stage_contract.get("workflow_blob_sha"), 40),
            "Reviewed exact-source reuse capability required")
    names = stage_contract.get("input_names", {})
    require(set(names) == set(values) and all(isinstance(n, str)
            and re.fullmatch(r"[a-z][a-z0-9_]*", n) for n in names.values())
            and len(set(names.values())) == len(names), "Ambiguous or incomplete reuse input contract")
    plan.update(status="staging-plan-only", dispatch_allowed=True,
                stage_workflow_blob_sha=stage_contract["workflow_blob_sha"],
                inputs={names[key]: value for key, value in values.items()})
    return plan
