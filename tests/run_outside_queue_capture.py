"""Capture exact v0.1.9 and candidate motion in isolated synthetic profiles."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BASE = "11c1f8d904b0c4c9a2565cbd557d1552b4ba9401"

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if output.exists():
        raise SystemExit("Use a new directory to preserve prior evidence")
    output.mkdir(parents=True)
    engine = os.environ["GODOT_BIN"]
    with tempfile.TemporaryDirectory(prefix="outside-queue-", dir=output.parent,
                                     ignore_cleanup_errors=True) as temp:
        temp = Path(temp)
        archive = temp / "baseline.tar"
        subprocess.run(["git", "archive", BASE, "-o", str(archive)], cwd=ROOT, check=True)
        for label in ["before", "after"]:
            project = temp / label / "project"
            project.mkdir(parents=True)
            if label == "before":
                with tarfile.open(archive) as source:
                    source.extractall(project, filter="data")
            else:
                shutil.copytree(ROOT, project, dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns(".git", ".godot", "qa-project", "__pycache__", "evidence", "*.log"))
            shutil.copy2(ROOT / "tests/capture_outside_queue.gd", project / "tests/capture_outside_queue.gd")
            evidence = output / label
            evidence.mkdir()
            env = os.environ.copy()
            for key in ["HOME", "APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"]:
                profile = temp / label / "synthetic-profile" / key
                profile.mkdir(parents=True)
                env[key] = str(profile)
            env["QUEUE_OUTPUT"] = str(evidence)
            env["QUEUE_SOURCE"] = BASE if label == "before" else "candidate working tree"
            for phase, flags in [("import", ["--headless", "--editor", "--import", "--quit"]),
                                 ("motion", ["--script", "res://tests/capture_outside_queue.gd", "--", "--visual-qa", "--fresh-review", "--skip-intro"])]:
                result = subprocess.run([engine, "--audio-driver", "Dummy", "--path", str(project), *flags],
                    env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=240,
                    creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
                log = result.stdout.decode("utf-8", errors="replace")
                (evidence / (phase + ".log")).write_text(log, encoding="utf-8")
                if result.returncode or "SCRIPT ERROR:" in log:
                    raise RuntimeError(f"{label}/{phase} failed: {log[-5000:]}")
            if not (evidence / "motion.json").is_file():
                raise RuntimeError("Missing completed motion report")
            print(json.dumps({"label": label, "source": env["QUEUE_SOURCE"], "frames": 87}), flush=True)

if __name__ == "__main__":
    main()
