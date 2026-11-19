"""Verify seven exact native floor frames and paired independent state receipts."""
import argparse
import hashlib
import json
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

from floor_fixture import FIXTURE, ORIGINAL, overlay
from qualify import git, load_binding, module, require, sha, verify_sources

PROFILES = ("HOME", "APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME")

LABELS = ("approach-cold", "approach-transitional", "paused", "solid-first",
          "through-door", "furniture", "mop")


def verify(control: Path, candidate: Path, *, semantic_only=False):
    from PIL import Image

    receipts, pixels, digests = [], [], []
    for root in (control, candidate):
        data = json.loads((root / "runtime.json").read_text())
        rows = data["records"]
        if (data["native_visible"] is not (not semantic_only)
                or data["player_save_used"] is not False
                or data["unowned"] != "unowned floor"
                or tuple(r["label"] for r in rows) != LABELS):
            raise ValueError("Incomplete floor fixture receipt")
        for r in rows:
            expected_host = "wall:fixture:4" if r["label"] == "solid-first" else "wall:fixture:5"
            if r["save_attempts"] != 0 or r["aperture_count"] != 1 or r["door_host"] != expected_host:
                raise ValueError("Fixture did not retain the expected real hosted door")
        receipts.append(data)
        if semantic_only:
            continue
        if {p.stem for p in root.glob("*.png")} != set(LABELS):
            raise ValueError("Incorrect native PNG inventory")
        pair, arm_digests = {}, {}
        for label in LABELS:
            p = root / f"{label}.png"
            with Image.open(p) as f:
                rgba = f.convert("RGBA")
                if (f.format != "PNG" or f.size != (1360, 880)
                        or rgba.getchannel("A").getextrema() != (255, 255)
                        or len(rgba.getcolors(64) or ()) in range(1, 16)):
                    raise ValueError(f"Not an opaque detailed cafe PNG: {p}")
                pair[label] = rgba.tobytes()
                arm_digests[label] = {"png_sha256": hashlib.sha256(p.read_bytes()).hexdigest(),
                                      "rgba_sha256": hashlib.sha256(pair[label]).hexdigest()}
        for a, b in (("approach-cold", "approach-transitional"), ("solid-first", "through-door"),
                     ("through-door", "furniture"), ("through-door", "mop")):
            if pair[a] == pair[b]:
                raise ValueError(f"Distinct cafe state must visibly change: {a}/{b}")
        pixels.append(pair)
        digests.append(arm_digests)
    if receipts[0] != receipts[1]:
        raise ValueError("Floor contact, obstruction, or state receipts differ")
    if not semantic_only and pixels[0] != pixels[1]:
        raise ValueError("Native exact RGBA parity failed: " +
                         ", ".join(label for label in LABELS if pixels[0][label] != pixels[1][label]))
    return {"frames_verified": 0 if semantic_only else len(LABELS),
            "semantic_records_verified": len(LABELS), "digests": digests}


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
    staged = overlay(source)
    fixture_hash = hashlib.sha256(staged).hexdigest()
    report = {"control": base, "candidate": head, "control_tree": binding["control_tree"],
              "candidate_tree": binding["candidate_tree"], "scope": "Native still RGBA, not FPS",
              "fixture_source_sha256": ORIGINAL, "staged_fixture_sha256": fixture_hash,
              "atlas": closure, "stages": [], "status": "running", "pixels_inspected": False}
    if args.verify_only:
        print(json.dumps({**report, "status": "source_bound"}))
        return
    native = module("ll_floor_storage_helpers", root / "tools/diagnostics/storage_native_review.py")
    require(args.godot and args.output and sha(args.godot) == native.ENGINE_SHA and os.environ.get("DISPLAY"),
            "Official Godot, isolated output and actual X11 display required")
    out = args.output.resolve()
    require(not out.is_relative_to(root), "External output required")
    out.mkdir(parents=True, exist_ok=False)
    report["engine_sha256"] = sha(args.godot)

    def save():
        (out / "floor-summary.json").write_text(json.dumps(report, indent=2) + "\n")

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
        env.pop("FLOOR_SEMANTIC_ONLY", None)
        for key in PROFILES:
            folder = temp / tag / key
            folder.mkdir(parents=True)
            env[key] = str(folder)
        return env

    (out / "capture_floor_cleaning_approach-executed.gd.txt").write_bytes(staged)
    try:
        stage = module("ll_floor_stage", root / "tools/build/project_layout.py").stage_project
        with tempfile.TemporaryDirectory(prefix="floor-saveguard-") as folder:
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
                    "--", "--skip-tutorial"], env, "FLOOR_CLEANING_NATIVE_RESULT")
                require(all(sha(project / p) == digest for p, digest in inputs.items()), "Staged inputs mutated")
        report.update(verify(out / "control", out / "candidate"))
        report["status"] = "rgba_equal_pending_visual_review"
    except Exception as error:
        report.update(status="failed", error=str(error))
        raise
    finally:
        save()


if __name__ == "__main__":
    main()
