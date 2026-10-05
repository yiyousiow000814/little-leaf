"""Run available engine regression suites against a disposable candidate copy.

No browser or native window is launched. Only generated test profiles are used.
Requires Python 3 and Godot 4.6.3. Example:
  python3 tests/run_integration_candidate.py --output /tmp/little-leaf-qa
"""
import argparse
import fcntl
import hashlib
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
SUITES = [
    ("test_economy_revision", "ECONOMY_REVISION_RESULT"),
    ("test_intro_lifecycle_headless", "INTRO_LIFECYCLE_RESULT"),
    ("test_intro_cli_bypass", "INTRO_CLI_RESULT"),
    ("test_hud_icon_scale", "HUD_ICON_SCALE_RESULT"),
    ("test_hud_layout", "HUD_LAYOUT_RESULT"),
    ("test_toolbar_help", "TOOLBAR_HELP_RESULT"),
    ("test_mobile_toolbar", "MOBILE_TOOLBAR_RESULT"),
    ("test_wallet_alignment", "WALLET_ALIGNMENT_RESULT"),
    ("test_cancel_icon", "CANCEL_ICON_RESULT"),
    ("test_build_tiles_ui", "BUILD_TILES_UI_RESULT"),
    ("test_staff_header_done", "STAFF_HEADER_DONE_RESULT"),
    ("test_startup_retry", "STARTUP_RETRY_RESULT"),
    ("test_no_bottom_notifications", "NO_BOTTOM_NOTIFICATIONS_RESULT"),
    ("test_starter_geometry", "STARTER_GEOMETRY_RESULT"),
    ("test_starter_door_grid", "STARTER_DOOR_GRID_RESULT"),
    ("test_opening_jamb_occlusion", "OPENING_JAMB_RESULT"),
    ("test_expansion_visibility", "EXPANSION_VISIBILITY_RESULT"),
    ("test_expansion_ring_prices", "EXPANSION_RING_PRICES_RESULT"),
    ("test_expansion_tree_visibility", "EXPANSION_TREE_RESULT"),
    ("test_role_boundaries", "ROLE_BOUNDARIES_RESULT"),
    ("test_role_release", "ROLE_RELEASE_RESULT"),
    ("test_dishwashing_queue", "DISHWASHING_QUEUE_RESULT"),
    ("test_sink_basin_visual", "SINK_BASIN_VISUAL_RESULT"),
    ("test_sink_wash_action", "SINK_WASH_ACTION_RESULT"),
    ("test_floor_availability", "FLOOR_AVAILABILITY_RESULT"),
    ("test_furniture_worker_egress", "FURNITURE_WORKER_EGRESS"),
    ("test_staff_relocation_service", "STAFF_RELOCATION_SERVICE_RESULT"),
    ("test_autosave_feedback", "AUTOSAVE_FEEDBACK_RESULT"),
    ("test_autosave_feedback_adversarial", "AUTOSAVE_ADVERSARIAL_RESULT"),
    ("test_autosave_feedback_ui", "AUTOSAVE_UI_RESULT"),
    ("test_stove_optional", "STOVE_OPTIONAL_RESULT"),
    ("test_stove_work_reservation", "STOVE_WORK_RESERVATION_RESULT"),
    ("test_stove_reservation_ui", "STOVE_RESERVATION_UI_RESULT"),
    ("test_stove_pause_service", "STOVE_PAUSE_SERVICE_RESULT"),
    ("test_workface_ground_guidance", "WORKFACE_GROUND_GUIDANCE_RESULT"),
    ("test_workface_single_tint", "WORKFACE_SINGLE_TINT_RESULT"),
    ("test_departing_route_edit", "DEPARTING_ROUTE_RESULT"),
    ("test_departing_route_service", "DEPARTING_ROUTE_SERVICE_RESULT"),
    ("test_register_edge", "REGISTER_EDGE_RESULT"),
    ("test_chef_fire", "CHEF_FIRE_TESTS"),
    ("test_food_contact", "FOOD_CONTACT_TESTS"),
    ("test_simple_kitchen", "SIMPLE_KITCHEN_TESTS"),
    ("test_pan_handle_workface", "PAN_HANDLE_WORKFACE_TESTS"),
    ("test_chef_hat", "CHEF_HAT_TESTS"),
    ("test_character_bubble", "CHARACTER_BUBBLE_RESULT"),
    ("test_arm_occlusion", "ARM_OCCLUSION_RESULT"),
    ("test_bubble_symbol_clarity", "BUBBLE_SYMBOL_CLARITY_RESULT"),
    ("test_art_raster_strokes", "ART_RASTER_STROKE_TESTS"),
    ("test_customer_litter", "@json"),
    ("test_litter_visibility", "@json"),
]
EXCLUDE = shutil.ignore_patterns(
    ".git", ".godot", "qa-project", "evidence", "__pycache__", "build", "builds",
    "export", "exports", "export_templates", "dist", "*.log", "*.zip")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--only", nargs="+", choices=[name for name, _ in SUITES] + ["staff-start"])
    parser.add_argument("--lock", type=Path, default=Path(os.environ.get(
        "LL_ENGINE_LOCK", str(ROOT.parent / ".little-leaf-engine.lock"))))
    args = parser.parse_args()
    available = [name for name, _ in SUITES if (ROOT / "tests" / (name + ".gd")).is_file()]
    if (ROOT / "tests/test_staff_start.gd").is_file():
        available.append("staff-start")
    selected = set(args.only or available)
    missing = selected - set(available)
    if missing:
        parser.error("Missing test files: " + ", ".join(sorted(missing)))
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    if (output / "summary.json").exists():
        raise SystemExit("Use a new output directory to preserve prior evidence")
    qa = ROOT / "qa-project"
    qa.mkdir(exist_ok=True)
    godot = os.environ.get("GODOT_BIN", "godot")
    report = {"mode": "headless engine only", "source_commit": subprocess.run(["git", "-C", str(ROOT), "rev-parse", "HEAD"],
                    capture_output=True, text=True).stdout.strip() or "source archive",
              "browser_verified": False, "native_render_verified": False,
              "player_save_used": False, "records": [], "status": "running"}
    source_files = [p for p in ROOT.rglob("*") if p.is_file() and
                    not any(part in {".git", ".godot", "qa-project", "__pycache__"}
                            for part in p.relative_to(ROOT).parts)]
    report["source_sha256"] = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                               for p in sorted(source_files)}

    def save():
        (output / "summary.json").write_text(json.dumps(report, indent=2) + "\n")

    with args.lock.open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        with tempfile.TemporaryDirectory(prefix="integration-saveguard-", dir=qa) as temp:
            temp = Path(temp).resolve()
            project = temp / "project"
            shutil.copytree(ROOT, project, ignore=EXCLUDE)
            # The Web staging file is MEMFS in production. Keep its native analogue
            # entirely inside this disposable copy, without changing delivered source.
            controller = project / "scripts/cafe_web_save.gd"
            code = controller.read_text()
            old = 'const STAGING_FILE="/tmp/little_leaf_vault_staging.json"'
            assert old in code, "Review native staging adaptation after source changes"
            code = code.replace(old, 'const STAGING_FILE="res://tests/synthetic_stage.json"')
            code = code.replace('DirAccess.make_dir_recursive_absolute("/tmp")',
                                'DirAccess.make_dir_recursive_absolute("res://tests")')
            controller.write_text(code)

            def env_for(name):
                env = os.environ.copy()
                for key in ["HOME", "APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"]:
                    directory = temp / "profiles" / name / key.lower()
                    directory.mkdir(parents=True, exist_ok=True)
                    env[key] = str(directory)
                return env

            def run(name, arguments, env, marker=None):
                start = time.monotonic()
                command = [godot, "--headless", "--path", str(project), *arguments]
                completed = subprocess.run(command, env=env, stdout=subprocess.PIPE,
                                           stderr=subprocess.STDOUT, timeout=300)
                text = completed.stdout.decode("utf-8", errors="replace")
                (output / (name + ".log")).write_text(text)
                payloads = []
                for line in text.splitlines():
                    if marker == "@json":
                        if not line.startswith("{"):
                            continue
                        body = line
                    else:
                        if not marker or not line.startswith(marker + " "):
                            continue
                        body = line[len(marker) + 1:]
                    if body.startswith("{"):
                        payloads.append(json.loads(body))
                    else:
                        match = re.fullmatch(r"checks=(\d+) failures=(\d+)", body)
                        if not match:
                            raise RuntimeError("Unrecognized result: " + line)
                        payloads.append({"checks": int(match[1]), "failures":
                                         [] if int(match[2]) == 0 else ["fixture failures=" + match[2]]})
                record = {"test": name, "exit_code": completed.returncode,
                          "seconds": round(time.monotonic() - start, 2),
                          "checks": sum(int(p.get("checks", 0)) for p in payloads),
                          "failures": [f for p in payloads for f in p.get("failures", [])],
                          "diagnostics": [l for l in text.splitlines() if "WARNING" in l or "ERROR" in l],
                          "log": name + ".log"}
                report["records"].append(record)
                save()
                print(json.dumps(record), flush=True)
                if completed.returncode or "SCRIPT ERROR:" in text or record["failures"]:
                    raise RuntimeError("Failed: " + name)
                if marker and (len(payloads) != 1 or record["checks"] <= 0):
                    raise RuntimeError("Missing/duplicate/empty result: " + name)

            try:
                run("import", ["--editor", "--import", "--quit"], env_for("import"))
                for script, marker in SUITES:
                    if script not in selected:
                        continue
                    env = env_for("expansion-saveguard-geometry-saveguard-" + script)
                    env["LL_UI_RESULT"] = str(output / (script + "-result.json"))
                    env["LL_LITTER_EVIDENCE"] = str(output / (script + "-litter.json"))
                    flags = ["--visual-qa", "--fresh-review"]
                    if script != "test_intro_lifecycle_headless":
                        flags.append("--skip-intro")
                    # These controller fixtures never create the game scene. The
                    # adversarial native harness uses a zero-I/O model and must
                    # exercise _save rather than suppress it via --visual-qa.
                    if script in {"test_autosave_feedback", "test_autosave_feedback_adversarial"}:
                        flags = ["--skip-intro"]
                    if script == "test_intro_lifecycle_headless":
                        env["LL_INTRO_RESULT"] = str(output / "intro-lifecycle.json")
                    run(script, ["--script", "res://tests/" + script + ".gd", "--", *flags], env, marker)

                # These five starts intentionally share one generated profile so that
                # the native entry point loads the exact preceding synthetic saves.
                env = env_for("staff-start-generated-profile")
                save_dir = Path(env["XDG_DATA_HOME"]) / "godot/app_userdata/Little Leaf Cafe"
                save_file = save_dir / "little_leaf_cafe_layout_motion_v15.json"
                for case in (["empty-profile", "fresh", "saved-load", "standalone-load", "bad-load"]
                             if "staff-start" in selected else []):
                    env["LL_START_CASE"] = case
                    env["LL_START_RESULT"] = str(output / ("staff-start-" + case + ".json"))
                    if case == "empty-profile":
                        assert not save_file.exists()
                    elif case == "saved-load":
                        shutil.copy2(save_dir / "staff-start-roundtrip.json", save_file)
                    elif case == "standalone-load":
                        shutil.copy2(save_dir / "staff-start-standalone.json", save_file)
                    elif case == "bad-load":
                        save_file.write_text("not a valid cafe")
                    flags = ["--visual-qa", "--skip-intro"]
                    if case == "fresh":
                        flags.append("--fresh-review")
                    run("staff-start-" + case, ["--script", "res://tests/test_staff_start.gd", "--", *flags],
                        env, "STAFF_START_RESULT")
                report["status"] = "passed"
            except BaseException:
                report["status"] = "failed"
                raise
            finally:
                report["total_checks"] = sum(r["checks"] for r in report["records"])
                report["test_processes"] = len(report["records"]) - 1
                save()
    print(json.dumps({k: report[k] for k in ["status", "total_checks", "test_processes"]}), flush=True)


if __name__ == "__main__":
    main()
