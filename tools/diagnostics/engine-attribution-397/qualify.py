"""Verify private raw app/engine rows and emit bounded, non-overlapping aggregates only."""
import json,math,re,statistics,sys
from pathlib import Path
import guard

LABELS=("sync","render_other","render_begin","older_gl_query_and_begin","prepare","viewport_other",
        "canvas_cull","canvas_submit","screen_blit","buffer_swap","existing_finish","visibility_notifiers","post_callbacks")
DETAIL=LABELS[1:]
ARMS=(0,0,1,0,1,0)
UNIQUE=("sync","render_other","render_begin","older_gl_query_and_begin","prepare","buffer_swap","visibility_notifiers","post_callbacks")
FIXTURE="ed6fcfc1e4a3396389eff71b09f60740d099de9c046eb0e37eabe900e8c1cf4f"
ARCHIVE="5a236669cca594a1437b289f4b4b8a933a204ddab064844485d2868ce8ee1406"
HEAD=("frame","detail","outer_wall_ns","outer_thread_cpu_ns","tail_wall_ns","tail_thread_cpu_ns")
HEADER=HEAD+tuple(f"{k}_{f}" for k in LABELS for f in ("wall_ns","thread_cpu_ns","calls"))

class Decline(ValueError):
    def __init__(self,stage): self.stage=stage; super().__init__(stage)
def want(ok,stage):
    if not ok: raise Decline(stage)
def bounded(path,limit):
    want(path.is_file() and 0<path.stat().st_size<=limit,"native_accounting")
    return path.read_bytes()
def as_int(x):
    want(type(x) in {int,float} and math.isfinite(x) and x==int(x) and x>=0,"workload")
    return int(x)
def load_app(path,rebuilt):
    d=json.loads(bounded(path,100_000))
    want(set(d)=={"schema","mode","state","windows","adapter","class_digest"} and d["schema"]=="ll397-engine-app-raw-v1" and
         d["mode"]==("rebuilt" if rebuilt else "stock"),"workload")
    want(type(d["adapter"]) is str and "llvmpipe" in d["adapter"].lower() and "mesa" in d["adapter"].lower() and len(d["adapter"])<300,"workload")
    st=d["state"]
    want(set(st)=={"cooking_id","customers","served","items","walls","openings"} and
         tuple(as_int(st[k]) for k in ("items","walls","openings"))==(7,21,1) and
         as_int(st["customers"])>=1 and as_int(st["cooking_id"])>=1 and as_int(st["served"])>=0,"workload")
    arms=ARMS if rebuilt else (0,0,0)
    want(len(d["windows"])==len(arms),"workload")
    windows=[]
    seen=set()
    for arm,w in zip(arms,d["windows"]):
        want(set(w)=={"arm","rows"} and w["arm"]==arm and len(w["rows"])==24*6,"workload")
        rows=[tuple(as_int(x) for x in w["rows"][i:i+6]) for i in range(0,24*6,6)]
        ids=[r[0] for r in rows]
        want(ids==list(range(ids[0],ids[0]+24)) and (not seen or ids[0]>=max(seen)+9),"workload")
        seen.update(ids)
        want(all(0<r[2]<=r[1]<1_000_000 and all(0<x<1_000_000 for x in r[3:]) for r in rows),"workload")
        windows.append(rows)
    want(type(d["class_digest"]) is str and re.fullmatch(r"[a-f0-9]{64}",d["class_digest"]),"workload")
    return (d["adapter"],d["class_digest"]),st,windows
def q(xs,p):
    return sorted(xs)[math.ceil(len(xs)*p)-1]
def stats(rows,k):
    xs=[r[k] for r in rows]
    return statistics.median(xs),q(xs,.95)
def close_metric(a,b,absolute,relative):
    return abs(a-b)<=max(absolute,abs(b)*relative)
def time_match(a,b):
    return all(close_metric(x,y,ad,re) for k in (1,2) for (x,y),(ad,re) in zip(
        zip(stats(a,k),stats(b,k)),((400,.03),(1000,.06))))
def max_drift(pairs):
    changes=[tuple(abs(x-y) for x,y in zip(stats(a,k),stats(b,k))) for a,b in pairs for k in (1,2)]
    return {f"max_{name}_delta_ms":round(max(row[i] for row in changes)/1000,4) for i,name in enumerate(("p50","p95"))}
def witness_match(a,b):
    # Bounded structural render witness only, not pixel parity. Allow small animation-driven variation.
    return all(close_metric(x,y,1,.02) for k in (3,4,5) for x,y in zip(stats(a,k),stats(b,k)))
def load_native(path,windows):
    lines=bounded(path,1_000_000).decode("ascii").splitlines()
    want(len(lines)>=2 and lines[0]=="ll397-engine-scopes-v1\terrors\t0" and
         tuple(lines[1].split("\t"))==HEADER and 144<=len(lines)-2<=192,"native_accounting")
    records={}
    for line in lines[2:]:
        cols=line.split("\t")
        want(len(cols)==len(HEADER) and all(x.isascii() and x.isdigit() and len(x)<=12 for x in cols),"native_accounting")
        i,arm,ow,oc,tw,tc,*rest=map(int,cols)
        want((not records or i>next(reversed(records))) and arm in {0,1} and 0<ow<=2_000_000_000 and
             oc<=ow+50_000 and tc<=tw+50_000 and tw<=2_000_000_000,"native_accounting")
        phases={k:tuple(rest[pos:pos+3]) for k,pos in zip(LABELS,range(0,len(rest),3))}
        want(all(w<=2_000_000_000 and c<=w+50_000 and n<=64 and (n!=0 or w==c==0)
                 for w,c,n in phases.values()),"native_accounting")
        want(phases["sync"][2]==1,"native_accounting")
        if arm:
            want(tuple(sum(phases[k][d] for k in DETAIL) for d in (0,1))==(ow,oc) and
                 all(phases[k][2]==1 for k in UNIQUE) and phases["existing_finish"]==(0,0,0) and
                 all(phases[k][2]>0 for k in ("viewport_other","canvas_cull","canvas_submit","screen_blit")),
                 "native_accounting")
        else:
            want(all(phases[k]==(0,0,0) for k in DETAIL),"native_accounting")
        records[i]=(arm,ow,oc,tw,tc,phases)
    matched=[]
    trace_ids=set(records)
    for arm,rows in zip(ARMS,windows):
        ids={r[0] for r in rows}
        warm=set(range(min(ids)-8,min(ids)))
        want(ids<=trace_ids and all(records[i][0]==arm for i in ids| (warm & trace_ids)),"native_accounting")
        trace_ids-=ids|warm
        group=[records[i] for i,*_ in rows]
        # Same serial, measured narrower than GDScript pre/post. Allow rounding, not a shifted frame.
        want(all(n[1]<=app[2]*1000+2_000 for n,app in zip(group,rows)),"native_accounting")
        matched.append(group)
    want(not trace_ids,"native_accounting")
    return matched
def pack(w,binpath):
    a,st,before=load_app(w/"stock-before/app.json",False)
    b,stb,rebuilt=load_app(w/"rebuilt/app.json",True)
    c,stc,after=load_app(w/"stock-after/app.json",False)
    want(a==b==c and st==stb==stc,"workload")
    controls=before+after
    want(all(witness_match(x,y) for x in controls+rebuilt for y in (controls[0],)),"workload")
    aa=[(x,y) for i,x in enumerate(controls) for j,y in enumerate(controls) if i!=j]
    want(all(time_match(x,y) for x,y in aa),"stock_noise")
    cross=[(rebuilt[i],control) for i in (0,1,3,5) for control in controls]
    observed=[(rebuilt[on],rebuilt[off]) for on,off in ((2,1),(2,3),(4,3),(4,5))]
    for i in (0,1,3,5):
        want(all(time_match(rebuilt[i],control) for control in controls),"rebuild_match")
    for ion,offs in ((2,(1,3)),(4,(3,5))):
        want(all(time_match(rebuilt[ion],rebuilt[i]) for i in offs),"marker_overhead")
    native=load_native(w/"rebuilt/engine.tsv",rebuilt)
    on=[native[2],native[4]]
    # Rebuilt same-process compare both at script span AND INNER native outer wall,
    # with the latter having fewer probe callbacks/calls inside than script span.
    for ion,offs in ((2,(1,3)),(4,(3,5))):
        want(all(all(close_metric(x,y,abs_ns,rel) for (x,y),(abs_ns,rel) in zip(
                  zip(stats(native[ion],1),stats(native[i],1)),((400_000,.03),(1_000_000,.06)))) for i in offs),
             "marker_overhead")
    leaders=[max(DETAIL,key=lambda k:statistics.median(r[5][k][0] for r in group)) for group in on]
    want(leaders[0]==leaders[1],"dominant_not_repeatable")
    both=sum(on,[])
    def clock_stats(values):
        return {"p50_ms":round(statistics.median(values)/1_000_000,4),"p95_ms":round(q(values,.95)/1_000_000,4)}
    def pair(wall,cpu):
        return {"wall":clock_stats(wall),"same_thread_cpu":clock_stats(cpu)}
    bins={k:pair([r[5][k][0] for r in both],[r[5][k][1] for r in both]) for k in LABELS}
    return {"schema":"ll397-engine-full-v1","status":"qualified_rebuilt_diagnostic","product":guard.BASE,"tree":guard.TREE,
            "stock_aa_within_guard":True,"rebuilt_off_matches_observed_stock":True,"same_binary_off_on_within_guard":True,
            "workload_witness":"active_synthetic_and_visible_canvas_counts_not_pixels",
            "observed_boundary_drift":{"stock_aa":max_drift(aa),"stock_vs_rebuilt_off":max_drift(cross),"rebuilt_on_vs_off":max_drift(observed)},
            "registered_class_catalog_sha256":a[1],
            "stock_executable_sha256":"f64d4ed19fc9df9440321653fcc80df8c6e365ba7b6de0a29e2cfa9fa71bfeb3",
            "rebuilt_executable_sha256":guard.sha(binpath),"rebuilt_bytes":binpath.stat().st_size,
            "patch_sha256":guard.sha(guard.H/"engine-scopes.review.patch"),
            "product_archive_sha256":ARCHIVE,"fixture_sha256":FIXTURE,
            "upstream_source_tag":guard.TAG,"upstream_build_stamp":guard.STAMP,
            "engine_asset_sha256":json.loads((guard.H/"inputs.json").read_bytes())["source"]["sha256"],
            "executables_uploaded":False,"rows":len(both),"inner_dominant_repeated_wall":leaders[0],
            "native_render_outer":pair([r[1] for r in both],[r[2] for r in both]),
            "tail_outside_outer":pair([r[3] for r in both],[r[4] for r in both]),
            "elapsed_buckets":bins,"context":"x11_gl_compatibility_llvmpipe_diagnostic_native_render_not_stock_fps"}
def main():
    w,binpath,out=map(Path,sys.argv[1:])
    try: s=pack(w,binpath)
    except Decline as e:
        guard.summary(out,"not_qualified",e.stage);raise
    b=(json.dumps(s,sort_keys=True)+"\n").encode()
    want(len(b)<=4096,"qualification")
    out.write_bytes(b)
if __name__=="__main__":main()
