"""Run stove-workspace regressions and optional native GL screenshots in disposable profiles.

Example: python3 tests/run_stove_work_reservation.py --output /tmp/stove-work-qa --native
GODOT_BIN selects Godot 4.6.3. Native mode uses DISPLAY or an isolated Xvfb.
--import-cache SOURCE_PROJECT reuses only imported assets after exact SHA256
validation of all asset inputs and import metadata; it is not a clean import.
Never reads player profiles or the real Web staging file. Source is not modified.
"""
import argparse
from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import select
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
EXCLUDED = {".git", ".godot", "qa-project", "evidence", "__pycache__", "build", "builds",
            "export", "exports", "export_templates", "dist"}
IGNORE = shutil.ignore_patterns(*EXCLUDED, "*.log", "*.zip")


@contextmanager
def native_display(env, temp, output):
    if env.get("DISPLAY"):
        yield env
        return
    executable = shutil.which("Xvfb")
    if not executable:
        raise RuntimeError("Native rendering needs a working DISPLAY or Xvfb; headless checks remain independent")
    read_fd, write_fd = os.pipe()
    server = None
    with (output / "xvfb.log").open("wb") as log:
        try:
            server = subprocess.Popen([executable, "-displayfd", str(write_fd), "-screen", "0", "1600x1000x24",
                                       "-nolisten", "tcp", "-noreset"], pass_fds=(write_fd,),
                                      stdout=log, stderr=subprocess.STDOUT, env=env, cwd=temp)
            os.close(write_fd)
            write_fd = None
            if not select.select([read_fd], [], [], 15)[0]:
                raise RuntimeError("Xvfb did not become ready; see xvfb.log")
            display = os.read(read_fd, 32).decode().strip()
            if not display.isdigit():
                raise RuntimeError("Xvfb did not return a display number; see xvfb.log")
            yield {**env, "DISPLAY": ":" + display}
        finally:
            os.close(read_fd)
            if write_fd is not None:
                os.close(write_fd)
            if server is not None:
                server.terminate()
                try:
                    server.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    server.kill()
                    server.wait()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--native", action="store_true", help="Also repeat pointer tests with native GL and capture reserved work tiles")
    parser.add_argument("--import-cache", type=Path, help="Reuse only .godot/imported after exact asset/metadata SHA256 comparison")
    parser.add_argument("--lock", type=Path, default=Path(os.environ.get("LL_ENGINE_LOCK", str(ROOT.parent / ".little-leaf-engine.lock"))))
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    if any(output.iterdir()):
        parser.error("Use a new empty output directory to preserve previous evidence")
    godot = os.environ.get("GODOT_BIN", "godot")
    # One core limits shared cloud renderer pressure, without a nonportable wrapper.
    if hasattr(os, "sched_getaffinity"):
        os.sched_setaffinity(0, {min(os.sched_getaffinity(0))})
    report = {"source_commit": subprocess.run(["git", "-C", str(ROOT), "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip(),
              "status": "running", "player_save_used": False, "native_render_verified": False,
              "browser_verified": False, "clean_import_verified": False, "records": []}
    source_files = [p for p in ROOT.rglob("*") if p.is_file() and not any(part in EXCLUDED for part in p.relative_to(ROOT).parts)]
    report["source_sha256"] = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(source_files)}

    def save():
        (output / "summary.json").write_text(json.dumps(report, indent=2) + "\n")

    with args.lock.open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        with tempfile.TemporaryDirectory(prefix="stove-work-saveguard-") as temporary:
            temporary = Path(temporary)
            project = temporary / "project"
            shutil.copytree(ROOT, project, ignore=IGNORE)
            controller = project / "scripts/cafe_web_save.gd"
            code = controller.read_text()
            old = 'const STAGING_FILE="/tmp/little_leaf_vault_staging.json"'
            assert old in code, "Review isolated native staging adaptation after source changes"
            code = code.replace(old, 'const STAGING_FILE="res://tests/synthetic_stage.json"')
            code = code.replace('DirAccess.make_dir_recursive_absolute("/tmp")', 'DirAccess.make_dir_recursive_absolute("res://tests")')
            controller.write_text(code)

            def profile(name):
                env = os.environ.copy()
                for key in ["HOME", "APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"]:
                    path = temporary / "profiles" / name / key.lower()
                    path.mkdir(parents=True, exist_ok=True)
                    env[key] = str(path)
                return env

            def run(name, extra, env, marker=None, native=False):
                start = time.monotonic()
                command = [godot, *([] if native else ["--headless"]), "--path", str(project),
                           "--audio-driver", "Dummy", "--rendering-method", "gl_compatibility", *extra]
                result = subprocess.run(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=300)
                text = result.stdout.decode("utf-8", errors="replace")
                (output / (name + ".log")).write_text(text)
                payloads = [json.loads(line[len(marker) + 1:]) for line in text.splitlines() if marker and line.startswith(marker + " ")]
                record = {"test": name, "exit_code": result.returncode, "seconds": round(time.monotonic() - start, 2),
                          "checks": sum(int(p.get("checks", 0)) for p in payloads),
                          "failures": [f for p in payloads for f in p.get("failures", [])],
                          "diagnostics": [line for line in text.splitlines() if "ERROR" in line or "WARNING" in line], "log": name + ".log"}
                report["records"].append(record)
                save()
                print(json.dumps(record), flush=True)
                if result.returncode or "SCRIPT ERROR:" in text or record["failures"]:
                    raise RuntimeError("Failed: " + name)
                if marker and (len(payloads) != 1 or record["checks"] <= 0):
                    raise RuntimeError("Missing or invalid result: " + name)

            flags = ["--", "--visual-qa", "--fresh-review", "--skip-intro"]
            try:
                if args.import_cache:
                    cache_project = args.import_cache.resolve()
                    def assets_manifest(base):
                        # Exact equality includes every source asset and its .import
                        # metadata, including files Godot marks importer=keep.
                        entries = {p.relative_to(base) for p in (base / "assets").rglob("*") if p.is_file()}
                        for metadata in base.rglob("*.import"):
                            relative = metadata.relative_to(base)
                            if any(part in EXCLUDED for part in relative.parts):
                                continue
                            entries.add(relative)
                            entries.add(Path(str(relative)[:-len(".import")]))
                        return {str(path): hashlib.sha256((base / path).read_bytes()).hexdigest() for path in sorted(entries)}
                    expected = assets_manifest(ROOT)
                    actual = assets_manifest(cache_project)
                    if not expected or expected != actual:
                        differences = [name for name in sorted(expected.keys() | actual.keys()) if expected.get(name) != actual.get(name)]
                        raise RuntimeError("Imported cache asset/metadata mismatch: " + ", ".join(differences))
                    imported = cache_project / ".godot/imported"
                    if not imported.is_dir() or not any(imported.iterdir()):
                        raise RuntimeError("Verified source has no imported asset cache")
                    cache_hashes = {str(path.relative_to(imported)): hashlib.sha256(path.read_bytes()).hexdigest()
                                    for path in sorted(imported.rglob("*")) if path.is_file()}
                    shutil.copytree(imported, project / ".godot/imported")
                    copied = project / ".godot/imported"
                    if any(hashlib.sha256((copied / name).read_bytes()).hexdigest() != digest for name, digest in cache_hashes.items()):
                        raise RuntimeError("Imported cache copy hash mismatch")
                    receipt = {"source_project": str(cache_project), "assets_and_import_metadata_verified": True,
                               "asset_file_count": len(expected), "source_asset_sha256": expected,
                               "copied_imported_sha256": cache_hashes, "copied_only": ".godot/imported",
                               "clean_import_verified": False}
                    (output / "import-cache-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
                    report["import_cache_receipt"] = "import-cache-receipt.json"
                    save()
                else:
                    run("import", ["--editor", "--import", "--quit"], profile("import"))
                    report["clean_import_verified"] = True
                run("model", ["--script", "res://tests/test_stove_work_reservation.gd", *flags], profile("model"), "STOVE_WORK_RESERVATION_RESULT")
                run("headless", ["--script", "res://tests/test_stove_reservation_ui.gd", *flags], profile("headless"), "STOVE_RESERVATION_UI_RESULT")
                if args.native:
                    captures = output / "captures"
                    captures.mkdir()
                    with native_display(profile("display"), temporary, output) as display:
                        native_env = {**profile("native"), "DISPLAY": display["DISPLAY"], "LL_STOVE_CAPTURE": str(captures)}
                        run("native", ["--script", "res://tests/test_stove_reservation_ui.gd", *flags], native_env, "STOVE_RESERVATION_UI_RESULT", True)
                        report["native_render_verified"] = True
                report["status"] = "passed"
            except BaseException as error:
                report["status"] = "failed"
                report["error"] = str(error)
                raise
            finally:
                report["total_checks"] = sum(record["checks"] for record in report["records"])
                save()
    print(json.dumps({key: report[key] for key in ["status", "total_checks", "native_render_verified"]}), flush=True)


if __name__ == "__main__":
    main()
