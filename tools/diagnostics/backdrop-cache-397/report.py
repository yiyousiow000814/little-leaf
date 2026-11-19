"""Digest-only receipt for a bounded standalone native-resolution backdrop A/B test."""
from __future__ import annotations

import argparse
import json
import math
import statistics
from pathlib import Path

SOURCE = "ce1435afb2329a6c1d2d77a8a19923dfd96bd205"
TREE = "03632a0d56e4294f5664859656c8809541766d1b"
ENGINE = "f64d4ed19fc9df9440321653fcc80df8c6e365ba7b6de0a29e2cfa9fa71bfeb3"
WALL = "55abd21e9305293539b88327c9cd1b3dbc46d5a38fe44f77664243851cb42490"
WARM, SAMPLE = 12, 36
PUBLIC_SCHEMA = "ll-backdrop-cache-397-summary-v1"

class Invalid(ValueError):
    """Fixed safe code, never arbitrary exception output."""

def need(value, code):
    if not value:
        raise Invalid(code)

def is_int(value, lo=0, hi=10**9):
    return type(value) is int and lo <= value <= hi

def digest(value):
    return isinstance(value,str) and len(value)==64 and all(c in "0123456789abcdef" for c in value)

def ms(usec):
    return round(usec/1000,4)

def q95(xs):
    return sorted(xs)[math.ceil(len(xs)*.95)-1]

def sign(value):
    return (value>0)-(value<0)

def compare(blocks, old, new, field):
    """Compare observations within each block. Positive is lower elapsed when cached."""
    def center(windows, key, summary):
        xs=[summary(w[field]) for w in windows if w["state"]==key]
        need(len(xs)==2,"wrong_arm_count")
        return statistics.median(xs)
    originals=[center(b,old,statistics.median) for b in blocks]
    candidates=[center(b,new,statistics.median) for b in blocks]
    differences=[a-b for a,b in zip(originals,candidates)]
    tails=[center(b,old,q95)-center(b,new,q95) for b in blocks]
    median_old=statistics.median(originals)
    effect=statistics.median(differences)
    median_tail_delta=statistics.median(tails)
    threshold=max(500,median_old*.10)
    wins=sum(x>0 for x in differences)
    losses=sum(x<0 for x in differences)
    p95_veto=median_tail_delta<0
    passes=wins>=5 and effect>=threshold and not p95_veto
    return {
        "effect_direction": "original_minus_cached; positive is less elapsed when cached",
        "block_effects_ms": list(map(ms,differences)),
        "block_signs": list(map(sign,differences)),
        "median_paired_effect_ms": ms(effect), "median_of_original_blocks_ms": ms(median_old),
        "relative_to_original_pct": round(100*effect/median_old,4),
        "min_effect_ms": ms(min(differences)), "max_effect_ms": ms(max(differences)),
        "positive_blocks": wins, "negative_blocks": losses, "zero_blocks": len(blocks)-wins-losses,
        "block_p95_differences_ms": list(map(ms,tails)), "median_paired_p95_difference_ms": ms(median_tail_delta),
        "p95_veto": p95_veto, "minimum_effect_ms": ms(threshold),
        "status": "meets_preregistered_threshold" if passes else "not_qualified",
    }

def totals(blocks, old, new, fields):
    out={}
    for state in (old,new):
        out[state]={}
        for title, field in fields.items():
            xs=[value for b in blocks for w in b if w["state"]==state for value in w[field]]
            out[state][title]={"samples":len(xs),"median_ms":ms(statistics.median(xs)),"p95_ms":ms(q95(xs))}
    return out

def _pairs(pairs):
    result={}
    for k,v in pairs:
        need(k not in result,"invalid_shape")
        result[k]=v
    return result

def _invalid_number(_):
    raise Invalid("invalid_shape")

RAW_SCHEMA = "ll-backdrop-cache-397-v1"
PROOFS = frozenset((
    "main_absent","ground_opaque","exact_rgba","wall_rids_same",
    "producer_disabled_during_samples","native_nearest_1to1",
    "camera_miss_falls_back","moved_rebuild_rgba","restored_rgba","no_double_draw",
))
ORDERS = [tuple(s) for s in ("RCCR", "CRRC")*3]
TIMINGS = {"pre_to_post":"draw_us","inter_post":"interval_us"}

def summarize(raw,wall,mechanism,fixture):
    need(wall==WALL and digest(mechanism) and digest(fixture),"external_binding")
    need(raw["schema"]==RAW_SCHEMA,"schema")
    need(raw["source"]=={"commit":SOURCE,"tree":TREE},"source_binding")
    need((raw["wall_sha256"],raw["mechanism_sha256"],raw["fixture_sha256"])==(wall,mechanism,fixture),"diagnostic_binding")
    need(raw["renderer_class"]=="X11_llvmpipe_compatibility" and is_int(raw["vsync_mode"],0,3),"renderer")
    need(is_int(raw["engine_cap"],60,60),"cap")
    proofs=raw["proofs"]
    need(type(proofs) is dict and set(proofs)==PROOFS and all(v is True for v in proofs.values()),"parity_or_invalidation")
    def masks(v):
        return is_int(v["warm_frames"],WARM,WARM) and is_int(v["sample_frames"],SAMPLE,SAMPLE)
    need(masks(raw),"window_masks")
    states=raw["states"]
    need(type(states) is dict and set(states)=={"R","C"},"state_set")
    for a in states.values():
        need(is_int(a["primitive_count"],660) and is_int(a["draw_calls"],1),"invalid_counter")
        need(digest(a["rgba_sha256"]),"pixel_digest")
    need(states["R"]["rgba_sha256"]==states["C"]["rgba_sha256"],"pixel_parity")
    need(states["C"]["primitive_count"]==662 and states["R"]["primitive_count"]>662,"duplicate_ground_or_counter")
    blocks=raw["blocks"]
    need(type(blocks) is list and len(blocks)==6,"block_count")
    for b,expected in zip(blocks,ORDERS):
        need(type(b) is list and len(b)==4,"arm_count")
        need(tuple(w["state"] for w in b)==expected,"arm_order")
        for w in b:
            need(masks(w),"window_masks")
            for f in TIMINGS.values():
                xs=w[f]
                need(type(xs) is list and len(xs)==SAMPLE and all(is_int(x,1,10**7) for x in xs),"window_samples")
            need(all(i>=d for d,i in zip(w["draw_us"],w["interval_us"])),"elapsed_order")
            for k in ("primitive_count","draw_calls"):
                need(is_int(w[k]) and w[k]==states[w["state"]][k],"counter_drift")
    draw=compare(blocks,"R","C",TIMINGS["pre_to_post"])
    interval=compare(blocks,"R","C",TIMINGS["inter_post"])
    interval["status"]="paced_context_only"
    draw["median_paired_p95_sign"]=sign(draw["median_paired_p95_difference_ms"])
    decision=draw["status"]=="meets_preregistered_threshold"
    return {
        "schema":PUBLIC_SCHEMA,
        "status":"valid",
        "commit":SOURCE, "tree":TREE, "engine_sha256":ENGINE,
        "wall_sha256":wall, "mechanism_sha256":mechanism, "fixture_sha256":fixture,
        "scope":"Standalone exact #397 retained ground plus fixed packed wall fixture; no Main. Root and logical canvas 1360×880, X11 compatibility / llvmpipe, cap 60 throughout.",
        "vsync_mode":raw["vsync_mode"], "verified_proofs":sorted(PROOFS),
        "states":{k:{f:v[f] for f in ("primitive_count","draw_calls","rgba_sha256")} for k,v in states.items()},
        "labels":{"R":"Original retained ground canvas","C":"Cached native-resolution backdrop; producer disabled in sampled windows"},
        "windows":{"design":"ABBA/BAAB alternating","blocks":6,"warm_per_window":WARM,"counted_per_window":SAMPLE},
        "pooled_observations":totals(blocks,"R","C",TIMINGS),
        "pre_to_post":draw, "inter_post":interval,
        "practical_decision":"isolated_steady_state_followup_only" if decision else "inconclusive_or_below_preregistered_threshold",
        "limits":"Elapsed pre→post boundary includes rendering, driver and waits. Inter-post may be paced. No whole-game or physical presentation FPS, previous-frame attribution, or bake amortization. Wall path is unchanged and not a second counted intervention. No expected improvement is added to any other test.",
        "statistic":"Per block, median of two original window medians minus median of two cached window medians. p95 veto uses the same pairing for each window's nearest-rank p95; aggregate p95s are descriptive only.",
    }

def publish(private, output, wall, mechanism, fixture):
    try:
        need(private.stat().st_size<=1_000_000,"invalid_shape")
        raw=json.loads(private.read_text(),object_pairs_hook=_pairs,parse_constant=_invalid_number)
        receipt=summarize(raw,wall,mechanism,fixture)
    except Invalid as exc:
        receipt={"schema":PUBLIC_SCHEMA,"status":"not_qualified","stage":str(exc),"measurements_published":False}
    except (AttributeError,KeyError,IndexError,TypeError,ValueError,OSError):
        receipt={"schema":PUBLIC_SCHEMA,"status":"not_qualified","stage":"invalid_shape","measurements_published":False}
    data=json.dumps(receipt,sort_keys=True,indent=2,allow_nan=False)+"\n"
    need(len(data)<16384,"output_bound")
    output.write_text(data)
    return 2 if receipt["status"]=="not_qualified" else 0

if __name__=="__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("private",type=Path)
    parser.add_argument("output",type=Path)
    parser.add_argument("--wall-sha256",required=True)
    parser.add_argument("--mechanism-sha256",required=True)
    parser.add_argument("--fixture-sha256",required=True)
    args=parser.parse_args()
    raise SystemExit(publish(args.private,args.output,args.wall_sha256,args.mechanism_sha256,args.fixture_sha256))
