"""Native dining still-frame parity, independent of Web and live FPS."""
import argparse
import hashlib
import json
from pathlib import Path
import os
import shutil
import subprocess
import tempfile


FIXTURES = {'capture_dining_parity.gd': 'e56a003ad119be4551b4ff0f0ca51f9716f1bef9ba8e4c71beae9abbb736f2f3', 'capture_dining_parity.tscn': 'f825c89d13362aec8a0026d27ce72e145ce684ca402fc4760e16f66b47e48629', 'verify_pixels.py': 'fd9388dba23b7bfa80e27235ee0c44171312c54881fbba7b56a542c8140a38f3'}
from qualify import git, load_binding, module, require, sha, verify_sources

PROFILES = ("HOME", "APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME")

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
    here = Path(__file__).resolve().parent
    require(all(sha(here / p) == digest for p, digest in FIXTURES.items()), "Exact reviewed dining fixture/comparator required")
    staged = {p: (here / p).read_bytes() for p in FIXTURES if p.endswith((".gd", ".tscn"))}
    report = {"control": base, "candidate": head, "control_tree": binding["control_tree"],
              "candidate_tree": binding["candidate_tree"], "scope": "Native still RGBA, not FPS",
              "fixture_source_sha256": FIXTURES,
              "atlas": closure, "stages": [], "status": "running", "pixels_inspected": False}
    if args.verify_only:
        print(json.dumps({**report, "status": "source_bound"}))
        return
    native = module("ll_dining_storage_helpers", root / "tools/diagnostics/storage_native_review.py")
    require(args.godot and args.output and sha(args.godot) == native.ENGINE_SHA and os.environ.get("DISPLAY"),
            "Official Godot, isolated output and actual X11 display required")
    out = args.output.resolve()
    require(not out.is_relative_to(root), "External output required")
    out.mkdir(parents=True, exist_ok=False)
    report["engine_sha256"] = sha(args.godot)

    def save():
        (out / "dining-summary.json").write_text(json.dumps(report, indent=2) + "\n")

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
        env.pop("DINING_SEMANTIC_ONLY", None)
        for key in PROFILES:
            folder = temp / tag / key
            folder.mkdir(parents=True)
            env[key] = str(folder)
        return env

    for path, contents in staged.items():
        (out / (path + "-executed.txt")).write_bytes(contents)
    try:
        stage = module("ll_dining_stage", root / "tools/build/project_layout.py").stage_project
        with tempfile.TemporaryDirectory(prefix="dining-saveguard-") as folder:
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
                for path, contents in staged.items():
                    (project / path).write_bytes(contents)
                inputs = {p.relative_to(project).as_posix(): sha(p) for p in project.rglob("*") if p.is_file()}
                (out / (tag + "-input-sha256.json")).write_text(json.dumps(inputs, indent=2) + "\n")
                engine = [str(args.godot.resolve()), "--path", str(project), "--audio-driver", "Dummy"]
                run(tag + "-import", engine + ["--headless", "--editor", "--import", "--quit"], isolate(temp, tag + "-import"))
                dest = out / tag
                dest.mkdir()
                env = isolate(temp, tag + "-capture")
                env.update(OUTPUT=str(dest), LIBGL_ALWAYS_SOFTWARE="1")
                run(tag + "-capture", engine + ["--display-driver", "x11", "--rendering-method", "gl_compatibility",
                    "--resolution", "1360x880", "--fixed-fps", "60", "res://capture_dining_parity.tscn",
                    "--", "--skip-tutorial"], env, "DINING_APPEARANCE_PARITY_RESULT")
                require(all(sha(project / p) == digest for p, digest in inputs.items()), "Staged inputs mutated")
        from verify_pixels import inspect
        control, candidate = [inspect(out / tag) for tag in ("control", "candidate")]
        report["rgba"] = {"control": control[1], "candidate": candidate[1]}
        by_arm = {tag: {p.name: sha(p) for p in sorted((out / tag).glob("*.png"))}
                  for tag in ("control", "candidate")}
        require(all(len(a) == 4 for a in by_arm.values()), "Expected exactly four native frames per arm")
        report["png_sha256"] = by_arm
        require(control == candidate, "Paired dining pixels and retained-object receipts differ")
        report.update(frames_verified=4, changed_pixels=control[2], receipts_equal=True)
        report["status"] = "rgba_equal_pending_visual_review"
    except Exception as error:
        report.update(status="failed", error=str(error))
        raise
    finally:
        save()


if __name__ == "__main__":
    main()
