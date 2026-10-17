"""One-shot paired wall-retention pixels; never qualifies or rewrites atlases."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
BASE = "a26e52b23f67a2de3ee3d078a3233f90f946cf4c"
FIXTURE = "tests/diagnostics/capture_wall_retention.gd"
FIXTURE_SHA = "1d3fb8805a40dfcc37515386415ff9b4b08c7e32fa137925fb20442cd7748fcc"
PRODUCTION = {
    "game/scripts/rendering/illustrated_cafe.gd": "a011b1bc70048059bf1c1beef449f6223d699faf87193a541030b222c010caaf",
    "game/scripts/rendering/illustrated_openings.gd": "e17458b8b35b04aca43da1ba38c8d6098a9d35ca71f8f03e2a0d4e83aaf57672",
}
LABELS = ("baseline", "pan-first-frame", "zoom-out-first-frame", "zoom-in-first-frame",
          "opening-added", "opening-moved", "material-texture", "neighbor-height",
          "neighbor-deleted", "wall-moved", "draft-valid", "draft-invalid",
          "draft-cancelled", "actor-behind-wall", "actor-before-wall", "wall-and-opening-removed")


def require(ok, message):
    if not ok:
        raise RuntimeError(message)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec); spec.loader.exec_module(value)
    return value


def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), *args]).decode().strip()


def verify_source():
    require(all(sha(ROOT / p) == digest for p, digest in PRODUCTION.items()), "Unreviewed renderer bytes")
    require(sha(ROOT / FIXTURE) == FIXTURE_SHA, "Capture fixture changed")
    require(set(git("diff", "--name-only", BASE, "--", "game", "platform").splitlines()) == set(PRODUCTION),
            "Unexpected production/atlas/platform change")
    atlas = module("wall_atlas_guard", ROOT / "tools/qualification/verify_prebaked_atlases.py")
    current = atlas.sources(); qualified = json.loads((ROOT / "game/data/prebaked_atlas_manifest.json").read_text())["source_sha256"]
    require(current.keys() == qualified.keys() and len(current) == 83, "Producer dependency set changed")
    stale = sorted(p for p in current if current[p] != qualified[p])
    require(stale == sorted(p.removeprefix("game/") for p in PRODUCTION), "Unexpected atlas qualification drift")
    return {"producer_count": len(current), "changed_producers": stale, "source_closure_qualified": False,
            "manifest_changed": False, "atlas_regenerated": False}


def read_frames(folder):
    from PIL import Image
    receipt = json.loads((folder / "capture.json").read_text())
    require(receipt["display"] == "X11" and receipt["renderer"] == "gl_compatibility"
            and not receipt["smoke_only"] and receipt["save_calls"] == 0, "Native isolated capture required")
    require(tuple(row["label"] for row in receipt["frames"]) == LABELS, "Incomplete frame sequence")
    expected = {f"{i:02d}-{name}.png" for i, name in enumerate(LABELS)}
    require({p.name for p in folder.glob("*.png")} == expected, "Unexpected PNG set")
    decoded = {}
    for row in receipt["frames"]:
        require(row["first_completed_frame"], "A transition skipped its first completed frame")
        with Image.open(folder / row["file"]) as png:
            require(png.size == (1360, 880), "Viewport changed")
            pixels = png.convert("RGBA").tobytes()
        digest = hashlib.sha256(pixels).hexdigest()
        require(digest == row["rgba_sha256"], "Independent PNG decode disagrees with native pixels")
        decoded[row["label"]] = digest
    return receipt, decoded


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expected-head", required=True)
    parser.add_argument("--godot", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    require(git("rev-parse", "HEAD") == args.expected_head, "Unexpected source head")
    require(not git("status", "--porcelain", "--untracked-files=no"), "Tracked checkout must be clean")
    require(subprocess.run(["git", "-C", str(ROOT), "merge-base", "--is-ancestor", BASE, "HEAD"]).returncode == 0,
            "Mail main must remain an ancestor")
    closure = verify_source()
    if args.verify_only:
        print(json.dumps(closure)); return
    require(args.godot and args.output, "Engine and output required")
    native = module("wall_native_process", ROOT / "tools/diagnostics/storage_native_review.py")
    require(sha(args.godot) == native.ENGINE_SHA, "Official engine checksum differs")
    output = args.output.resolve(); output.mkdir(parents=True, exist_ok=True)
    require(not any(output.iterdir()) and not output.is_relative_to(ROOT), "Use fresh evidence outside checkout")
    report = {"head": args.expected_head, "tree": git("rev-parse", "HEAD^{tree}"), "baseline": BASE,
              "fixture_sha256": FIXTURE_SHA, "production_sha256": PRODUCTION, "atlas": closure,
              "engine_sha256": sha(args.godot), "status": "running", "steps": [], "pixels_inspected": False}
    def save():
        (output / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
    def run(label, command, env):
        log = output / (label + ".log")
        code, reason = native.execute_native(command, env, log, timeout=120)
        report["steps"].append({"stage": label, "exit_code": code, "reason": reason, "log_sha256": sha(log)}); save()
        require(code == 0 and not reason and "ERROR:" not in log.read_text(errors="replace"), "Failed stage: " + label)
    save()
    try:
        stage = module("wall_project_stage", ROOT / "tools/build/project_layout.py").stage_project
        with tempfile.TemporaryDirectory(prefix="wall-native-saveguard-") as temporary:
            temp = Path(temporary); base = temp / "baseline-source"; base.mkdir()
            archive = subprocess.Popen(["git", "-C", str(ROOT), "archive", BASE, "game", "platform/web"], stdout=subprocess.PIPE)
            subprocess.run(["tar", "-x", "-C", str(base)], stdin=archive.stdout, check=True)
            archive.stdout.close(); require(archive.wait() == 0, "Baseline archive failed")
            captures = {}
            for label, source in (("baseline", base), ("candidate", ROOT)):
                project = temp / (label + "-project"); stage(source, project, ignore=shutil.ignore_patterns(".godot", "__pycache__"))
                fixture = project / FIXTURE; fixture.parent.mkdir(parents=True); shutil.copyfile(ROOT / FIXTURE, fixture)
                originals = {p.relative_to(project).as_posix(): sha(p) for p in project.rglob("*") if p.is_file()}
                (output / (label + "-source-sha256.json")).write_text(json.dumps(originals, indent=2))
                env = os.environ.copy(); env.pop("WALL_CAPTURE_HEADLESS_SMOKE", None)
                for key in ("HOME", "APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
                    folder = temp / (label + "-saveguard") / key; folder.mkdir(parents=True); env[key] = str(folder)
                frames = output / label; frames.mkdir(); env["OUTPUT"] = str(frames); env["LIBGL_ALWAYS_SOFTWARE"] = "1"
                engine = [str(args.godot.resolve()), "--path", str(project), "--audio-driver", "Dummy"]
                run(label + "-import", engine + ["--headless", "--editor", "--import", "--quit"], env)
                run(label + "-capture", engine + ["--rendering-method", "gl_compatibility", "--fixed-fps", "60", "--script", "res://" + FIXTURE, "--", "--skip-tutorial"], env)
                require(all(sha(project / p) == value for p, value in originals.items()), "Staged input mutated")
                captures[label] = read_frames(frames)
            before, after = captures["baseline"], captures["candidate"]
            ignored = {"frame", "draw_cpu_ms", "rgba_sha256"}
            require([{k: v for k, v in f.items() if k not in ignored} for f in before[0]["frames"]]
                    == [{k: v for k, v in f.items() if k not in ignored} for f in after[0]["frames"]], "Fixture states differ")
            report["pairs"] = [{"label": name, "baseline_rgba": before[1][name], "candidate_rgba": after[1][name],
                                "equal": before[1][name] == after[1][name]} for name in LABELS]
            save(); require(all(pair["equal"] for pair in report["pairs"]), "Pixel differences retained for review")
        report["status"] = "rgba_equal_pending_visual_review"
    except Exception as error:
        report["status"] = "failed"; report["error"] = str(error); raise
    finally:
        save()


if __name__ == "__main__":
    main()
