"""PR349-only native evidence. Never update source, atlas manifest, assets or saves."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
REVIEWED_SOURCE = "9127a53d31258c28eaa37e06cc1752e8bd48b9f4"
REVIEWED_TREE = "c82bf154e29da90ad34ff40a8910956c7bd9d68e"
COMPONENT_SOURCE = "d40fe870b56c1614a9ba84ade8c9cf5d4ae177d0"
FIXTURE = "tests/presentation/test_storage_ui.gd"
FIXTURE_SHA = "cbc24301f1c939a0d32ef3b1c212946293821bf80ecb7bf136d339a8049845c1"
REVIEWED_POSTIMAGES = {
    "game/scripts/main.gd": "4c1fb1afcb0d1c72797bd42b07937bb5828f4c389f0e1607a57c1aa9a50192be",
    "game/scripts/ui/cafe_shop_ui.gd": "4d3502e99344331349e495c02a52727864995bae887440ee73afaf5675264dd0",
    "tests/presentation/test_storage_ui.gd": "cbc24301f1c939a0d32ef3b1c212946293821bf80ecb7bf136d339a8049845c1"
}
PRIOR_ATLAS = {
    "source": "207409f5f19187e13f005de0f8a832b69f430cb9",
    "tree": "e27e58e115590eb7e973d1dcbe01fc28b7ddab7f",
    "run": "https://github.com/yiyousiow000814/little-leaf/actions/runs/38998426362",
    "receipt_sha256": "ea7452ab917c85ae36f261e0372471291d1941254717e3b9736716dff7a18133",
}
CLOSURE_SHA = "e540266523346c68bb05fd52e5050aea96a4a26c5b0cb4e0b528a13274814bec"
ENGINE_SHA = "f64d4ed19fc9df9440321653fcc80df8c6e365ba7b6de0a29e2cfa9fa71bfeb3"
HELPERS = {
    "parity.gd": "db965918fe450b3e05d859368313f7d10ee89902c27b58d783bd1e0b943d7033",
    "check_saved.gd": "50d376bba86697725afdf48389d692f98ed7504cfd6a8cc9af1dfe054796ba2c",
    "check_source_png.gd": "4ff8da9349ead29fd1087979490611d28a5886670efd24a4f4cbcd14918acc39",
}
NAMES = ("furniture", "moving", "heads")
EXPECTED_RGBA = (
    "ba615c7535d6e3806d1b6b27abf2c50575e59486c8b9ab8c08d4eadff401b5ac",
    "6dc71a1bde51fc5c514356e5188736d24b6edc54acfa15185091b31cfce69bbc",
    "d16a8ea4064eb3aa5fa1daa90f61731e1288aa1e5089b0a8b3d9b381b106c1d7",
)
STALE = {
    "scripts/gameplay/cafe_dining_sets.gd", "scripts/persistence/cafe_runtime_codec.gd",
    "scripts/persistence/cafe_save_contract.gd", "scripts/rendering/illustrated_cafe.gd",
}


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def file_sha(path):
    return digest(path.read_bytes())


def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), *args])


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def check_reviewed_postimages(changed, root):
    require(set(changed) == set(REVIEWED_POSTIMAGES), "Unreviewed protected source changes")
    require(all(file_sha(root / name) == sha for name, sha in REVIEWED_POSTIMAGES.items()),
            "Reviewed Storage UI postimage changed")


def check_closure(current, manifest):
    require(len(current) == 83, "Expected the reviewed 83-input producer closure")
    require(digest(json.dumps(current, sort_keys=True, separators=(",", ":")).encode()) == CLOSURE_SHA,
            "Producer closure differs from reviewed Storage source")
    previous = manifest["source_sha256"]
    require(set(previous) == set(current), "Producer dependency set changed")
    require({name for name in current if current[name] != previous[name]} == STALE,
            "Expected exactly four pending source qualifications")
    require(tuple(manifest["atlases"][n]["rgba_sha256"] for n in NAMES) == EXPECTED_RGBA,
            "Fixed reference RGBA changed")


def check_atlas(folder, head):
    receipt = json.loads((folder / "atlas-parity.json").read_text())
    require(receipt.get("source_commit") == head and receipt.get("checks") == 3 and
            receipt.get("failures") == [], "Incomplete or failed native atlas receipt")
    require(receipt.get("baseline_sha256") == receipt.get("candidate_sha256") == list(EXPECTED_RGBA),
            "Generated/imported atlases differ from fixed references")
    require(receipt.get("engine") == "4.6.3-stable (official)" and
            receipt.get("display_server") == "X11" and receipt.get("renderer") == "gl_compatibility",
            "Actual official native GL renderer required")
    require(receipt.get("player_data_used") is False and receipt.get("game_instance_created") is False,
            "Atlas verification must not create a game or use player data")
    requests = receipt.get("runtime_requests", [])
    require(len(requests) == 3, "Missing runtime atlas requests")
    for i, row in enumerate(requests):
        require(row.get("name") == NAMES[i] and row.get("prebaked") is True and
                row.get("state") == "ready" and row.get("rgba_sha256") == EXPECTED_RGBA[i],
                "Runtime READY reference mismatch")
    for name, keys in (("saved-png-check.json", ("regenerated_rgba", "imported_rgba")),
                       ("source-png-check.json", ("source_rgba",))):
        decoded = json.loads((folder / name).read_text())
        require(decoded.get("source_commit") == head and decoded.get("failures") == [] and
                len(decoded.get("rows", [])) == 3, "Incomplete PNG decoding receipt: " + name)
        for i, row in enumerate(decoded["rows"]):
            require(row.get("name") == NAMES[i] and row.get("passed") is True and
                    all(row.get(key) == EXPECTED_RGBA[i] for key in keys), "PNG reference mismatch: " + name)
    return receipt


def check_frames(folder, log):
    results = [json.loads(line.split(" ", 1)[1]) for line in log.splitlines()
               if line.startswith("STORAGE_UI_RESULT ")]
    require(len(results) == 1 and results[0].get("failures") == [] and
            results[0].get("checks", 0) >= 100 and results[0].get("player_save_used") is False,
            "Missing or failed full-game Storage UI result")
    require("Godot Engine v4.6.3.stable.official.7d41c59c4" in log and
            "OpenGL API" in log and "Compatibility" in log, "Missing native UI renderer evidence")
    expected = {f"{state}-{size}.png": tuple(map(int, size.split("x")))
                for state in ("shop", "storage", "storage-count2", "storage-count1", "storage-categories", "store-action")
                for size in ("1360x880", "390x844", "844x390")}
    require({p.name for p in folder.glob("*.png")} == set(expected), "Incomplete or extra Storage captures")
    rows = {}
    for name, size in expected.items():
        data = (folder / name).read_bytes()
        require(data.startswith(b"\x89PNG\r\n\x1a\n") and len(data) > 1000 and
                (int.from_bytes(data[16:20], "big"), int.from_bytes(data[20:24], "big")) == size,
                "Invalid or wrongly sized capture: " + name)
        rows[name] = {"sha256": digest(data), "bytes": len(data), "size": size}
    return {"result": results[0], "frames": rows, "pixels_inspected": False}


def execute_native(command, env, log_path, timeout=300):
    """Retain diagnostics and stop this owned process group on the first error."""
    reason = None
    with log_path.open("wb") as stream:
        process = subprocess.Popen(command, env=env, stdout=stream, stderr=subprocess.STDOUT,
                                   start_new_session=True)
        started = time.monotonic()
        while process.poll() is None:
            text = log_path.read_text(errors="replace")
            if "ERROR:" in text:
                reason = "engine reported an error"
            elif time.monotonic() - started > timeout:
                reason = "native stage timed out"
            if reason:
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                break
            time.sleep(.1)
    return process.returncode, reason


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expected-head", required=True)
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    require(re.fullmatch(r"[0-9a-f]{40}", args.expected_head), "Exact head SHA required")
    head = git("rev-parse", "HEAD").decode().strip()
    require(head == args.expected_head, "Checkout differs from expected PR head")
    require(not git("status", "--porcelain", "--untracked-files=no"), "Tracked checkout must be clean")
    require(git("rev-parse", REVIEWED_SOURCE + "^{tree}").decode().strip() == REVIEWED_TREE,
            "Reviewed implementation tree unavailable or changed")
    protected = ("game", "platform/web", FIXTURE, "tools/build/project_layout.py",
                 "tools/qualification/verify_prebaked_atlases.py", "tools/ci/toolchain.json")
    changed = git("diff", "--name-only", REVIEWED_SOURCE, head, "--", *protected).decode().splitlines()
    check_reviewed_postimages(changed, ROOT)
    require(file_sha(args.godot) == ENGINE_SHA, "Official engine binary hash mismatch")
    require(file_sha(ROOT / FIXTURE) == FIXTURE_SHA, "Storage capture fixture changed")
    helper = ROOT / "tests/diagnostics/canonical_atlas"
    require(all(file_sha(helper / n) == sha for n, sha in HELPERS.items()), "Historical helper bytes changed")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    require(not any(output.iterdir()) and not output.is_relative_to(ROOT), "Use fresh evidence outside checkout")
    manifest_path = ROOT / "game/data/prebaked_atlas_manifest.json"
    manifest = json.loads(manifest_path.read_text())
    guard = load_module("storage_atlas_guard", ROOT / "tools/qualification/verify_prebaked_atlases.py")
    closure = guard.sources()
    check_closure(closure, manifest)
    for name in NAMES:
        require(all(manifest["atlases"][name][k] == v for k, v in guard.asset(name).items()),
                "Source atlas PNG/import record changed: " + name)
    (output / "producer-closure.json").write_text(json.dumps(closure, indent=2) + "\n")
    report = {"head": head, "tree": git("rev-parse", "HEAD^{tree}").decode().strip(),
              "reviewed_source": REVIEWED_SOURCE, "component_source": COMPONENT_SOURCE,
              "helper_sha256": HELPERS, "fixture_sha256": FIXTURE_SHA,
              "reviewed_ui_postimages": REVIEWED_POSTIMAGES,
              "prior_atlas_qualification": PRIOR_ATLAS, "atlas_regenerated": False,
              "producer_count": len(closure), "closure_sha256": CLOSURE_SHA,
              "manifest_sha256": file_sha(manifest_path), "engine_sha256": file_sha(args.godot),
              "expected_rgba": EXPECTED_RGBA, "manifest_written": False, "player_save_used": False,
              "status": "running", "steps": [], "pixels_inspected": False}

    def save():
        (output / "summary.json").write_text(json.dumps(report, indent=2) + "\n")

    def run(label, command, env):
        path = output / (label + ".log")
        code, reason = execute_native(command, env, path)
        text = path.read_text(errors="replace")
        report["steps"].append({"label": label, "exit_code": code, "log_sha256": file_sha(path),
                                "stop_reason": reason,
                                "diagnostics": [l for l in text.splitlines() if "WARNING" in l or "ERROR" in l]})
        save()
        require(code == 0 and not reason and "ERROR:" not in text, "Native stage failed; retained evidence: " + label)
        return text

    save()
    try:
        stage = load_module("storage_project_layout", ROOT / "tools/build/project_layout.py").stage_project
        with tempfile.TemporaryDirectory(prefix="storage-native-saveguard-") as temporary:
            temp = Path(temporary)
            project = temp / "project"
            stage(ROOT, project, tests=True, ignore=shutil.ignore_patterns(".git", ".godot", "__pycache__"))
            originals = {p.relative_to(project).as_posix(): file_sha(p) for p in project.rglob("*") if p.is_file()}
            config = project / "project.godot"
            config.write_text(config.read_text().replace("[application]", '[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="storage-native-saveguard"', 1))
            web_save = project / "scripts/persistence/cafe_web_save.gd"
            code = web_save.read_text()
            old = 'const STAGING_FILE="/tmp/little_leaf_vault_staging.json"'
            require(old in code, "Native staging contract changed")
            web_save.write_text(code.replace(old, 'const STAGING_FILE="user://generated_visual_stage.json"'))
            report["disposable_overrides"] = {n: file_sha(project / n) for n in ("project.godot", "scripts/persistence/cafe_web_save.gd")}
            (output / "staged-source-sha256.json").write_text(json.dumps(originals, indent=2) + "\n")
            env = os.environ.copy()
            for key in ("HOME", "APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
                folder = temp / "profile" / key.lower()
                folder.mkdir(parents=True)
                env[key] = str(folder)
            frames = output / "storage"
            frames.mkdir()
            env.update(LIBGL_ALWAYS_SOFTWARE="1", LL_CAPTURE_OUTPUT=str(frames))
            runtime_config = config.read_text()
            require("[editor]" not in runtime_config, "Review existing editor import policy")
            config.write_text(runtime_config + "\n[editor]\nimport/use_multiple_threads=false\n")
            engine = [str(args.godot.resolve()), "--path", str(project), "--audio-driver", "Dummy"]
            try:
                run("import", engine + ["--headless", "--editor", "--import", "--quit"], env)
            finally:
                config.write_text(runtime_config)
            # The complete83-source closure, source PNG/import records and fixed
            # references above equal the retained original-three qualification.
            # Main/Shop UI are outside that closure: capture only changed UI.
            native = engine + ["--rendering-method", "gl_compatibility"]
            log = run("storage-native", native + ["--script", "res://" + FIXTURE, "--", "--visual-qa", "--fresh-review", "--skip-intro", "--skip-tutorial"], env)
            report["storage"] = check_frames(frames, log)
            require(all(file_sha(project / n) == sha for n, sha in originals.items() if n not in report["disposable_overrides"]),
                    "Staged production, assets, imports or fixture changed during native run")
            require(not list((temp / "profile").rglob("little_leaf_cafe_layout_motion_v15.json")), "Unexpected normal save")
            report["staged_protected_bytes_unchanged"] = True
        require(not git("status", "--porcelain", "--untracked-files=no"), "Tracked source was modified")
        report["status"] = "rendered_pending_pixel_review"
    except Exception as error:
        report["status"] = "failed"
        report["error"] = str(error)
        raise
    finally:
        save()


if __name__ == "__main__":
    main()
