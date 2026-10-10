"""Export checked source into a fresh directory; no browser, player profile, or publication."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
from release_metadata import version
from artifacts import sha256

ROOT = Path(__file__).resolve().parents[1]
LOCK = json.loads(Path(__file__).with_name("toolchain.json").read_text())
PRODUCTION_DIRS = {"assets", "data", "scripts", "shaders", "web"}
PRODUCTION_FILES = {"project.godot", "main.tscn", "export_presets.cfg"}
REQUIRED_NOTICES = {"docs/third-party/GODOT-AA-LICENSE.txt": "GODOT-AA-LICENSE.txt"}


def copy_notices(root, web, tested_hashes):
    notices = {}
    for source, destination in REQUIRED_NOTICES.items():
        path = root / source
        if not path.is_file() or not path.read_text().strip():
            raise RuntimeError("Required distribution notice is missing: " + source)
        digest = sha256(path)
        if tested_hashes.get(source) != digest:
            raise RuntimeError("Notice changed after source validation: " + source)
        shutil.copy2(path, web / destination)
        notices[source] = {"file": destination, "sha256": digest}
    return notices


def verify_installer_receipt(binary, template, receipt_path):
    receipt = json.loads(receipt_path.read_text())
    for tool, path in [("godot", binary), ("templates", template)]:
        installed = receipt.get(tool, {})
        expected = LOCK[tool]
        if (installed.get("url") != expected["url"]
                or installed.get("archive_sha256") != expected["sha256"]
                or installed.get("member") != expected["member"]
                or installed.get("member_sha256") != sha256(path)):
            raise RuntimeError("Installed tool does not match the verified official archive receipt: " + tool)
    return receipt


def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), *args], text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--test-report", type=Path, required=True)
    parser.add_argument("--tag", default="")
    parser.add_argument("--local-tools", action="store_true", help="Local smoke validation only; artifact cannot be published by CI")
    args = parser.parse_args()
    release_version = version(ROOT, args.tag)
    if git("status", "--porcelain", "--untracked-files=no"):
        raise RuntimeError("Tracked source differs from the commit; commit/review it before exporting")
    source_sha, source_tree = git("rev-parse", "HEAD"), git("rev-parse", "HEAD^{tree}")
    test_report = json.loads(args.test_report.read_text())
    if (test_report.get("source_commit") != source_sha or test_report.get("status") != "passed"
            or test_report.get("total_checks", 0) <= 0):
        raise RuntimeError("Tests must have passed against this exact source commit")
    # Do not let a focused --only test run masquerade as the complete gate.
    from importlib.util import spec_from_file_location, module_from_spec
    spec = spec_from_file_location("suite", ROOT / "tests/run_integration_candidate.py")
    suite = module_from_spec(spec)
    spec.loader.exec_module(suite)
    expected = {name for name, _ in suite.SUITES} | {
        "import", *("staff-start-" + case for case in
                    ["empty-profile", "fresh", "saved-load", "standalone-load", "bad-load"])}
    if {r["test"] for r in test_report["records"]} != expected:
        raise RuntimeError("Complete integration suite evidence is required")
    if len(test_report["records"]) != len(expected):
        raise RuntimeError("Duplicate integration suite records")
    known_diagnostics = {"test_autosave_feedback_adversarial": {
        "ERROR: Parse JSON failed. Error at line 0: Expected 'true', 'false', or 'null', got 'not'"}}
    for record in test_report["records"]:
        if record["exit_code"] or record["failures"] or any(
                "ERROR:" in line and line not in known_diagnostics.get(record["test"], set())
                for line in record["diagnostics"]):
            raise RuntimeError("Test evidence contains a failure or engine error")
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    project, web, evidence = (out / name for name in ["project", "web", "evidence"])
    for folder in [project, web, evidence]:
        folder.mkdir()
    template = Path(os.environ["GODOT_TEMPLATE"])
    (project / "export_templates").mkdir()
    shutil.copy2(template, project / "export_templates/web_nothreads_release.zip")
    files = git("ls-files", "-z").split("\0")
    if not set(REQUIRED_NOTICES).issubset(files):
        raise RuntimeError("Merge the required Godot AA notice before exporting a release")
    notices = copy_notices(ROOT, web, test_report.get("source_sha256", {}))
    production = {}
    for name in files:
        if not name or not (name in PRODUCTION_FILES or Path(name).parts[0] in PRODUCTION_DIRS):
            continue
        src, target = ROOT / name, project / name
        if src.is_symlink():
            raise RuntimeError("Symlink production inputs require explicit review")
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, target)
        production[name] = sha256(src)
        if test_report.get("source_sha256", {}).get(name) != production[name]:
            raise RuntimeError("Test source hash differs: " + name)
    env = os.environ.copy()
    for key in ["HOME", "APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"]:
        folder = out / "disposable-profile" / key.lower()
        folder.mkdir(parents=True)
        env[key] = str(folder)
    godot = os.environ.get("GODOT_BIN", "godot")
    if args.local_tools:
        if os.environ.get("GITHUB_ACTIONS") == "true":
            raise RuntimeError("GitHub builds must use the checksum-pinned installer")
        tool_receipt = None
        tool_verification = "local-tools-unverified-for-release"
    else:
        receipt_path = os.environ.get("GODOT_TOOLCHAIN_RECEIPT")
        if not receipt_path:
            raise RuntimeError("Official installer receipt required; local smoke checks may use --local-tools")
        binary = Path(shutil.which(godot) or godot).resolve()
        tool_receipt = verify_installer_receipt(binary, template, Path(receipt_path))
        tool_verification = "checksum-pinned-official-archives"
    engine_version = subprocess.check_output([godot, "--version"], env=env, text=True).strip()
    if not engine_version.startswith(LOCK["godot"]["runtime_prefix"]):
        raise RuntimeError("Expected the pinned official Godot runtime, got " + engine_version)
    records = []
    for name, command in [
        ("import", [godot, "--headless", "--path", str(project), "--editor", "--import", "--quit"]),
        ("export", [godot, "--headless", "--path", str(project), "--export-release", "Web", str(web / "index.html")]),
        ("packed-smoke", [godot, "--headless", "--main-pack", str(web / "index.pck"), "--",
                          "--self-check", "--fresh-review", "--visual-qa", "--skip-intro"]),
    ]:
        result = subprocess.run(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=300)
        text = result.stdout.decode(errors="replace")
        (evidence / (name + ".log")).write_text(text)
        if result.returncode or "ERROR:" in text:
            raise RuntimeError(f"{name} failed; inspect its evidence log")
        if name == "packed-smoke" and "SCENE_READY furniture=" not in text:
            raise RuntimeError("Packed game failed to reach scene-ready")
        records.append({"stage": name, "exit_code": result.returncode})
    for name, digest in production.items():
        if sha256(project / name) != digest:
            raise RuntimeError("Export changed production input: " + name)
    if list((out / "disposable-profile").rglob("little_leaf_cafe_layout_motion_v15.json")):
        raise RuntimeError("Smoke test unexpectedly wrote a normal save")
    html = (web / "index.html").read_text()
    match = re.search(r"const GODOT_CONFIG\s*=\s*(\{.*?\});", html)
    if not match:
        raise RuntimeError("Exported HTML has no Godot configuration")
    config = json.loads(match[1])
    for name, size in config["fileSizes"].items():
        if (web / name).stat().st_size != size:
            raise RuntimeError("HTML asset size mismatch: " + name)
    if (web / "index.wasm").read_bytes()[:4] != b"\0asm" or (web / "index.pck").read_bytes()[:4] != b"GDPC":
        raise RuntimeError("Invalid Web binary headers")
    manifest = {
        "schema_version": 1, "version": release_version, "tag": args.tag,
        "source_commit": source_sha, "source_tree": source_tree, "godot": engine_version,
        "web_template_sha256": sha256(template),
        "toolchain_verification": tool_verification, "toolchain_receipt": tool_receipt,
        "workflow_run": os.environ.get("GITHUB_RUN_ID", "local"),
        "workflow_attempt": os.environ.get("GITHUB_RUN_ATTEMPT", "local"),
        "engine_checks": test_report["total_checks"], "test_processes": test_report["test_processes"],
        "test_report_sha256": sha256(args.test_report), "packed_smoke": "passed",
        "browser_runtime": "not_covered_by_headless_ci", "production_sha256": production,
        "distribution_notices": notices,
        "files": {p.name: {"sha256": sha256(p), "bytes": p.stat().st_size}
                  for p in sorted(web.iterdir()) if p.is_file()},
    }
    (web / "release-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    (evidence / "export-report.json").write_text(json.dumps({"stages": records, "manifest": manifest}, indent=2) + "\n")
    print(f"Built {release_version} from {source_sha}; {test_report['total_checks']} engine checks passed")


if __name__ == "__main__":
    main()
