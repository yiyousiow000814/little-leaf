"""Fail closed; sanitizes an isolated run, never emits raw GL/host/log/readback values."""
import argparse
import json
from pathlib import Path
import re
import sys


FIXTURE = "388527b937e67df65e55cbee3b6f88c56b42d2aae9d6b82584d64a3a2825e273"


def require(ok, reason):
    if not ok:
        raise ValueError(reason)


def constant_positive(values):
    return isinstance(values, list) and len(values) == 5 and all(type(v) is int and v > 0 and v == values[0] for v in values)


def report(raw):
    require(raw.get("schema") == "wall-fixed-canvas-counter-v1", "schema_mismatch")
    require(raw.get("fixture_sha256") == FIXTURE, "fixture_identity")
    require(raw.get("status") == "observed", "no_native_observation")
    require(raw.get("renderer_class") == "llvmpipe" and raw.get("rendering_method") == "gl_compatibility" and raw.get("size") == [1360, 880], "native_envelope")
    arms = raw.get("arms")
    require(isinstance(arms, list) and len(arms) == 4, "arm_count")
    for arm, label, planned in zip(arms, ("control", "packed") * 2, (330, 84) * 2):
        require(isinstance(arm, dict) and arm.get("arm") == label and arm.get("committed_commands") == planned, "arm_submission")
        require(arm.get("visible") is True and isinstance(arm.get("rgba_sha256"), str) and re.fullmatch(r"[0-9a-f]{64}", arm["rgba_sha256"]) is not None, "framebuffer_coverage")
        require(constant_positive(arm.get("calls")) and constant_positive(arm.get("primitives")), "unstable_or_missing_native_counter")
    require(len({a["rgba_sha256"] for a in arms}) == 1, "wall_framebuffer_changed")
    require(len({a["primitives"][0] for a in arms}) == 1, "native_primitive_counter_changed")
    require(arms[0]["calls"] == arms[2]["calls"] and arms[1]["calls"] == arms[3]["calls"], "counter_not_repeatable")
    control, packed = (a["calls"][0] for a in arms[:2])
    require(packed < control, "packed_path_not_distinguished_by_native_counter")
    return {
        "scope": "Isolated wall-only stock Godot 4.6.3 GL Compatibility SubViewport: native software renderer statistics; not GL trace, timing, game or Web parity",
        "fixture_sha256": FIXTURE,
        "renderer_class":"llvmpipe",
        "dimensions":[1360,880],
        "paired_repeats":2,
        "frames_per_arm":5,
        "canvas_commands":{"control":330, "packed":84},
        "canvas_draw_calls_in_frame":{"control":control,"packed":packed},
        "canvas_primitives_in_frame":arms[0]["primitives"][0],
        "rgba_bytes_identical":True,
    }


def main():
    a = argparse.ArgumentParser()
    a.add_argument("private", type=Path)
    args = a.parse_args()
    try:
        summary = report(json.loads(args.private.read_text()))
    except (OSError, KeyError, TypeError, IndexError, AttributeError, ValueError) as e:
        # Never print exceptions that could include input values.
        code = e.args[0] if type(e) is ValueError and len(e.args) == 1 and e.args[0] in KNOWN else "malformed_native_evidence"
        print(json.dumps({"status":"inconclusive","reason":code}), file=sys.stderr)
        return 4
    print(json.dumps(summary, indent=2))
    return 0


KNOWN = {"schema_mismatch","fixture_identity","no_native_observation","native_envelope","arm_count","arm_submission","framebuffer_coverage","unstable_or_missing_native_counter","wall_framebuffer_changed","native_primitive_counter_changed","counter_not_repeatable","packed_path_not_distinguished_by_native_counter"}
if __name__ == "__main__":
    raise SystemExit(main())
