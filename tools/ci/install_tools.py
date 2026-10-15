"""Install checksum-pinned official Linux tools, using only Python's standard library."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import urllib.request
import zipfile

LOCK = json.loads(Path(__file__).with_name("toolchain.json").read_text())
# Keep the historical Godot/Butler lock byte-identical to the wall-format-1 client.
LOCK["chrome"] = json.loads(Path(__file__).with_name("chrome.json").read_text())


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
    if name == "chrome":
        archive.replace(destination)  # Verified official Debian package; CI installs it.
    else:
        with zipfile.ZipFile(archive) as source, source.open(member or spec["member"]) as stream:
            with destination.open("wb") as output:
                shutil.copyfileobj(stream, output)
        archive.unlink()
    destination.chmod(0o644 if name in {"templates", "chrome"} else 0o755)
    print(f"Verified and installed {name}")
    with destination.open("rb") as stream:
        member_digest = hashlib.file_digest(stream, "sha256").hexdigest()
    return {"url": spec["url"], "archive_sha256": digest, "member": member or spec["member"],
            "member_sha256": member_digest}


def verify_chrome_version():
    # Playwright's chrome channel uses this exact system path, not PATH lookup.
    actual = subprocess.check_output(["/opt/google/chrome/chrome", "--version"], text=True).strip()
    if actual != "Google Chrome " + LOCK["chrome"]["version"]:
        raise RuntimeError("Installed Chrome differs from the exact compatibility pin: " + actual)
    print(actual)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tool", choices=["godot", "butler", "chrome"])
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--native-only", action="store_true", help="Install Godot without unused Web export templates for native tests")
    args = parser.parse_args()
    if args.native_only and args.tool != "godot":
        parser.error("--native-only applies only to Godot")
    folder = args.output.resolve()
    folder.mkdir(parents=True, exist_ok=True)
    destination = folder / ("google-chrome-stable.deb" if args.tool == "chrome" else args.tool)
    installed = install(args.tool, destination)
    if args.tool == "chrome" and os.environ.get("GITHUB_ENV"):
        with open(os.environ["GITHUB_ENV"], "a") as output:
            output.write(f"CHROME_DEB={destination}\n")
    if args.tool == "godot":
        verified = {"godot": installed}
        if not args.native_only:
            template = folder / "web_nothreads_release.zip"
            verified["templates"] = install("templates", template)
        receipt = folder / "godot-toolchain-receipt.json"
        receipt.write_text(json.dumps(verified, indent=2) + "\n")
        if os.environ.get("GITHUB_ENV"):
            with open(os.environ["GITHUB_ENV"], "a") as output:
                if not args.native_only:
                    output.write(f"GODOT_TEMPLATE={template}\n")
                output.write(f"GODOT_TOOLCHAIN_RECEIPT={receipt}\n")
    if os.environ.get("GITHUB_PATH"):
        with open(os.environ["GITHUB_PATH"], "a") as output:
            output.write(str(folder) + "\n")


if __name__ == "__main__":
    main()
