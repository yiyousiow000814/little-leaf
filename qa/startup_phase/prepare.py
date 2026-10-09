"""Prepare/export paired diagnostic overlays; never export a release or touch source.

Default is offline preparation only. --export uses already installed tools, a
shared engine lock, and fresh saveguard profiles. This does not run a browser.
"""
import argparse
import fcntl
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[2]
PINNED_SOURCE = "29974be8f124832083d4b2852131ad9ea32abe24"
PRODUCTION_DIRS = {"assets", "data", "scripts", "shaders", "web"}
PRODUCTION_FILES = {"project.godot", "main.tscn", "export_presets.cfg"}
MODES = ("control", "instrumented")
OVERLAY_PATH = "qa/startup_phase/main.gd"


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args])


def production(name):
    return name in PRODUCTION_FILES or name.split("/")[0] in PRODUCTION_DIRS


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def source_snapshot(root, expected):
    head = git(root, "rev-parse", "HEAD").decode().strip()
    if head != expected:
        raise RuntimeError("Source HEAD differs from expected source commit")
    tree = git(root, "rev-parse", "HEAD^{tree}").decode().strip()
    with zipfile.ZipFile(io.BytesIO(git(root, "archive", "--format=zip", head))) as archive:
        names = [name for name in archive.namelist() if not name.endswith("/") and production(name)]
        sources = {name: archive.read(name) for name in names}
    for name, data in sources.items():
        path = root / name
        if path.is_symlink() or not path.is_file() or path.read_bytes() != data:
            raise RuntimeError("Production source differs from pinned commit: " + name)
    extras = git(root, "ls-files", "--others", "--exclude-standard", "-z").decode().split("\0")
    if any(name and production(name) for name in extras):
        raise RuntimeError("Untracked production inputs are not permitted")
    return head, tree, sources


def prepare(root, output, expected=PINNED_SOURCE):
    root, output = root.resolve(), output.resolve()
    if output == root or root in output.parents:
        raise RuntimeError("Disposable output must be outside the checkout")
    head, tree, sources = source_snapshot(root, expected)
    templates = {p.name: p.read_bytes() for p in sorted((root / "qa/startup_phase").iterdir())
                 if p.is_file() and p.suffix in {".gd", ".json", ".py", ".js", ".md"}}
    template_hashes = {name: digest(data) for name, data in templates.items()}
    source_hashes = {name: digest(data) for name, data in sources.items()}
    basis = {"schema_version": 1, "source_commit": head, "source_tree": tree,
             "base_production_sha256": source_hashes, "overlay_templates_sha256": template_hashes}
    pair_id = digest(canonical(basis))
    output.mkdir(parents=True, exist_ok=False)
    frozen = output / "overlay-source"
    frozen.mkdir()
    for name, data in templates.items():
        (frozen / name).write_bytes(data)
    manifests = {}
    for mode in MODES:
        project = output / mode / "project"
        project.mkdir(parents=True)
        payload = dict(sources)
        entry = sources["main.tscn"].decode()
        old = 'path="res://scripts/main.gd"'
        if entry.count(old) != 1 or entry.count("[node ") != 1:
            raise RuntimeError("Entry scene structure changed; review overlay substitution")
        payload["main.tscn"] = entry.replace(old, 'path="res://' + OVERLAY_PATH + '"').encode()
        overlay_id = digest(canonical({"pair_id": pair_id, "mode": mode}))
        script = templates[mode + ".gd"].decode()
        for token, value in [("SOURCE_COMMIT", head), ("SOURCE_TREE", tree), ("OVERLAY_ID", overlay_id)]:
            script = script.replace("@" + token + "@", value)
        if "@SOURCE_" in script or "@OVERLAY_" in script:
            raise RuntimeError("Unresolved overlay token")
        payload[OVERLAY_PATH] = script.encode()
        for name, data in payload.items():
            path = project / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        hashes = {name: digest(data) for name, data in payload.items()}
        manifest = {**basis, "kind": "startup-phase-diagnostic-export", "mode": mode,
                    "pair_id": pair_id, "overlay_id": overlay_id,
                    "diagnostic_only": True, "release_qualified": False,
                    "release_qualification_prohibited": True,
                    "diagnostic_project_sha256": hashes,
                    "changed_production_paths": ["main.tscn"],
                    "added_overlay_paths": [OVERLAY_PATH],
                    "browser_status": "not_run_actual_browser_pending",
                    "export_status": "not_run", "production_checkout_unchanged": True,
                    "source_scope": "Pinned production source plus explicit diagnostic overlay; NOT the release tree",
                    "control_difference": "Both use an extra inherited script. Instrumented adds wrappers, pre-ready buffer allocation, marks and post-draw emission. These change parse/export size and runtime cost.",
                    "overhead_status": "unmeasured; use paired control browser trials, do not subtract assumed constants"}
        write_json(output / mode / "diagnostic-manifest.json", manifest)
        manifests[mode] = manifest
    # Establish precisely what the two engine input sets differ on.
    differences = [name for name in manifests["control"]["diagnostic_project_sha256"]
                   if manifests["control"]["diagnostic_project_sha256"][name] != manifests["instrumented"]["diagnostic_project_sha256"][name]]
    if differences != [OVERLAY_PATH]:
        raise RuntimeError("Unexpected control/instrumented project difference: " + str(differences))
    pair = {"schema_version": 1, "kind": "startup-phase-diagnostic-pair", "diagnostic_only": True,
            "release_qualified": False, "pair_id": pair_id, "source_commit": head, "source_tree": tree,
            "project_differences": differences, "browser_status": "not_run_actual_browser_pending"}
    write_json(output / "pair.json", pair)
    return manifests


def check_project(project, manifest):
    for name, expected in manifest["diagnostic_project_sha256"].items():
        if digest((project / name).read_bytes()) != expected:
            raise RuntimeError("Engine changed staged input: " + name)


def export_pair(root, output, manifests, engine, template, lock, receipt=None):
    engine = Path(shutil.which(str(engine)) or engine).resolve()
    template = template.resolve()
    identity = {"engine_sha256": digest(engine.read_bytes()), "template_sha256": digest(template.read_bytes()),
                "toolchain_verification": "local-tools-not-release-qualified"}
    if receipt:
        trusted = json.loads(receipt.read_text())
        toolchain_bytes = git(root, "show", manifests["control"]["source_commit"] + ":ci/toolchain.json")
        if (root / "ci/toolchain.json").read_bytes() != toolchain_bytes:
            raise RuntimeError("Toolchain lock differs from pinned source commit")
        toolchain = json.loads(toolchain_bytes)
        identity["toolchain_lock_sha256"] = digest(toolchain_bytes)
        for tool, file in [("godot", engine), ("templates", template)]:
            row = trusted[tool]
            if (row["member_sha256"] != digest(file.read_bytes()) or row["url"] != toolchain[tool]["url"]
                    or row["archive_sha256"] != toolchain[tool]["sha256"] or row["member"] != toolchain[tool]["member"]):
                raise RuntimeError("Tool differs from pinned toolchain receipt: " + tool)
        identity.update(toolchain_verification="checksum-pinned-official-archives", toolchain_receipt=trusted)
    lock.parent.mkdir(parents=True, exist_ok=True)
    with lock.open("a+") as locked:
        fcntl.flock(locked, fcntl.LOCK_EX)
        for mode in MODES:
            folder, manifest = output / mode, manifests[mode]
            project, web = folder / "project", folder / "web"
            web.mkdir()
            env = os.environ.copy()
            for key in ["HOME", "APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"]:
                directory = folder / "saveguard-profile" / key.lower()
                directory.mkdir(parents=True)
                env[key] = str(directory)
            version = subprocess.check_output([str(engine), "--version"], env=env, text=True).strip()
            if not version.startswith("4.6.3.stable"):
                raise RuntimeError("Expected Godot 4.6.3 stable")
            (project / "export_templates").mkdir()
            shutil.copy2(template, project / "export_templates/web_nothreads_release.zip")
            logs = folder / "evidence"
            logs.mkdir()
            for name, args in [("import", ["--editor", "--import", "--quit"]),
                               ("export", ["--export-release", "Web", str(web / "index.html")])]:
                command = [str(engine), "--headless", "--path", str(project), *args]
                result = subprocess.run(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=300)
                text = result.stdout.decode(errors="replace")
                (logs / (name + ".log")).write_text(text)
                if result.returncode or "ERROR:" in text:
                    raise RuntimeError(mode + " " + name + " failed; inspect evidence; no browser conclusion")
                check_project(project, manifest)
            shutil.copy2(root / "docs/third-party/GODOT-AA-LICENSE.txt", web / "GODOT-AA-LICENSE.txt")
            manifest.update(identity, engine_version=version, export_status="passed",
                            files={p.name: {"sha256": digest(p.read_bytes()), "bytes": p.stat().st_size}
                                   for p in sorted(web.iterdir()) if p.is_file()})
            # Deliberately not named release-manifest.json; existing release gates reject it.
            write_json(web / "diagnostic-manifest.json", manifest)
            write_json(folder / "diagnostic-manifest.json", manifest)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, default=ROOT)
    parser.add_argument("--expected-source", default=PINNED_SOURCE)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--export", action="store_true")
    parser.add_argument("--engine-lock", type=Path)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN") or "godot")
    parser.add_argument("--template", type=Path, default=os.environ.get("GODOT_TEMPLATE"))
    parser.add_argument("--toolchain-receipt", type=Path, default=os.environ.get("GODOT_TOOLCHAIN_RECEIPT"))
    args = parser.parse_args()
    args.godot = args.godot or "godot"
    if args.export and (not args.engine_lock or not args.template):
        parser.error("--export requires --engine-lock and --template (already installed, no downloads)")
    root, output = args.source_root.resolve(), args.output.resolve()
    manifests = prepare(root, output, args.expected_source)
    if args.export:
        export_pair(root, output, manifests, args.godot, args.template, args.engine_lock, args.toolchain_receipt)
    source_snapshot(root, args.expected_source)
    print(json.dumps({"output": str(output), "source_commit": args.expected_source,
                      "pair_id": manifests["control"]["pair_id"], "diagnostic_only": True,
                      "release_qualified": False, "browser_status": "not_run_actual_browser_pending"}))


if __name__ == "__main__":
    main()
