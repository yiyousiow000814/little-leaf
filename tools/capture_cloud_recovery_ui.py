"""Render genuine pinned-base/head cloud-recovery pairs; no player profile or deployment."""
import argparse
import fcntl
import hashlib
import io
import json
import os
from pathlib import Path
import re
import signal
import time
import subprocess
import tempfile
import zipfile
from project_layout import stage_project

ROOT = Path(__file__).resolve().parents[1]
BASE = "b8b80eea57ac3cb141cb5c771b375207a284436a"
FIXTURE = "tests/diagnostics/capture_cloud_recovery_ui.gd"
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), *args])


def digest(data):
    return hashlib.sha256(data).hexdigest()


def expected_frames():
    return {f"{size}-{state}-{edge}.png"
            for size in ("390x844", "344x680", "844x390", "566x360", "1360x880")
            for state in ("retry", "cloud", "loading", "changed", "other-device", "waiting", "handoff-requested", "timeout", "update", "update-saving", "update-error")
            for edge in ("top", "bottom")}


def verify_frames(folder):
    manifest = json.loads((folder / "capture.json").read_text())
    if manifest.get("generated_profile") is not True or not manifest.get("renderer"):
        raise RuntimeError("Missing native renderer/generated-profile receipt")
    names = [row["file"] for row in manifest["frames"]]
    if len(names) != len(expected_frames()) or set(names) != expected_frames():
        raise RuntimeError("Incomplete or duplicate cloud recovery viewport-state matrix")
    receipts = {}
    for name in names:
        data = (folder / name).read_bytes()
        if not data.startswith(PNG_MAGIC) or len(data) < 1000:
            raise RuntimeError("Invalid or empty native PNG: " + name)
        width, height = int.from_bytes(data[16:20], "big"), int.from_bytes(data[20:24], "big")
        if (width, height) != tuple(map(int, name.split("-", 1)[0].split("x"))):
            raise RuntimeError("Unexpected frame size: " + name)
        receipts[name] = {"sha256": digest(data), "bytes": len(data)}
    return receipts


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expected-head", required=True)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9a-f]{40}", args.expected_head):
        parser.error("Expected head must be an exact 40-character commit SHA")
    head = git("rev-parse", "HEAD").decode().strip()
    if head != args.expected_head:
        raise RuntimeError("Checkout does not match requested exact head")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    if any(output.iterdir()):
        raise RuntimeError("Use an empty evidence directory")
    fixture = git("show", f"{head}:{FIXTURE}")
    report = {"status": "running", "base": BASE, "head": head,
              "fixture_sha256": digest(fixture), "player_save_used": False, "sources": {}}

    def save():
        (output / "paired-source-receipt.json").write_text(json.dumps(report, indent=2) + "\n")

    save()
    try:
        with Path(os.environ.get("LL_ENGINE_LOCK", str(output.parent / "cloud-recovery-engine.lock"))).open("a+b") as lock, tempfile.TemporaryDirectory(prefix="cloud-recovery-visual-") as tmp:
            fcntl.flock(lock, fcntl.LOCK_EX)
            tmp = Path(tmp)
            for label, commit in (("before", BASE), ("after", head)):
                project = tmp / label / "project"
                project.mkdir(parents=True)
                archive_root = tmp / label / "source"
                with zipfile.ZipFile(io.BytesIO(git("archive", "--format=zip", commit))) as archive:
                    for name in archive.namelist():
                        if Path(name).is_absolute() or ".." in Path(name).parts:
                            raise RuntimeError("Unsafe repository archive path")
                    archive.extractall(archive_root)
                # Each revision keeps its own old/new filesystem layout; Godot
                # receives a disposable project with the same resource labels.
                project.rmdir()
                stage_project(archive_root, project, tests=True)
                original = {str(p.relative_to(project)): digest(p.read_bytes())
                            for p in sorted(project.rglob("*")) if p.is_file()}
                (project / FIXTURE).parent.mkdir(parents=True, exist_ok=True)
                (project / FIXTURE).write_bytes(fixture)
                # Defense in depth: isolate even the native staging fallback.
                staging = project / "scripts/cafe_web_save.gd"
                code = staging.read_text()
                old = 'const STAGING_FILE="/tmp/little_leaf_vault_staging.json"'
                if old not in code:
                    raise RuntimeError("Native staging contract changed")
                staging.write_text(code.replace(old, 'const STAGING_FILE="user://generated_visual_stage.json"'))
                frames = output / label
                frames.mkdir()
                env = os.environ.copy()
                for key in ("HOME", "APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
                    folder = tmp / label / "profile" / key.lower()
                    folder.mkdir(parents=True)
                    env[key] = str(folder)
                env["RECOVERY_CAPTURE_OUTPUT"] = str(frames)
                env["LIBGL_ALWAYS_SOFTWARE"] = "1"
                godot = os.environ.get("GODOT_BIN", "godot")
                commands = [
                    ("import", [godot, "--headless", "--path", str(project), "--editor", "--import", "--quit"]),
                    ("capture", ["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", godot,
                                 "--path", str(project), "--audio-driver", "Dummy", "--rendering-method",
                                 "gl_compatibility", "--script", FIXTURE, "--", "--skip-intro", "--skip-tutorial", "--fresh-review", "--visual-qa"]),
                ]
                for stage, command in commands:
                    log_path = output / f"{label}-{stage}.log"
                    print(f"Starting {label} {stage}", flush=True)
                    with log_path.open("wb") as stream:
                        process = subprocess.Popen(command, env=env, stdout=stream,
                                                   stderr=subprocess.STDOUT, start_new_session=True)
                        start = time.monotonic()
                        reason = None
                        while process.poll() is None:
                            time.sleep(.5)
                            text = log_path.read_text(errors="replace")
                            if "SCRIPT ERROR" in text or "ERROR:" in text:
                                reason = "engine reported an error"
                            elif time.monotonic() - start > 360:
                                reason = "native stage exceeded 360 seconds"
                            if reason:
                                os.killpg(process.pid, signal.SIGTERM)
                                try:
                                    process.wait(timeout=10)
                                except subprocess.TimeoutExpired:
                                    os.killpg(process.pid, signal.SIGKILL)
                                    process.wait()
                                break
                    log = log_path.read_text(errors="replace")
                    if reason or process.returncode or "SCRIPT ERROR" in log or "ERROR:" in log:
                        print(log[-12000:], flush=True)
                        raise RuntimeError(f"{label} {stage} failed: {reason or process.returncode}; inspect retained log")
                    print(f"Completed {label} {stage}", flush=True)
                report["sources"][label] = {
                    "commit": commit, "tree": git("rev-parse", f"{commit}^{{tree}}").decode().strip(),
                    "original_source_sha256": original,
                    "fixture_override_sha256": digest(fixture),
                    "staging_override_sha256": digest(staging.read_bytes()),
                    "frames": verify_frames(frames),
                }
                save()
        report["status"] = "rendered_pending_pixel_review"
    except Exception as error:
        report["status"] = "failed"
        report["error"] = str(error)
        raise
    finally:
        save()


if __name__ == "__main__":
    main()
