#!/usr/bin/env python3
"""Run unchanged wall parity and original-three qualification on a bound candidate.

Only the historical input binding is replaced; rendering, PNG decoders, proofs and
qualification routines come from the identical committed source in both revisions.
This driver deliberately does not adopt or update any atlas manifest.
"""
import argparse
import hashlib
import importlib.util
import json
import re
import subprocess
import sys
from pathlib import Path

sys.dont_write_bytecode = True
FIXTURE = "tests/diagnostics/capture_wall_retention.gd"
FIXTURE_SHA = "1d3fb8805a40dfcc37515386415ff9b4b08c7e32fa137925fb20442cd7748fcc"
REUSED = (
    "tools/diagnostics/wall_retention_native.py",
    "tools/diagnostics/wall_atlas_qualification.py",
    "tools/diagnostics/storage_native_review.py",
    "tools/qualification/verify_prebaked_atlases.py",
    "tools/build/project_layout.py",
    "tools/ci/toolchain.json",
    FIXTURE,
)
MANIFEST = "game/data/prebaked_atlas_manifest.json"
NAMES = ("furniture", "moving", "heads")


def require(test, reason):
    if not test:
        raise ValueError(reason)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args])


def path_ok(s):
    return isinstance(s, str) and re.fullmatch(r"[a-zA-Z0-9_./-]+", s) and not s.startswith("/") and all(
        piece not in ("", ".", "..") for piece in s.split("/")
    )


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    sys.modules[name] = value
    spec.loader.exec_module(value)
    return value


def closure_delta(current, fixed):
    return {
        "changed": sorted(k for k in current.keys() & fixed.keys() if current[k] != fixed[k]),
        "added": sorted(current.keys() - fixed.keys()),
        "removed": sorted(fixed.keys() - current.keys()),
    }


def load_binding(root, binding):
    for k in ("control", "control_tree", "candidate", "candidate_tree"):
        require(re.fullmatch(r"[0-9a-f]{40}", binding[k]), f"Immutable {k} is required")
    base, cand = binding["control"], binding["candidate"]
    require(base != cand, "Control may not equal candidate")
    for key in ("control", "candidate"):
        require(git(root, "rev-parse", binding[key] + "^{tree}").decode().strip() == binding[key + "_tree"],
                f"{key} tree does not match")
    require(git(root, "rev-parse", "HEAD").decode().strip() == cand, "Run against exact detached candidate HEAD")
    require(not git(root, "status", "--porcelain", "--untracked-files=all"), "Candidate checkout must be clean")
    require(subprocess.run(["git", "-C", str(root), "merge-base", "--is-ancestor", base, cand]).returncode == 0,
            "Bound control is not on candidate ancestry")
    expected = binding["reviewed_paths"]
    require(isinstance(expected, dict) and expected, "No reviewed paths")
    for path, digest in expected.items():
        require(path_ok(path) and re.fullmatch(r"[0-9a-f]{64}", digest), "Invalid reviewed path/hash")
        require(not (root / path).is_symlink() and (root / path).is_file(), f"Expected regular file {path}")
        require(sha(root / path) == digest, f"Unreviewed postimage {path}")
    tracked_diff = git(root, "diff", "--no-renames", "--name-only", "-z", base, cand).decode().split("\0")[:-1]
    require(set(tracked_diff) == expected.keys(), "Unexpected candidate delta")
    protected = REUSED + (MANIFEST,) + tuple(
        f"game/assets/cache/{name}-atlas.png{suffix}" for name in NAMES for suffix in ("", ".import")
    )
    for path in protected:
        require(path not in expected and (root / path).read_bytes() == git(root, "show", f"{base}:{path}"),
                f"Reference workflow, fixture, manifest or source image changed: {path}")
    require(sha(root / FIXTURE) == FIXTURE_SHA, "The original focused capture fixture is required")
    require(set(binding["closure_delta"]) == {"changed", "added", "removed"}, "Explicit producer delta required")
    for rows in binding["closure_delta"].values():
        require(isinstance(rows, list) and rows == sorted(set(rows)) and all(path_ok(p) for p in rows),
                "Producer paths must be unique, sorted and relative to game/")
    return base, cand


def verify_sources(root, binding):
    guard = module("ll_bound_atlas", root / "tools/qualification/verify_prebaked_atlases.py")
    manifest = json.loads((root / MANIFEST).read_text())
    fixed = manifest["source_sha256"]
    current = guard.sources()
    gotten = closure_delta(current, fixed)
    require(gotten == binding["closure_delta"], f"Unexpected producer delta: {gotten}")
    reviewed = binding["reviewed_paths"]
    require(all(current[k] == reviewed.get("game/" + k) for k in gotten["changed"] + gotten["added"]),
            "Producer postimage not explicitly reviewed")
    for name in NAMES:
        asset = guard.asset(name)
        require(all(manifest["atlases"][name][k] == v for k, v in asset.items()), f"Atlas import bytes changed: {name}")
    return {
        "producer_count": len(current), "producer_delta": gotten,
        "changed_producers": gotten["changed"], "source_closure_qualified": False,
        "manifest_changed": False, "atlas_regenerated": False,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--bind", type=Path, required=True)
    parser.add_argument("--lane", choices=("pixels", "atlas"), required=True)
    parser.add_argument("--godot", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    root = args.repo.resolve()
    binding = json.loads(args.bind.read_text())
    base, cand = load_binding(root, binding)
    closure = verify_sources(root, binding)
    native = module("wall_retention_native", root / "tools/diagnostics/wall_retention_native.py")
    # Replace only the historic commit-specific binding, not any rendering,
    # framing, isolation, decoding, parity or report code.
    native.BASE = base
    native.PRODUCTION = {k: v for k, v in binding["reviewed_paths"].items() if k.startswith(("game/", "platform/"))}
    native.verify_source = lambda: closure
    selected = native
    if args.lane == "atlas":
        selected = module("ll_bound_atlas_runner", root / "tools/diagnostics/wall_atlas_qualification.py")
        selected.PRODUCT = cand

        def atlas_verify():
            helpers = module("ll_bound_canonical_helpers", root / "tools/diagnostics/storage_native_review.py")
            for name, digest in helpers.HELPERS.items():
                require(sha(root / "tests/diagnostics/canonical_atlas" / name) == digest and
                        (root / "tests/diagnostics/canonical_atlas" / name).read_bytes()
                        == git(root, "show", f"{base}:tests/diagnostics/canonical_atlas/{name}"),
                        f"Canonical helper does not match pinned control: {name}")
            manifest = json.loads((root / MANIFEST).read_text())
            require(tuple(manifest["atlases"][n]["rgba_sha256"] for n in helpers.NAMES) == helpers.EXPECTED_RGBA,
                    "Fixed canonical RGBA references changed")
            return closure, helpers

        selected.verify = atlas_verify
    sys.argv = [sys.argv[0], "--expected-head", cand]
    if args.verify_only:
        sys.argv += ["--verify-only"]
    else:
        require(args.godot is not None and args.output is not None, "Engine and output required")
        sys.argv += ["--godot", str(args.godot.resolve()), "--output", str(args.output.resolve())]
    selected.main()


if __name__ == "__main__":
    main()
