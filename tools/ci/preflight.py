"""Run the existing fast source/contract checks once, locally or in CI.

--release selects the existing publication contracts instead of all tooling and
Node fixtures. Neither mode builds, downloads release artifacts, or publishes.
"""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
RELEASE_TESTS = (
    "test_common_tag", "test_reuse_main_ci", "test_release",
    "test_firebase_release_event", "test_stage_released_firebase",
    "test_firebase_hosting_deploy",
)
NODE_CHECKS = (
    "tests/persistence/crazygames_storage.js",
    "tests/persistence/legacy_byte_storage.js",
    "tests/presentation/boot_presentation.js",
    "tests/presentation/fresh_tutorial_browser_test.js",
    "--check tests/presentation/fresh_tutorial_browser.js",
    "tests/persistence/save_log_observers.js",
    "tests/persistence/save_log_privacy.js",
    "tests/rendering/web_performance_lifecycle.js",
    "tests/persistence/connection_recovery.js",
    "tests/persistence/compensation_inbox_storage.js",
    "tests/rendering/wall_compatibility_parallel_test.js",
    "tests/rendering/wall_compatibility_helpers_test.js",
    "tests/rendering/wall_compatibility_ocr_test.js",
    "--check tests/rendering/wall_compatibility_browser.js",
    "--check tests/persistence/save_log_browser.js",
    "--check tests/persistence/connection_recovery_browser.js",
    "--check platform/firebase/fullflow.test.mjs",
)


def commands(release=False, tag=""):
    yield "release metadata", [sys.executable, "tools/release/release_metadata.py", "--tag", tag]
    yield "atlas provenance", [sys.executable, "tools/qualification/verify_prebaked_atlases.py"]
    tests = (["tests.tooling." + name for name in RELEASE_TESTS] if release else
             ["discover", "-s", "tests/tooling", "-t", ".", "-p", "test_*.py"])
    yield "release contracts" if release else "tooling contracts", [sys.executable, "-m", "unittest", *tests, "-v"]
    if not release:
        for check in NODE_CHECKS:
            yield check, ["node", *check.split()]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release", action="store_true", help="Run focused release contracts, not the complete fast guard")
    args = parser.parse_args(argv)
    started = time.monotonic()
    for name, command in commands(args.release, os.environ.get("RELEASE_TAG", "")):
        print("Preflight: " + name, flush=True)
        result = subprocess.run(command, cwd=ROOT)
        if result.returncode:
            raise SystemExit(f"Preflight failed: {name} (exit {result.returncode})")
    print(f"Preflight passed in {time.monotonic() - started:.2f}s. No build or release qualification.")


if __name__ == "__main__":
    main()
