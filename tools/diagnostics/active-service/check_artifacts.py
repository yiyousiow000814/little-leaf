"""Read-only host-run/attempt checks before cross-run artifact download."""
import json
import os
from pathlib import Path
import time
from urllib.request import Request, urlopen

REPO = "yiyousiow000814/little-leaf"
assert os.environ["GITHUB_REPOSITORY"] == REPO, "Unexpected repository"
HEAD = os.environ["GAMEPLAY_HEAD"]
SOURCES = (
    (os.environ["BASE_RUN"], os.environ["BASE_COMMIT"], os.environ["BASE_COMMIT"], "push"),
    (os.environ["CANDIDATE_RUN"], HEAD, os.environ["CANDIDATE_COMMIT"], "pull_request"),
)
def api(path):
    req = Request(
        f"https://api.github.com/repos/{REPO}/actions/{path}",
        headers={
            "Authorization": "Bearer " + os.environ["GH_TOKEN"],
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    with urlopen(req, timeout=12) as response:
        return json.load(response)

deadline = time.monotonic() + 235
waiting = True
while waiting:
    waiting = False
    summary = []
    for run, head, build, event in SOURCES:
        meta = api("runs/" + run)
        assert (meta["id"], meta["event"], meta["head_sha"], meta["run_attempt"]) == (
            int(run), event, head, 1
        ), "Unexpected run binding"
        assert meta["path"].split("@", 1)[0] == ".github/workflows/ci.yml", "Wrong producer workflow"
        if event == "pull_request" and meta.get("pull_requests"):
            assert any(row["number"] == 364 for row in meta["pull_requests"]), "Wrong producer PR"
        expected = f"little-leaf-ci-inputs-{build}-1"
        matches = [
            a for a in api(f"runs/{run}/artifacts?per_page=100")["artifacts"]
            if a["name"] == expected and not a["expired"]
        ]
        assert len(matches) <= 1, "Ambiguous input archive"
        if not matches:
            assert meta["status"] != "completed", "Producer already ended without the exact archive"
            waiting = True
        else:
            assert matches[0]["size_in_bytes"] > 0
            summary.append({
                "run_id": run, "archive_id": matches[0]["id"], "archive_name": expected,
                "digest": matches[0].get("digest"), "producer_head": head, "export_commit": build,
            })
    if waiting:
        assert time.monotonic() < deadline, "Exact source-bound inputs are not yet available"
        time.sleep(10)
receipt = Path(os.environ["RUNNER_TEMP"]) / "cadence-results" / "source-archives.json"
receipt.write_text(json.dumps(summary, indent=2) + "\n")
