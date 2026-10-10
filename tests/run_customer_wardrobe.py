"""Run focused visit clothing model tests in a disposable minimal Godot project.

Invoke after the parent schedules engine time. Never import the production project.
"""
import argparse
import hashlib
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
FILES = ["scripts/customer_wardrobe_catalog.gd", "scripts/customer_wardrobe.gd",
         "scripts/customer_wardrobe_record.gd", "tests/test_customer_wardrobe.gd"]

def dependency_files(seeds):
    found, pending = set(), list(seeds)
    while pending:
        name = pending.pop()
        if name in found:
            continue
        path = (ROOT / name).resolve()
        if not path.is_relative_to(ROOT) or not path.is_file():
            raise ValueError("Missing or escaping fixture dependency: " + name)
        found.add(name)
        if path.suffix == ".gd":
            for dependency in re.findall(r'"res://([^"\n]+)"', path.read_text(encoding="utf-8")):
                if (ROOT / dependency).is_file():
                    pending.append(dependency)
    return sorted(found)

SUITES = {
    "wardrobe": (FILES, "tests/test_customer_wardrobe.gd", "CUSTOMER_WARDROBE_RESULT "),
    "adapter": (FILES[:3] + ["scripts/character_appearance_contract.gd", "scripts/customer_appearance_adapter.gd", "tests/test_customer_appearance_adapter.gd", "tests/fixtures/customer_appearance_compatibility.json"], "tests/test_customer_appearance_adapter.gd", "CUSTOMER_APPEARANCE_ADAPTER_RESULT "),
    "visit_outfits": (dependency_files(["tests/test_customer_visit_outfits.gd"]), "tests/test_customer_visit_outfits.gd", "CUSTOMER_VISIT_OUTFITS_RESULT "),
}


def prepare(project, files=None):
    project.mkdir(parents=True, exist_ok=True)
    (project / "project.godot").write_text('[application]\nconfig/name="Synthetic wardrobe contracts"\n', encoding="utf-8")
    for name in FILES if files is None else files:
        target = project / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / name, target)
    env = os.environ.copy()
    for key in ["HOME", "APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"]:
        env[key] = str((project / "synthetic-profile").resolve()).replace("\\", "/")
    (project / "synthetic-profile").mkdir()
    return env


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, help="Explicit installed engine executable")
    parser.add_argument("--output", required=True, type=Path, help="New evidence directory outside source")
    parser.add_argument("--suite", choices=SUITES, default="wardrobe", help="Run only the selected pure data suite")
    args = parser.parse_args()
    output = args.output.resolve()
    if output == ROOT or ROOT in output.parents:
        parser.error("evidence must be outside the source checkout")
    if output.exists():
        parser.error("use a new evidence directory; existing evidence is never overwritten")
    engine = shutil.which(args.godot)
    if engine is None:
        parser.error("Godot executable is unavailable")
    output.mkdir(parents=True)
    files, script, marker = SUITES[args.suite]
    hashes = {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in files}
    report = {"source_sha256": hashes, "player_saves_used": False, "production_project_imported": False,
              "engine": engine, "status": "failed", "runtime_acceptance": "pure_data_only", "suite": args.suite}
    with tempfile.TemporaryDirectory(prefix="customer-wardrobe-") as scratch:
        project = Path(scratch) / "project"
        env = prepare(project, files)
        command = [engine, "--headless", "--audio-driver", "Dummy", "--quit-after", "120", "--path", str(project),
                   "--script", "res://" + script]
        report["command"] = command
        try:
            result = subprocess.run(command, env=env, capture_output=True, timeout=60)
            log = (result.stdout + result.stderr).decode("utf-8", errors="replace")
            (output / "engine.txt").write_text(log, encoding="utf-8")
            report["exit_code"] = result.returncode
            report["script_errors"] = log.count("SCRIPT ERROR")
            results = [line.split(marker, 1)[1] for line in log.splitlines() if line.startswith(marker)]
            if len(results) == 1:
                report["result"] = json.loads(results[0])
                if result.returncode == 0 and report["script_errors"] == 0 and report["result"]["checks"] > 0 and not report["result"]["failures"]:
                    report["status"] = "passed"
        except subprocess.TimeoutExpired as error:
            report["error"] = type(error).__name__
            log = ((error.stdout or b"") + (error.stderr or b"")).decode("utf-8", errors="replace")
            (output / "engine.txt").write_text(log, encoding="utf-8")
        except (OSError, ValueError) as error:
            report["error"] = type(error).__name__
    report["disposable_project_removed"] = True
    (output / "summary.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    result = report.get("result", {})
    print(json.dumps({"status": report["status"], "checks": result.get("checks"),
                      "failures": len(result.get("failures", [])), "script_errors": report.get("script_errors"),
                      "error": report.get("error"), "evidence": str(output)}, indent=2))
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
