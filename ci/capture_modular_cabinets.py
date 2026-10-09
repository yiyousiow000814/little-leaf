"""Render genuine pinned-base/head modular-cabinet pairs; no player profile or deployment."""
import argparse
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

ROOT = Path(__file__).resolve().parents[1]
BASE = "88f48a2f0793e46eb2e23693fbaa2647751dfa62"
FIXTURE = "tests/capture_modular_cabinets.gd"
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), *args])


def digest(data):
    return hashlib.sha256(data).hexdigest()


def expected_frames():
    return {f"{scene}-r{rotation}-{zoom}.png" for scene in
            ("adjacent", "wall-corner", "work-sink", "work-beverage", "work-register")
            for rotation in range(4) for zoom in ("normal", "medium")}


def verify_frames(folder):
    manifest = json.loads((folder / "capture.json").read_text())
    if manifest.get("generated_profile") is not True or not manifest.get("renderer"):
        raise RuntimeError("Missing native renderer/generated-profile receipt")
    names = [row["file"] for row in manifest["frames"]]
    if len(names) != 40 or set(names) != expected_frames():
        raise RuntimeError("Incomplete or duplicate normal/medium-zoom frame matrix")
    receipts = {}
    for name in names:
        data = (folder / name).read_bytes()
        if not data.startswith(PNG_MAGIC) or len(data) < 1000:
            raise RuntimeError("Invalid or empty native PNG: " + name)
        width, height = int.from_bytes(data[16:20], "big"), int.from_bytes(data[20:24], "big")
        if (width, height) != (1360, 880):
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
    # Rebased PRs may no longer advertise the historical comparison commit.
    # Fetch only this exact public repository object, never a moving branch.
    exists = subprocess.run(["git", "-C", str(ROOT), "cat-file", "-e", BASE + "^{commit}"],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if exists.returncode:
        git("fetch", "--no-tags", "--depth=1", "origin", BASE)
    if git("rev-parse", BASE + "^{commit}").decode().strip() != BASE:
        raise RuntimeError("Pinned comparison base did not resolve exactly")
    fixture = git("show", f"{head}:{FIXTURE}")
    report = {"status": "running", "base": BASE, "head": head,
              "fixture_sha256": digest(fixture), "player_save_used": False, "sources": {}}

    def save():
        (output / "paired-source-receipt.json").write_text(json.dumps(report, indent=2) + "\n")

    save()
    try:
        with tempfile.TemporaryDirectory(prefix="cabinet-visual-") as tmp:
            tmp = Path(tmp)
            for label, commit in (("before", BASE), ("after", head)):
                project = tmp / label / "project"
                project.mkdir(parents=True)
                with zipfile.ZipFile(io.BytesIO(git("archive", "--format=zip", commit))) as archive:
                    for name in archive.namelist():
                        if Path(name).is_absolute() or ".." in Path(name).parts:
                            raise RuntimeError("Unsafe repository archive path")
                    archive.extractall(project)
                original = {str(p.relative_to(project)): digest(p.read_bytes())
                            for p in sorted(project.rglob("*")) if p.is_file()}
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
                env["CABINET_CAPTURE_OUTPUT"] = str(frames)
                env["LIBGL_ALWAYS_SOFTWARE"] = "1"
                godot = os.environ.get("GODOT_BIN", "godot")
                commands = [
                    ("import", [godot, "--headless", "--path", str(project), "--editor", "--import", "--quit"]),
                    ("capture", ["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", godot,
                                 "--path", str(project), "--audio-driver", "Dummy", "--rendering-method",
                                 "gl_compatibility", "--script", FIXTURE, "--", "--skip-intro", "--visual-qa"]),
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
        before = json.loads((output / "before/capture.json").read_text())["frames"]
        after = json.loads((output / "after/capture.json").read_text())["frames"]
        for left, right in zip(before, after):
            if left["file"] != right["file"] or abs(left["zoom"] - right["zoom"]) > .00001:
                raise RuntimeError("Paired camera/sample identity differs")
            if any(abs(a-b) > .001 for a, b in zip(left["camera_origin"], right["camera_origin"])):
                raise RuntimeError("Paired camera origins differ: " + left["file"])
        report["status"] = "rendered_pending_pixel_review"
    except Exception as error:
        report["status"] = "failed"
        report["error"] = str(error)
        raise
    finally:
        save()


if __name__ == "__main__":
    main()
