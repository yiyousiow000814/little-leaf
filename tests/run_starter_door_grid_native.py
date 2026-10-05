"""Check door grid, starter geometry, startup retry and X centering in an isolated disposable project."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
qa_root = root / "qa-project"
qa_root.mkdir(exist_ok=True)
godot = os.environ.get("GODOT_BIN", "godot")


def run(arguments, env, timeout):
    result = subprocess.run(
        [godot, "--headless", *arguments], env=env,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout,
    )
    sys.stdout.buffer.write(result.stdout)
    if result.returncode or b"SCRIPT ERROR:" in result.stdout:
        raise SystemExit(result.returncode or 1)
    return result.stdout


with tempfile.TemporaryDirectory(prefix="geometry-saveguard-", dir=qa_root) as temporary:
    temporary = Path(temporary).resolve()
    assert temporary.parent == qa_root.resolve()
    project = temporary / "project"
    shutil.copytree(
        root, project,
        ignore=shutil.ignore_patterns(".git", ".godot", "qa-project", "__pycache__"),
    )
    # Translate only Web MEMFS staging in this disposable native test copy.
    controller = project / "scripts/cafe_web_save.gd"
    content = controller.read_text(encoding="utf-8")
    content = content.replace(
        'const STAGING_FILE="/tmp/little_leaf_vault_staging.json"',
        'const STAGING_FILE="res://tests/synthetic_stage.json"',
    ).replace(
        'DirAccess.make_dir_recursive_absolute("/tmp")',
        'DirAccess.make_dir_recursive_absolute("res://tests")',
    )
    controller.write_text(content, encoding="utf-8")
    saves = temporary / "saves"
    saves.mkdir()
    env = {
        **os.environ, "APPDATA": str(saves), "LOCALAPPDATA": str(saves),
        "XDG_DATA_HOME": str(saves), "XDG_CONFIG_HOME": str(temporary / "config"),
        "XDG_CACHE_HOME": str(temporary / "cache"),
    }
    run(["--path", str(project), "--editor", "--import", "--quit"], env, 120)
    for script, marker in [
        ("test_starter_geometry.gd", b"STARTER_GEOMETRY_RESULT"),
        ("test_startup_retry.gd", b"STARTUP_RETRY_RESULT"),
        ("test_cancel_icon.gd", b"CANCEL_ICON_RESULT"),
        ("test_no_bottom_notifications.gd", b"NO_BOTTOM_NOTIFICATIONS_RESULT"),
        ("test_starter_door_grid.gd", b"STARTER_DOOR_GRID_RESULT"),
    ]:
        output = run(["--path", str(project), "--script", "res://tests/" + script, "--", "--visual-qa", "--skip-intro", "--fresh-review"], env, 60)
        if marker not in output:
            raise SystemExit("Missing completion result: " + script)
