"""Verify seven exact native floor frames and paired independent state receipts."""
import argparse
import hashlib
import json
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

from litter_fixture import FIXTURE, overlay
from qualify import FIXTURE_SHA, git, load_binding, module, require, sha, verify_sources

PROFILES = ("HOME", "APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME")

def inspect(folder):
    from PIL import Image

    report = json.loads((folder / "runtime.json").read_text())
    require(report["semantic_only"] is False and report["native_visible"] is True and
            report["player_save_used"] is False and report["save_attempts"] == 0 and
            len(report["routes"]) == 3 and len(report["messes"]["messes"]) == 3 and report["in_frame_active_litter"], "Real visible isolated litter fixture required")
    require({p.name for p in folder.glob("*.png")} == {"litter.png"}, "Unexpected native PNG inventory")
    p = folder / "litter.png"
    with Image.open(p) as image:
        rgba = image.convert("RGBA")
        require(image.format == "PNG" and image.size == (1360, 880) and
                rgba.getchannel("A").getextrema() == (255, 255) and rgba.getcolors(128) is None,
                "Expected opaque detailed cafe PNG")
        return report, rgba.tobytes(), {"png_sha256": sha(p), "rgba_sha256": hashlib.sha256(rgba.tobytes()).hexdigest()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--bind", type=Path, required=True)
    parser.add_argument("--godot", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    root = args.repo.resolve()
    binding = json.loads(args.bind.read_text())
    base, head = load_binding(root, binding)
    closure = verify_sources(root, binding)
    source = (root / FIXTURE).read_bytes()
    staged = overlay(source, FIXTURE_SHA)
    fixture_hash = hashlib.sha256(staged).hexdigest()
    report = {"control": base, "candidate": head, "control_tree": binding["control_tree"],
              "candidate_tree": binding["candidate_tree"], "scope": "Native still RGBA, not FPS",
              "fixture_source_sha256": FIXTURE_SHA, "staged_fixture_sha256": fixture_hash,
              "atlas": closure, "stages": [], "status": "running", "pixels_inspected": False}
    if args.verify_only:
        print(json.dumps({**report, "status": "source_bound"}))
        return
    native = module("ll_litter_storage_helpers", root / "tools/diagnostics/storage_native_review.py")
    require(args.godot and args.output and sha(args.godot) == native.ENGINE_SHA and os.environ.get("DISPLAY"),
            "Official Godot, isolated output and actual X11 display required")
    out = args.output.resolve()
    require(not out.is_relative_to(root), "External output required")
    out.mkdir(parents=True, exist_ok=False)
    report["engine_sha256"] = sha(args.godot)

    def save():
        (out / "litter-summary.json").write_text(json.dumps(report, indent=2) + "\n")

    def run(tag, command, env, completion=None):
        log = out / (tag + ".log")
        code, reason = native.execute_native(command, env, log, timeout=120)
        report["stages"].append({"stage": tag, "exit": code, "reason": reason, "log_sha256": sha(log)})
        save()
        content = log.read_text(errors="replace")
        require(code == 0 and not reason and "ERROR:" not in content
                and (not completion or completion in content), "Failed native step: " + tag)

    def isolate(temp, tag):
        env = os.environ.copy()
        env.pop("LITTER_SEMANTIC_ONLY", None)
        for key in PROFILES:
            folder = temp / tag / key
            folder.mkdir(parents=True)
            env[key] = str(folder)
        return env

    (out / "capture_litter_visibility-executed.gd.txt").write_bytes(staged)
    try:
        stage = module("ll_litter_stage", root / "tools/build/project_layout.py").stage_project
        with tempfile.TemporaryDirectory(prefix="litter-saveguard-") as folder:
            temp = Path(folder)
            control = temp / "control"
            control.mkdir()
            proc = subprocess.Popen(["git", "-C", str(root), "archive", base, "game", "platform/web"],
                                    stdout=subprocess.PIPE)
            try:
                subprocess.run(["tar", "-x", "-C", str(control)], check=True, stdin=proc.stdout)
            finally:
                proc.stdout.close()
                require(proc.wait() == 0, "Source archive failed")
            for tag, source_root in (("control", control), ("candidate", root)):
                project = temp / (tag + "-project")
                stage(source_root, project, ignore=shutil.ignore_patterns(".godot", "__pycache__"))
                f = project / FIXTURE
                f.parent.mkdir(parents=True, exist_ok=True)
                f.write_bytes(staged)
                inputs = {p.relative_to(project).as_posix(): sha(p) for p in project.rglob("*") if p.is_file()}
                (out / (tag + "-input-sha256.json")).write_text(json.dumps(inputs, indent=2) + "\n")
                engine = [str(args.godot.resolve()), "--path", str(project), "--audio-driver", "Dummy"]
                run(tag + "-import", engine + ["--headless", "--editor", "--import", "--quit"], isolate(temp, tag + "-import"))
                dest = out / tag
                dest.mkdir()
                env = isolate(temp, tag + "-capture")
                env.update(OUTPUT=str(dest), LIBGL_ALWAYS_SOFTWARE="1")
                run(tag + "-capture", engine + ["--display-driver", "x11", "--rendering-method", "gl_compatibility",
                    "--resolution", "1360x880", "--fixed-fps", "60", "--script", "res://" + FIXTURE,
                    "--", "--skip-tutorial"], env, "LITTER_NATIVE_COMPLETE")
                require(all(sha(project / p) == digest for p, digest in inputs.items()), "Staged inputs mutated")
        control, candidate = [inspect(out / tag) for tag in ("control", "candidate")]
        report["digests"] = {"control": control[2], "candidate": candidate[2]}
        require(control[:2] == candidate[:2], "Litter state or native pixels differ")
        report.update(frames_verified=1, receipts_equal=True)
        report["status"] = "rgba_equal_pending_visual_review"
    except Exception as error:
        report.update(status="failed", error=str(error))
        raise
    finally:
        save()


if __name__ == "__main__":
    main()
