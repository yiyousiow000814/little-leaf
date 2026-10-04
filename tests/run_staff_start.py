"""Check fresh staff posts, generated saved starts and focused compatibility in isolation."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
qa = root / "qa-project"
qa.mkdir(exist_ok=True)
godot = os.environ.get("GODOT_BIN", "godot")
reports = []
with tempfile.TemporaryDirectory(prefix="staff-start-saveguard-", dir=qa) as directory:
    temporary = Path(directory).resolve()
    project = temporary / "project"
    shutil.copytree(root, project, ignore=shutil.ignore_patterns(
        ".git", ".godot", "qa-project", "evidence", "__pycache__"))
    profile = temporary / "profile"
    env = {**os.environ, **{name: str(profile / name.lower()) for name in (
        "APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME")}}
    for name in ("APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
        Path(env[name]).mkdir(parents=True, exist_ok=True)

    def run(arguments, marker=None):
        result = subprocess.run([godot, "--headless", "--path", str(project), *arguments],
            env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
        sys.stdout.buffer.write(result.stdout)
        sys.stdout.buffer.flush()
        if result.returncode or b"SCRIPT ERROR:" in result.stdout:
            raise SystemExit(result.returncode or 1)
        if marker:
            records = [line[len(marker):] for line in result.stdout.decode().splitlines()
                       if line.startswith(marker)]
            if len(records) != 1:
                raise SystemExit("Missing or duplicate result: " + marker)
            report = json.loads(records[0])
            if report["failures"]:
                raise SystemExit("Failed checks: " + marker)
            reports.append({"suite": marker.strip(), "checks": report["checks"], "failures": []})

    run(["--editor", "--import", "--quit"])
    save_dir = Path(env["XDG_DATA_HOME"]) / "godot/app_userdata/Little Leaf Cafe"
    save_file = save_dir / "little_leaf_cafe_layout_motion_v15.json"
    for case in ["empty-profile", "fresh", "saved-load", "standalone-load", "bad-load"]:
        env["LL_START_CASE"] = case
        env["LL_START_RESULT"] = str(temporary / (case + ".json"))
        if case == "empty-profile":
            assert not save_file.exists(), "Ordinary startup must begin with no save file"
        elif case == "saved-load":
            shutil.copy2(save_dir / "staff-start-roundtrip.json", save_file)
        elif case == "standalone-load":
            shutil.copy2(save_dir / "staff-start-standalone.json", save_file)
        elif case == "bad-load":
            save_file.write_text("not a valid cafe")
        args = ["--script", "res://tests/test_staff_start.gd", "--", "--visual-qa"]
        if case == "fresh":
            args.append("--fresh-review")
        run(args, "STAFF_START_RESULT ")
    for script, marker in [
        ("test_role_boundaries.gd", "ROLE_BOUNDARIES_RESULT "),
        ("test_role_release.gd", "ROLE_RELEASE_RESULT "),
        ("test_staff_relocation_service.gd", "STAFF_RELOCATION_SERVICE_RESULT "),
        ("test_floor_availability.gd", "FLOOR_AVAILABILITY_RESULT "),
        ("test_furniture_worker_egress.gd", "FURNITURE_WORKER_EGRESS "),
    ]:
        run(["--script", "res://tests/" + script, "--", "--fresh-review", "--visual-qa"], marker)
print("STAFF_START_SUITE_RESULT " + json.dumps({"checks": sum(r["checks"] for r in reports),
      "failures": [], "suites": reports}))
