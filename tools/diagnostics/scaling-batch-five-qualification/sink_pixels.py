#!/usr/bin/env python3
"""True RGBA parity for draw-scoped washing, pause, multi-sink and lateral handoff."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from qualify import git, load_binding, module, require, sha, verify_sources
from sink_fixture import FIXED, SHEET, SIDE, SHEET_LABELS, SIDE_LABELS, overlay

PROFILES = ("HOME", "APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME")


def frames(folder, labels, size):
    from PIL import Image
    require({p.stem for p in folder.glob("*.png")} == set(labels), "Unexpected native PNG set")
    output = {}
    for label in labels:
        f = folder / (label + ".png")
        with Image.open(f) as image:
            require(image.size == size, "Unexpected native frame dimensions: " + label)
            output[label] = {"encoded": sha(f), "rgba": hashlib.sha256(image.convert("RGBA").tobytes()).hexdigest()}
    return output


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--repo", type=Path, required=True)
    p.add_argument("--bind", type=Path, required=True)
    p.add_argument("--godot", type=Path)
    p.add_argument("--output", type=Path)
    p.add_argument("--verify-only", action="store_true")
    a = p.parse_args()
    root = a.repo.resolve()
    binding = json.loads(a.bind.read_text())
    base, head = load_binding(root, binding)
    closure = verify_sources(root, binding)
    fixtures = {}
    for path, digest in FIXED.items():
        b = (root / path).read_bytes()
        require(path not in binding["reviewed_paths"] and sha(root / path) == digest and b == git(root, "show", f"{base}:{path}"),
                "Unbound fixture: " + path)
        fixtures[path] = overlay(path, b)
    fixture_hashes = {k: hashlib.sha256(b).hexdigest() for k, b in fixtures.items()}
    if a.verify_only:
        print(json.dumps({"control": base, "candidate": head, "fixtures": FIXED,
                          "staged_fixture_sha256": fixture_hashes, "atlas": closure}))
        return
    native = module("ll_native_sink_helpers", root / "tools/diagnostics/storage_native_review.py")
    require(a.godot and a.output and sha(a.godot) == native.ENGINE_SHA and os.environ.get("DISPLAY"),
            "Official Godot, isolated output and actual X11 display required")
    out = a.output.resolve()
    require(not out.is_relative_to(root), "External output required")
    out.mkdir(parents=True, exist_ok=False)
    report = {"control": base, "candidate": head, "control_tree": binding["control_tree"],
              "candidate_tree": binding["candidate_tree"], "engine_sha256": sha(a.godot),
              "fixture_source_sha256": FIXED, "staged_fixture_sha256": fixture_hashes,
              "scope": "Same-input actual X11 RGBA only, not FPS", "stages": [],
              "status": "running", "pixels_inspected": False}

    def save():
        (out / "sink-summary.json").write_text(json.dumps(report, indent=2) + "\n")

    def run(tag, command, env):
        log = out / (tag + ".log")
        code, reason = native.execute_native(command, env, log, timeout=120)
        report["stages"].append({"stage": tag, "exit": code, "reason": reason, "log_sha256": sha(log)})
        save()
        contents = log.read_text(errors="replace")
        require(code == 0 and not reason and "ERROR:" not in contents, "Failed native step: " + tag)
        return contents

    def isolate(temp, tag):
        env = os.environ.copy()
        for key in PROFILES:
            f = temp / tag / key
            f.mkdir(parents=True)
            env[key] = str(f)
        return env

    save()
    results = {}
    for path, data in fixtures.items():
        (out / (Path(path).stem + "-executed.gd.txt")).write_bytes(data)
    try:
        stage = module("ll_native_sink_stage", root / "tools/build/project_layout.py").stage_project
        with tempfile.TemporaryDirectory(prefix="sink-saveguard-") as folder:
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
            for tag, source in (("control", control), ("candidate", root)):
                project = temp / (tag + "-project")
                stage(source, project, ignore=shutil.ignore_patterns(".godot", "__pycache__"))
                for path, blob in fixtures.items():
                    f = project / path
                    f.parent.mkdir(parents=True, exist_ok=True)
                    f.write_bytes(blob)
                inputs = {p.relative_to(project).as_posix(): sha(p) for p in project.rglob("*") if p.is_file()}
                (out / (tag + "-input-sha256.json")).write_text(json.dumps(inputs, indent=2) + "\n")
                engine = [str(a.godot.resolve()), "--path", str(project), "--audio-driver", "Dummy"]
                run(tag + "-import", engine + ["--headless", "--editor", "--import", "--quit"], isolate(temp, tag + "-import"))
                results[tag] = {}
                for lane, fixture, labels, size in (("sheet", SHEET, SHEET_LABELS, (1360, 1024)),
                                                   ("side", SIDE, SIDE_LABELS, (1360, 880))):
                    dest = out / tag / lane
                    dest.mkdir(parents=True)
                    env = isolate(temp, tag + "-" + lane)
                    env.update(OUTPUT=str(dest), LIBGL_ALWAYS_SOFTWARE="1", SOURCE_COMMIT=(base if tag == "control" else head),
                               SINK_ROTATION="0", SINK_SIDE="left", SINK_EXPECT_FRONT_BLOCKED="0")
                    log = run(tag + "-" + lane, engine + ["--display-driver", "x11", "--rendering-method", "gl_compatibility",
                              "--resolution", f"{size[0]}x{size[1]}", "--fixed-fps", "60", "--script", "res://" + fixture,
                              "--", "--skip-tutorial"], env)
                    evidence = frames(dest, labels, size)
                    if lane == "sheet":
                        require("AUTOMATIC_WASH_NATIVE_COMPLETE frames=26 rotations=4 scoped=true" in log,
                                "Scoped sheet capture missing")
                        facts = json.loads((dest / "contacts.json").read_text())
                        require(facts["synthetic"] and not facts["normal_saves"] and facts["contacts"],
                                "Missing automatic wash contact proof")
                        require(evidence["paused-water-off"]["rgba"] != evidence["motion-19"]["rgba"],
                                "Paused water sample did not exercise distinct pixels")
                    else:
                        facts = json.loads((dest / "result.json").read_text())
                        captured_head = facts.pop("source_commit")
                        require(facts["intro_clear"] and captured_head == env["SOURCE_COMMIT"] and not facts["failures"]
                                and not facts["player_save_used"], "Visible same-fixture handoff proof missing")
                        owners = {s["label"]: s["owner"] for s in facts["states"]}
                        require(owners["precontact"] == "staff" and owners["queued"] == "dish_queue"
                                and owners["lowering"] == "dish_queue", "Expected pre/post release ownership")
                        contacts = facts["contacts"]
                        require(any(c["held"] and .60 <= c["phase"] < .65 for c in contacts if c["frame"] == "02b-precontact")
                                and any(not c["held"] and c["phase"] >= .65 for c in contacts if c["frame"] in {"03-queued", "03b-lowering"}),
                                "Missing held and released plate render contacts")
                        require(evidence["02b-precontact"]["rgba"] != evidence["03b-lowering"]["rgba"],
                                "Hand-off did not change pixels")
                    results[tag][lane] = (facts, evidence)
                require(all(sha(project / p) == digest for p, digest in inputs.items()), "Staged inputs mutated")
        report["pairs"] = [{ "lane": lane, "frame": frame, "control": entry, "candidate": results["candidate"][lane][1][frame],
                             "rgba_equal": entry["rgba"] == results["candidate"][lane][1][frame]["rgba"]}
                           for lane, (_, pictures) in results["control"].items() for frame, entry in pictures.items()]
        report["facts_equal"] = {lane: results["control"][lane][0] == results["candidate"][lane][0] for lane in ("sheet", "side")}
        require(all(report["facts_equal"].values()), "Exact synthetic fixture contacts/ownership differ")
        require(all(p["rgba_equal"] for p in report["pairs"]), "Native pixel differences retained")
        report["status"] = "rgba_equal_pending_visual_review"
    except Exception as failure:
        report.update(status="failed", error=str(failure))
        raise
    finally:
        save()


if __name__ == "__main__":
    main()
