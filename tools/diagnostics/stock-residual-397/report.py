"""Summarize a private stock timing window; never export frame rows or identifiers."""
import json
import math
import statistics
import sys
from pathlib import Path

PLAN = [False, False, True, False, True, False]
SAMPLE = 24
WARM = 8
ENGINE = "7d41c59c457bd5a245092b4e7eb2d833e3b3f8c3"

def need(ok, why):
    if not ok:
        raise ValueError(why)

def p95(vals):
    return sorted(vals)[math.ceil(.95 * len(vals)) - 1]

def describe(vals):
    return {"mean_ms":round(statistics.fmean(vals)/1000, 5),
            "median_ms":round(statistics.median(vals)/1000, 5),
            "p95_ms":round(p95(vals)/1000,5)}

def column(rows, i):
    return [row[i] for row in rows]

def read_windows(raw):
    need(raw.get("schema") == "ll397-stock-residual-raw-v1", "bad schema")
    state=raw.get("state",{})
    need(set(state)=={"cooking_id","customers","served","items","walls","openings"} and
         all(type(value) is int and value>=0 for value in state.values()) and
         (state["items"],state["walls"],state["openings"])==(7,21,1) and state["customers"]>=1,
         "not the active synthetic fixture")
    windows=raw.get("windows")
    need(isinstance(windows,list) and len(windows)==len(PLAN),"incomplete phase plan")
    out = []
    last = -1
    for expected,window in zip(PLAN,windows):
        data=window.get("rows")
        need(window.get("query") is expected and isinstance(data,list) and len(data)==SAMPLE*6,
             "bad arm or row count")
        need(all(type(v) in (int,float) and math.isfinite(v) and v>=0 for v in data),"nonfinite or negative")
        rows=[data[i:i+6] for i in range(0,len(data),6)]
        need(rows[0][0]>last+WARM and all(b[0]==a[0]+1 for a,b in zip(rows,rows[1:])) and
             all(row[0]==int(row[0]) and 0<row[2]<=row[1] and 0<=row[3]<=row[2] for row in rows),
             "draw order, missing warm frames or preparation not nested")
        last = rows[-1][0]
        out.append(rows)
    return out

def sanity_floor(view):
    return min(view)>0 and len(set(view))>=3 and max(view.count(v) for v in view)<=len(view)//2

def assess(raw):
    phases = read_windows(raw)
    off=[rows for mode,rows in zip(PLAN,phases) if not mode]
    on=[rows for mode,rows in zip(PLAN,phases) if mode]
    cross=[]
    for name,col,metric,floor,max_spread,relative in (
             ("inter_post_median",1,statistics.median,400,2000,.12),
             ("draw_median",2,statistics.median,400,1500,.12),
             ("inter_post_p95",1,p95,1000,4500,.22),
             ("draw_p95",2,p95,1000,3500,.22)):
        a=[metric(column(arm,col)) for arm in off]
        b=[metric(column(arm,col)) for arm in on]
        center=statistics.median(a)
        spread=max(a)-min(a)
        allowance=max(floor,spread)
        tuned=spread<=max(max_spread,center*relative)
        pass_=tuned and all(abs(value-center)<=allowance for value in b)
        cross.append({"metric":name,"off_spread_ms":round(spread/1000,5),
                      "tolerance_ms":round(allowance/1000,5),"guard":pass_})
    clean = [row for arm in off for row in arm]
    result={
        "schema":"ll397-stock-residual-summary-v1",
        "status":"prep_only",
        "counts":{"query_off_frames":len(clean),"query_on_frames":len(on)*SAMPLE},
        "query_off_same_frame":{"outer_pre_to_post":describe(column(clean,2)),
                           "prep_nested":describe(column(clean,3)),
                           "outer_less_prep_only":describe([row[2]-row[3] for row in clean])},
        "query_overhead":cross,
        "viewport_body":None,
        "scope":"Synthetic active cooking, stock Compatibility llvmpipe. No current-frame generation for viewport getters; never subtract viewport distributions from outer or prep. Outer less prep is unclassified, not swap/culling/fill time.",
    }
    # Query-off affects output separation only; do not let absent timestamps
    # manufacture a viewport split. No prior query exists in the first two arms.
    valid_cpu=all(v==0 for arm in off[:2] for v in column(arm,4))
    valid_cpu &= all(len(set(column(arm,4)))==1 for arm in off[2:])
    valid_cpu &= all(sanity_floor(column(arm,4)) for arm in on)
    body_medians=[statistics.median(column(arm,4)) for arm in on]
    body_stationary=max(body_medians)-min(body_medians)<=max(600,statistics.median(body_medians)*.10)
    if not all(row["guard"] for row in cross):
        result["viewport_status"]="query_perturbation_or_aa_drift"
    elif not valid_cpu:
        result["viewport_status"]="generationless_signal_failed_liveness"
    else:
        cpu=[v for arm in on for v in column(arm,4)]
        gpu=[v for arm in on for v in column(arm,5)]
        outer_max=max(row[2] for arm in on for row in arm)
        if max(cpu)>outer_max:
            result["viewport_status"]="inconsistent_outer_support"
        elif not body_stationary:
            result["viewport_status"]="viewport_windows_not_stationary"
        else:
            result["status"]="prep_plus_stationary_viewport_body"
            result["viewport_status"]="steady_state_lagged_only"
            valid_gl=all(v==0 for arm in off[:2] for v in column(arm,5))
            valid_gl &= all(len(set(column(arm,5)))==1 for arm in off[2:])
            valid_gl &= all(sanity_floor(column(arm,5)) for arm in on)
            result["viewport_body"]={"cpu_labeled_wall":describe(cpu),
                                     "software_gl_stream":describe(gpu) if valid_gl else None}
    return result

if __name__=="__main__":
    src,dst=map(Path,sys.argv[1:])
    need(src.stat().st_size <= 128*1024,"overlong private capture")
    result=assess(json.loads(src.read_bytes()))
    with dst.open("x") as target:
        target.write(json.dumps(result,indent=2,sort_keys=True)+"\n")
