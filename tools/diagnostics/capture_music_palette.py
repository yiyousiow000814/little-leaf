"""Four native Music-component PNGs for PR348; no full game, export or deployment."""
import argparse
import fcntl
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

if __name__ == "__main__":
    import sys
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from build.project_layout import stage_project
from diagnostics.capture_cloud_recovery_ui import digest, git

BASE = "dd3145b196845b4d163e1ff8191924651328317f"
PANEL = "game/scripts/ui/cafe_music_panel.gd"
PANEL_BLOBS = {"before": "1c4297c07b65683adc0d30276654cb2eaf0b49ee",
               "after": "15f87d5c709cfa6f3430e6fa10841e405877d4db"}
FIXTURE = "tests/diagnostics/capture_music_palette.gd"
STATES = ("first-painted", "settled-premium")
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


def verify_frames(folder):
    receipt = json.loads((folder / "capture.json").read_text())
    if (receipt.get("generated_profile") is not True
            or receipt.get("renderer") != "gl_compatibility"
            or receipt.get("display") != "X11"
            or receipt.get("player_save_used") is not False
            or receipt.get("preferences_persist_enabled") is not False
            or receipt.get("viewport") != [1360, 880]
            or receipt.get("fixed_fps") != 60
            or receipt.get("scale") != 1.0
            or receipt.get("transition_seconds") != 1.0
            or not receipt.get("engine", "").startswith("4.6.3.stable.official.")):
        raise RuntimeError("Missing native component/profile/viewport contract")
    frames = receipt["frames"]
    expected = [f"1360x880-{state}.png" for state in STATES]
    if [row["file"] for row in frames] != expected:
        raise RuntimeError("Expected exactly first-painted and settled Premium frames")
    if sorted(p.name for p in folder.glob("*.png")) != sorted(expected):
        raise RuntimeError("Unexpected screenshot files")
    for row in frames:
        data = (folder / row["file"]).read_bytes()
        if (not data.startswith(PNG_MAGIC) or len(data) < 1000
                or (int.from_bytes(data[16:20], "big"), int.from_bytes(data[20:24], "big")) != (1360, 880)
                or row.get("rgba_bytes") != 1360 * 880 * 4
                or not re.fullmatch(r"[0-9a-f]{64}", row.get("rgba_sha256", ""))
                or row.get("selected") != "service-1nd"):
            raise RuntimeError("Invalid native frame: " + row["file"])
        row.update(png_sha256=digest(data), png_bytes=len(data))
    if not (0 <= frames[0]["board_reveal"] < 1 and 0 <= frames[0]["hero_reveal"] < 1
            and frames[1]["board_reveal"] == frames[1]["hero_reveal"] == 1):
        raise RuntimeError("Transition poses do not match the requested states")
    if frames[0]["rgba_sha256"] == frames[1]["rgba_sha256"]:
        raise RuntimeError("Edition transition produced identical first/settled pixels")
    return receipt


def run_stage(command, env, log_path):
    with log_path.open("wb") as log:
        process = subprocess.Popen(command, env=env, stdout=log,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        started = time.monotonic()
        while process.poll() is None:
            time.sleep(.25)
            text = log_path.read_text(errors="replace")
            if "SCRIPT ERROR" in text or "ERROR:" in text or time.monotonic() - started > 360:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                raise RuntimeError("Native stage errored or timed out; inspect " + log_path.name)
    text = log_path.read_text(errors="replace")
    if process.returncode or "SCRIPT ERROR" in text or "ERROR:" in text:
        raise RuntimeError("Native stage failed; inspect " + log_path.name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expected-head", required=True)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9a-f]{40}", args.expected_head):
        parser.error("Expected an exact 40-character commit SHA")
    head = git("rev-parse", "HEAD").decode().strip()
    if head != args.expected_head:
        raise RuntimeError("Checkout differs from requested head")
    # A future unrelated runtime change needs its own reviewed comparison.
    changed = git("diff", "--name-only", BASE, head, "--", "game").decode().splitlines()
    if changed != [PANEL]:
        raise RuntimeError("Expected only the frozen Music panel runtime delta")
    for label, commit in (("before", BASE), ("after", head)):
        if git("rev-parse", f"{commit}:{PANEL}").decode().strip() != PANEL_BLOBS[label]:
            raise RuntimeError("Frozen Music panel postimage mismatch: " + label)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    if any(output.iterdir()):
        raise RuntimeError("Use an empty evidence directory")
    fixture = git("show", f"{head}:{FIXTURE}")
    godot = os.environ.get("GODOT_BIN", "godot")
    version = subprocess.check_output([godot, "--version"], text=True).strip()
    if not version.startswith("4.6.3.stable.official."):
        raise RuntimeError("Expected official Godot 4.6.3")
    report = {"status": "running", "base": BASE, "head": head, "engine": version,
              "fixture_sha256": digest(fixture), "scope": "native Music component only",
              "fixed_fps": 60, "real_time_performance": False, "player_save_used": False,
              "full_game": False, "audio_playback": False, "sources": {}}
    toolchain = os.environ.get("GODOT_TOOLCHAIN_RECEIPT")
    if toolchain:
        report["toolchain"] = json.loads(Path(toolchain).read_text())

    def save():
        (output / "paired-source-receipt.json").write_text(json.dumps(report, indent=2) + "\n")

    save()
    try:
        with Path(os.environ.get("LL_ENGINE_LOCK", str(output.parent / "music-engine.lock"))).open("a+b") as lock, tempfile.TemporaryDirectory(prefix="music-palette-") as tmp:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            tmp = Path(tmp)
            for label, commit in (("before", BASE), ("after", head)):
                source = tmp / label / "source"
                with zipfile.ZipFile(io.BytesIO(git("archive", "--format=zip", commit, "game", "platform/web"))) as archive:
                    if any(Path(n).is_absolute() or ".." in Path(n).parts for n in archive.namelist()):
                        raise RuntimeError("Unsafe source archive path")
                    archive.extractall(source)
                project = tmp / label / "project"
                stage_project(source, project)
                path = project / FIXTURE
                path.parent.mkdir(parents=True)
                path.write_bytes(fixture)
                scene = path.with_suffix(".tscn")
                scene.write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://' + FIXTURE + '" id="1"]\n[node name="MusicCapture" type="Node"]\nscript=ExtResource("1")\n')
                frames = output / label
                frames.mkdir()
                env = os.environ.copy()
                for key in ("HOME", "APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
                    folder = tmp / label / "profile" / key.lower()
                    folder.mkdir(parents=True)
                    env[key] = str(folder)
                env.update(MUSIC_CAPTURE_OUTPUT=str(frames), LIBGL_ALWAYS_SOFTWARE="1")
                commands = [
                    [godot, "--headless", "--path", str(project), "--editor", "--import", "--quit"],
                    ["xvfb-run", "-a", "-s", "-screen 0 1600x1000x24", godot,
                     "--path", str(project), "--display-driver", "x11", "--audio-driver", "Dummy",
                     "--rendering-method", "gl_compatibility", "--fixed-fps", "60",
                     "res://" + scene.relative_to(project).as_posix(), "--", "--visual-qa"],
                ]
                source_receipt = {"commit": commit, "tree": git("rev-parse", f"{commit}^{{tree}}").decode().strip(),
                                  "game_tree": git("rev-parse", f"{commit}:game").decode().strip(),
                                  "panel_blob": PANEL_BLOBS[label], "commands": commands,
                                  "fixture_sha256": digest(fixture), "scene_sha256": digest(scene.read_bytes())}
                report["sources"][label] = source_receipt
                save()
                for stage, command in zip(("import", "capture"), commands):
                    print(f"Starting {label} {stage}", flush=True)
                    run_stage(command, env, output / f"{label}-{stage}.log")
                source_receipt["capture"] = verify_frames(frames)
                save()
        report["comparisons"] = []
        for before, after in zip(report["sources"]["before"]["capture"]["frames"], report["sources"]["after"]["capture"]["frames"]):
            keys = ("selected", "board_reveal", "hero_reveal", "frames_after_switch", "panel")
            report["comparisons"].append({"file": before["file"],
                                          "same_state": all(before[k] == after[k] for k in keys),
                                          "exact_rgba": before["rgba_sha256"] == after["rgba_sha256"]})
        if not all(row["same_state"] and row["exact_rgba"] for row in report["comparisons"]):
            raise RuntimeError("Music frame state/RGBA mismatch; preserve pixels and investigate")
        report["status"] = "exact_rgba_pending_visual_inspection"
        print(json.dumps({"status": report["status"], "comparisons": report["comparisons"]}), flush=True)
    except Exception as error:
        report.update(status="failed", error=str(error))
        raise
    finally:
        save()


if __name__ == "__main__":
    main()
