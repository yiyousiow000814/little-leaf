"""Stock A/A workload-only readiness. Import locally reviewed qualifier; publish no rows."""
import json
import sys
from pathlib import Path
import guard
import qualify

STAGES=frozenset({"passed","source_binding","official_pin","import","display","session",
                  "invalid_app_receipt","stock_noise","workload"})
def stock_only(base):
    x,a,before=qualify.load_app(base/"stock-before/app.json",False)
    y,b,after=qualify.load_app(base/"stock-after/app.json",False)
    qualify.workload(x[0]==y[0],"cross_adapter")
    qualify.workload(x[1]==y[1],"cross_class_digest")
    qualify.workload(a==b,"cross_scene")
    controls=before+after
    qualify.workload(all(qualify.witness_match(w,controls[0]) for w in controls),"stock_canvas_witness")
    qualify.want(all(qualify.time_match(x,y) for i,x in enumerate(controls)
                     for j,y in enumerate(controls) if i!=j),"stock_noise")

def summary(path,stage,reason=None):
    if stage not in STAGES or (reason is not None and (stage!="workload" or reason not in guard.WORKLOAD_REASONS)):
        raise ValueError("bad stock preflight enum")
    result={"schema":"ll397-stock-aa-preflight-v1","status":"passed" if stage=="passed" else "not_qualified",
            "stage":stage,"product":guard.BASE,"tree":guard.TREE,
            "scope":"official_stock_only_no_native_attribution"}
    if reason is not None:
        result["workload_reason"]=reason
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(result,sort_keys=True)+"\n")

def main(argv):
    if len(argv)!=3 or argv[0] not in {"package","fail"}:
        raise SystemExit("invalid stock preflight command")
    cmd,value,out=argv
    out=Path(out)
    if cmd=="fail":
        if value=="passed":
            raise SystemExit("cannot emit unchecked pass")
        summary(out,value)
        return 0
    try:
        stock_only(Path(value))
    except qualify.Decline as rejected:
        summary(out,"invalid_app_receipt" if rejected.stage=="native_accounting" else rejected.stage,rejected.reason)
        return 1
    except (ValueError,KeyError,TypeError,OverflowError,OSError):
        summary(out,"invalid_app_receipt")
        return 1
    summary(out,"passed")
    return 0
if __name__=="__main__":
    raise SystemExit(main(sys.argv[1:]))
