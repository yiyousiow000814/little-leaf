"""One original-three native qualification; artifact-only, never writes a manifest."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import tempfile
from wall_retention_native import ROOT, PRODUCTION, git, module, require, sha, verify_source

PRODUCT = "023ea0a89dc71d65087a6ae6cb610abeb5ba0d98"
ALLOWED = {"tools/diagnostics/wall_atlas_qualification.py", ".github/workflows/wall-atlas-qualification.yml"}


def verify():
    require(set(git("diff", "--name-only", PRODUCT).splitlines()) == ALLOWED,
            "Only the two reviewed diagnostic paths may differ from captured product")
    closure = verify_source()
    native = module("atlas_native_helpers", ROOT / "tools/diagnostics/storage_native_review.py")
    for name, digest in native.HELPERS.items():
        require(sha(ROOT / "tests/diagnostics/canonical_atlas" / name) == digest, "Canonical helper changed")
    manifest = json.loads((ROOT / "game/data/prebaked_atlas_manifest.json").read_text())
    require(tuple(manifest["atlases"][n]["rgba_sha256"] for n in native.NAMES) == native.EXPECTED_RGBA,
            "Fixed image references changed")
    return closure, native


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expected-head", required=True)
    parser.add_argument("--godot", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    require(git("rev-parse", "HEAD") == args.expected_head, "Unexpected source head")
    require(not git("status", "--porcelain", "--untracked-files=no"), "Tracked checkout must be clean")
    closure, native = verify()
    if args.verify_only:
        print(json.dumps(closure)); return
    require(args.godot and args.output and sha(args.godot) == native.ENGINE_SHA, "Pinned official engine required")
    output = args.output.resolve(); output.mkdir(parents=True, exist_ok=True)
    require(not any(output.iterdir()) and not output.is_relative_to(ROOT), "Fresh external evidence directory required")
    guard = module("wall_atlas_guard_final", ROOT / "tools/qualification/verify_prebaked_atlases.py")
    producers = guard.sources()
    report = {"head": args.expected_head, "tree": git("rev-parse", "HEAD^{tree}"), "product": PRODUCT,
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


if __name__ == "__main__":
    main()
