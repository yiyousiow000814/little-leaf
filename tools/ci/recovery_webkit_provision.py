"""Provision the ordinary-PR WebKit package closure from signed Ubuntu Noble indexes."""
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

PW_BUNDLE = "549070af3acabb3efcc4f55bfe6210f9f7c2fcf633cf7eaa59bfe60719969171"
DIRECT = "45487ecacfe2fef11e6902c5f800a7f58f48fbf8b304ea411e76c93ee8f33d15"
KEYRING = "/usr/share/keyrings/ubuntu-archive-keyring.gpg"
ARCHIVE_URI = "https://archive.ubuntu.com/ubuntu"
SECURITY_URI = "https://security.ubuntu.com/ubuntu"

APT_CAPTURE_GRACE_SECONDS = 8
REFRESH_BUDGET_SECONDS = 75
FIRST_REFRESH_SECONDS = 50
FETCH_BUDGET_SECONDS = 100
FIRST_FETCH_SECONDS = 65


def direct_dependency_names(bundle):
    raw = bundle.read_bytes()
    if hashlib.sha256(raw).hexdigest() != PW_BUNDLE:
        raise ValueError("Unexpected pinned Playwright core bundle hash")
    section = raw.decode().split('"ubuntu24.04-x64": {', 1)[1].split("lib2package:", 1)[0]
    groups = dict(re.findall(r"(tools|webkit): \[([\s\S]*?)\],", section))
    if set(groups) != {"tools", "webkit"}:
        raise ValueError("Pinned Playwright dependency groups absent")
    names = sorted(set(re.findall(r'"([a-z0-9.+-]+)"', groups["tools"] + groups["webkit"])))
    if len(names) != 61 or hashlib.sha256(("\n".join(names) + "\n").encode()).hexdigest() != DIRECT:
        raise ValueError("Unexpected Playwright Noble dependency request")
    return names

def operations(stdout):
    result = {}
    for line in stdout.splitlines():
        if re.match(r"^(Remv|Purg) ", line):
            raise ValueError("Package removal is out of scope")
        if not line.startswith("Inst "):
            continue
        # APT may append an empty transient dependency-status marker after the version.
        # Nonempty annotations and all other unexpected syntax still fail closed.
        m = re.fullmatch(r"Inst ([\w.+:-]+)(?: \[([^\]]+)\])? \(([^ ]+)(?: .*)?\)(?: \[\])?", line)
        if not m or m[1] in result:
            raise ValueError("Unrecognized or duplicate APT operation: " + line)
        result[m[1]] = {"from": m[2], "to": m[3]}
    return result

def isolated_config(root):
    parts = root / "conf.d"
    parts.mkdir()
    sources = root / "ubuntu.sources"
    # Same archive suites/components as the tested runner, but never third-party repos;
    # base/backports/updates and security keys use Ubuntu's official keyring only.
    def section(url, suites):
        return f"""Types: deb
URIs: {url}
Suites: {suites}
Components: main restricted universe multiverse
Architectures: amd64
Signed-By: {KEYRING}
"""
    sources.write_text(section(ARCHIVE_URI, "noble noble-updates noble-backports")
                       + "\n" + section(SECURITY_URI, "noble-security"))
    for name in ("lists", "cache", "cache/archives"):
        (root / name).mkdir()
    conf=root/"apt.conf"
    conf.write_text(f'''Dir::Etc::parts "{parts}";
Dir::Etc::main "{root}/nonexistent-apt-main.conf";
Dir::Etc::sourcelist "{sources}";
Dir::Etc::sourceparts "{parts}";
Dir::State::lists "{root}/lists";
Dir::Cache "{root}/cache";
Dir::Cache::archives "{root}/cache/archives";
Acquire::Languages "none";
Acquire::https::Timeout "20";
Acquire::https::Verify-Peer "true";
Acquire::https::Verify-Host "true";
Acquire::https::AllowRedirect "false";
Acquire::AllowInsecureRepositories "false";
APT::Get::AllowUnauthenticated "false";
Acquire::Retries "0";
Acquire::Check-Valid-Until "true";
APT::Update::Error-Mode "any";
''')
    return conf
def capture(receipts, name, command, max_seconds, **opts):
    start=time.monotonic()
    try:
        with (receipts/(name+".log")).open("w") as log:
            job=subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, text=True, timeout=max_seconds,
                               env={**os.environ, "LC_ALL":"C"}, **opts)
        job.check_returncode()
        return (receipts/(name+".log")).read_text()
    finally:
        (receipts/(name+".seconds")).write_text(f"{time.monotonic()-start:.3f}\n")
def root_apt(conf, max_seconds, exe, *args):
    # Explicit env argument crosses sudo's env reset without editing sudoers or /etc/apt.
    return ("sudo", "-n", "/usr/bin/timeout", "--kill-after=5s", str(max_seconds),
            "/usr/bin/env", f"APT_CONFIG={conf}", "LC_ALL=C", "DEBIAN_FRONTEND=noninteractive",
            exe, *args)

def refresh_webkit_indexes(apt_phase):
    # Reuse the same isolated signed configuration. A successful full update
    # is required before the solver can inspect any lists.
    deadline = time.monotonic() + REFRESH_BUDGET_SECONDS
    try:
        apt_phase("webkit-apt-refresh", FIRST_REFRESH_SECONDS, "update")
    except subprocess.CalledProcessError as error:
        # GNU timeout only; normal APT errors (including signature/hash
        # rejection), capture timeouts and hard kills never retry.
        if error.returncode != 124:
            raise
        remaining = int(deadline - time.monotonic()) - APT_CAPTURE_GRACE_SECONDS
        if remaining <= 0:
            raise
        print("Retrying timed-out WebKit index refresh once with the same signed APT configuration",
              file=sys.stderr)
        apt_phase("webkit-apt-refresh-retry", remaining, "update")


def fetch_webkit_packages(apt_phase, install, names):
    # Keep the same private signed indexes and APT archive/partial cache. APT
    # checks all required bytes against those indexes before the offline install.
    command = (*install, "--download-only", "-y", *names)
    deadline = time.monotonic() + FETCH_BUDGET_SECONDS
    try:
        apt_phase("webkit-apt-fetch", FIRST_FETCH_SECONDS, *command)
    except subprocess.CalledProcessError as error:
        # 124 is GNU timeout. Never retry APT's normal errors, including failed
        # integrity checks, or retry after a hard kill/outer process timeout.
        if error.returncode != 124:
            raise
        remaining = int(deadline - time.monotonic()) - APT_CAPTURE_GRACE_SECONDS
        if remaining <= 0:
            raise
        print("Retrying timed-out WebKit download once with the same signed APT cache", file=sys.stderr)
        apt_phase("webkit-apt-fetch-retry", remaining, *command)


def require_installed(name, expected_version=None):
    row = subprocess.check_output(("dpkg-query", "-W", "-f=${db:Status-Status}\t${Version}", name),
                                  text=True, timeout=10).split("\t")
    if len(row) != 2 or row[0] != "installed" or (expected_version is not None and row[1] != expected_version):
        raise ValueError("Required WebKit package absent or version changed: " + name)

def main(core, out):
    out.mkdir(parents=True, exist_ok=True)
    if platform.freedesktop_os_release().get("VERSION_CODENAME") != "noble" or platform.machine() != "x86_64":
        raise ValueError("Expected Ubuntu Noble x64")
    if json.loads((core/"package.json").read_text())["version"] != "1.63.0":
        raise ValueError("Unpinned Playwright version")
    browsers = json.loads((core/"browsers.json").read_text())["browsers"]
    revisions = {b["name"]: b for b in browsers if b["name"] in {"webkit", "ffmpeg"}}
    if (revisions.get("webkit", {}).get("revision") != "2359"
            or revisions["webkit"].get("browserVersion") != "26.6"
            or revisions.get("ffmpeg", {}).get("revision") != "1011"):
        raise ValueError("Unexpected Playwright WebKit or FFmpeg build")
    if not Path(KEYRING).is_file():
        raise ValueError("Missing Ubuntu archive keyring")
    names = direct_dependency_names(core/"lib/coreBundle.js")
    (out/"webkit-direct-package-names.txt").write_text("\n".join(names)+"\n")
    (out/"browser-revisions.json").write_text(json.dumps(revisions, indent=2)+"\n")
    # Root APT owns files it creates; the hosted runner disposes of this isolated scratch.
    root = Path(tempfile.mkdtemp(prefix="recovery-webkit-noble-", dir="/tmp"))
    root.chmod(0o755)  # _apt may traverse public inputs, not write the config.
    conf = isolated_config(root)

    def apt_phase(name, seconds, *args):
        return capture(out, name, root_apt(conf, seconds, "/usr/bin/apt-get", *args),
                       seconds + APT_CAPTURE_GRACE_SECONDS)

    effective = capture(out, "apt-effective",
                        root_apt(conf, 8, "/usr/bin/apt-config", "dump"), 16)
    if str(root/"ubuntu.sources") not in effective or any(
        x in effective for x in ("packages.microsoft.com", "Pre-Invoke", "Post-Invoke",
                                 'AllowInsecureRepositories "true"', 'AllowUnauthenticated "true"')
    ):
        raise ValueError("Unexpected effective APT sources, trust, or hooks")
    (out/"apt-official-sources.txt").write_text((root/"ubuntu.sources").read_text())
    refresh_webkit_indexes(apt_phase)
    install = ("install", "--no-remove", "--no-install-recommends")
    selected = operations(apt_phase("webkit-apt-solver", 15, "-s", *install, *names))
    (out/"webkit-transaction.json").write_text(json.dumps({
        "image": os.getenv("ImageVersion"), "selected": selected,
        "scope": "Ubuntu-only fresh signed indexes; no alternate package source"
    }, sort_keys=True, indent=2)+"\n")
    # The sole signed source set is unchanged through solve, fetch, and install.
    # No download fallback is permitted in the actual transaction.
    if selected:
        fetch_webkit_packages(apt_phase, install, names)
        apt_phase("webkit-apt-install", 60, *install, "--no-download", "-y", *names)
    for pkg in names:
        require_installed(pkg)
    for pkg, op in selected.items():
        require_installed(pkg, op["to"])
    loaded = []
    for name in ("libgstlibav.so", "libgstplayback.so", "libgstsoup.so"):
        path = Path("/usr/lib/x86_64-linux-gnu/gstreamer-1.0") / name
        if not path.is_file():
            raise ValueError("Required media plugin missing: " + name)
        result = subprocess.check_output(("/usr/bin/ldd", str(path)), text=True, timeout=10)
        if "not found" in result:
            raise ValueError("Missing media plugin dependency: " + name)
        loaded.append(name + "\n" + result)
    (out/"gstreamer-ldd.txt").write_text("\n".join(loaded))

if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]))
