"""Bound, scrub and analyze the #397 active-scene forced-draw diagnostic."""
import argparse
import json
import math
import statistics
from pathlib import Path

RAW="ll-active-backdrop-397-v1"
FAIL="ll-active-backdrop-failure-397-v1"
PUBLIC="ll-backdrop-gain-397-summary-v1"
COMMIT="ce1435afb2329a6c1d2d77a8a19923dfd96bd205"
TREE="03632a0d56e4294f5664859656c8809541766d1b"
ENGINE="f64d4ed19fc9df9440321653fcc80df8c6e365ba7b6de0a29e2cfa9fa71bfeb3"
WARM,COUNT,BLOCKS=2,8,6
SIZE=(1360,880)
ORDERS=[("original","cache","cache","original"),("cache","original","original","cache")]*3

class Invalid(ValueError):
    pass

def need(ok,code):
    if not ok:
        raise Invalid(code)

def integer(x,lo,hi):
    return type(x) is int and lo<=x<=hi

def sha(x):
    return isinstance(x,str) and len(x)==64 and all(c in "0123456789abcdef" for c in x)

def ms(x):
    return round(x/1000,4)

def check_counters(values):
    need(set(values)=={"primitive_count","draw_calls"} and
         all(integer(values[k],1,10**9) for k in values),"counter_shape")
    return values

def q95(xs):
    return sorted(xs)[math.ceil(.95*len(xs))-1]

def compare(blocks):
    def center(block,name,agg):
        return statistics.median([agg(w["draw_us"]) for w in block if w["arm"]==name])
    natural=[center(b,"original",statistics.median) for b in blocks]
    cached=[center(b,"cache",statistics.median) for b in blocks]
    effects=[r-c for r,c in zip(natural,cached)]
    tails=[center(b,"original",q95)-center(b,"cache",q95) for b in blocks]
    baseline=statistics.median(natural)
    absolute=statistics.median(effects)
    tail=statistics.median(tails)
    minimum=max(500,.1*baseline)
    wins=sum(x>0 for x in effects)
    good=wins>=5 and absolute>=minimum and tail>=0
    arms={}
    for a in ("original","cache"):
        xs=[v for b in blocks for w in b if w["arm"]==a for v in w["draw_us"]]
        arms[a]={"n":len(xs),"median_ms":ms(statistics.median(xs)),"p95_ms":ms(q95(xs))}
    return absolute,good,{
        "arms":arms,
        "block_effects_ms":list(map(ms,effects)),
        "block_signs":[(v>0)-(v<0) for v in effects],
        "blocks_with_positive_gain":wins,
        "median_original_block_ms":ms(baseline),
        "median_effect_ms":ms(absolute),
        "percent_of_median_original":round(absolute/baseline*100,4),
        "minimum_effect_ms":ms(minimum),
        "block_window_p95_differences_ms":list(map(ms,tails)),
        "median_paired_p95_difference_ms":ms(tail),
        "p95_veto":tail<0,
        "meets_preregistered_steady_threshold":good,
        "method":"Original minus cache. Per block: median of two original window medians minus median of two cached window medians. Side p95s pool all windows. The paired p95 veto compares within-window nearest ranks (max of eight draws per window), not pooled p95s.",
    }

def validate_blocks(blocks,steady):
    need(type(blocks) is list and len(blocks)==BLOCKS,"block_count")
    for got,expected in zip(blocks,ORDERS):
        need(type(got) is list and len(got)==4 and tuple(x["arm"] for x in got)==expected,"block_order")
        for row in got:
            need(integer(row["warm_draws"],WARM,WARM) and integer(row["sample_draws"],COUNT,COUNT),"window_masks")
            xs=row["draw_us"]
            need(type(xs) is list and len(xs)==COUNT and all(integer(x,1,2_000_000) for x in xs),"draw_samples")
            k=check_counters({key:row[key] for key in ("primitive_count","draw_calls")})
            need(k==steady[row["arm"]],"counter_drift")

def break_even(delta,good,bakes,observations):
    if not good or delta<=0:
        return {"available":False,"reason":"No qualifying steady-state saving."}
    # Full bake prices are charged against the observed paired median
    # effect, not treated as incremental or an empirically proven lower bound.
    hits={k:math.ceil(v["wall_us"]/delta) for k,v in bakes.items()}
    worst=max(hits.values())
    projected_observations={
        k:(math.ceil(worst*v["draw_updates"]/v["hits"]) if v["hits"] else None)
        for k,v in observations.items()
    }
    return {"available":True,
            "valid_cache_hit_draws_at_paired_median":hits,
            "worst_observed_bake_hit_draws_at_paired_median":worst,
            "forced_draw_equivalents_if_observed_redraw_fractions_persist":projected_observations,
            "conditions":"Projection only; assumes each later valid hit saves the measured paired median and misses add no other cost. Total draws to each next invalidation must provide this many hits (required total ≈ hits / hit fraction); ratios from short controlled redrawing windows are not representative hit rates. Null means no hits there; no universal break-even."}

CHECKPOINTS={"settled":SIZE,"pan":SIZE,"resize":(1280,820),"restored":SIZE}
BAKES={"first":SIZE,"pan":SIZE,"resize":(1280,820),"restored":SIZE}
PROOFS=frozenset(("same_logical_instant_each_pair","exact_root_rgba","positive_root_sensitivity",
    "restored_home_projection","restored_new_generation","unsupported_canvas_effects_absent","pan_cache_miss","resize_cache_miss","producer_opaque",
    "exact_one_pre_and_post_per_draw","no_readback_in_steady_samples",
    "matched_target_class","original_repeat_exact","prefix_conservation","exact_one_pre_and_post_per_bake",
    "pan_fallback_exact","resize_fallback_exact","restored_fallback_exact"))
TARGET_CLASS_KEYS=frozenset(("producer_transparent","root_transparent","producer_hdr","root_hdr"))
PROBE_FAILURES=frozenset(("adapter","arm_unstable","first_bake","gate_env","natural_observation",
    "pan_bake","pan_miss","pan_parity","resize_bake","resize_miss","resize_parity",
    "restore_bake","restore_miss","restore_parity","scene_wait","settled_key","settled_parity"))

DETAIL_CODES=frozenset((
    "draw_events","root_target_changed","target_class_or_size","readback_empty","readback_size","readback_format",
    "readback_length","readback_format_changed","repeat_counters","sentinel_region","original_selection",
    "original_counters","canvas_admission","hit_selection","primitive_conservation","restore_selection",
    "scene_advanced","digest","fallback_selection","bake_rejected","bake_events","bake_accounting",
    "bake_producer_state","bake_opacity","sentinel_restore_pixels","original_repeat_pixels","cache_pixels",
    "restore_pixels","fallback_pixels","bake_restore_pixels",
))
PIXEL_FAILURES=frozenset(("sentinel_region","sentinel_restore_pixels","original_repeat_pixels","cache_pixels",
    "restore_pixels","fallback_pixels","bake_restore_pixels"))
PIXELS=SIZE[0]*SIZE[1]
DIFF_KEYS=frozenset(("changed","rgb_changed","alpha_changed","alpha_only","one_lsb",
    "outside_sentinel","outside_sentinel_flipped","max_byte_delta","quadrants"))

def bounded_diff(row, pixels=PIXELS):
    need(type(row) is dict and set(row)==DIFF_KEYS,"failure_diff")
    need(all(integer(row[k],0,pixels) for k in DIFF_KEYS-{"max_byte_delta","quadrants"})
      and integer(row["max_byte_delta"],0,255),"failure_diff")
    quads=row["quadrants"]
    need(type(quads) is list and len(quads)==4 and all(integer(n,0,pixels//4) for n in quads)
      and sum(quads)==row["changed"]==row["rgb_changed"]+row["alpha_only"]
      and row["alpha_only"]<=row["alpha_changed"]<=row["changed"]
      and row["one_lsb"]<=row["changed"]
      and row["outside_sentinel"]<=row["changed"] and row["outside_sentinel_flipped"]<=row["changed"]
      and (row["max_byte_delta"]==0)==(row["changed"]==0),"failure_diff")
    return {k:row[k] for k in DIFF_KEYS}

def bounded_failure_counters(row):
    need(type(row) is dict and bool(row) and set(row)<={"original","cache","restored","prefix_primitives"},"failure_counters")
    result={}
    for key,value in row.items():
        if key=="prefix_primitives":
            need(integer(value,0,10**9),"failure_counters")
        else:
            need(type(value) is dict and set(value)=={"primitive_count","draw_calls"}
              and all(integer(v,0,10**9) for v in value.values()),"failure_counters")
        result[key]=value
    return result

def summarize(raw, commit, tree, engine, probe, adapter):
    need((commit,tree,engine)==(COMMIT,TREE,ENGINE) and sha(probe) and sha(adapter),"source_binding")
    need(raw["schema"]==RAW,"schema")
    need(set(raw)=={"schema","passes","bakes","blocks","observations","final_witness","policies","proofs","target_class"},"unexpected_success_fields")
    target_class=raw["target_class"]
    need(type(target_class) is dict and set(target_class)==TARGET_CLASS_KEYS and
          all(v is False for v in target_class.values()),"target_class")
    policies=raw["policies"]
    expected={"cap":60,"closed_loop_swap":False,"frame_step_arg":0,
              "rendering_server_force_sync":True,"natural_fps":False}
    need(set(policies)==set(expected)|{"unchanged_vsync"} and integer(policies["unchanged_vsync"],0,3)
      and all(type(policies[k]) is bool and policies[k] is v if type(v) is bool
              else type(policies[k]) in (int,float) and policies[k]==v for k,v in expected.items()),"policy")
    need(set(raw["proofs"])==PROOFS and all(v is True for v in raw["proofs"].values()),"proofs")
    passes=raw["passes"]
    need(set(passes)==set(CHECKPOINTS),"checkpoint_set")
    public_checks={}
    for label, (w,h) in CHECKPOINTS.items():
        p=passes[label]
        need(integer(p["width"],w,w) and integer(p["height"],h,h) and sha(p["rgba_sha256"]),"checkpoint_receipt")
        before=check_counters(p["original"]);after=check_counters(p["cache"])
        repeat=check_counters(p["original_repeat"]);restored=check_counters(p["restored"])
        need(repeat==restored==before and p["original_repeat_equal"] is True and p["restored_equal"] is True,
             "original_counter_or_parity")
        prefix=p["prefix_primitives"]
        need(integer(prefix,3,10**9) and before["primitive_count"]-after["primitive_count"]==prefix-2,"counter_confound")
        # Do not publish image digest, view state, camera transforms or snapshot identity.
        public_checks[label]={"size":[w,h],"exact_root_rgba":True,"original":before,"cache":after,"prefix_primitives":prefix,
                              "original_repeat_matches":True,"restored_original_matches":True,
                              "primitives_removed":before["primitive_count"]-after["primitive_count"]}
    bakes=raw["bakes"]
    need(set(bakes)==set(BAKES),"bake_set")
    peak=SIZE[0]*SIZE[1]*4
    for label,(w,h) in BAKES.items():
        value=bakes[label]
        need(integer(value["wall_us"],1,60_000_000) and integer(value["pixel_bytes"],w*h*4,w*h*4),"bake_receipt")
        need(value["unchanged_by_bake"] is True,"bake_original_parity")
    final=raw["final_witness"]
    need(integer(final["bakes"],4,4) and final["selected"] is False and final["producer_disabled"] is True
         and integer(final["pixel_bytes"],peak,peak),"final_witness")
    observed=raw["observations"]
    need(set(observed)=={"stationary","camera_pan_including_fractional"},"observation_set")
    observation_public={}
    for name in ("stationary","camera_pan_including_fractional"):
        o=observed[name]
        need(set(o)=={"changes","draw_updates","eligible_updates","process_frames","hits","misses"} and
             integer(o["changes"],0 if name=="stationary" else 1,0 if name=="stationary" else 10**7) and
             integer(o["draw_updates"],1,10**7) and integer(o["process_frames"],1,10**7) and
             integer(o["eligible_updates"],0,o["draw_updates"]) and
             integer(o["hits"],0,o["eligible_updates"]) and integer(o["misses"],0,o["draw_updates"]) and
             o["hits"]+o["misses"]==o["draw_updates"] and
             (o["hits"]==o["eligible_updates"]==o["draw_updates"] if name=="stationary" else o["misses"]>0),"observation_receipt")
        observation_public[name]={**o,"eligible_redraw_fraction":round(o["eligible_updates"]/o["draw_updates"],4),
             "observed_cache_hit_fraction":round(o["hits"]/o["draw_updates"],4)}
    blocks=raw["blocks"]
    validate_blocks(blocks,passes["restored"])
    delta,good,timing=compare(blocks)
    return {"schema":PUBLIC,"status":"valid","commit":commit,"tree":tree,"engine_sha256":engine,
            "probe_sha256":probe,"adapter_sha256":adapter,
            "scope":"Standalone experiment inside the #397 synthetic active-cooking scene; X11 Mesa llvmpipe Compatibility, one tracked cooking guest fixture. No player data.",
            "timing":"Elapsed full-root retained redraw: stock force_draw(false, 0) plus force_sync, including callbacks, rendering, driver waits and the Compatibility glFinish instead of swap. Source scene does not advance; only the restored checkpoint is timed. 60 cap and VSync remain configured but normal pacing and gameplay updates are bypassed. This is neither natural cadence, physical presentation FPS nor GPU-only time.",
            "layout":{"blocks":BLOCKS,"counterbalance":"ABBA/BAAB alternating","warm_per_window":WARM,"draws_per_window":COUNT},
            "checkpoints":public_checks,
            "proofs_verified":sorted(PROOFS), "matched_target_class":target_class,
            "draw_timing":timing,
            "bakes":{"first_and_rebuild_envelope_ms":{k:ms(v["wall_us"]) for k,v in bakes.items()},
                     "base_storage_bytes_by_checkpoint":{k:w*h*8 for k,(w,h) in BAKES.items()},
                     "peak_native_color_plus_depth_bytes":peak*2,
                     "peak_native_color_plus_depth_mib":round(peak*2/2**20,2),
                     "storage_scope":"Pinned GLES3 Compatibility opaque non-HDR target uses RGB10_A2 color (4 bytes/pixel) plus DEPTH24_STENCIL8 (4 bytes/pixel). Exposed image readback is RGBA8; that is not the native color format. This is base attachment storage, not peak/resident memory; staging, padding, transitions, readbacks and driver overhead are additional.",
                     "scope":"Full first/rebuild wall-time envelope includes setup, the stock original root rendered alongside the producer, and synchronization. Explicit CPU pixel readback and parity checks are outside this window. No incremental bake-only cost was measured."},
            "projected_break_even":break_even(delta,good,bakes,observation_public),
            "eligibility_observation":{"counts":observation_public,
                                       "scope":"Short scripted natural redraw windows after the first cache bake. Cache eligibility alone is not a hit. Observed hit/miss deltas are not representative of player behavior; incremental miss/rebake cost is unmeasured."},
            "decision":"isolated_followup_only" if good else "valid_below_threshold_or_regression",
            "not_claimed":"No production patch, game or moving FPS, driver-cost isolation, frame budget, historical attribution, or payback guarantee."}

def pairs(items):
    out={}
    for k,v in items:
        need(k not in out,"invalid_shape")
        out[k]=v
    return out

def nonfinite(_):
    raise Invalid("invalid_shape")

def finite_float(token):
    value=float(token)
    need(math.isfinite(value),"invalid_shape")
    return value

def safe_failure(stage, detail=None, diagnostics=None):
    result={"schema":PUBLIC,"status":"not_qualified","stage":stage,"measurements_published":False}
    if detail is not None: result["detail_code"]=detail
    if diagnostics: result["bounded_diagnostics"]=diagnostics
    return result

def publish(private,output,*binding):
    try:
        need(private.stat().st_size<=1_000_000,"invalid_shape")
        raw=json.loads(private.read_text(),object_pairs_hook=pairs,parse_constant=nonfinite,parse_float=finite_float)
        if raw.get("schema")==FAIL:
            stage=raw.get("stage_code")
            need(isinstance(stage,str) and stage in PROBE_FAILURES,"unclassified_probe_failure")
            # Never propagate unknown metadata even when the fixed stage is valid.
            detail=raw.get("detail_code")
            need(detail is None or isinstance(detail,str) and detail in DETAIL_CODES,"unclassified_probe_detail")
            clean={}
            if "diff" in raw:
                need(detail in PIXEL_FAILURES,"failure_diff")
                # resize_miss expects the small target; restore_miss expects the native target.
                pixels=1280*820 if stage in {"resize_bake","resize_parity","resize_miss"} else PIXELS
                clean["diff"]=bounded_diff(raw["diff"],pixels)
            if "counters" in raw:
                clean["counters"]=bounded_failure_counters(raw["counters"])
            value=safe_failure(stage,detail,clean)
        else:
            value=summarize(raw,*binding)
    except Invalid as exc:
        value=safe_failure(str(exc))
    except (AttributeError,KeyError,TypeError,ValueError,IndexError,OSError):
        value=safe_failure("invalid_shape")
    data=json.dumps(value,sort_keys=True,indent=2,allow_nan=False)+"\n"
    need(len(data)<16384,"summary_size")
    output.write_text(data)
    return 0 if value["status"]=="valid" else 2

if __name__=="__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("private",type=Path)
    parser.add_argument("output",type=Path)
    parser.add_argument("--expected-commit",required=True)
    parser.add_argument("--expected-tree",required=True)
    parser.add_argument("--engine-sha256",required=True)
    parser.add_argument("--probe-sha256",required=True)
    parser.add_argument("--adapter-sha256",required=True)
    a=parser.parse_args()
    raise SystemExit(publish(a.private,a.output,a.expected_commit,a.expected_tree,a.engine_sha256,a.probe_sha256,a.adapter_sha256))
