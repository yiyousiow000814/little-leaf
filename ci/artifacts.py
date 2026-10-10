"""Shared Web artifact payload and exact-source contracts; no export or publication."""
import hashlib
import json
from pathlib import Path


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def validate_web_gate(build, commit, tree, local_tools=False, *, source_root):
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
        if sha256(source_root / name) != digest or sha256(build / "project" / name) != digest:
            raise RuntimeError("Source changed after existing Web gate: " + name)
    html = (build / "web/index.html").read_text(encoding="utf-8")
    if "https://sdk.crazygames.com/crazygames-sdk-v3.js" in html:
        raise RuntimeError("Normal Web export must not load the CrazyGames SDK")
    return manifest


def validate_export_inventory(web):
    if web.is_symlink() or not web.is_dir():raise ValueError('Export root must be a real directory')
    manifest_path=web/'release-manifest.json'
    if manifest_path.is_symlink():raise ValueError('Export manifest symlink forbidden')
    base=json.loads(manifest_path.read_text());files=base.get('files')
    if not isinstance(files,dict) or not files:raise ValueError('Complete export inventory required')
    if any(not isinstance(name,str) or not name or Path(name).name!=name or '\\' in name or name=='release-manifest.json' for name in files):
        raise ValueError('Unsafe export inventory path')
    if {p.name for p in web.iterdir()}!=set(files)|{'release-manifest.json'}:
        raise ValueError('Unexpected or missing export files')
    verify_files(web, files, strict_records=True)
    return base


def verify_files(web, files, *, strict_records=False):
    """Hash every declared payload; preserve staging's stricter record schema."""
    for name, record in files.items():
        path = web / name
        if path.is_symlink() or not path.is_file():
            raise ValueError('Export symlink or non-file forbidden')
        if strict_records and (not isinstance(record, dict) or type(record.get('bytes')) is not int):
            raise ValueError('Export inventory hash/size mismatch: ' + name)
        digest = record.get('sha256') if strict_records else record['sha256']
        if digest != sha256(path) or record['bytes'] != path.stat().st_size:
            raise ValueError('Export inventory hash/size mismatch: ' + name)
