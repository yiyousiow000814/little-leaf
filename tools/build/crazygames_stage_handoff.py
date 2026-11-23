"""Transfer only generated metadata from the ordinary post-import export stage."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil

if __name__ == "__main__":
    import sys
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from build.build_web import ROOT, PRODUCTION_DIRS, PRODUCTION_FILES, git, verify_installer_receipt
from build.project_layout import resource_name, source_path
from ci.crazygames_pr_evidence import ordinary_sibling_route
from qualification.artifacts import sha256, validate_export_inventory, validate_web_gate
from release.release_metadata import projected_metadata, version


TEMPLATE = "export_templates/web_nothreads_release.zip"
CAP = 512 * 1024


def digest(data):
    return hashlib.sha256(data).hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def safe(name):
    path = PurePosixPath(name)
    require(bool(path.parts) and str(path) == name and not path.is_absolute()
            and ".." not in path.parts and "\\" not in name and ".godot" not in path.parts,
            "Unsafe staged project path")
    return name


def tracked_project():
    tracked = git("ls-files", "-z").split("\0")
    names = [name for path in tracked if path and (name := resource_name(path))
             and (name in PRODUCTION_FILES or PurePosixPath(name).parts[0] in PRODUCTION_DIRS)]
    require(len(names) == len(set(names)), "Ambiguous production staging path")
    return set(map(safe, names))


def scan(project):
    require(project.is_dir() and not project.is_symlink(), "Staged project root must be real")
    files, dirs = {}, set()

    def visit(path):
        for entry in path.iterdir():
            if entry.name == ".godot":  # Matches build_crazygames.copytree(ignore=.godot).
                continue
            name = safe(entry.relative_to(project).as_posix())
            require(not entry.is_symlink(), "Symlink not allowed in staged project")
            if entry.is_dir():
                dirs.add(name)
                visit(entry)
            else:
                require(entry.is_file(), "Non-regular staged project member")
                files[name] = sha256(entry)
    visit(project)
    return {"files": files, "directories": sorted(dirs)}


def generated(name, tracked):
    path = PurePosixPath(safe(name))
    require(path.suffix in (".uid", ".import") and str(path.with_suffix("")) in tracked,
            "Only generated metadata for tracked inputs can be transferred: " + name)


def expected_directories(names):
    return sorted({str(parent) for name in names for parent in PurePosixPath(name).parents
                   if str(parent) != "."})


def exact_inputs(build):
    require(not git("status", "--porcelain", "--untracked-files=no"), "Tracked checkout must be clean")
    commit, tree = git("rev-parse", "HEAD"), git("rev-parse", "HEAD^{tree}")
    require(commit == os.environ.get("GITHUB_SHA") and ordinary_sibling_route(os.environ),
            "Exact ordinary CI checkout required")
    manifest = validate_export_inventory(build / "web")
    run, attempt = (os.environ.get(key, "") for key in ("GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT"))
    binding = {"source_commit": commit, "source_tree": tree, "workflow_run": run, "workflow_attempt": attempt}
    require(all(manifest.get(k) == v for k, v in binding.items())
            and all(re.fullmatch("[1-9][0-9]*", item) for item in (run, attempt))
            and manifest.get("tag") == "" and manifest.get("version") == version(ROOT, source_commit=commit),
            "Exact ordinary export receipt required")
    binding["ordinary_manifest_sha256"] = sha256(build / "web/release-manifest.json")
    tracked = tracked_project()
    production = manifest.get("production_sha256", {})
    projected = projected_metadata(ROOT, commit)
    require(set(production) == tracked and projected.keys() <= tracked
            and manifest.get("projected_metadata_sha256") == {n: digest(b) for n, b in projected.items()},
            "Ordinary export production inventory or projections differ")
    template = Path(os.environ["GODOT_TEMPLATE"])
    godot = os.environ.get("GODOT_BIN", "godot")
    binary = Path(shutil.which(godot) or godot).resolve()
    receipt = verify_installer_receipt(binary, template, Path(os.environ["GODOT_TOOLCHAIN_RECEIPT"]))
    template_hash = sha256(template)
    require(template_hash == manifest.get("web_template_sha256")
            and receipt == manifest.get("toolchain_receipt"), "Exact ordinary Web template/toolchain required")
    expected = {name: digest(projected[name]) if name in projected else production[name] for name in tracked}
    expected[TEMPLATE] = template_hash
    return binding, expected, projected, template


def pack(build, packet):
    binding, expected, _, _ = exact_inputs(build)
    project = build / "project"
    validate_web_gate(build, binding["source_commit"], binding["source_tree"], source_root=ROOT)
    original = scan(project)
    require(set(expected) <= original["files"].keys()
            and all(original["files"][n] == expected[n] for n in expected),
            "Staged tracked inputs or template changed")
    require(original["directories"] == expected_directories(original["files"]),
            "Unexpected empty project directory")
    extras = {}
    tracked = expected.keys() - {TEMPLATE}
    for name in sorted(original["files"].keys() - expected.keys()):
        generated(name, tracked)
        require((project / name).stat().st_size <= CAP, "Generated metadata exceeds byte cap")
        data = (project / name).read_bytes()
        require(digest(data) == original["files"][name], "Generated metadata changed")
        extras[name] = base64.b64encode(data).decode("ascii")
    data = json.dumps({"binding": binding, "inventory": original, "extras": extras},
                      ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    require(len(data) <= CAP, "Staged transfer exceeds byte cap")
    with packet.open("xb") as out:
        out.write(data)


def restore(build, packet):
    binding, expected, projected, template = exact_inputs(build)
    require(packet.is_file() and not packet.is_symlink() and packet.stat().st_size <= CAP,
            "Staged transfer is not a bounded regular file")
    data = json.loads(packet.read_bytes())
    require(data["binding"] == binding, "Staged project proof is not from this exact ordinary export")
    extras, inventory = data["extras"], data["inventory"]
    require(type(extras) is dict and set(expected).isdisjoint(extras), "Unexpected generated input overlap")
    tracked = expected.keys() - {TEMPLATE}
    for name in extras:
        generated(name, tracked)
    decoded = {n: base64.b64decode(v, validate=True) for n, v in extras.items()}
    reconstructed = {**expected, **{n: digest(b) for n, b in decoded.items()}}
    require(inventory == {"files": reconstructed, "directories": expected_directories(reconstructed)},
            "Staged transfer differs from original inventory")
    project = build / "project"
    project.mkdir()  # No stale or merged staged trees.
    for name in sorted(reconstructed):
        out = project / name
        out.parent.mkdir(parents=True, exist_ok=True)
        if name in projected:
            out.write_bytes(projected[name])
        elif name in decoded:
            out.write_bytes(decoded[name])
        else:
            src = template if name == TEMPLATE else source_path(ROOT, name)
            require(src.is_file() and not src.is_symlink(), "Invalid tracked production input")
            shutil.copy2(src, out)
    require(scan(project) == inventory, "Recreated project differs from ordinary staged source")
    validate_web_gate(build, binding["source_commit"], binding["source_tree"], source_root=ROOT)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=["pack", "restore"])
    parser.add_argument("--web-build", type=Path, required=True)
    parser.add_argument("--packet", type=Path, required=True)
    args = parser.parse_args()
    (pack if args.operation == "pack" else restore)(args.web_build, args.packet)
    print("Verified ordinary staged project transfer: " + args.operation)


if __name__ == "__main__":
    main()
