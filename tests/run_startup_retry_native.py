"""Run native startup validation against a disposable project copy."""
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

with tempfile.TemporaryDirectory(prefix="startup-retry-", dir=qa_root) as temporary:
    temporary = Path(temporary).resolve()
    assert temporary.parent == qa_root.resolve()
    project = temporary / "project"
    shutil.copytree(root, project, ignore=shutil.ignore_patterns(".git", ".godot", "qa-project", "__pycache__"))
    # Production stages in unmounted Web MEMFS /tmp. Native Windows lacks
    # that filesystem; translate only its path/directory in this test copy.
    controller = project / "scripts/cafe_web_save.gd"
    text = controller.read_text(encoding="utf-8")
    text = text.replace('const STAGING_FILE="/tmp/little_leaf_vault_staging.json"',
                        'const STAGING_FILE="res://tests/synthetic_stage.json"')
    text = text.replace('DirAccess.make_dir_recursive_absolute("/tmp")',
                        'DirAccess.make_dir_recursive_absolute("res://tests")')
    controller.write_text(text, encoding="utf-8")
    saves = temporary / "saves"
    saves.mkdir()
    env = {**os.environ, "APPDATA": str(saves), "XDG_DATA_HOME": str(saves)}
    result = subprocess.run([godot, "--headless", "--path", str(project),
                             "--editor", "--import", "--quit"], env=env,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            timeout=120)
    if result.returncode:
        sys.stdout.buffer.write(result.stdout)
        raise SystemExit(result.returncode)
    result = subprocess.run([godot, "--headless", "--path", str(project),
                             "--script", "res://tests/test_startup_retry.gd"],
                            env=env, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=60)
    sys.stdout.buffer.write(result.stdout)
    raise SystemExit(result.returncode)
