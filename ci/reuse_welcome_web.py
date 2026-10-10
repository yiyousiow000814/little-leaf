"""Select and verify one equivalent-source successful Web artifact for manual QA.

No rebuild fallback: absent, failed, expired or mismatched evidence is an error.
The existing source/export verifier runs before any browser is launched.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess


def qualify(run, artifact, repository, source, run_id, artifact_id):
    if not re.fullmatch(r"[0-9a-f]{40}", source):
        raise ValueError("Exact source commit required")
    if (run.get("id") != run_id or run.get("repository", {}).get("full_name") != repository
            or run.get("path") != ".github/workflows/ci.yml"
            or run.get("status") != "completed" or run.get("conclusion") != "success"):
        raise ValueError("Completed successful ordinary-Web run required")
    # PR runs build the merge commit, which differs from the API's head_sha.
    refs = run.get("referenced_workflows", [])
    built_refs = [ref for ref in refs if ref.get("path", "").startswith(
        repository + "/.github/workflows/build-web.yml@")]
    if len(built_refs) != 1 or not re.fullmatch(r"[0-9a-f]{40}", built_refs[0].get("sha", "")):
        raise ValueError("One exact built Web source required")
    built_source = built_refs[0]["sha"]
    attempt = run.get("run_attempt")
    if type(attempt) is not int or attempt < 1:
        raise ValueError("Run attempt required")
    expected_name = f"little-leaf-web-{built_source}-{attempt}"
    if (artifact.get("id") != artifact_id or artifact.get("expired") is not False
            or artifact.get("name") != expected_name
            or artifact.get("workflow_run", {}).get("id") != run_id):
        raise ValueError("Exact nonexpired Web artifact from successful attempt required")
    return {"source_commit": source, "built_source_commit": built_source,
            "artifact_name": expected_name, "artifact_id": artifact_id, "run_id": run_id,
            "run_attempt": attempt}


def verify_equivalence(source_root, source, built_source):
    # Compare the complete Git tree, including the validation/build inputs.
    # Never treat unchanged runtime files alone as proof of a tested source.
    exists = subprocess.run(["git", "-C", str(source_root), "cat-file", "-e",
                             built_source + "^{commit}"], capture_output=True)
    if exists.returncode:
        subprocess.run(["git", "-C", str(source_root), "fetch", "--no-tags", "origin", built_source], check=True)
    def tree(commit):
        return subprocess.check_output(["git", "-C", str(source_root), "rev-parse", commit + "^{tree}"], text=True).strip()
    requested_tree, built_tree = tree(source), tree(built_source)
    if requested_tree != built_tree:
        raise ValueError("Built and requested source trees must be identical")
    return requested_tree


def reuse(repository, run_id, artifact_id, source_root, output, phase="select"):
    source_root = source_root.resolve()
    source = subprocess.check_output(["git", "-C", str(source_root), "rev-parse", "HEAD"], text=True).strip()
    selection_path = output / "artifact-selection.json"
    if phase == "select":
        def api(path):
            return json.loads(subprocess.check_output(["gh", "api", f"repos/{repository}/{path}"], text=True))
        run = api(f"actions/runs/{run_id}")
        artifact = api(f"actions/artifacts/{artifact_id}")
        selection = qualify(run, artifact, repository, source, run_id, artifact_id)
        selection["source_tree"] = verify_equivalence(source_root, source, selection["built_source_commit"])
        selection["run_url"] = run["html_url"]
        output.mkdir(parents=True, exist_ok=False)
        selection_path.write_text(json.dumps(selection, indent=2) + "\n", encoding="utf-8")
        # The pinned download action consumes only these validated IDs.
        import os
        if os.environ.get("GITHUB_OUTPUT"):
            with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as stream:
                for key in ("run_id", "artifact_id"):
                    stream.write(f"{key}={selection[key]}\n")
        return selection
    selection = json.loads(selection_path.read_text(encoding="utf-8"))
    if (selection["source_commit"] != source or selection["run_id"] != run_id
            or selection["artifact_id"] != artifact_id):
        raise ValueError("Downloaded artifact selection must match requested checkout and IDs")
    helper = source_root / "tests/welcome_audio_helpers.js"
    script = "const h=require(process.argv[1]);console.log(JSON.stringify(h.verifySource(process.argv[2],process.argv[3],process.argv[4])));"
    binding = json.loads(subprocess.check_output(["node", "-e", script, str(helper), str(output / "web"),
        str(source_root), selection["built_source_commit"]], text=True))
    receipt = {**selection, "binding": binding,
               "scope": "Reused successful equivalent-source Web artifact; no engine/export rerun or browser acceptance"}
    (output / "artifact-reuse.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: receipt[key] for key in ("source_commit", "built_source_commit", "run_id", "artifact_id")}))
    return receipt


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--phase", choices=("select", "verify"), required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--run-id", type=int, required=True)
    parser.add_argument("--artifact-id", type=int, required=True)
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    reuse(args.repository, args.run_id, args.artifact_id, args.source_root, args.output, args.phase)
