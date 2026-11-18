"""Ordinary WebKit prerequisite A/B: unchanged package request, isolated signed Ubuntu config."""
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
        m = re.fullmatch(r"Inst ([\w.+:-]+)(?: \[([^\]]+)\])? \(([^ ]+)(?: .*)?\)", line)
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
    sources.write_text(section("https://archive.ubuntu.com/ubuntu", "noble noble-updates noble-backports")
                       + "\n" + section("https://security.ubuntu.com/ubuntu", "noble-security"))
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
def root_apt(conf, exe, *args):
    # Explicit env argument crosses sudo's env reset without editing sudoers or /etc/apt.
    return ("sudo","-n","/usr/bin/env",f"APT_CONFIG={conf}","LC_ALL=C","DEBIAN_FRONTEND=noninteractive",exe,*args)

def main(arm, core, out):
    out.mkdir(parents=True, exist_ok=True)
    if platform.freedesktop_os_release().get("VERSION_CODENAME") != "noble" or platform.machine() != "x86_64":
        raise ValueError("Expected Ubuntu Noble x64")
    if json.loads((core/"package.json").read_text())["version"] != "1.63.0":
        raise ValueError("Unpinned Playwright version")
    names = direct_dependency_names(core/"lib/coreBundle.js")
    (out/"webkit-direct-package-names.txt").write_text("\n".join(names)+"\n")
    if arm=="baseline":
        pw = core.parent/".bin/playwright"
        capture(out, "webkit-original-apt", (str(pw),"install-deps","webkit"), 14*60)
        return
    if arm!="candidate" or not Path(KEYRING).is_file():
        raise ValueError("Missing Ubuntu archive keyring or invalid arm")
    # Root APT owns files it creates; hosted runner disposes of this isolated scratch.
    root=Path(tempfile.mkdtemp(prefix="ab-official-noble-", dir="/tmp"))
    # Allow _apt to access public config paths; the temp directory still contains no secrets.
    root.chmod(0o755)
    conf=isolated_config(root)
    apt=lambda *args: root_apt(conf,"/usr/bin/apt-get",*args)
    effective=capture(out,"apt-effective",root_apt(conf,"/usr/bin/apt-config","dump"),10)
    if str(root/"ubuntu.sources") not in effective or any(x in effective for x in ("packages.microsoft.com","Pre-Invoke","Post-Invoke","AllowInsecureRepositories \"true\"")):
        raise ValueError("Unexpected effective APT sources or hooks")
    (out/"apt-official-sources.txt").write_text((root/"ubuntu.sources").read_text())
    capture(out,"webkit-apt-refresh",apt("update"),90)
    original=capture(out,"webkit-original-solver",("/usr/bin/apt-get","-s","--no-install-recommends","install",*names),20)
    isolated=capture(out,"webkit-isolated-solver",apt("-s","--no-install-recommends","install",*names),20)
    expected,selected=operations(original),operations(isolated)
    (out/"webkit-transaction.json").write_text(json.dumps({"image":os.getenv("ImageVersion"),"legacy_cached":expected,"isolated_signed":selected},sort_keys=True,indent=2)+"\n")
    if expected!=selected:
        raise ValueError("Legacy runner-cache vs isolated-signed transaction differs; no installation")
    capture(out,"webkit-apt-fetch",apt("install","--download-only","-y","--no-remove","--no-install-recommends",*names),160)
    capture(out,"webkit-apt-install",apt("install","--no-download","-y","--no-remove","--no-install-recommends",*names),105)
    for pkg in names:
        if subprocess.check_output(("dpkg-query","-W","-f=${db:Status-Status}",pkg),text=True).strip()!="installed":
            raise ValueError("Required WebKit package not installed: "+pkg)
if __name__=="__main__":
    main(sys.argv[1],Path(sys.argv[2]),Path(sys.argv[3]))
