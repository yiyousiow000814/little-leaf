"""Narrow Noble amd64 package setup for the isolated Play benchmark."""
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys
import tempfile
import time

LOCK = Path(__file__).with_name("noble-lock.json")
ORIGIN = "https://archive.ubuntu.com/ubuntu/pool/"
RETRYABLE_DOWNLOAD_CODES = {28, 52}  # Timeout, empty reply.
DOWNLOAD_PHASE_SECONDS = 110  # Shared by all packages, inside each 3-minute CI step.
FIRST_DOWNLOAD_SECONDS = 45
RETRY_DOWNLOAD_SECONDS = 55
# Playwright 1.63.0's Noble Chromium dependency/tool list, excluding locked fonts.
# Also require the helpers used by the original headed lane.
LOCKED_TRANSITIVE = {
    "liblept5": ("libgif7", "libjpeg8"), "libjpeg8": ("libjpeg-turbo8",),
    "xfonts-cyrillic": ("xfonts-utils",), "xfonts-scalable": ("xfonts-utils",),
    "xfonts-utils": ("xfonts-encodings",),
}
TRANSITIVE_ONLY = {n for deps in LOCKED_TRANSITIVE.values() for n in deps}
PREINSTALLED = """xvfb xauth libfontconfig1 libfreetype6
libasound2t64 libatk-bridge2.0-0t64 libatk1.0-0t64 libatspi2.0-0t64
libcairo2 libcups2t64 libdbus-1-3 libdrm2 libgbm1 libglib2.0-0t64 libnspr4
libnss3 libpango-1.0-0 libx11-6 libxcb1 libxcomposite1 libxdamage1 libxext6
libxfixes3 libxkbcommon0 libxrandr2""".split()

def run(*args, **opts):
    return subprocess.run(args, check=True, text=True, **opts)

def installed(name):
    p = subprocess.run(("dpkg-query", "-W", "-f=${db:Status-Status}\t${Version}", name),
                       capture_output=True, text=True)
    fields = p.stdout.split("\t")
    return fields[1] if p.returncode == 0 and fields[0] == "installed" and len(fields) == 2 else None

def plan(current, lock):
    missing = [name for name in PREINSTALLED if not current.get(name)]
    if missing:
        raise ValueError(f"Required nonlocked runner dependencies missing: {missing}")
    wanted = {name for name in lock if name not in TRANSITIVE_ONLY and not current.get(name)}
    todo = list(wanted)
    while todo:
        for dep in LOCKED_TRANSITIVE.get(todo.pop(), ()):
            if dep not in wanted and not current.get(dep):
                if dep not in lock:
                    raise ValueError(f"Required transitive package without pin: {dep}")
                wanted.add(dep)
                todo.append(dep)
    return sorted(wanted)

def verify_simulation(stdout, needed):
    changes = re.findall(r"^(?:Inst|Remv) ([^ \n:]+)", stdout, re.M)
    if sorted(changes) != sorted(needed) or re.search(r"^Remv ", stdout, re.M):
        raise ValueError(f"Unexpected dependency transaction: {changes}")

def simulate(files, report, write):
    # APT can prefer a remote archive record for the exact same bytes as a supplied
    # local .deb. Keep the real installed dpkg status, but expose no remote indexes.
    # A dependency absent from both installed status and the local files must fail.
    with tempfile.TemporaryDirectory(prefix="noble-apt-local-index-") as td:
        root = Path(td)
        source_list = root / "sources.list"
        source_list.touch()
        source_parts, lists = root / "sources.list.d", root / "lists"
        source_parts.mkdir()
        lists.mkdir()
        command = ("apt-get", "-s", "--no-download", "--no-install-recommends",
                   "-o", f"Dir::Etc::sourcelist={source_list}",
                   "-o", f"Dir::Etc::sourceparts={source_parts}",
                   "-o", f"Dir::State::lists={lists}",
                   "-o", "Dir::Cache::pkgcache=", "-o", "Dir::Cache::srcpkgcache=",
                   "install", *map(str, files))
        sims = subprocess.run(command, text=True, capture_output=True, check=False,
                              env={**os.environ, "LC_ALL": "C"})
    report["simulation"] = {"exit_code": sims.returncode,
                            "stdout": sims.stdout, "stderr": sims.stderr}
    write()
    if sims.returncode:
        if sims.stdout:
            print(sims.stdout, file=sys.stderr, end="")
        if sims.stderr:
            print(sims.stderr, file=sys.stderr, end="")
        raise RuntimeError(f"Offline apt simulation failed ({sims.returncode}); no packages installed")
    return sims.stdout

def download_pinned_package(name, url, dest, deadline):
    resume = False
    for attempt, limit in enumerate((FIRST_DOWNLOAD_SECONDS, RETRY_DOWNLOAD_SECONDS)):
        budget = min(limit, deadline - time.monotonic())
        if budget < 0.01:
            raise TimeoutError(f"Pinned package download budget exhausted before {name}")
        try:
            # No redirects, mirror fallback, or unverified URL. Only curl's
            # validated Range continuation may reuse a timeout's partial bytes.
            run("curl", "--fail", "--silent", "--show-error", "--proto", "=https",
                "--connect-timeout", f"{min(10, budget):.3f}", "--max-time", f"{budget:.3f}",
                *(("--continue-at", "-") if resume else ()), "--output", str(dest), url,
                timeout=budget + 1)
            return
        except subprocess.CalledProcessError as error:
            if attempt or error.returncode not in RETRYABLE_DOWNLOAD_CODES:
                raise
            resume = error.returncode == 28 and dest.exists() and dest.stat().st_size > 0
            if not resume:
                dest.unlink(missing_ok=True)
            print(f"Retrying pinned package {name} once after curl exit {error.returncode}"
                  f" ({'resume' if resume else 'restart'})", file=sys.stderr)

def fetch_package(name, spec, root, deadline=None):
    rel = spec["file"]
    if not re.fullmatch(r"(main|universe)/[a-z0-9+.-]+/[a-z0-9+.-]+/[A-Za-z0-9+._~%-]+[.]deb", rel):
        raise ValueError(f"Unsafe package path: {rel}")
    dest = root / Path(rel).name
    if deadline is None:
        deadline = time.monotonic() + DOWNLOAD_PHASE_SECONDS
    download_pinned_package(name, ORIGIN + rel, dest, deadline)
    # Check the entire file after either a fresh transfer or continuation.
    # Hash and package metadata failures never trigger a retry.
    with dest.open("rb") as stream:
        actual = hashlib.file_digest(stream, "sha256").hexdigest()
    if actual != spec["sha256"]:
        raise ValueError(f"{name} package checksum mismatch")
    for key, expected in (("Package", name), ("Version", spec["version"])):
        result = run("dpkg-deb", "-f", str(dest), key, capture_output=True).stdout.strip()
        if result != expected:
            raise ValueError(f"{name} unexpected {key}: {result}")
    if run("dpkg-deb", "-f", str(dest), "Architecture", capture_output=True).stdout.strip() not in {"all", "amd64"}:
        raise ValueError(f"{name} unexpected architecture")
    return dest

def main(mode, receipt):
    lock = json.loads(LOCK.read_text())
    if mode not in {"baseline", "candidate", "snapshot"}:
        raise ValueError("Unknown arm")
    if platform.freedesktop_os_release().get("VERSION_CODENAME") != "noble" or platform.machine() != "x86_64":
        raise ValueError("Expected Ubuntu Noble amd64")
    names = sorted(set(PREINSTALLED) | lock.keys())
    current = {name: installed(name) for name in names}
    report = {"image_os": os.getenv("ImageOS"), "image_version": os.getenv("ImageVersion"), "mode": mode,
              "arm": os.getenv("ARM"), "before": current}
    def write():
        Path(receipt).write_text(json.dumps(report, indent=2) + "\n")
    write()
    try:
        if mode == "candidate":
            needed = plan(current, lock)
            report["selected"] = {n: lock[n] for n in needed}
            write()
            with tempfile.TemporaryDirectory(prefix="checked-noble-") as td:
                root = Path(td)
                deadline = time.monotonic() + DOWNLOAD_PHASE_SECONDS
                with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
                    files = list(pool.map(lambda n: fetch_package(n, lock[n], root, deadline), needed))
                if files:
                    # Dry-run uses installed versions and local file dependencies only. It must
                    # resolve before the original lane's existing sudo is allowed to mutate dpkg.
                    verify_simulation(simulate(files, report, write), needed)
                    run("sudo", "-n", "dpkg", "-i", *map(str, files))
                for n in needed:
                    if installed(n) != lock[n]["version"]:
                        raise ValueError(f"{n} expected pinned installed version")
        elif mode == "baseline":
            raise ValueError("Use the unchanged inline baseline shell steps")
        report["status"] = "passed"
    except Exception as error:
        report["status"], report["error"] = "failed", str(error)
        raise
    finally:
        report["after"] = {name: installed(name) for name in names}
        write()

if __name__ == "__main__":
    main(*sys.argv[1:])
