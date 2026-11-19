"""Audit a one-session isolated six-arm renderer diagnostic; publish aggregates only."""
from __future__ import annotations

import argparse
import json
import math
import statistics as stats
from collections import Counter
from pathlib import Path

ARMS = ("FP", "HP", "FS", "HS", "FE", "HE")
BLOCKS = tuple(tuple(ARMS[(j + i) % 6] for j in (0, 1, 5, 2, 4, 3)) for i in range(6))
WARM, SAMPLE = 12, 36
SOURCE = "ce1435afb2329a6c1d2d77a8a19923dfd96bd205"
TREE = "03632a0d56e4294f5664859656c8809541766d1b"
ENGINE = "f64d4ed19fc9df9440321653fcc80df8c6e365ba7b6de0a29e2cfa9fa71bfeb3"
PUBLIC_SCHEMA = "ll-render-mechanism-397-summary-v1"

CONTRASTS = {
    "pixel_packed": ({"FP": 1, "HP": -1}, "FP"),
    "pixel_fragmented": ({"FS": 1, "HS": -1}, "FS"),
    "command_full": ({"FS": 1, "FP": -1}, "FP"),
    "command_half": ({"HS": 1, "HP": -1}, "HP"),
    "pixel_empty_floor": ({"FE": 1, "HE": -1}, "FE"),
    "pixel_packed_minus_empty": ({"FP": 1, "HP": -1, "FE": -1, "HE": 1}, "FP"),
    "pixel_fragmented_minus_empty": ({"FS": 1, "HS": -1, "FE": -1, "HE": 1}, "FS"),
    "pixel_by_command_interaction": ({"FS": 1, "HS": -1, "FP": -1, "HP": 1}, "FP"),
}
WALL_SCOPE = "exact #397 standalone wall geometry and retained ground; not the live #397 viewport"
PROOFS = frozenset((
    "main_absent", "same_root", "same_logical_rect", "same_ground_meshes",
    "same_shader", "same_expanded_triangles", "same_wall_slot_ids_per_size",
    "inactive_disabled", "full_rgba_equal", "half_rgba_equal",
    "full_layers_visible", "half_layers_visible", "bounds_match", "redraw_verified",
))
SLOTS, TRIANGLES = 84, 660
WALL_FIXED = "55abd21e9305293539b88327c9cd1b3dbc46d5a38fe44f77664243851cb42490"


class Invalid(ValueError):
    pass

def need(condition, code):
    if not condition:
        raise Invalid(code)

def ms(usec):
    return round(usec / 1000, 4)

def sign(x):
    return (x > 0) - (x < 0)

def q95(xs):
    return sorted(xs)[math.ceil(len(xs) * .95) - 1]

def describe(xs):
    return {"n": len(xs), "median_ms": ms(stats.median(xs)), "p95_ms": ms(q95(xs))}

def contrasts(blocks, field, dimension, command_ok, fragmented_size_ok):
    medians = [{k: stats.median(block[k][field]) for k in ARMS} for block in blocks]
    tails = [{k: q95(block[k][field]) for k in ARMS} for block in blocks]
    out = {}
    for key, (weights, reference) in CONTRASTS.items():
        # Command and interaction contrasts lose causal interpretation if batching
        # collapses the command intervention. Preserve the packed/empty pixel test.
        if not command_ok and (key.startswith("command_") or key == "pixel_by_command_interaction"):
            out[key] = {"status": "command_lever_not_exercised"}
            continue
        if not fragmented_size_ok and key in {"pixel_fragmented", "pixel_fragmented_minus_empty"}:
            out[key] = {"status": "size_changes_fragmented_draw_calls"}
            continue
        mids = [sum(w*b[a] for a,w in weights.items()) for b in medians]
        p95s = [sum(w*b[a] for a,w in weights.items()) for b in tails]
        effect = stats.median(mids)
        direction = sign(effect)
        same = sum(sign(x) == direction for x in mids) if direction else 0
        tail_direction = sign(stats.median(p95s))
        contradictory = bool(direction and tail_direction == -direction)
        threshold = max(500, .1 * stats.median(b[reference] for b in medians))
        qualifies = bool(direction and same >= 5 and abs(effect) >= threshold and not contradictory)
        status = "same_sign_and_threshold" if qualifies else "mixed_or_below_threshold"
        if dimension != "draw":
            status = "paced_interval_context_only"
        out[key] = {
            "status": status, "median_block_effect_ms": ms(effect),
            "signed_block_effects_ms": list(map(ms,mids)), "block_signs": list(map(sign,mids)),
            "min_block_effect_ms": ms(min(mids)), "max_block_effect_ms": ms(max(mids)),
            "same_sign_blocks": same, "magnitude_threshold_ms": ms(threshold),
            "block_p95_differences_ms": list(map(ms,p95s)),
            "median_block_p95_difference_ms": ms(stats.median(p95s)),
            "contradictory_p95_veto": contradictory,
        }
    return out

def is_int(x, lo=0, hi=10**9):
    return type(x) is int and lo <= x <= hi

def is_digest(x):
    return isinstance(x,str) and len(x)==64 and all(c in "0123456789abcdef" for c in x)

def validate_windows(raw, states):
    rows=raw["blocks"]
    need(type(rows) is list and len(rows)==6,"block_count")
    blocks=[]
    for expected, observations in zip(BLOCKS, rows):
        need(type(observations) is list and len(observations)==6,"block_count")
        need(tuple(a["state"] for a in observations)==expected,"williams_order")
        block={}
        for row in observations:
            code=row["state"]
            for field in ("draw_us", "interval_us"):
                xs=row[field]
                need(type(xs) is list and len(xs)==SAMPLE and all(is_int(x,1,10**7) for x in xs),"window_samples")
            need(all(y>=x for x,y in zip(row["draw_us"],row["interval_us"])),"elapsed_order")
            for k in ("primitive_count","draw_calls"):
                need(is_int(row[k]) and row[k]==states[code][k], "counter_drift")
            need(is_int(row.get("warm_frames"),WARM,WARM) and is_int(row.get("sample_frames"),SAMPLE,SAMPLE),"window_masks")
            block[code]=row
        blocks.append(block)
    return blocks

def validate_states(raw):
    states=raw["states"]
    need(type(states) is dict and set(states)==set(ARMS),"state_set")
    for key,row in states.items():
        need(is_int(row["width"]) and is_int(row["height"]) and (row["width"],row["height"])==((1360,880) if key[0]=="F" else (680,440)),"viewport_size")
        need(is_digest(row["rgba_sha256"]),"pixel_digest")
        need(all(is_int(row[f]) for f in ("primitive_count","draw_calls","wall_slots","wall_triangles")),"counter_shape")
        if key[-1]=="E":
            need(row["primitive_count"]==row["wall_slots"]==row["wall_triangles"]==0,"nonempty_floor")
        else:
            need(row["primitive_count"]>=TRIANGLES and row["draw_calls"]>0 and row["wall_slots"]==SLOTS and row["wall_triangles"]==TRIANGLES,"empty_active")
    for s in "FH":
        need(states[s+"P"]["rgba_sha256"]==states[s+"S"]["rgba_sha256"]!=states[s+"E"]["rgba_sha256"],"pixel_pair")
    for field in ("primitive_count","wall_slots","wall_triangles"):
        need(len({states[a][field] for a in ("FP","HP","FS","HS")})==1,"geometry_drift")
    need(states["FP"]["draw_calls"]==states["HP"]["draw_calls"],"size_confounds_packed_commands")
    fragmented_size_ok=states["FS"]["draw_calls"]==states["HS"]["draw_calls"]
    command_ok=fragmented_size_ok and all(states[s+"S"]["draw_calls"]>states[s+"P"]["draw_calls"] for s in "FH")
    return states,command_ok,fragmented_size_ok

def _pairs(pairs):
    result={}
    for key,value in pairs:
        need(key not in result,"invalid_shape")
        result[key]=value
    return result

def _invalid_number(_):
    raise Invalid("invalid_shape")

def discoveries(diffs,command_ok):
    def follow(key):
        return diffs[key].get("status")=="same_sign_and_threshold"
    packed=follow("pixel_packed") and follow("pixel_packed_minus_empty")
    split=follow("pixel_fragmented") and follow("pixel_fragmented_minus_empty")
    def direction_matches(a,b):
        return sign(diffs[a]["median_block_effect_ms"])==sign(diffs[b]["median_block_effect_ms"])
    packed=packed and direction_matches("pixel_packed","pixel_packed_minus_empty")
    split=split and direction_matches("pixel_fragmented","pixel_fragmented_minus_empty")
    command=command_ok and follow("command_full") and follow("command_half") and direction_matches("command_full","command_half")
    return {
        "packed_pixel_lever_beyond_empty":packed,
        "fragmented_pixel_lever_beyond_empty":split,
        "command_lever_exercised":command_ok,
        "command_lever_consistent_both_sizes":command,
        "decision":"isolated_followup_only" if packed or split or command else "mixed_or_unresolved",
    }

def verify_proof(raw, wall_sha, fixture_sha):
    need(wall_sha==WALL_FIXED and is_digest(fixture_sha), "external_binding")
    need(raw["wall_sha256"]==wall_sha and raw["fixture_sha256"]==fixture_sha, "probe_binding")
    need(raw["renderer_class"]=="X11_llvmpipe_compatibility" and is_int(raw["vsync_mode"],0,3),"renderer")
    proofs=raw["proofs"]
    need(type(proofs) is dict and set(proofs)==PROOFS and all(x is True for x in proofs.values()), "proofs")

def summarize(raw, wall_sha, fixture_sha):
    need(raw["schema"]=="ll-render-mechanism-397-v1","schema")
    need(raw["source"]=={"commit":SOURCE,"tree":TREE},"source")
    need(is_int(raw["engine_cap"],60,60) and is_int(raw["warm_frames"],WARM,WARM) and is_int(raw["sample_frames"],SAMPLE,SAMPLE),"window_masks")
    states,command_ok,fragmented_size_ok=validate_states(raw)
    verify_proof(raw,wall_sha,fixture_sha)
    blocks=validate_windows(raw,states)
    arm_summary={a:{f:describe([x for b in blocks for x in b[a][key]])
                    for f,key in (("pre_to_post","draw_us"),("inter_post","interval_us"))} for a in ARMS}
    main=contrasts(blocks,"draw_us","draw",command_ok,fragmented_size_ok)
    return {
        "schema":PUBLIC_SCHEMA,
        "status":"valid" if command_ok else "partial_pixel_only_command_not_exercised",
        "commit":SOURCE, "tree":TREE, "engine_sha256":ENGINE,
        "scope":WALL_SCOPE,
        "wall_sha256":wall_sha, "fixture_sha256":fixture_sha, "vsync_mode":raw["vsync_mode"], "verified_proofs":sorted(PROOFS),
        "scenario":"Isolated retained ground and walls; X11 software GL llvmpipe; 1360×880 root; 60 cap unchanged",
        "arm_summary":arm_summary,
        "states":{k:{f:v[f] for f in ("width","height","primitive_count","draw_calls","wall_slots","wall_triangles","rgba_sha256")} for k,v in states.items()},
        "pre_to_post_contrasts":main,
        "inter_post_contrasts":contrasts(blocks,"interval_us","cadence",command_ok,fragmented_size_ok),
        "interpretation":discoveries(main,command_ok),
        "limitations":"No full-game or displayed FPS. Pre→post elapsed mixes rendering, driver and waits; empty floor still includes engine, driver and root work. Contrasts and interactions are isolated, not components of historical #397 frame time. Inter-post may be paced by cap or VSync.",
        "windows":{"schedule":"six Williams counterbalanced blocks","warm_draws_per_arm":WARM,"measured_draws_per_arm":SAMPLE},
        "sample_p95_definition":"Nearest-rank within each arm; contrast veto checks median block p95 difference sign, never a subtraction of independent global quantiles.",
    }

def publish(private, out, wall_sha, fixture_sha):
    try:
        need(private.stat().st_size<=1_500_000,"invalid_shape")
        raw=json.loads(private.read_text(),object_pairs_hook=_pairs,parse_constant=_invalid_number)
        receipt=summarize(raw,wall_sha,fixture_sha)
    except Invalid as exc:
        receipt={"schema":PUBLIC_SCHEMA,"status":"not_qualified","stage":str(exc),"measurements_published":False}
    except (AttributeError,KeyError,IndexError,TypeError,ValueError,OSError):
        receipt={"schema":PUBLIC_SCHEMA,"status":"not_qualified","stage":"invalid_shape","measurements_published":False}
    data=json.dumps(receipt,sort_keys=True,indent=2,allow_nan=False)+"\n"
    need(len(data)<32768,"output_bound")
    out.write_text(data)
    return 2 if receipt["status"]=="not_qualified" else 0

if __name__=="__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("private",type=Path)
    parser.add_argument("output",type=Path)
    parser.add_argument("--wall-sha256",required=True)
    parser.add_argument("--fixture-sha256",required=True)
    args=parser.parse_args()
    raise SystemExit(publish(args.private,args.output,args.wall_sha256,args.fixture_sha256))
