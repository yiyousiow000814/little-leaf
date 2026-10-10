"""Export the separate CrazyGames variant after the existing full Web gate.

Portable local smoke: pass --local-tools and --validated-web-build from
tools/build_web.py. CI keeps every existing integration/browser gate mandatory.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

from build_web import ROOT, LOCK
from optimize_web_present import optimize_presentation
from artifacts import sha256
import artifacts


PRODUCTION_KEYS = {"profile": "little-leaf.cg.profile.v1",
                   "preferences": "little-leaf.cg.preferences.v1"}
PREVIEW_KEYS = {"profile": "little-leaf.cg.developer-preview.profile.v1",
                "preferences": "little-leaf.cg.developer-preview.preferences.v1"}
TITLE_MARKER = "<title>$GODOT_PROJECT_NAME</title>"
PREVIEW_TITLE_SUFFIX = " · Developer preview</title>"
LOADING_MARKER = '\t\t\t\t<progress id="status-progress"'
# Inside the existing loading layer: its normal dismissal leaves no game overlay.
PREVIEW_NOTICE = '''<p id="developer-preview-notice" style="margin:0 0 12px;font-size:12px;line-height:1.4;pointer-events:none">Developer preview · Separate test progress</p>'''
PREVIEW_README = """Little Leaf: CrazyGames developer preview

Separate test progress only. This export uses these SDK Data keys:
- little-leaf.cg.developer-preview.profile.v1
- little-leaf.cg.developer-preview.preferences.v1

Production progress is not read, imported, reset, or written by this adapter.
Test progress is reused on reload. SDK account scope and quota are shared;
key separation does not create another backend or confirm remote cloud sync.
See crazygames-manifest.json for source identity and transformed input hashes.
"""


def key_declaration(keys):
    return "  const KEY = '%s', PREFS = '%s';" % (keys["profile"], keys["preferences"])


def validate_variant_html(html, developer_preview=False):
    keys, excluded = (PREVIEW_KEYS, PRODUCTION_KEYS) if developer_preview else (PRODUCTION_KEYS, PREVIEW_KEYS)
    if html.count(key_declaration(keys)) != 1 or any(key in html for key in excluded.values()):
        raise RuntimeError("CrazyGames export has the wrong save namespace")
    if developer_preview:
        if html.count(PREVIEW_NOTICE) != 1 or html.count(PREVIEW_TITLE_SUFFIX) != 1:
            raise RuntimeError("Developer preview must visibly identify its separate test progress")
    elif 'id="developer-preview-notice"' in html or PREVIEW_TITLE_SUFFIX in html:
        raise RuntimeError("Production export must not contain the developer preview notice")


def prepare_variant(project, developer_preview=False):
    """Change only the fresh export copy; no runtime/URL-selected namespace."""
    adapter_path = project / "web/little_leaf_crazygames.js"
    shell_path = project / "web/little_leaf_crazygames_shell.html"
    adapter = adapter_path.read_text(encoding="utf-8")
    shell = shell_path.read_text(encoding="utf-8")
    declaration = key_declaration(PRODUCTION_KEYS)
    if (adapter.count(declaration) != 1 or shell.count(adapter.strip()) != 1
            or shell.count(TITLE_MARKER) != 1 or shell.count(LOADING_MARKER) != 1):
        raise RuntimeError("CrazyGames adapter/shell changed; review export transformation")
    validate_variant_html(shell)
    changes = {}
    if developer_preview:
        staged_adapter = adapter.replace(declaration, key_declaration(PREVIEW_KEYS))
        staged_shell = shell.replace(adapter.strip(), staged_adapter.strip())
        staged_shell = staged_shell.replace(TITLE_MARKER, "<title>$GODOT_PROJECT_NAME" + PREVIEW_TITLE_SUFFIX)
        staged_shell = staged_shell.replace(LOADING_MARKER, "\t\t\t\t" + PREVIEW_NOTICE + "\n" + LOADING_MARKER)
        validate_variant_html(staged_shell, True)
        for path, text in [(adapter_path, staged_adapter), (shell_path, staged_shell)]:
            before = sha256(path)
            path.write_text(text, encoding="utf-8")
            changes[path.relative_to(project).as_posix()] = {"source_sha256": before,
                                                            "staged_sha256": sha256(path)}
    return {"name": "developer-preview" if developer_preview else "production",
            "storage_keys": dict(PREVIEW_KEYS if developer_preview else PRODUCTION_KEYS),
            "transformed_inputs": changes}


def validate_web_gate(build, commit, tree, local_tools=False):
    return artifacts.validate_web_gate(build, commit, tree, local_tools, source_root=ROOT)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--validated-web-build", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--local-tools", action="store_true")
    parser.add_argument("--developer-preview", action="store_true",
                        help="Export separate SDK test-progress keys and a visible developer notice")
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
    variant = prepare_variant(project, args.developer_preview)
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
        ("sdk-contract", ["node", "tests/crazygames_storage.js", "--web-dir", str(project / "web")]
         + (["--developer-preview"] if args.developer_preview else []), ROOT),
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
    validate_variant_html(html, args.developer_preview)
    for name in ["index.pck", "music.pck"]:
        if (web / name).read_bytes()[:4] != b"GDPC":
            raise RuntimeError("Invalid pack header: " + name)
    if (web / "index.wasm").read_bytes()[:4] != b"\0asm":
        raise RuntimeError("Invalid WebAssembly header")
    shutil.copy2(ROOT / "docs/art-audio/third-party/CRAZYGAMES-SDK-NOTICE.md", web / "CRAZYGAMES-SDK-NOTICE.md")
    shutil.copy2(ROOT / "docs/art-audio/third-party/GODOT-AA-LICENSE.txt", web / "GODOT-AA-LICENSE.txt")
    if args.developer_preview:
        (web / "DEVELOPER-PREVIEW.txt").write_text(PREVIEW_README, encoding="utf-8")
    validate_web_gate(args.validated_web_build.resolve(), commit, tree, args.local_tools)
    for name, hashes in variant["transformed_inputs"].items():
        if sha256(project / name) != hashes["staged_sha256"]:
            raise RuntimeError("Export changed staged developer preview input: " + name)
    presentation_optimization = optimize_presentation(web / "index.js")
    manifest = {"source_commit": commit, "source_tree": tree, "godot": version,
                "platform": "crazygames", "existing_web_gate_checks": legacy["engine_checks"],
                "save_variant": variant,
                "presentation_optimization": presentation_optimization,
                "toolchain_verification": legacy["toolchain_verification"], "stages": stages,
                "browser_runtime": "requires separate browser/hosted validation",
                "files": {p.name: {"bytes": p.stat().st_size, "sha256": sha256(p)}
                          for p in sorted(web.iterdir()) if p.is_file()}}
    (web / "crazygames-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    (evidence / "export-report.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print("Built separate CrazyGames export after unchanged complete Web gate: " + commit)


if __name__ == "__main__":
    main()
