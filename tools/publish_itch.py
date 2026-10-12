"""Publish an already-tested artifact to the one approved itch channel; fail closed."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import time
from release.release_metadata import STABLE, RELEASE, release_key
from qualification.artifacts import verify_files, sha256

TARGET = "siowyiyou/little-leaf:html5"
# Numeric prerelease identifiers cannot have leading zeroes; other identifiers
# must contain a letter or hyphen. Empty identifiers and trailing dots are invalid.
PRERELEASE_ID = r"(?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)"
PRERELEASE = PRERELEASE_ID + r"(?:\." + PRERELEASE_ID + r")*"
BUILD_METADATA = r"[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*"


def parse_result(text):
    results = []
    for line in text.splitlines():
        if not line.strip():
            continue
        message = json.loads(line)
        if message.get("type") == "error":
            raise ValueError("Butler reported an error; no automatic retry is safe")
        if message.get("type") == "result":
            results.append(message.get("value"))
    if len(results) != 1 or not isinstance(results[0], dict):
        raise ValueError("Expected exactly one structured Butler result")
    return results[0]


def butler(*arguments, timeout=None):
    # Never print raw output: auth errors and temporary upload URLs need not enter logs.
    if timeout is None:
        timeout = 600 if arguments[0] == "push" else 60
    result = subprocess.run(["butler", "--json", *arguments], stdin=subprocess.DEVNULL,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=timeout)
    if result.returncode:
        raise RuntimeError("Butler command failed. Check key permissions/itch service; inspect the channel before retrying. Raw output suppressed to protect credentials.")
    return parse_result(result.stdout)


def channel(status):
    if status.get("target") != TARGET.split(":")[0]:
        raise ValueError("Unexpected itch project in status")
    matches = [c for c in status.get("channels", []) if c.get("name") == "html5"]
    if len(matches) != 1 or not matches[0].get("uploadId"):
        raise ValueError("Existing html5 upload was not found; refusing to create or replace another channel")
    return matches[0]


def check_previous(status, new_version, new_sha=None):
    current = channel(status)
    if current.get("pending"):
        raise ValueError("itch already has a pending build. Wait/review it before another release")
    head = current.get("head") or {}
    if head.get("state") != "completed":
        raise ValueError("itch channel has no completed baseline; review it before publishing")
    previous = head.get("userVersion", "")
    # Recognize legacy SemVer baselines (including 0.1.5-dev.1) and
    # project-specific hotfixes. Hotfix prerelease combinations stay invalid.
    sha_previous = re.fullmatch(f"v?({STABLE})-pre\\.([0-9a-f]{{8}})", previous)
    sha_new = re.fullmatch(f"({STABLE})-pre\\.([0-9a-f]{{8}})", new_version)
    match = re.fullmatch(f"v?({STABLE})(?:-({PRERELEASE}))?(?:\\+{BUILD_METADATA})?", previous)
    hotfix = re.fullmatch(f"v?({STABLE}[a-z])(?:\\+{BUILD_METADATA})?", previous)
    if not match and not hotfix and not sha_previous:
        raise ValueError("itch baseline has an empty/unrecognized userVersion. Confirm the live build and give it a normal version before enabling this release; no upload attempted")
    old = release_key((hotfix or sha_previous or match)[1])
    new = release_key(sha_new[1] if sha_new else new_version)
    is_prerelease = bool(sha_previous or (match is not None and match[2] is not None))
    if old > new or (old == new and not is_prerelease):
        raise ValueError("This version or a newer version is already on itch; refusing a duplicate or rollback")
    if sha_new:
        if not re.fullmatch(r'[0-9a-f]{40}', new_sha or '') or sha_new[2] != new_sha[:8]:
            raise ValueError('Prerelease must bind the exact qualified source')
        if sha_previous and old == new:
            # SHA is an opaque identity. Source ancestry prevents delayed older
            # tags from publishing after a newer prerelease in the same family.
            old_tag = 'refs/tags/v' + previous.removeprefix('v') + '^{commit}'
            old_sha = subprocess.check_output(['git', 'rev-parse', '--verify', old_tag], text=True).strip()
            if (not re.fullmatch(r'[0-9a-f]{40}', old_sha) or old_sha[:8] != sha_previous[2]
                    or old_sha == new_sha or subprocess.run(['git', 'merge-base', '--is-ancestor', old_sha, new_sha], capture_output=True).returncode):
                raise ValueError('Refusing duplicate, unrelated or older prerelease source')
    return head["id"]


def check_common_previous(status,new_version,new_sha):
    """New common route: all versions must move forward in immutable source."""
    baseline=check_previous(status,new_version,new_sha)
    previous=channel(status)['head']['userVersion'].removeprefix('v')
    # Unknown legacy labels cannot assert their compiled source. Inspect them;
    # do not interpret version text as an ancestry proof.
    if not re.fullmatch(RELEASE,previous):
        raise ValueError('Common publication needs an immutable known baseline tag')
    old_sha=subprocess.check_output(['git','rev-parse','--verify','refs/tags/v'+previous+'^{commit}'],text=True).strip()
    if (not re.fullmatch('[0-9a-f]{40}',old_sha) or old_sha==new_sha
            or subprocess.run(['git','merge-base','--is-ancestor',old_sha,new_sha],capture_output=True).returncode):
        raise ValueError('Refusing unrelated, duplicate or older common release source')
    return baseline


def verify_artifact(web, tag, sha):
    if not re.fullmatch("v" + RELEASE, tag) or not re.fullmatch(r"[0-9a-f]{40}", sha):
        raise ValueError("Expected a release version tag and exact commit SHA")
    manifest = json.loads((web / "release-manifest.json").read_text())
    if '-pre.' in tag and tag.rsplit('.', 1)[1] != sha[:8]:
        raise ValueError('Prerelease tag differs from exact source')
    if (manifest.get("source_commit") != sha or manifest.get("tag") != tag
            or manifest.get("version") != tag[1:] or manifest.get("packed_smoke") != "passed"
            or manifest.get("engine_checks", 0) <= 0
            or manifest.get("toolchain_verification") != "checksum-pinned-official-archives"):

        raise ValueError("Artifact provenance does not match this tested release")
    paths = {p.relative_to(web).as_posix() for p in web.rglob("*") if p.is_file()}
    if any(p.is_symlink() for p in web.rglob("*")):
        raise ValueError("Symlinks are not permitted in a release artifact")
    if paths != set(manifest["files"]) | {"release-manifest.json"}:
        raise ValueError("Artifact includes unexpected or missing files")
    for name, expected in manifest["files"].items():
        if Path(name).name != name or name.startswith("."):
            raise ValueError("Unexpected artifact path")
    verify_files(web, manifest['files'])
    for required in ["index.html", "index.js", "index.wasm", "index.pck"]:
        if required not in manifest["files"]:
            raise ValueError("Incomplete HTML5 export")
    return manifest


def completed(status, build_id, version):
    current = channel(status)
    for record in [current.get("head") or {}, current.get("pending") or {}]:
        if record.get("id") == build_id:
            if record.get("state") in {"failed", "cancelled", "canceled"}:
                raise RuntimeError("itch processing failed; inspect this build before retrying")
    head = current.get("head") or {}
    return head.get("id") == build_id and head.get("userVersion") == version and head.get("state") == "completed"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--web", required=True, type=Path)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--sha", required=True)
    parser.add_argument("--receipt", type=Path, help="Write only the confirmed completed publication")
    parser.add_argument("--common-receipt", type=Path, help="Already authenticated immutable common qualification")
    args = parser.parse_args()
    manifest = verify_artifact(args.web, args.tag, args.sha)
    common_path = getattr(args,'common_receipt',None)
    common = json.loads(common_path.read_text()) if common_path else None
    if common is not None:
        from release.common_tag import STATUS, valid_order
        if (common.get('status') != STATUS or common.get('source_commit') != args.sha
                or common.get('release_tag') != args.tag or common.get('version') != manifest['version']
                or common.get('web_manifest_sha256') != sha256(args.web/'release-manifest.json')
                or common.get('qualification') != manifest.get('release_reuse')
                or not valid_order(common.get('release_order'))):
            raise ValueError('Exact authenticated common qualification required')
    if not os.environ.get("BUTLER_API_KEY", "").strip():
        raise RuntimeError("Missing BUTLER_API_KEY. The owner must personally set GitHub Actions Secrets; never paste a key into chat or a commit")
    version = args.tag[1:]
    previous_status=butler("status", TARGET)
    if common is not None:check_common_previous(previous_status,version,args.sha)
    else:check_previous(previous_status,version,args.sha)
    # One attempt only. A timeout may have uploaded successfully; never retry blindly.
    result = butler("push", str(args.web), TARGET, "--userversion", version, "--no-auto-wrap")
    build_id = result.get("buildId")
    if (not isinstance(build_id, int) or build_id <= 0 or result.get("channel") != "html5"
            or result.get("dryRun") or result.get("skipped")):
        raise RuntimeError("Upload outcome is unconfirmed; inspect itch before retrying")
    print(f"Uploaded itch build {build_id}; waiting for processing", flush=True)
    deadline = time.monotonic() + 600
    while time.monotonic() < deadline:
        remaining = max(1, min(60, int(deadline - time.monotonic())))
        observed = butler("status", TARGET, timeout=remaining)
        if completed(observed, build_id, version):
            order = channel(observed)['head'].get('version')
            if '-pre.' in version and (type(order) is not int or not 0 < order <= 9007199254740991):
                raise RuntimeError('Completed upload lacks a confirmed channel sequence; inspect before retrying')
            receipt = {"target": TARGET, "version": version, "source_commit": args.sha,
                       "itch_build_id": build_id, "state": "completed",
                       "browser_runtime": "manual post-publish smoke still required"}
            if type(order) is int and 0 < order <= 9007199254740991:
                receipt['itch_channel_version'] = order
            if args.receipt:
                receipt.update(tag=args.tag, workflow_run=os.environ.get("GITHUB_RUN_ID"),
                    workflow_attempt=os.environ.get("GITHUB_RUN_ATTEMPT"),
                    release_manifest_sha256=sha256(args.web / "release-manifest.json"),
                    qualification=manifest.get("release_reuse"))
                if common is not None:
                    receipt['common_qualification'] = common
                args.receipt.parent.mkdir(parents=True, exist_ok=True)
                args.receipt.write_text(json.dumps(receipt, indent=2) + "\n")
            print(json.dumps(receipt), flush=True)
            if os.environ.get("GITHUB_STEP_SUMMARY"):
                with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as summary:
                    summary.write(f"Released {args.tag} ({args.sha}) to {TARGET}, itch build {build_id}.\n\nVerify https://siowyiyou.itch.io/little-leaf in a fresh browser profile, then a copied-save profile.\n")
            return
        time.sleep(15)
    raise RuntimeError(f"Build {build_id} uploaded but processing is still unconfirmed after 10 minutes. Check itch status before rerunning; do not assume the live game changed")


if __name__ == "__main__":
    main()
