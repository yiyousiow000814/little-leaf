"""Verify fixed artifact IDs, digests and successful build jobs. Read-only."""
import json
import os
from pathlib import Path
from urllib.request import Request, urlopen

REPO = "yiyousiow000814/little-leaf"
assert os.environ["GITHUB_REPOSITORY"] == REPO, "Unexpected repository"
SOURCES = (
    ("BASE", os.environ["BASE_COMMIT"], os.environ["BASE_COMMIT"], "push"),
    ("CANDIDATE", os.environ["GAMEPLAY_HEAD"], os.environ["CANDIDATE_COMMIT"], "pull_request"),
)
def api(path):
    headers = {
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    if token := os.environ.get("GH_TOKEN"):
        headers["Authorization"] = "Bearer " + token
    with urlopen(Request(f"https://api.github.com/repos/{REPO}/actions/{path}", headers=headers), timeout=12) as response:
        return json.load(response)

summary = []
for variant, head, build, event in SOURCES:
    run = int(os.environ[f"{variant}_RUN"])
    aid = int(os.environ[f"{variant}_ARCHIVE"])
    digest = os.environ[f"{variant}_DIGEST"]
    expected = f"little-leaf-ci-inputs-{build}-1"
    meta = api(f"runs/{run}")
    assert (meta["id"], meta["event"], meta["head_sha"], meta["run_attempt"]) == (
        run, event, head, 1
    ), "Unexpected run binding"
    assert meta["path"].split("@", 1)[0] == ".github/workflows/ci.yml", "Wrong producer workflow"
    if event == "pull_request":
        assert any(row["number"] == 364 for row in meta["pull_requests"]), "Wrong producer PR"
    jobs = api(f"runs/{run}/attempts/1/jobs?per_page=100")["jobs"]
    builds = [j for j in jobs if j["name"] == "web / build"]
    assert len(builds) == 1 and builds[0]["conclusion"] == "success", "Producer export build must succeed"
    artifact = api(f"artifacts/{aid}")
    assert (artifact["name"], artifact["digest"], artifact["workflow_run"]["id"]) == (
        expected, digest, run
    ), "Wrong archive name, signature or producer"
    assert not artifact["expired"] and artifact["size_in_bytes"] > 0, "Archive unavailable"
    summary.append({
        "run_id": run, "archive_id": aid, "archive_name": expected,
        "digest": digest, "producer_head": head, "export_commit": build,
        "build_job_result": builds[0]["conclusion"],
        "full_workflow_result": meta["conclusion"],
    })
receipt = Path(os.environ["RUNNER_TEMP"]) / "cadence-results" / "source-archives.json"
receipt.write_text(json.dumps(summary, indent=2) + "\n")
