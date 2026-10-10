"""Run available engine regression suites against a disposable candidate copy.

No browser or native window is launched. Only generated test profiles are used.
Requires Python 3 and Godot 4.6.3. Example:
  python3 tests/run_integration_candidate.py --output /tmp/little-leaf-qa
"""
import argparse
import hashlib
import json
import os
if os.name == "nt":
    import msvcrt
else:
    import fcntl
import re
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from project_layout import stage_project
SUITES = [
    ("test_staff_ground_ring", "STAFF_GROUND_RING_RESULT"),
    ("test_camera_geometry_lifetime", "CAMERA_GEOMETRY_LIFETIME_RESULT"),
    ("test_native_shape_retention", "NATIVE_SHAPE_RETENTION_RESULT"),
    ("test_retained_canvas_geometry", "RETAINED_CANVAS_RESULT"),
    ("test_prebaked_atlas", "PREBAKED_ATLAS_RESULT"),
    ("test_startup_readiness", "STARTUP_READINESS_RESULT"),
    ("test_cloud_recovery_ui", "CLOUD_RECOVERY_UI_RESULT"),
    ("test_update_notice", "UPDATE_NOTICE_RESULT"),
    ("test_direct_janitor_cleanup", "DIRECT_JANITOR_RESULT"),
    ("test_cloud_settings", "CLOUD_SETTINGS_RESULT"),
    ("test_fresh_service", "FRESH_SERVICE_RESULT"),
    ("test_interactive_tutorial", "INTERACTIVE_TUTORIAL_RESULT"),
    ("test_first_guest", "FIRST_GUEST_RESULT"),
    ("test_parking", "PARKING_RESULT"),
    ("test_parking_decor_ui", "PARKING_DECOR_UI_RESULT"),
    ("test_parking_render", "PARKING_RENDER_RESULT"),
    ("test_parking_service", "PARKING_SERVICE_RESULT"),
    ("test_parking_validation", "PARKING_VALIDATION_RESULT"),
    ("test_background_cache", "BACKGROUND_CACHE_RESULT"),

    ("test_shell_draw_cache", "SHELL_DRAW_CACHE_RESULT"),
    ("test_render_idle", "RENDER_IDLE_RESULT"),
    ("test_render_visibility", "RENDER_VISIBILITY_RESULT"),
    ("test_frame_rate_alignment", "FRAME_RATE_ALIGNMENT_RESULT"),
    ("test_web_performance", "WEB_PERFORMANCE_RESULT"),
    ("test_performance_simulation_cache", "PERFORMANCE_SIMULATION_CACHE_RESULT"),
    ("test_performance_shell_cache", "PERFORMANCE_SHELL_CACHE_RESULT"),
    ("test_legacy_3d_suppression", "LEGACY_3D_SUPPRESSION_RESULT"),
    ("test_decoration_build_refund", "DECORATION_BUILD_REFUND_RESULT"),
    ("test_decoration_refund", "DECORATION_REFUND_RESULT"),
    ("test_floor_approach_cache", "FLOOR_APPROACH_CACHE_RESULT"),
    ("test_floor_cleaning_approach", "FLOOR_CLEANING_APPROACH_RESULT"),
    ("test_floor_tool_depth", "FLOOR_TOOL_DEPTH_RESULT"),
    ("test_floor_work_side", "FLOOR_WORK_SIDE_RESULT"),
    ("test_crazygames_ack", "CRAZYGAMES_ACK_RESULT"),
    ("test_platform_gameplay_gate", "PLATFORM_GATE_RESULT"),
    ("test_crazygames_autosave", "CRAZYGAMES_AUTOSAVE_RESULT"),
    ("test_save_log", "SAVE_LOG_RESULT"),
    ("test_ambient_traffic_culling", "AMBIENT_TRAFFIC_CULLING_RESULT"),
    ("test_environment_scope", "ENVIRONMENT_SCOPE_RESULT"),
    ("test_environment", "ENVIRONMENT_RESULT"),
    ("test_bus_stop", "BUS_STOP_RESULT"),
    ("test_environment_camera_access", "ENVIRONMENT_CAMERA_ACCESS_RESULT"),

    ("test_fit_owned_cafe", "FIT_OWNED_CAFE_RESULT"),
    ("test_beverage_accessory_depth", "BEVERAGE_ACCESSORY_DEPTH_RESULT"),
    ("test_continuous_spout", "CONTINUOUS_SPOUT_RESULT"),
    ("test_decorate_camera", "DECORATE_CAMERA_RESULT"),
    ("test_camera_input_ownership", "CAMERA_INPUT_OWNERSHIP_RESULT"),
    ("test_square_neighborhood_camera", "SQUARE_NEIGHBORHOOD_CAMERA_RESULT"),
    ("test_overview_triangulation", "OVERVIEW_TRIANGULATION_RESULT"),

    ("test_ui_guard_performance", "UI_GUARD_PERFORMANCE_RESULT"),
    ("test_floor_claim_retry", "FLOOR_CLAIM_RETRY_RESULT"),
    ("test_shell_segment_codec", "SHELL_SEGMENT_CODEC_RESULT"),
    ("test_shell_segment_model", "SHELL_SEGMENT_MODEL_RESULT"),
    ("test_shell_segment_ui", "SHELL_SEGMENT_UI_RESULT"),
    ("test_economy_revision", "ECONOMY_REVISION_RESULT"),
    ("test_intro_lifecycle_headless", "INTRO_LIFECYCLE_RESULT"),
    ("test_intro_cli_bypass", "INTRO_CLI_RESULT"),
    ("test_hud_icon_scale", "HUD_ICON_SCALE_RESULT"),
    ("test_hud_layout", "HUD_LAYOUT_RESULT"),
    ("test_pause_only", "PAUSE_ONLY_RESULT"),
    ("test_toolbar_help", "TOOLBAR_HELP_RESULT"),
    ("test_update_notes", "UPDATE_NOTES_RESULT"),
    ("test_mobile_toolbar", "MOBILE_TOOLBAR_RESULT"),
    ("test_wallet_alignment", "WALLET_ALIGNMENT_RESULT"),
    ("test_cancel_icon", "CANCEL_ICON_RESULT"),
    ("test_build_tiles_ui", "BUILD_TILES_UI_RESULT"),
    ("test_build_actor_positions", "BUILD_ACTOR_POSITIONS_RESULT"),
    ("test_existing_wall_actions", "EXISTING_WALL_ACTIONS_RESULT"),
    ("test_build_wall_ui", "BUILD_WALL_UI_RESULT"),
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
    ("test_single_guest_patience", "SINGLE_GUEST_PATIENCE_RESULT"),
    ("test_sink_basin_visual", "SINK_BASIN_VISUAL_RESULT"),
    ("test_sink_wash_action", "SINK_WASH_ACTION_RESULT"),
    ("test_floor_availability", "FLOOR_AVAILABILITY_RESULT"),
    ("test_furniture_worker_egress", "FURNITURE_WORKER_EGRESS"),
    ("test_staff_relocation_service", "STAFF_RELOCATION_SERVICE_RESULT"),
    ("test_autosave_feedback", "AUTOSAVE_FEEDBACK_RESULT"),
    ("test_autosave_feedback_adversarial", "AUTOSAVE_ADVERSARIAL_RESULT"),
    ("test_autosave_feedback_ui", "AUTOSAVE_UI_RESULT"),
    ("test_inbox_save_cache", "INBOX_SAVE_CACHE_RESULT"),
    ("test_compensation_inbox", "COMPENSATION_INBOX_RESULT"),
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
    ("test_chair_ground_contact", "CHAIR_GROUND_CONTACT_RESULT"),
    ("test_simple_kitchen", "SIMPLE_KITCHEN_TESTS"),
    ("test_pan_handle_workface", "PAN_HANDLE_WORKFACE_TESTS"),
    ("test_chef_hat", "CHEF_HAT_TESTS"),
    ("test_character_bubble", "CHARACTER_BUBBLE_RESULT"),
    ("test_arm_occlusion", "ARM_OCCLUSION_RESULT"),
    ("test_dining_pose", "DINING_POSE_RESULT"),
    ("test_seated_proportions", "SEATED_PROPORTIONS_RESULT"),
    ("test_dining_service_plane", "DINING_SERVICE_RESULT"),
    ("test_dining_placement", "DINING_PLACEMENT_RESULT"),
    ("test_dining_docking", "DINING_DOCKING_RESULT"),
    ("test_dining_occlusion", "DINING_OCCLUSION_RESULT"),
    ("test_bubble_symbol_clarity", "BUBBLE_SYMBOL_CLARITY_RESULT"),
    ("test_art_raster_strokes", "ART_RASTER_STROKE_TESTS"),
    ("test_customer_litter", "@json"),
    ("test_litter_visibility", "@json"),
    ("test_street_pedestrians", "STREET_PEDESTRIANS_RESULT"),
    ("test_street_endpoints", "STREET_ENDPOINTS_RESULT"),
    ("test_street_service_save", "STREET_SERVICE_SAVE_RESULT"),
    ("test_outside_queue", "OUTSIDE_QUEUE_RESULT"),
]
EXCLUDE = shutil.ignore_patterns(
    ".git", ".godot", "qa-project", "evidence", "__pycache__", "build", "builds",
    "export", "exports", "export_templates", "dist", "*.log", "*.zip")
# These paused, input/layout suites assert frame order rather than wall time.
# All lifecycle, save, startup, service and FPS suites retain real-time pacing.
UNPACED_UI = {"test_toolbar_help", "test_environment_camera_access"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--only", nargs="+", choices=[name for name, _ in SUITES] + ["staff-start"])
    parser.add_argument("--unpaced-ui", action="store_true",
                        help="Use fixed 60 Hz simulation only for two reviewed paused UI suites")
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
    if qa.is_symlink():
        raise RuntimeError("Disposable fixture root cannot be a symlink")
    godot = os.environ.get("GODOT_BIN", "godot")
    report = {"mode": "headless engine only", "source_commit": subprocess.run(["git", "-C", str(ROOT), "rev-parse", "HEAD"],
                    capture_output=True, text=True).stdout.strip() or "source archive",
              "browser_verified": False, "native_render_verified": False,
              "player_save_used": False, "records": [], "status": "running"}
    source_files = [p for p in ROOT.rglob("*") if p.is_file() and
                    not any(part in {".git", ".godot", "qa-project", "__pycache__"}
                            for part in p.relative_to(ROOT).parts)]
    report["source_sha256"] = {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                               for p in sorted(source_files)}

    def save():
        (output / "summary.json").write_text(json.dumps(report, indent=2) + "\n")

    with args.lock.open("a+b") as lock:
        if os.name == "nt":
            lock.seek(0)
            lock.write(b"\0"); lock.flush(); lock.seek(0)
            msvcrt.locking(lock.fileno(), msvcrt.LK_LOCK, 1)
        else:
            fcntl.flock(lock, fcntl.LOCK_EX)
        with tempfile.TemporaryDirectory(prefix="integration-saveguard-", dir=qa,
                                             ignore_cleanup_errors=(os.name == "nt")) as temp:
            temp = Path(temp).resolve()
            if not temp.is_relative_to(qa.resolve()):
                raise RuntimeError("Disposable fixture escaped its reviewed root")
            project = temp / "project"
            stage_project(ROOT, project, tests=True, ignore=EXCLUDE)
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
                    directory = temp / "profiles" / name / ("windows-data" if os.name == "nt" else key.lower())
                    directory.mkdir(parents=True, exist_ok=True)
                    env[key] = directory.as_posix()
                return env

            def run(name, arguments, env, marker=None):
                start = time.monotonic()
                pacing = ["--fixed-fps", "60"] if args.unpaced_ui and name in UNPACED_UI else []
                command = [godot, "--headless", "--audio-driver", "Dummy", "--path", str(project), *pacing, *arguments]
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
                if pacing:
                    record["simulation_fixed_fps"] = 60
                # Bind derived UI receipts to the exact aggregate report used
                # by the export manifest, rather than trusting a loose JSON file.
                result_file = env.get("LL_UI_RESULT")
                if result_file and Path(result_file).is_file():
                    record["result_sha256"] = hashlib.sha256(Path(result_file).read_bytes()).hexdigest()
                report["records"].append(record)
                save()
                print(json.dumps(record), flush=True)
                if completed.returncode or "SCRIPT ERROR:" in text or ("Nondegenerate overview contour failed stable triangulation" in text or "Authored overview contour has no source triangles" in text) or record["failures"]:
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
                    if script != "test_interactive_tutorial":
                        flags.append("--skip-tutorial")
                    if script not in {"test_intro_lifecycle_headless", "test_startup_readiness"}:
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
                save_dir = Path(env["XDG_DATA_HOME"]) / ("Godot/app_userdata/Little Leaf Cafe" if os.name == "nt" else "godot/app_userdata/Little Leaf Cafe")
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
                    flags = ["--visual-qa", "--skip-intro", "--skip-tutorial"]
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
    report["disposable_fixture_retained"] = temp.exists()
    if temp.exists():
        report["disposable_fixture_path"] = str(temp)
        report["cleanup_note"] = "Windows may retain task-only fixture files while filesystem handles close; no process termination attempted"
    save()
    print(json.dumps({k: report[k] for k in ["status", "total_checks", "test_processes"]}), flush=True)


if __name__ == "__main__":
    main()
