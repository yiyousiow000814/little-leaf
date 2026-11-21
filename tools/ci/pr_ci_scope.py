"""Fail-closed PR merge-tree scope classification; never release qualification."""
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SHA = re.compile(r"[0-9a-f]{40}")
DIAGNOSTICS = {"tools/diagnostics/diagnose_itch_status.py",
               "tools/diagnostics/retained_handoff_route.py",
               "tools/diagnostics/current_handoff_route.py"}
# Reviewed architecture deliverables. Exact paths only; no extension or
# directory-wide exemption (the generator is authoring-only, not a CI input).
ARCHITECTURE_DOCS = {
    "docs/architecture-performance/current-function-atlas.mmd",
    "docs/architecture-performance/generate-function-atlas.py",
    "docs/architecture-performance/performance-workload-ledger.xlsx",
    "docs/architecture-performance/target-workflow.mmd",
}
TOOLING_TEST = re.compile(r"tests/tooling/test_[A-Za-z0-9_]+\.py")
JOBS = ("preflight", "engine", "historical", "build", "crazygames", "play", "browser", "compatibility", "firebase")


def allowed(path):
    if any(ord(c) < 32 for c in path) or "\\" in path:
        return False
    parts = path.split("/")
    if any(p in ("", ".", "..") for p in parts):
        return False
    # Guard always discovers these unittest modules; engine/browser jobs do not
    # consume them. Shared helpers, fixtures and runtime test scripts stay full.
    return (path in DIAGNOSTICS or path in ARCHITECTURE_DOCS or
            TOOLING_TEST.fullmatch(path) is not None or path == "README.md" or
            path.startswith("docs/") and path.endswith(".md") and
            not path.startswith("docs/art-audio/third-party/"))


def lightweight_diff(raw):
    # --raw -z --no-renames makes renames delete/add, so deletion fails closed.
    fields = raw.split(b"\0")
    if not raw or fields[-1] != b"" or (len(fields) - 1) % 2:
        return False
    for header, path in zip(fields[0:-1:2], fields[1:-1:2]):
        bits = header.decode("ascii").split()
        if len(bits) != 5 or bits[0] not in (":000000", ":100644") or bits[1] != "100644":
            return False
        if bits[4] not in ("A", "M") or (bits[4] == "A") != (bits[0] == ":000000"):
            return False
        if not all(SHA.fullmatch(sha) for sha in bits[2:4]):
            return False
        if not allowed(path.decode("utf-8", errors="strict")):
            return False
    return True


def classify(env, event, git):
    if (env.get("GITHUB_EVENT_NAME") != "pull_request" or
            env.get("RELEASE_TAG", "") or env.get("FIREBASE_PREVIEW") != "false" or
            env.get("ITCH_PREVIEW") != "false"):
        return "full"
    try:
        pr = event["pull_request"]
        base, head, merge = pr["base"]["sha"], pr["head"]["sha"], env["GITHUB_SHA"]
        if not all(isinstance(sha, str) and SHA.fullmatch(sha) for sha in (base, head, merge)):
            return "full"
        # Bind to the actual clean checkout, including both merge parents. An API
        # changed-file list, stale base, head-only checkout or pagination is insufficient.
        if git("rev-parse", "HEAD").decode().strip() != merge:
            return "full"
        if git("rev-list", "--parents", "-n", "1", "HEAD").decode().split() != [merge, base, head]:
            return "full"
        if git("status", "--porcelain", "--untracked-files=no"):
            return "full"
        raw = git("diff", "--raw", "--no-abbrev", "-z", "--no-renames", "--no-ext-diff", "--no-textconv", base, "HEAD", "--")
        return "lightweight" if lightweight_diff(raw) else "full"
    except (KeyError, TypeError, ValueError, UnicodeError, OSError, subprocess.SubprocessError):
        return "full"


def preflight_join(env):
    scope, ordinary = env.get("CI_SCOPE"), env.get("ORDINARY_PR")
    if (scope not in ("lightweight", "full") or ordinary not in ("true", "false")
            or (ordinary == "true" and env.get("GITHUB_EVENT_NAME") != "pull_request")
            or (scope == "lightweight" and ordinary != "true")):
        return False
    inline, sibling, binding = (env.get(k) for k in ("INLINE_PREFLIGHT", "PREFLIGHT", "PREFLIGHT_BINDING"))
    if scope == "full" and ordinary == "true":
        sha, run, attempt = (env.get(k, "") for k in ("GITHUB_SHA", "GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT"))
        return bool(inline == "skipped" and sibling == "success"
                    and SHA.fullmatch(sha) and re.fullmatch("[1-9][0-9]*", run)
                    and re.fullmatch("[1-9][0-9]*", attempt) and binding == f"{sha}:{run}:{attempt}")
    return inline == "success" and sibling == "skipped" and not binding


def lightweight_gate(env):
    return (env.get("CI_SCOPE") == "lightweight" and env.get("GITHUB_EVENT_NAME") == "pull_request" and
            env.get("RELEASE_TAG", "") == "" and env.get("FIREBASE_PREVIEW") == "false" and
            env.get("ITCH_PREVIEW") == "false" and env.get("GUARD") == "success" and
            all(env.get(job.upper()) == "skipped" for job in JOBS) and
            not env.get("WEB_ARTIFACT") and not env.get("CRAZYGAMES_ARTIFACT") and not env.get("CRAZYGAMES_EVIDENCE") and
            not env.get("FIREBASE_ARTIFACT") and not env.get("FIREBASE_MANIFEST"))


def main():
    import sys
    if sys.argv[1:] == ["--check-preflight-join"]:
        if not preflight_join(os.environ):
            raise SystemExit("Missing or unbound complete preflight for the selected route")
        return
    if sys.argv[1:] == ["--check-lightweight-gate"]:
        if not lightweight_gate(os.environ):
            raise SystemExit("Invalid lightweight PR gate; full build evidence is required")
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as summary:
            summary.write("PR docs, tooling tests or diagnostic guard passed. Heavy jobs intentionally skipped. No build artifact or full Web/release qualification.\n")
        return
    try:
        event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text(encoding="utf-8"))
        scope = classify(os.environ, event, lambda *args: subprocess.check_output(["git", *args], cwd=ROOT))
    except (KeyError, ValueError, OSError):
        scope = "full"
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
        output.write("scope=" + scope + "\n")
    print("PR CI scope: " + scope)


if __name__ == "__main__":
    main()
