"""Observe real 1x natural traffic in an isolated exact-head game; never inject work."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import tempfile
import time
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expected-head", required=True)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    head = subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"]).decode().strip()
    if not re.fullmatch(r"[0-9a-f]{40}", args.expected_head) or head != args.expected_head:
        raise RuntimeError("Exact source head mismatch")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    if any(output.iterdir()):
        raise RuntimeError("Use an empty evidence directory")
    with tempfile.TemporaryDirectory(prefix="natural-cleanup-saveguard-") as temp:
        temp = Path(temp)
        project = temp / "project"
        project.mkdir()
        archive = subprocess.check_output(["git", "-C", str(ROOT), "archive", "--format=zip", head])
        with zipfile.ZipFile(io.BytesIO(archive)) as source:
            if any(Path(p).is_absolute() or ".." in Path(p).parts for p in source.namelist()):
                raise RuntimeError("Unsafe source path")
            source.extractall(project)
        receipt = {"head": head, "archive_sha256": hashlib.sha256(archive).hexdigest(),
                   "generated_profile": True, "player_save_used": False,
                   "simulation": "real elapsed time at normal 1x; no arrivals or litter injected"}
        (output / "source-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
        staging = project / "scripts/cafe_web_save.gd"
        text = staging.read_text()
        old = 'const STAGING_FILE="/tmp/little_leaf_vault_staging.json"'
        if old not in text:
            raise RuntimeError("Review staging isolation contract")
        staging.write_text(text.replace(old, 'const STAGING_FILE="user://generated_natural_stage.json"'))
        env = os.environ.copy()
        for key in ("HOME", "APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
            folder = temp / "profiles" / key.lower()
            folder.mkdir(parents=True)
            env[key] = str(folder)
        env["EXPECTED_HEAD"] = head
        env["NATURAL_CLEANUP_OUTPUT"] = str(output)
        godot = os.environ.get("GODOT_BIN", "godot")
        commands = [
            ("import", 120, [godot, "--headless", "--path", str(project), "--editor", "--import", "--quit"]),
            ("observe", 930, [godot, "--headless", "--audio-driver", "Dummy", "--path", str(project),
                              "--script", "tests/observe_natural_cleanup.gd", "--", "--skip-intro", "--visual-qa"]),
        ]
        for name, limit, command in commands:
            log_path = output / (name + ".log")
            with log_path.open("wb") as stream:
                proc = subprocess.Popen(command, env=env, stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
                started = time.monotonic()
                problem = None
                while proc.poll() is None:
                    time.sleep(1)
                    log = log_path.read_text(errors="replace")
                    if "SCRIPT ERROR" in log or "ERROR:" in log:
                        problem = "engine error"
                    elif time.monotonic() - started > limit:
                        problem = "observation timeout"
                    if problem:
                        os.killpg(proc.pid, signal.SIGTERM)
                        try:
                            proc.wait(timeout=10)
                        except subprocess.TimeoutExpired:
                            os.killpg(proc.pid, signal.SIGKILL)
                            proc.wait()
                        break
            if problem or proc.returncode:
                raise RuntimeError(f"{name} failed: {problem or proc.returncode}; inspect retained log")
        result = json.loads((output / "natural-cleanup.json").read_text())
        if result.get("status") not in {"passed", "inconclusive"}:
            raise RuntimeError("Natural cleanup observation failed")
        print(json.dumps({k: result[k] for k in ("status", "reason", "wall_seconds", "game_seconds", "served", "independent_completed")}))


if __name__ == "__main__":
    main()
