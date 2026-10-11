"""Install checksum-pinned official Linux tools, using only Python's standard library."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import urllib.request
import zipfile

LOCK = json.loads(Path(__file__).with_name("toolchain.json").read_text())


def install(name, destination, member=None):
    spec = LOCK[name]
    archive = destination.parent / (name + ".zip")
    with urllib.request.urlopen(spec["url"], timeout=120) as response, archive.open("wb") as output:
        shutil.copyfileobj(response, output)
    with archive.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    if digest != spec["sha256"]:
        raise RuntimeError(f"{name}: official archive checksum mismatch; refusing to execute")
    # Extract a single named member, never archive-provided paths or permissions.
    with zipfile.ZipFile(archive) as source, source.open(member or spec["member"]) as stream:
        with destination.open("wb") as output:
            shutil.copyfileobj(stream, output)
    destination.chmod(0o755 if name != "templates" else 0o644)
    archive.unlink()
    print(f"Verified and installed {name}")
    with destination.open("rb") as stream:
        member_digest = hashlib.file_digest(stream, "sha256").hexdigest()
    return {"url": spec["url"], "archive_sha256": digest, "member": member or spec["member"],
            "member_sha256": member_digest}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tool", choices=["godot", "butler"])
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    folder = args.output.resolve()
    folder.mkdir(parents=True, exist_ok=True)
    installed = install(args.tool, folder / args.tool)
    if args.tool == "godot":
        template = folder / "web_nothreads_release.zip"
        templates = install("templates", template)
        receipt = folder / "godot-toolchain-receipt.json"
        receipt.write_text(json.dumps({"godot": installed, "templates": templates}, indent=2) + "\n")
        if os.environ.get("GITHUB_ENV"):
            with open(os.environ["GITHUB_ENV"], "a") as output:
                output.write(f"GODOT_TEMPLATE={template}\nGODOT_TOOLCHAIN_RECEIPT={receipt}\n")
    if os.environ.get("GITHUB_PATH"):
        with open(os.environ["GITHUB_PATH"], "a") as output:
            output.write(str(folder) + "\n")


if __name__ == "__main__":
    main()
