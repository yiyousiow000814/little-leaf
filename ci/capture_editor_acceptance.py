"""Capture exact-source editor acceptance frames using generated disposable profiles."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = "tests/capture_editor_acceptance.gd"
EXPECTED = ["01-tiles-true-color", "02-tiles-hidden-objects", "03-tiles-four-cell-preview",
            "04-tiles-four-cell-applied", "05-original-wall-actions", "06-original-wall-move-preview",
            "07-wall-three-edge-preview", "08-wall-three-edge-applied", "09-portrait-tiles-inspection",
            "10-landscape-tiles-inspection"]


def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), *args])


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expected-head", required=True)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9a-f]{40}", args.expected_head):
        parser.error("Use an exact 40-character source commit")
    head = git("rev-parse", "HEAD").decode().strip()
    if head != args.expected_head:
        raise RuntimeError("Checkout differs from requested source")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    if any(output.iterdir()):
        raise RuntimeError("Use an empty evidence directory")
    report = {"status": "running", "head": head, "tree": git("rev-parse", "HEAD^{tree}").decode().strip(),
              "player_save_used": False, "deployment_performed": False}
    try:
        with tempfile.TemporaryDirectory(prefix="editor-saveguard-") as temp:
            temp = Path(temp)
            project = temp / "project"
            project.mkdir()
            with zipfile.ZipFile(io.BytesIO(git("archive", "--format=zip", head))) as archive:
                for name in archive.namelist():
                    if Path(name).is_absolute() or ".." in Path(name).parts:
                        raise RuntimeError("Unsafe repository archive path")
                archive.extractall(project)
            report["source_sha256"] = {str(p.relative_to(project)): digest(p.read_bytes())
                                       for p in sorted(project.rglob("*")) if p.is_file()}
            staging = project / "scripts/cafe_web_save.gd"
            code = staging.read_text()
            old = 'const STAGING_FILE="/tmp/little_leaf_vault_staging.json"'
            if old not in code:
                raise RuntimeError("Native staging isolation contract changed")
            staging.write_text(code.replace(old, 'const STAGING_FILE="user://generated_editor_stage.json"'))
            report["staging_isolation_sha256"] = digest(staging.read_bytes())
            frames = output / "frames"
            frames.mkdir()
            env = os.environ.copy()
            for key in ("HOME", "APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
                directory = temp / "profile" / key.lower()
                directory.mkdir(parents=True)
                env[key] = str(directory)
            env["EDITOR_CAPTURE_OUTPUT"] = str(frames)
            env["LIBGL_ALWAYS_SOFTWARE"] = "1"
            godot = os.environ.get("GODOT_BIN", "godot")
            commands = [
                ("import", [godot, "--headless", "--path", str(project), "--editor", "--import", "--quit"]),
                ("capture", ["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", godot, "--path", str(project),
                             "--audio-driver", "Dummy", "--rendering-method", "gl_compatibility", "--script", FIXTURE,
                             "--", "--skip-intro", "--visual-qa"]),
            ]
            for name, command in commands:
                result = subprocess.run(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=360)
                log = result.stdout.decode(errors="replace")
                (output / (name + ".log")).write_text(log)
                if result.returncode or "SCRIPT ERROR" in log or "ERROR:" in log:
                    raise RuntimeError(f"{name} failed; inspect retained log")
            capture = json.loads((frames / "capture.json").read_text())
            if not capture["native_rendered"] or capture["failures"] or not capture["generated_profile"] or capture["player_save_used"]:
                raise RuntimeError("Native generated-state capture assertions failed")
            rows = capture["frames"]
            if [row["file"] for row in rows] != [name + ".png" for name in EXPECTED]:
                raise RuntimeError("Incomplete or duplicate capture matrix")
            report["frames"] = {}
            for row in rows:
                data = (frames / row["file"]).read_bytes()
                if not data.startswith(b"\x89PNG\r\n\x1a\n") or len(data) < 1000:
                    raise RuntimeError("Invalid native frame")
                size = [int.from_bytes(data[16:20], "big"), int.from_bytes(data[20:24], "big")]
                if size != row["viewport"]:
                    raise RuntimeError("Native frame size differs from viewport")
                report["frames"][row["file"]] = {"sha256": digest(data), "bytes": len(data), "viewport": size}
            report["status"] = "rendered_pending_pixel_review"
    except Exception as error:
        report["status"] = "failed"
        report["error"] = str(error)
        raise
    finally:
        (output / "source-receipt.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
