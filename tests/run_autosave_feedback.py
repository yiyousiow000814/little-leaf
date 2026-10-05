"""Run synthetic autosave/controller/headless UI checks in a disposable profile.

Never accesses a player profile, real browser, or IndexedDB. Native feedback uses
an in-memory save stub. Full-scene checks use --visual-qa and only web staging
writes redirected beneath this runner's disposable project. UI checks verify
scene state and layout geometry, not native-rendered or browser pixels.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
reports = []
with tempfile.TemporaryDirectory(prefix="geometry-saveguard-feedback-") as temporary:
    temporary = Path(temporary)
    project = temporary / "project"
    shutil.copytree(root, project, ignore=shutil.ignore_patterns(
        ".git", ".godot", "qa-project", "evidence", "__pycache__"))
    controller = project / "scripts/cafe_web_save.gd"
    text = controller.read_text(encoding="utf-8").replace(
        'const STAGING_FILE="/tmp/little_leaf_vault_staging.json"',
        'const STAGING_FILE="res://tests/synthetic_stage.json"').replace(
        'DirAccess.make_dir_recursive_absolute("/tmp")',
        'DirAccess.make_dir_recursive_absolute("res://tests")')
    controller.write_text(text, encoding="utf-8")
    env = {**os.environ, **{name: str(temporary / name.lower()) for name in (
        "HOME", "APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CACHE_HOME", "XDG_CONFIG_HOME")}}
    for name in ("HOME", "APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CACHE_HOME", "XDG_CONFIG_HOME"):
        Path(env[name]).mkdir(parents=True, exist_ok=True)
    godot = os.environ.get("GODOT_BIN", "godot")

    def run(args, marker=None):
        result = subprocess.run([godot, "--headless", "--path", str(project), *args],
            env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
        output = result.stdout.decode(errors="replace")
        print(output.replace(str(temporary), "<isolated-test-root>"), end="", flush=True)
        if result.returncode or "SCRIPT ERROR:" in output:
            raise SystemExit(result.returncode or 1)
        if marker:
            records = [line[len(marker):] for line in output.splitlines() if line.startswith(marker)]
            if len(records) != 1:
                raise SystemExit("Missing or duplicate test marker: " + marker)
            report = json.loads(records[0])
            if report["failures"]:
                raise SystemExit("Failed assertions: " + marker)
            reports.append({"suite": marker.strip(), "checks": report["checks"], "failures": []})

    run(["--editor", "--import", "--quit"])
    for script, marker, flags in [
        ("test_autosave_feedback.gd", "AUTOSAVE_FEEDBACK_RESULT ", []),
        ("test_autosave_feedback_adversarial.gd", "AUTOSAVE_ADVERSARIAL_RESULT ", []),
        ("test_autosave_feedback_ui.gd", "AUTOSAVE_UI_RESULT ", ["--", "--visual-qa", "--fresh-review", "--skip-intro"]),
        ("test_no_bottom_notifications.gd", "NO_BOTTOM_NOTIFICATIONS_RESULT ", ["--", "--visual-qa", "--fresh-review", "--skip-intro"]),
        ("test_hud_layout.gd", "HUD_LAYOUT_RESULT ", ["--", "--visual-qa", "--fresh-review", "--skip-intro"]),
        ("test_startup_retry.gd", "STARTUP_RETRY_RESULT ", []),
        ("test_starter_geometry.gd", "STARTER_GEOMETRY_RESULT ", []),
    ]:
        run(["--script", "res://tests/" + script, *flags], marker)
    for profile in (Path(env["XDG_DATA_HOME"]), Path(env["APPDATA"]), Path(env["LOCALAPPDATA"])):
        assert not list(profile.rglob("little_leaf_cafe_layout_motion_v15.json")), "Unexpected regular save filename"
print("AUTOSAVE_SUITE_RESULT " + json.dumps({"checks": sum(r["checks"] for r in reports),
    "failures": [], "suites": reports, "player_data_accessed": False,
    "browser_run": False, "rendered_pixels_verified": False}))
