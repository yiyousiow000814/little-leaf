"""One-shot standby native parity plus canonical atlas proof; artifact-only."""
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
BASE = "314c2e6ee7217173bdece0c8c425a234f070859c"
FIXTURE = "tests/diagnostics/capture_standby_retention.gd"
FIXTURE_SHA = "200504f9a8cea5bd8a32eff56bc1a779eb8b261eba712250a30a3b7167dbb1b2"
PRODUCTION = {'game/scripts/rendering/illustrated_cafe.gd': '11ff59969cf60918b5e2b48c1df7f436b76d48ee9798530d82d8caa7d178023e', 'game/scripts/rendering/cafe_native_draw_node.gd': '485c298089fb735ccad3e99af0980b19eb4d44b5e434b1f1dc2c1a7c6baa60a3'}
PRODUCT = BASE
LABELS = ('first-deferred-latest', 'cycle-00', 'cycle-01', 'cycle-02', 'cycle-03', 'cycle-04', 'cycle-05', 'cycle-06', 'cycle-07', 'cycle-08', 'cycle-09', 'cycle-10', 'cycle-11', 'cycle-12', 'cycle-13', 'cycle-14', 'cycle-15', 'cycle-16', 'blink-on', 'blink-off', 'walking-a', 'walking-b', 'work-a', 'work-b', 'payload-on', 'payload-off', 'tool-on', 'tool-off', 'seated-on', 'seated-off', 'slots-reversed', 'owners-removed', 'owners-returned')


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
    require(set(git("diff", "--name-only", BASE).splitlines()) == {'game/scripts/rendering/cafe_native_draw_node.gd', 'tests/diagnostics/capture_standby_retention.gd', 'tools/diagnostics/standby_retention_native.py', 'tests/run_integration_candidate.py', 'tests/rendering/test_standby_native_retention.gd', '.github/workflows/standby-retention-native.yml', 'game/scripts/rendering/illustrated_cafe.gd'}, "Only the seven reviewed initial paths may differ")
    require(all(sha(ROOT / p) == digest for p, digest in PRODUCTION.items()), "Unreviewed renderer bytes")
    require(sha(ROOT / FIXTURE) == FIXTURE_SHA, "Capture fixture changed")
    require(set(git("diff", "--name-only", BASE, "--", "game", "platform").splitlines()) == set(PRODUCTION),
            "Unexpected production/atlas/platform change")
    require(sha(ROOT / "game/data/prebaked_atlas_manifest.json") == "47d4c0be8ba2aa6fd3f68052ae725d435deae8d33caad434f3f1545303758cde", "Prequalification manifest changed")
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
            and not receipt["smoke_only"] and not receipt["game_instance_created"] and receipt["save_calls"] == 0, "Native isolated capture required")
    require(tuple(row["label"] for row in receipt["frames"]) == LABELS, "Incomplete frame sequence")
    expected = {f"{i:02d}-{name}.png" for i, name in enumerate(LABELS)}
    require({p.name for p in folder.glob("*.png")} == expected, "Unexpected PNG set")
    decoded = {}
    for row in receipt["frames"]:
        require(row["completed"]["all_completed"] and row["completed"]["native_groups"] > 0 and row["completed"]["shapes"] > 0, "Visible native descendants incomplete")
        require(row["first_completed_frame"], "A transition skipped its first completed frame")
        with Image.open(folder / row["file"]) as png:
            require(png.size == (1360, 880), "Viewport changed")
            pixels = png.convert("RGBA").tobytes()
        digest = hashlib.sha256(pixels).hexdigest()
        require(digest == row["rgba_sha256"], "Independent PNG decode disagrees with native pixels")
        decoded[row["label"]] = digest
    return receipt, decoded


def run_native(args):
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
        with tempfile.TemporaryDirectory(prefix="standby-native-saveguard-") as temporary:
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


def run_atlas(args):
    closure = verify_source()
    native = module("standby_atlas_helpers", ROOT / "tools/diagnostics/storage_native_review.py")
    for name, digest in native.HELPERS.items():
        require(sha(ROOT / "tests/diagnostics/canonical_atlas" / name) == digest, "Canonical helper changed")
    require(args.godot and args.output and sha(args.godot) == native.ENGINE_SHA, "Pinned official engine required")
    output = args.output.resolve(); output.mkdir(parents=True, exist_ok=True)
    require(not any(output.iterdir()) and not output.is_relative_to(ROOT), "Fresh external evidence directory required")
    guard = module("wall_atlas_guard_final", ROOT / "tools/qualification/verify_prebaked_atlases.py")
    producers = guard.sources()
    original_manifest = json.loads((ROOT / "game/data/prebaked_atlas_manifest.json").read_text())
    report = {"head": args.expected_head, "tree": git("rev-parse", "HEAD^{tree}"), "baseline": BASE,
              "production_sha256": PRODUCTION, "producer_sha256": producers,
              "producer_closure_sha256": hashlib.sha256(json.dumps(producers, sort_keys=True, separators=(",", ":")).encode()).hexdigest(),
              "engine_sha256": sha(args.godot), "helpers_sha256": native.HELPERS,
              "manifest_written": False, "source_assets_written": False, "player_data_used": False,
              "game_instance_created": False, "status": "running", "steps": [], "pixels_inspected": False}
    def save():
        (output / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
    def run(label, command, env):
        log = output / (label + ".log")
        code, reason = native.execute_native(command, env, log, timeout=120)
        report["steps"].append({"stage": label, "exit_code": code, "reason": reason, "log_sha256": sha(log)}); save()
        require(code == 0 and not reason and "ERROR:" not in log.read_text(errors="replace"), "Failed stage: " + label)
    save()
    try:
        from PIL import Image
        stage = module("wall_atlas_stage", ROOT / "tools/build/project_layout.py").stage_project
        with tempfile.TemporaryDirectory(prefix="wall-atlas-saveguard-") as temporary:
            temp = Path(temporary); project = temp / "project"
            stage(ROOT, project, ignore=shutil.ignore_patterns(".godot", "__pycache__"))
            helpers = project / "tests/diagnostics/canonical_atlas"
            shutil.copytree(ROOT / "tests/diagnostics/canonical_atlas", helpers)
            originals = {p.relative_to(project).as_posix(): sha(p) for p in project.rglob("*") if p.is_file()}
            (output / "staged-source-sha256.json").write_text(json.dumps(originals, indent=2) + "\n")
            scene = project / "wall-atlas-parity.tscn"
            scene.write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://tests/diagnostics/canonical_atlas/parity.gd" id="1"]\n[node name="AtlasParity" type="Node"]\nscript = ExtResource("1")\n')
            report["disposable_scene_sha256"] = sha(scene)
            env = os.environ.copy()
            for key in ("HOME", "APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
                folder = temp / "profile" / key; folder.mkdir(parents=True); env[key] = str(folder)
            atlas = output / "atlas"; atlas.mkdir()
            env.update(LIBGL_ALWAYS_SOFTWARE="1", LL_ATLAS_SOURCE=args.expected_head, LL_ATLAS_OUTPUT=str(atlas))
            engine = [str(args.godot.resolve()), "--path", str(project), "--audio-driver", "Dummy"]
            config = project / "project.godot"; original_config = config.read_bytes()
            require(b"[editor]" not in original_config, "Review changed editor import policy")
            try:
                config.write_bytes(original_config + b"\n[editor]\nimport/use_multiple_threads=false\n")
                run("import", engine + ["--headless", "--editor", "--import", "--quit"], env)
            finally:
                config.write_bytes(original_config)
            run("original-three", engine + ["--rendering-method", "gl_compatibility", "res://wall-atlas-parity.tscn"], env)
            for name in ("check_saved", "check_source_png"):
                run(name, engine + ["--headless", "--script", "res://tests/diagnostics/canonical_atlas/" + name + ".gd"], env)
            native.check_atlas(atlas, args.expected_head)
            rows = []
            for index, name in enumerate(native.NAMES):
                source = project / "assets/cache" / (name + "-atlas.png")
                shutil.copyfile(source, atlas / (name + "-source.png"))
                for suffix in ("regenerated", "atlas", "source"):
                    path = atlas / (name + "-" + suffix + ".png")
                    with Image.open(path) as image:
                        digest = hashlib.sha256(image.convert("RGBA").tobytes()).hexdigest()
                        require(digest == native.EXPECTED_RGBA[index], "Independent PNG decode mismatch")
                        require(sha(path) == original_manifest["atlases"][name]["png_sha256"], "Encoded PNG differs from qualified original")
                        rows.append({"file": path.name, "size": list(image.size), "png_sha256": sha(path), "rgba_sha256": digest})
            report["independent_pngs"] = rows
            require(all(sha(project / p) == digest for p, digest in originals.items()), "Staged source mutated")
            require(guard.sources() == producers, "Repository source changed during qualification")
            report["atlas_receipt_sha256"] = sha(atlas / "atlas-parity.json")
            report["status"] = "fixed_rgba_equal_pending_review"
    except Exception as error:
        report["status"] = "failed"; report["error"] = str(error); raise
    finally:
        save()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expected-head", required=True)
    parser.add_argument("--godot", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    if args.verify_only:
        run_native(args); return
    require(args.output and not args.output.exists(), "Fresh combined output required")
    output = args.output.resolve(); output.mkdir(parents=True)
    args.output = output / "native"
    run_native(args)
    args.output = output / "qualification"
    run_atlas(args)


if __name__ == "__main__":
    main()
