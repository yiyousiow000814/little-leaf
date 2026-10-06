"""Export the separate CrazyGames variant after the existing full Web gate.

Portable local smoke: pass --local-tools and --validated-web-build from
ci/build_web.py. CI keeps every existing integration/browser gate mandatory.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

from build_web import ROOT, LOCK, sha256


def validate_web_gate(build, commit, tree, local_tools=False):
    manifest = json.loads((build / "web/release-manifest.json").read_text())
    if (manifest.get("source_commit") != commit or manifest.get("source_tree") != tree
            or manifest.get("packed_smoke") != "passed"
            or manifest.get("engine_checks", 0) <= 0 or manifest.get("test_processes", 0) <= 0):
        raise RuntimeError("Existing complete Web export gate must pass for this exact source")
    if not local_tools and manifest.get("toolchain_verification") != "checksum-pinned-official-archives":
        raise RuntimeError("CI requires the existing checksum-pinned official toolchain gate")
    if not manifest.get("production_sha256"):
        raise RuntimeError("Existing production source hashes are required")
    for name, digest in manifest["production_sha256"].items():
        if sha256(ROOT / name) != digest or sha256(build / "project" / name) != digest:
            raise RuntimeError("Source changed after existing Web gate: " + name)
    html = (build / "web/index.html").read_text(encoding="utf-8")
    if "https://sdk.crazygames.com/crazygames-sdk-v3.js" in html:
        raise RuntimeError("Normal Web export must not load the CrazyGames SDK")
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--validated-web-build", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--local-tools", action="store_true")
    args = parser.parse_args()
    if args.local_tools and os.environ.get("GITHUB_ACTIONS") == "true":
        raise RuntimeError("CI cannot use the local smoke exception")
    def git(*args):
        return subprocess.check_output(["git", "-C", str(ROOT), *args], text=True).strip()
    if git("status", "--porcelain", "--untracked-files=no"):
        raise RuntimeError("Commit/review tracked changes before export")
    commit, tree = git("rev-parse", "HEAD"), git("rev-parse", "HEAD^{tree}")
    legacy = validate_web_gate(args.validated_web_build.resolve(), commit, tree, args.local_tools)
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    project, web, evidence = [out / name for name in ["project", "web", "evidence"]]
    shutil.copytree(args.validated_web_build / "project", project,
                    ignore=shutil.ignore_patterns(".godot"))
    web.mkdir(); evidence.mkdir()
    (project / "tests").mkdir(exist_ok=True)
    for name in ["test_crazygames_ack.gd", "test_platform_gameplay_gate.gd", "test_crazygames_autosave.gd"]:
        shutil.copy2(ROOT / "tests" / name, project / "tests" / name)
    env = os.environ.copy()
    for key in ["APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"]:
        folder = out / "synthetic-profile"
        folder.mkdir(exist_ok=True)
        env[key] = folder.as_posix()
    godot = os.environ.get("GODOT_BIN", "godot")
    version = subprocess.check_output([godot, "--version"], env=env, text=True).strip()
    if not version.startswith(LOCK["godot"]["runtime_prefix"]):
        raise RuntimeError("Expected the pinned official Godot runtime")
    if sha256(Path(os.environ["GODOT_TEMPLATE"])) != legacy["web_template_sha256"]:
        raise RuntimeError("Web template changed after existing gate")
    stages = []
    commands = [
        ("sdk-contract", ["node", "tests/crazygames_storage.js"], ROOT),
        ("import", [godot, "--headless", "--path", str(project), "--editor", "--import", "--quit"], ROOT),
        ("ack", [godot, "--headless", "--path", str(project), "--script", "res://tests/test_crazygames_ack.gd"], ROOT),
        ("playable-gate", [godot, "--headless", "--path", str(project), "--script", "res://tests/test_platform_gameplay_gate.gd"], ROOT),
        ("dirty-cadence", [godot, "--headless", "--path", str(project), "--script", "res://tests/test_crazygames_autosave.gd"], ROOT),
        ("music", [godot, "--headless", "--path", str(project), "--export-pack", "CrazyGamesMusic", str(web / "music.pck")], ROOT),
        ("export", [godot, "--headless", "--path", str(project), "--export-release", "CrazyGames", str(web / "index.html")], ROOT),
        ("packed-smoke", [godot, "--headless", "--main-pack", str(web / "index.pck"), "--", "--self-check", "--fresh-review", "--visual-qa", "--skip-intro"], ROOT),
    ]
    for name, command, cwd in commands:
        result = subprocess.run(command, cwd=cwd, env=env, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=300)
        text = result.stdout.decode("utf-8", errors="replace")
        (evidence / (name + ".log")).write_text(text, encoding="utf-8")
        if result.returncode or "ERROR:" in text or "SCRIPT ERROR:" in text:
            raise RuntimeError("CrazyGames " + name + " failed; inspect evidence")
        if name == "packed-smoke" and "SCENE_READY furniture=" not in text:
            raise RuntimeError("CrazyGames packed game did not reach scene ready")
        stages.append({"stage": name, "exit_code": result.returncode})
    html = (web / "index.html").read_text(encoding="utf-8")
    if "https://sdk.crazygames.com/crazygames-sdk-v3.js" not in html or "crazygames-data" not in html:
        raise RuntimeError("CrazyGames shell/storage adapter missing")
    for name in ["index.pck", "music.pck"]:
        if (web / name).read_bytes()[:4] != b"GDPC":
            raise RuntimeError("Invalid pack header: " + name)
    if (web / "index.wasm").read_bytes()[:4] != b"\0asm":
        raise RuntimeError("Invalid WebAssembly header")
    shutil.copy2(ROOT / "docs/third-party/CRAZYGAMES-SDK-NOTICE.md", web / "CRAZYGAMES-SDK-NOTICE.md")
    shutil.copy2(ROOT / "docs/third-party/GODOT-AA-LICENSE.txt", web / "GODOT-AA-LICENSE.txt")
    validate_web_gate(args.validated_web_build.resolve(), commit, tree, args.local_tools)
    manifest = {"source_commit": commit, "source_tree": tree, "godot": version,
                "platform": "crazygames", "existing_web_gate_checks": legacy["engine_checks"],
                "toolchain_verification": legacy["toolchain_verification"], "stages": stages,
                "browser_runtime": "requires separate browser/hosted validation",
                "files": {p.name: {"bytes": p.stat().st_size, "sha256": sha256(p)}
                          for p in sorted(web.iterdir()) if p.is_file()}}
    (web / "crazygames-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    (evidence / "export-report.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print("Built separate CrazyGames export after unchanged complete Web gate: " + commit)


if __name__ == "__main__":
    main()
