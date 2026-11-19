#!/usr/bin/env python3
"""Two immutable detached sources, the same committed dining fixture, actual RGBA."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from qualify import git, load_binding, module, require, sha, verify_sources

FIXTURE = "tests/diagnostics/capture_dining_live.gd"
FIXTURE_SHA = "7724284232ccc85a6c8f7969e488a9a19764a773a1ebc04bea55416f88144b59"
LABELS = ("scoop", "lift", "chew", "interbite-rest", "interbite-return", "last-scoop",
          "used-while-chewing", "finished", "undock-0", "undock-8", "undock-20")
PROFILES = ("HOME", "APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME")


def frames(folder):
    from PIL import Image
    contacts = json.loads((folder / "live-capture.json").read_text())
    require(tuple(row["label"] for row in contacts) == LABELS, "Missing or reordered dining phase")
    require(all(row["saves"] == 0 and row["paused"] is (index < 8)
                for index, row in enumerate(contacts)), "Unexpected pause state or write")
    for index, row in enumerate(contacts):
        require(sorted({int(c["id"]) for c in row["contacts"]}) == [0, 3, 6, 9],
                f"All four synthetic guest contacts required: {row['label']}")
        if index < 8:
            require(any(bool(c.get("dining_pose")) for c in row["contacts"]),
                    f"Missing seated docking/meal pose: {row['label']}")
    expected = {"live-" + label + ".png" for label in LABELS}
    require({p.name for p in folder.glob("*.png")} == expected, "Missing or excess dining frames")
    result = {}
    for label in LABELS:
        path = folder / ("live-" + label + ".png")
        with Image.open(path) as png:
            require(png.size == (1800, 1200), f"Unexpected viewport at {label}: {png.size}")
            rgba = png.convert("RGBA").tobytes()
        result[label] = {"encoded_sha256": sha(path), "rgba_sha256": hashlib.sha256(rgba).hexdigest()}
    require(result["scoop"]["rgba_sha256"] != result["lift"]["rgba_sha256"], "Lift did not animate")
    require(result["undock-0"]["rgba_sha256"] != result["undock-20"]["rgba_sha256"], "Undocking did not animate")
    return contacts, result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True, type=Path)
    parser.add_argument("--bind", required=True, type=Path)
    parser.add_argument("--godot", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    root = args.repo.resolve()
    binding = json.loads(args.bind.read_text())
    base, cand = load_binding(root, binding)
    closure = verify_sources(root, binding)
    fixture = (root / FIXTURE).read_bytes()
    require(FIXTURE not in binding["reviewed_paths"] and sha(root / FIXTURE) == FIXTURE_SHA
            and fixture == git(root, "show", f"{base}:{FIXTURE}"),
            "Use original identical committed live dining fixture")
    if args.verify_only:
        print(json.dumps({"control": base, "candidate": cand, "fixture": FIXTURE_SHA, "atlas": closure}))
        return
    native = module("ll_bound_native_helpers", root / "tools/diagnostics/storage_native_review.py")
    require(args.godot and args.output and sha(args.godot) == native.ENGINE_SHA,
            "Pinned official Godot and isolated output required")
    require(os.environ.get("DISPLAY"), "Native X11 requires a real display socket")
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    require(not out.is_relative_to(root), "Output must be outside checkout")
    report = {"control": base, "candidate": cand, "control_tree": binding["control_tree"],
              "candidate_tree": binding["candidate_tree"], "fixture_sha256": FIXTURE_SHA,
              "engine_sha256": sha(args.godot), "steps": [], "scope": "11 native same-scene PNG pairs; no FPS",
              "status": "running", "pixels_inspected": False}

    def save():
        (out / "dining-summary.json").write_text(json.dumps(report, indent=2) + "\n")

    def run(label, cmd, env):
        log = out / (label + ".log")
        code, problem = native.execute_native(cmd, env, log, timeout=120)
        contents = log.read_text(errors="replace")
        report["steps"].append({"label": label, "exit_code": code, "problem": problem, "log_sha256": sha(log)})
        save()
        require(code == 0 and not problem and "ERROR:" not in contents, f"Failed native stage: {label}")
        return contents

    results = {}
    save()
    try:
        stage = module("ll_bound_layout", root / "tools/build/project_layout.py").stage_project
        with tempfile.TemporaryDirectory(prefix="dining-saveguard-") as tmp:
            temp = Path(tmp)
            baseline = temp / "control"
            baseline.mkdir()
            proc = subprocess.Popen(["git", "-C", str(root), "archive", base, "game", "platform/web"],
                                    stdout=subprocess.PIPE)
            try:
                subprocess.run(["tar", "-x", "-C", str(baseline)], check=True, stdin=proc.stdout)
            finally:
                proc.stdout.close()
                require(proc.wait() == 0, "Could not archive exact control project")
            for tag, source in (("control", baseline), ("candidate", root)):
                project = temp / (tag + "-project")
                stage(source, project, ignore=shutil.ignore_patterns(".godot", "__pycache__"))
                staged_fixture = project / FIXTURE
                staged_fixture.parent.mkdir(parents=True)
                staged_fixture.write_bytes(fixture)
                originals = {p.relative_to(project).as_posix(): sha(p) for p in project.rglob("*") if p.is_file()}
                (out / (tag + "-source-sha256.json")).write_text(json.dumps(originals, indent=2) + "\n")
                env = os.environ.copy()
                for key in PROFILES:
                    folder = temp / tag / key
                    folder.mkdir(parents=True)
                    env[key] = str(folder)
                folder = out / tag
                folder.mkdir()
                env.update(OUTPUT=str(folder), LIBGL_ALWAYS_SOFTWARE="1")
                engine = [str(args.godot.resolve()), "--path", str(project), "--audio-driver", "Dummy"]
                run(tag + "-import", engine + ["--headless", "--editor", "--import", "--quit"], env)
                log = run(tag + "-capture", engine + ["--display-driver", "x11", "--rendering-method", "gl_compatibility",
                          "--resolution", "1800x1200", "--fixed-fps", "60", "--script", "res://" + FIXTURE,
                          "--", "--skip-tutorial"], env)
                require("DINING_LIVE_RESULT facings=4 phases=11 paused=true save_calls=0" in log,
                        "Expected actual fixture and no persistence writes")
                require(all(sha(project / p) == digest for p, digest in originals.items()), "Staged inputs mutated")
                results[tag] = frames(folder)
        contact_equal = results["control"][0] == results["candidate"][0]
        report.update(contacts_equal=contact_equal, pairs=[
            {"label": label, "control": results["control"][1][label], "candidate": results["candidate"][1][label],
             "rgba_equal": (results["control"][1][label]["rgba_sha256"] == results["candidate"][1][label]["rgba_sha256"])}
            for label in LABELS])
        require(contact_equal, "Guest phase/pose contacts differ")
        require(all(row["rgba_equal"] for row in report["pairs"]), "RGBA differences retained")
        report["status"] = "rgba_equal_pending_visual_review"
    except Exception as failure:
        report["status"] = "failed"
        report["error"] = str(failure)
        raise
    finally:
        save()


if __name__ == "__main__":
    main()
