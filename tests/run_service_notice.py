"""Run real-scene notice checks in a disposable profile; optional rendered capture.

Usage: python3 tests/run_service_notice.py
       python3 tests/run_service_notice.py --rendered
Rendered mode requires a working native display and saves PNG evidence locally.
"""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
rendered = "--rendered" in sys.argv
args = [] if rendered else ["--headless"]
with tempfile.TemporaryDirectory(prefix="little-leaf-notice-") as profile:
    env = {**os.environ, "XDG_DATA_HOME": profile, "APPDATA": profile,
           "XDG_CACHE_HOME": str(Path(profile) / "cache"),
           "XDG_CONFIG_HOME": str(Path(profile) / "config")}
    godot = os.environ.get("GODOT_BIN", "godot")
    subprocess.run([godot, "--headless", "--path", str(root), "--editor", "--import", "--quit"],
                   env=env, check=True, timeout=120)
    user_args = ["--", "--visual-qa", "--fresh-review"]
    if rendered:
        captures = root / "evidence/service-notice/after"
        captures.mkdir(parents=True, exist_ok=True)
        user_args.append("--capture-dir=" + str(captures))
    result = subprocess.run([godot, *args, "--path", str(root), "--script",
                             "res://tests/test_service_notice.gd", *user_args],
                            env=env, timeout=90)
    raise SystemExit(result.returncode)
