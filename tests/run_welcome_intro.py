"""Check Welcome lifecycle in a disposable Godot 4.6.3 project/profile."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="welcome-saveguard-") as temp:
    temp = Path(temp)
    project = temp / "project"
    shutil.copytree(root, project, ignore=shutil.ignore_patterns(
        ".git", ".godot", "qa-project", "__pycache__", "evidence"))
    env = os.environ.copy()
    for key in ["HOME", "APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"]:
        directory = temp / key.lower()
        directory.mkdir()
        env[key] = str(directory)
    godot = os.environ.get("GODOT_BIN", "godot")
    reports = []

    def run(args, marker=None):
        result = subprocess.run([godot, "--headless", "--path", str(project), *args],
                                env=env, capture_output=True, text=True, timeout=180)
        text = result.stdout + result.stderr
        print(text.replace(str(temp), "<isolated-test-root>"), end="", flush=True)
        if result.returncode or "SCRIPT ERROR:" in text:
            raise SystemExit(result.returncode or 1)
        if marker:
            found = [json.loads(line[len(marker):]) for line in text.splitlines() if line.startswith(marker)]
            assert len(found) == 1 and found[0]["checks"] > 0 and not found[0]["failures"], marker
            reports.append(found[0])

    run(["--editor", "--import", "--quit"])
    run(["--script", "res://tests/test_intro_lifecycle_headless.gd", "--", "--visual-qa", "--fresh-review"],
        "INTRO_LIFECYCLE_RESULT ")
    run(["--script", "res://tests/test_intro_cli_bypass.gd", "--", "--visual-qa", "--fresh-review", "--skip-intro"],
        "INTRO_CLI_RESULT ")
    assert not list(temp.rglob("little_leaf_cafe_layout_motion_v15.json")), "Unexpected normal save"
    print("WELCOME_SUITE_RESULT " + json.dumps({"checks": sum(r["checks"] for r in reports),
          "failures": [], "native_or_browser_rendering_verified": False, "player_data_used": False}))
