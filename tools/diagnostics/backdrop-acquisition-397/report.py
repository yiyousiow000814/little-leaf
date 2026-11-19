"""Fail-closed digest-only reporter for the #397 acquisition verification."""
from __future__ import annotations
import argparse
from fractions import Fraction
import json
import math
from pathlib import Path
import statistics as st

PROBE="ll397-acquire-private-v1"
PUBLIC="ll397-acquisition-summary-v1"
FAIL="ll-active-backdrop-failure-397-v1"
HEAD="ce1435afb2329a6c1d2d77a8a19923dfd96bd205"
TREE="03632a0d56e4294f5664859656c8809541766d1b"
ENGINE="f64d4ed19fc9df9440321653fcc80df8c6e365ba7b6de0a29e2cfa9fa71bfeb3"
PREFIX=139288
FRAME=(1360,880)
SMALL=(1280,820)
PRIOR_US=Fraction(68576,10)
LIVE_BOUND=5_000_000
FORCED_BOUND=2_000_000
LIVE_FLAGS={"process_frames_advanced","animation_advanced","service_progressed","same_guest_cooking",
            "warm_process_reuse","no_forced_draws_during_observation","no_readbacks_during_observation"}
ARM_FLAGS={"original_through_post","commit_after_post","producer_disabled","native_once_consumed"}
TIMES={"pre_to_post_us","post_interval_us"}

class Rejected(ValueError):
    pass

def need(yes,stage):
    if not yes: raise Rejected(stage)

def exact(values,fields,stage):
    need(type(values) is dict and set(values)==fields,stage)

def check_int(x,lo,hi,stage):
    need(type(x) is int and lo<=x<=hi,stage)
    return x

def digest(x):
    return isinstance(x,str) and len(x)==64 and all(c in "0123456789abcdef" for c in x)

def ms(x):
    return round(float(x)/1000,4)

def frames(rows):
    need(type(rows) is list and len(rows)==8,"live_window")
    boundary=[]; intervals=[]
    for i,row in enumerate(rows):
        exact(row,TIMES,"live_window")
        elapsed=check_int(row["pre_to_post_us"],1,LIVE_BOUND,"live_elapsed")
        interval=check_int(row["post_interval_us"],0 if i==0 else elapsed,LIVE_BOUND,"live_elapsed")
        need(interval==0 or interval>=elapsed,"live_elapsed")
        boundary.append(elapsed)
        if interval: intervals.append(interval)
    return {"completed_roots":8,"pre_to_post_median_ms":ms(st.median(boundary)),
        "pre_to_post_max_observed_ms":ms(max(boundary)),"positive_post_intervals":len(intervals),
        "post_interval_median_ms":ms(st.median(intervals)),"post_interval_max_observed_ms":ms(max(intervals))}

def check_counter(c):
    exact(c,{"primitive_count","draw_calls"},"root_counts")
    return {k:check_int(v,1,10**9,"root_counts") for k,v in c.items()}

def parity(value,size):
    exact(value,{"width","height","rgba_sha256","original","cache","prefix_primitives",
                 "original_repeat","restored","original_repeat_equal","restored_equal"},"root_parity")
    w,h=size
    check_int(value["width"],w,w,"root_parity");check_int(value["height"],h,h,"root_parity")
    need(digest(value["rgba_sha256"]) and value["original_repeat_equal"] is True
      and value["restored_equal"] is True,"root_parity")
    before,cached=map(check_counter,(value["original"],value["cache"]))
    need(check_counter(value["original_repeat"])==before==check_counter(value["restored"]),"root_parity")
    check_int(value["prefix_primitives"],PREFIX,PREFIX,"producer_prefix")
    need(before["primitive_count"]-cached["primitive_count"]==PREFIX-2,"root_primitive_conservation")
    return {"viewport":[w,h],"exact_root_rgba":True,"aa_and_restored_original_verified":True,
            "original":before,"cache":cached,"producer_primitives":PREFIX,"replacement_quad_primitives":2}

def natural_event(row):
    exact(row,TIMES|ARM_FLAGS|{"arm_setup_us","arm_to_finish_us","producer_primitives",
          "original_primitives","original_draw_calls"},"acquisition")
    e=check_int(row["pre_to_post_us"],1,LIVE_BOUND,"live_elapsed")
    i=check_int(row["post_interval_us"],e,LIVE_BOUND,"live_elapsed")
    a=check_int(row["arm_setup_us"],0,LIVE_BOUND,"arm_elapsed")
    total=check_int(row["arm_to_finish_us"],a+e,LIVE_BOUND,"arm_elapsed")
    check_int(row["producer_primitives"],PREFIX,PREFIX,"producer_prefix")
    p=check_int(row["original_primitives"],PREFIX+1,10**9,"root_counts")
    c=check_int(row["original_draw_calls"],1,10**9,"root_counts")
    need(all(row[k] is True for k in ARM_FLAGS),"live_commit")
    return {"observation_count":1,"original_root":{"primitive_count":p,"draw_calls":c},
            "producer_primitives":PREFIX,"pre_to_post_ms":ms(e),"prior_post_to_post_ms":ms(i),
            "arm_setup_ms":ms(a),"arm_to_post_and_commit_ms":ms(total),
            "original_displayed_through_acquisition_then_verified_commit":True}

def first_miss(value):
    exact(value,TIMES|{"new_target_original","pending"},"transition")
    need(value["new_target_original"] is True and value["pending"] is False,"transition")
    e=check_int(value["pre_to_post_us"],1,LIVE_BOUND,"live_elapsed")
    i=check_int(value["post_interval_us"],e,LIVE_BOUND,"live_elapsed")
    return {"first_new_target_stock_no_pending_bake":True,"pre_to_post_ms":ms(e),
            "prior_post_to_post_ms":ms(i),"observation_count":1}

def observational(value):
    exact(value,LIVE_FLAGS|{"home","pan","resize","pan_first_miss","resize_first_miss"},"natural_lane")
    need(all(value[k] is True for k in LIVE_FLAGS),"natural_progress_or_integrity")
    results={}
    for key,size in (("home",FRAME),("pan",FRAME),("resize",SMALL)):
        work=value[key]
        exact(work,{"original_frames","acquisition","hit_frames","parity"},"natural_lane")
        results[key]={"stock":frames(work["original_frames"]), "acquisition":natural_event(work["acquisition"]),
                      "cache_hit":frames(work["hit_frames"]), "separate_untimed_parity":parity(work["parity"],size)}
    return {"by_viewport_checkpoint":results,"observed_transition_first_misses":{
        k:first_miss(value[f"{k}_first_miss"]) for k in ("pan","resize")},
        "progress_flags_verified":sorted(LIVE_FLAGS),
        "max_of_three_acquisition_pre_to_post_ms":max(x["acquisition"]["pre_to_post_ms"] for x in results.values()),
        "max_of_three_acquisition_post_interval_ms":max(x["acquisition"]["prior_post_to_post_ms"] for x in results.values()),
        "same_state_counterfactual_available":False,
        "notes":"Unmodified natural pacing/swap/VSync policy; no forced draws or readbacks in the measured windows. " 
        "Readbacks exist only in separate untimed parity checks. Sampler labels 8 adjacent original roots and 8 actual verified hits per checkpoint, "
        "but logical gameplay advances and they are not a matched subtraction. Each acquisition and first miss is one observation; no p95. "
        "A resize post interval may include platform resize delivery; these are elapsed times, not driver or GPU busy time."}

def controlled(c):
    exact(c,{"first_aba","warm_counterbalanced_blocks","matching_root_primitives",
            "matching_root_calls","producer_primitives","same_retained_tick_full_rgba_exact"},"controlled")
    need(c["same_retained_tick_full_rgba_exact"] is True,"controlled_parity")
    check_int(c["producer_primitives"],PREFIX,PREFIX,"producer_prefix")
    p=check_int(c["matching_root_primitives"],PREFIX+1,10**9,"root_counts")
    d=check_int(c["matching_root_calls"],1,10**9,"root_counts")
    def samples(rows,arms,resident):
        need(type(rows) is list and len(rows)==len(arms),"arm_order")
        result=[]
        for v,arm,res in zip(rows,arms,resident):
            exact(v,{"us","acquire","producer_resident_before"},"arm_order")
            need(v["acquire"] is arm and v["producer_resident_before"] is res,"arm_order")
            result.append(check_int(v["us"],1,FORCED_BOUND,"controlled_elapsed"))
        return result
    b0,first,b2=samples(c["first_aba"],[False,True,False],[False,False,True])
    blocks=c["warm_counterbalanced_blocks"]
    need(type(blocks) is list and len(blocks)==6,"block_order")
    effects=[]; spreads=[]; a=[]; b=[]
    for i,rows in enumerate(blocks):
        arms=[False,True,True,False] if i%2==0 else [True,False,False,True]
        xs=samples(rows,arms,[True]*4)
        ct=[v for v,arm in zip(xs,arms) if not arm]; tx=[v for v,arm in zip(xs,arms) if arm]
        effects.append(Fraction(sum(tx)-sum(ct),2)); spreads.append(abs(ct[0]-ct[1]))
        a.extend(ct); b.extend(tx)
    cold=first-b0
    hot=st.median(effects)
    def projection(v):
        return math.ceil(v/PRIOR_US) if v>0 else None
    return {"first_lazy_allocation_n":1,"first_stock_before_ms":ms(b0),"first_acquisition_ms":ms(first),
        "stock_after_allocation_ms":ms(b2),"first_minus_preallocation_stock_ms":ms(cold),
        "first_bracketed_difference_ms":ms(first-Fraction(b0+b2,2)),
        "warm_blocks":6,"warm_samples_per_arm":len(a),"warm_signed_block_differences_ms":list(map(ms,effects)),
        "warm_median_difference_ms":ms(hot),"warm_acquisition_max_observed_ms":ms(max(b)),
        "warm_stock_max_observed_ms":ms(max(a)),"within_block_stock_spreads_ms":list(map(ms,spreads)),
        "root_unchanged_same_retained_tick_full_rgba":{"primitive_count":p,"draw_calls":d,"producer_primitives":PREFIX},
        "hypothetical_hits_at_separately_measured_steady_saving":{
            "prior_run_id":44523976066,"prior_steady_saving_ms":6.8576,
            "first_increment_primary_hits":projection(cold),"warm_increment_median_hits":projection(hot),
            "conditions":"Positive controlled increments only, divided by the steady saving observed in another hosted session "
                "then rounded up. Not same-session, natural, or production payoff. Assumes equally valuable valid hits and ignores any other miss cost."},
        "notes":"Matched forced no-swap rendering on one retained logical state, including whole enclosed arm/allocation and completion; "
            "difference versus stock is controlled-path elapsed, not incremental GPU time or presented FPS."}

def summarize(raw,head,tree,engine,probe,owner):
    need((head,tree,engine)==(HEAD,TREE,ENGINE) and digest(probe) and digest(owner),"source_binding")
    exact(raw,{"schema","controlled","natural"},"schema")
    need(raw["schema"]==PROBE,"schema")
    return {"schema":PUBLIC,"status":"valid_observations_no_adoption","measurements_published":True,
        "commit":HEAD,"tree":TREE,"engine_sha256":ENGINE,"probe_sha256":probe,"owner_sha256":owner,
        "controlled":controlled(raw["controlled"]),"natural":observational(raw["natural"]),
        "no_spike_gate_established":False,"adoption_qualified":False,
        "no_spike_gate":"This diagnostic cannot qualify deployment. Keep stock unless independent, adequately repeated presented "
            "first-use, stopped-camera rebake, movement and resize transitions show no added slow frame beyond matched stock repeatability. "
            "A positive stationary payoff or waiting eight frames does not remove an acquisition spike.",
        "scope":"Pinned stock native #397, X11 GL Compatibility/Mesa llvmpipe synthetic active cooking. "
        "Only the matched controlled and natural observational lanes; not full-game FPS or release evidence."}

STAGES={"gate_env","adapter","scene_wait","initial_state","same_state_acquisition_not_identified",
        "live_checkpoint_expired","live_observation","presentation_changed"}
DETAILS={"stock_repeat","draw_events","root_target_changed","target_class_or_size","readback_empty",
         "readback_size","readback_format","readback_length","readback_format_changed","repeat_counters",
         "sentinel_region","original_selection","original_counters","canvas_admission","hit_selection",
         "primitive_conservation","restore_selection","scene_advanced","digest","fallback_selection",
         "bake_rejected","bake_events","bake_accounting","bake_producer_state","bake_opacity",
         "sentinel_restore_pixels","original_repeat_pixels","cache_pixels","restore_pixels",
         "fallback_pixels","bake_restore_pixels","live_adapter","live_pre_order","live_environment",
         "live_root_target","live_post_order","live_counters_or_generation","live_interval",
         "live_immediate_miss","live_static_not_original","live_acquisition_not_original","live_commit",
         "live_commit_evidence","live_acquisition_elapsed","live_expected_hit","live_bad_stage",
         "live_timeout","live_pending","live_arm","live_parity","live_reselect","live_anchor_key",
         "live_entry","live_cold_selection","live_pan_direction","live_pan_fallback",
         "live_resize_fallback","live_progress"}

def screened_failure(raw):
    stage=raw.get("stage_code");detail=raw.get("detail_code")
    need(isinstance(stage,str) and stage in STAGES,"unclassified_probe_failure")
    need(detail is None or isinstance(detail,str) and detail in DETAILS,"unclassified_probe_detail")
    return failure(stage,detail)

def failure(stage,detail=None):
    out={"schema":PUBLIC,"status":"not_qualified","stage":stage,"measurements_published":False,
         "no_spike_gate_established":False,"adoption_qualified":False}
    if detail is not None:out["detail_code"]=detail
    return out

def unique(rows):
    result={}
    for k,v in rows:
        need(k not in result,"invalid_shape");result[k]=v
    return result

def nonfinite(_):
    raise Rejected("invalid_shape")

def finite_float(token):
    value=float(token)
    need(math.isfinite(value),"invalid_shape")
    return value

def publish(private,output,*binding):
    try:
        need((private.stat().st_size<=500000),"invalid_shape")
        raw=json.loads(private.read_text(),object_pairs_hook=unique,parse_constant=nonfinite,parse_float=finite_float)
        value=screened_failure(raw) if raw.get("schema")==FAIL else summarize(raw,*binding)
    except Rejected as exc:
        value=failure(str(exc))
    except (AttributeError,KeyError,TypeError,ValueError,IndexError,OSError,RecursionError):
        value=failure("invalid_shape")
    data=json.dumps(value,sort_keys=True,indent=2,allow_nan=False)+"\n"
    need(len(data)<16384,"output_bound")
    output.write_text(data)
    return 0 if value["measurements_published"] else 2

if __name__=="__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("private",type=Path);parser.add_argument("output",type=Path)
    for key in ("expected-commit","expected-tree","engine-sha256","probe-sha256","adapter-sha256"):
        parser.add_argument("--"+key,required=True)
    a=parser.parse_args()
    raise SystemExit(publish(a.private,a.output,a.expected_commit,a.expected_tree,a.engine_sha256,a.probe_sha256,a.adapter_sha256))
