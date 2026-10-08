"""Verify a candidate queue save with the exact v0.1.9 reader, headlessly.

Uses fresh archived baseline/current source copies and disposable profiles only.
Set GODOT_BIN to Godot 4.6.3; run with --output a new evidence directory.
Keeps synthetic saves and logs for independent review, never reads player saves.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[1]
BASE = "11c1f8d904b0c4c9a2565cbd557d1552b4ba9401"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    archive = output / "baseline.tar"
    git = ["git", "-c", f"safe.directory={ROOT.as_posix()}", "-C", str(ROOT)]
    subprocess.run([*git, "archive", BASE, "-o", str(archive)], check=True)
    baseline = output / "baseline-project"
    baseline.mkdir()
    with tarfile.open(archive) as source:
        source.extractall(baseline, filter="data")
    candidate = output / "candidate-project"
    shutil.copytree(ROOT, candidate, ignore=shutil.ignore_patterns(
        ".git", ".godot", "qa-project", "__pycache__", "evidence", "*.log"))
    shutil.copy2(ROOT / "tests/queue_backward_fixture.gd", baseline / "tests/queue_backward_fixture.gd")
    report = {"baseline_commit": BASE, "candidate_commit": subprocess.check_output(
        [*git, "rev-parse", "HEAD"], text=True).strip(), "headless_only": True,
        "player_save_used": False, "runs": []}
    report["candidate_source_sha256"] = {
        name: hashlib.sha256((candidate / "scripts" / name).read_bytes()).hexdigest()
        for name in ["cafe_model.gd", "cafe_outside_queue.gd", "cafe_runtime_codec.gd", "cafe_save_contract.gd"]}

    def run(label, project, mode=None, source=None, destination=None):
        env = os.environ.copy()
        profile = output / "profiles" / label
        profile.mkdir(parents=True)
        for key in ["HOME", "APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"]:
            env[key] = profile.as_posix()
        flags = ["--editor", "--import", "--quit"]
        if mode:
            flags = ["--script", "res://tests/queue_backward_fixture.gd"]
            env.update(QUEUE_COMPAT_MODE=mode, QUEUE_COMPAT_INPUT=str(source or ""),
                       QUEUE_COMPAT_OUTPUT=str(destination))
        result = subprocess.run([os.environ["GODOT_BIN"], "--headless", "--audio-driver", "Dummy",
                                 "--path", str(project), *flags], env=env,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=240,
                                creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
        log = result.stdout.decode("utf-8", errors="replace")
        (output / (label + ".log")).write_text(log, encoding="utf-8")
        if result.returncode or "SCRIPT ERROR:" in log:
            raise RuntimeError(label + " failed: " + log[-4000:])
        if mode:
            payload = [json.loads(line.split(" ", 1)[1]) for line in log.splitlines()
                       if line.startswith("QUEUE_BACKWARD_RESULT ")]
            assert len(payload) == 1 and payload[0]["ok"], log
            assert Path(payload[0]["user_data"]).is_relative_to(profile), payload
            report["runs"].append(payload[0])

    run("candidate-import", candidate)
    run("baseline-import", baseline)
    original = output / "candidate-queue-save.json"
    downgraded = output / "baseline-resaved.json"
    restored = output / "candidate-restored.json"
    run("candidate-produce", candidate, "produce", destination=original)
    digest = hashlib.sha256(original.read_bytes()).hexdigest()
    run("baseline-read", baseline, "baseline-read", original, downgraded)
    assert hashlib.sha256(original.read_bytes()).hexdigest() == digest
    run("candidate-read-baseline", candidate, "candidate-read-baseline", downgraded, restored)
    a, b, c = [json.loads(path.read_text(encoding="utf-8")) for path in [original, downgraded, restored]]
    fields = ["coins", "total_earned", "served", "total_cleaned", "dining_sets", "items", "next_item_id",
              "runtime", "operating_open", "owned_parcels", "duty_counts", "wages_due", "payroll_elapsed"]
    assert len(a["outside_queue"]["visitors"]) == 6
    assert "outside_queue" not in b
    assert c["outside_queue"]["visitors"] == []
    for field in fields:
        assert a[field] == b[field] == c[field], f"Changed preserved field: {field}"
    report.update(status="passed", checked_fields=fields, original_sha256=digest,
                  original_bytes_preserved=True, outside_visitors_before=6,
                  outside_visitors_after_baseline_resave=0,
                  limitation="v0.1.9 accepts schema 15, ignores optional outside_queue, and loses the six outside visitors when resaving; the shared next customer ID remains advanced.")
    (output / "summary.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
