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
TARGET_IDS = {0, 3, 6, 9}
FIXTURE_START = " await process_frame;game.illustration.set_process(false)"
FIXTURE_READY = """ await process_frame
 for wait_frame in 900:
  if not is_instance_valid(game.startup_readiness) or game.startup_readiness.completed:break
  await process_frame
 assert(not game.startup_preparation_report.is_empty() and not game.startup_preparation_report.timed_out and game.startup_preparation_report.ready==3,"Three atlas READY inputs required")
 if game.cafe_intro!=null:game.cafe_intro.finish()
 assert(game.cafe_intro!=null and not game.cafe_intro.active and not game.cafe_intro.preparing and not game.cafe_intro.cover.is_visible_in_tree(),"Welcome cover must be gone")
 for tween in get_processed_tweens():tween.kill()
 game.animation_time=1.0
 game.illustration.set_process(false)"""
PROFILES = ("HOME", "APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME")


def diagnostic_fixture(original):
    source = original.decode()
    changes = (
        (' root.size=Vector2i(1800,1200);game=TestMain.new()', ' root.size=Vector2i(1800,1200);seed(13017);game=TestMain.new()'),
        (FIXTURE_START, FIXTURE_READY),
        (' await RenderingServer.frame_post_draw\n root.get_texture()', ' await RenderingServer.frame_post_draw\n '
         'assert(not game.cafe_intro.active and not game.cafe_intro.cover.is_visible_in_tree(),"Visible cafe required after draw")\n root.get_texture()'),
        ('"saves":game.saves,"contacts":contacts', '"saves":game.saves,"intro_clear":not game.cafe_intro.active and not game.cafe_intro.cover.is_visible_in_tree(),"contacts":contacts'),
    )
    for old, new in changes:
        require(source.count(old) == 1, "Committed fixture transform no longer binds exactly")
        source = source.replace(old, new, 1)
    return source.encode()


def frames(folder):
    from PIL import Image
    contacts = json.loads((folder / "live-capture.json").read_text())
    require(tuple(row["label"] for row in contacts) == LABELS, "Missing or reordered dining phase")
    require(all(row["saves"] == 0 and row["intro_clear"] is True and row["paused"] is (index < 8)
                for index, row in enumerate(contacts)), "Unexpected cover, pause state or write")
    for index, row in enumerate(contacts):
        # Global contacts also contain street walkers (the exact #371 run has
        # 114–117) and duplicate draw contacts per owner. Keep those in the raw
        # receipt and compare them exactly, but don't miscount them as seats.
        targets = [c for c in row["contacts"] if int(c["id"]) in TARGET_IDS]
        require({int(c["id"]) for c in targets} == TARGET_IDS,
                f"All four synthetic guest contacts required: {row['label']}")
        if index < 8:
            require({int(c["id"]) for c in targets if c["action"] == "eating" and c.get("dining_pose")} == TARGET_IDS,
                    f"Missing seated docking/meal pose: {row['label']}")
        else:
            require({int(c["id"]) for c in targets if c["action"] == "idle" and not c.get("dining_pose")} == TARGET_IDS,
                    f"Missing idle transition coverage during undocking: {row['label']}")
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
    executed_fixture = diagnostic_fixture(fixture)
    executed_sha = hashlib.sha256(executed_fixture).hexdigest()
    if args.verify_only:
        print(json.dumps({"control": base, "candidate": cand, "fixture": FIXTURE_SHA, "diagnostic_fixture": executed_sha, "atlas": closure}))
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
              "diagnostic_fixture_sha256": executed_sha,
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
    (out / "executed-fixture.gd.txt").write_bytes(executed_fixture)
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
                staged_fixture.write_bytes(executed_fixture)
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
