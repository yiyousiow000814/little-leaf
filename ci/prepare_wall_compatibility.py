"""Derive UI coordinates in disposable copies of exact, already-exported sources.

Does not launch a browser or change either export. Old and new exports must have
been built once by their own ci/build_web.py using the checksum-pinned tools.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from build_web import verify_installer_receipt

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests/fixtures/wall-compatibility"
CONTRACT = json.loads((FIXTURES / "contract.json").read_text())


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def validate_export(build, source, old=False):
    manifest = json.loads((build / "web/release-manifest.json").read_text())
    commit = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
    if subprocess.check_output(["git", "-C", str(source), "status", "--porcelain", "--untracked-files=no"], text=True).strip():
        raise RuntimeError("Compatibility inputs require clean tracked source")
    if manifest["source_commit"] != commit or (old and commit != CONTRACT["old_commit"]):
        raise RuntimeError("Export/source commit mismatch")
    if manifest.get("toolchain_verification") != "checksum-pinned-official-archives":
        raise RuntimeError("Compatibility CI requires the pinned official toolchain")
    if old:
        if manifest["production_sha256"].get("web/little_leaf_vault.js") != CONTRACT["old_vault_sha256"]:
            raise RuntimeError("Historical vault hash differs")
    elif not set(CONTRACT["candidate_required_sources"]).issubset(manifest["production_sha256"]):
        raise RuntimeError("Candidate export is missing required production sources")
    for name, expected in manifest["production_sha256"].items():
        if digest(source / name) != expected or digest(build / "project" / name) != expected:
            raise RuntimeError("Source/export production mismatch: " + name)
    for name, spec in manifest["files"].items():
        file = build / "web" / name
        if file.stat().st_size != spec["bytes"] or digest(file) != spec["sha256"]:
            raise RuntimeError("Export asset changed: " + name)
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ["old-source", "old-build", "new-build", "output"]:
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    for name, expected in CONTRACT["fixture_sha256"].items():
        if digest(FIXTURES / name) != expected:
            raise RuntimeError("Fixture changed: " + name)
    old = validate_export(args.old_build, args.old_source, old=True)
    new = validate_export(args.new_build, ROOT)
    if old["toolchain_receipt"] != new["toolchain_receipt"]:
        raise RuntimeError("Old and new exports must use the same pinned toolchain")
    godot = os.environ.get("GODOT_BIN", "godot")
    installed = verify_installer_receipt(
        Path(shutil.which(godot) or godot).resolve(), Path(os.environ["GODOT_TEMPLATE"]),
        Path(os.environ["GODOT_TOOLCHAIN_RECEIPT"]))
    if installed != new["toolchain_receipt"]:
        raise RuntimeError("Native layout preflight must use the exports' verified toolchain")
    receipt = {"browser_verified": False, "synthetic_only": True, "old_commit": old["source_commit"],
               "new_commit": new["source_commit"], "fixture_sha256": CONTRACT["fixture_sha256"], "layouts": {},
               "production_sha256": {"old": old["production_sha256"], "new": new["production_sha256"]},
               "export_manifest_sha256": {
                   "old": digest(args.old_build / "web/release-manifest.json"),
                   "new": digest(args.new_build / "web/release-manifest.json")}}
    for label, build in [("old", args.old_build), ("new", args.new_build)]:
        with tempfile.TemporaryDirectory(prefix="wall-layout-saveguard-") as temporary:
            temporary = Path(temporary)
            project = temporary / "project"
            shutil.copytree(build / "project", project)
            tests = project / "tests"
            tests.mkdir(exist_ok=True)
            shutil.copy2(ROOT / "tests/wall_compatibility_layout.gd", tests / "wall_compatibility_layout.gd")
            shutil.copy2(FIXTURES / "old-format1.json", tests / "wall-fixture-old.json")
            shutil.copy2(FIXTURES / "new-format2.json", tests / "wall-fixture-new.json")
            env = os.environ.copy()
            for key in ["HOME", "APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"]:
                folder = temporary / "saveguard-profile" / key.lower()
                folder.mkdir(parents=True)
                env[key] = str(folder)
            result_path = output / (label + "-layout.json")
            command = [godot, "--headless", "--fixed-fps", "60",
                       "--path", str(project), "--script", "res://tests/wall_compatibility_layout.gd", "--",
                       "--skip-intro", "--fixture=res://tests/wall-fixture-old.json", "--layout-output=" + str(result_path)]
            if label == "new":
                command.append("--new-layout")
            completed = subprocess.run(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
            text = completed.stdout.decode(errors="replace")
            (output / (label + "-layout.log")).write_text(text)
            if completed.returncode or "ERROR:" in text or not result_path.is_file():
                raise RuntimeError(label + " layout/codec preflight failed; inspect retained log")
            result = json.loads(result_path.read_text())
            if result["failures"] or result["checks"] < 1:
                raise RuntimeError(label + " layout/codec assertions failed")
            receipt["layouts"][label] = {"sha256": digest(result_path), "checks": result["checks"]}
            for name, expected in (old if label == "old" else new)["production_sha256"].items():
                if digest(project / name) != expected:
                    raise RuntimeError("Native preflight changed production source: " + name)
    receipt["status"] = "passed"
    (output / "preflight.json").write_text(json.dumps(receipt, indent=2) + "\n")


if __name__ == "__main__":
    main()
