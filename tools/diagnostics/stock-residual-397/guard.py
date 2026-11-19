"""Exact local/hosted admission; only bounded provenance and aggregates escape."""
import hashlib, json, os, subprocess, sys
from pathlib import Path
from report import assess

HERE=Path(__file__).resolve().parent
HEAD="ce1435afb2329a6c1d2d77a8a19923dfd96bd205"
TREE="03632a0d56e4294f5664859656c8809541766d1b"
ARCHIVE="5a236669cca594a1437b289f4b4b8a933a204ddab064844485d2868ce8ee1406"
FIXTURE="ed6fcfc1e4a3396389eff71b09f60740d099de9c046eb0e37eabe900e8c1cf4f"
ENGINE="f64d4ed19fc9df9440321653fcc80df8c6e365ba7b6de0a29e2cfa9fa71bfeb3"
PROJECT="74d834b98aed6995fac701fd5a4bd7b8c7b33ae2a2b9a39b4f99cdd60d52f5ce"
INSTALLER={
 "tools/ci/install_tools.py":"76790d83bd436f73408515d5890763478a027f5645fde883776bcc92db81604f",
 "tools/ci/toolchain.json":"529627e9b964f98b417220ebde30d60388531fc53fc0b1fbad19fa4eb427fc70",
 "tools/ci/chrome.json":"086165986b36e4b03e11c2f590564e54f1dabcd789cca27ec88a1fa8c7b4cfaa",
}
FILES={"stage.py","prepare.py","fixture.json","input.json","probe.gd","report.py","run.sh","guard.py"}
REPO="yiyousiow000814/little-leaf"
REF="refs/heads/qa/stock-residual-397"
PREFIX="tools/diagnostics/stock-residual-397/"
WF=".github/workflows/stock-residual-397.yml"
FAIL={"source_binding","sparse_source","stage_binding","engine_acquisition","engine_sha","import","display",
      "session","unsupported_renderer","scene_or_phase","session_timeout","invalid_summary","query_unqualified"}

def need(condition, why):
    if not condition:
        raise ValueError(why)

def sha(path):
    with Path(path).open("rb") as f:
        return hashlib.file_digest(f,"sha256").hexdigest()

def git(repo,*args):
    return subprocess.check_output(["git","-C",str(repo),*args]).decode().strip()

def manifest():
    values=json.loads((HERE/"manifest.json").read_bytes())
    need(set(values)==FILES, "missing or additional declared dependency")
    need({f.relative_to(HERE).as_posix() for f in HERE.rglob("*") if f.is_file()}==FILES|{"manifest.json"}, "nonexact kit")
    need(all(sha(HERE/path)==digest for path,digest in values.items()), "changed kit input")
    need(values["fixture.json"]==FIXTURE, "wrong synthetic fixture")
    return values

def event(repo, ev, env):
    manifest()
    head=env["GITHUB_SHA"]
    need(env["GITHUB_ACTIONS"]=="true" and env["GITHUB_REPOSITORY"]==REPO and
         env["GITHUB_ACTOR"]==REPO.split("/")[0] and env["GITHUB_REF"]==REF and
         env["GITHUB_RUN_ATTEMPT"]=="1" and env["GITHUB_EVENT_NAME"]=="push","wrong launch context")
    need(ev.get("ref")==REF and ev.get("before")==HEAD and ev.get("after")==head and
         all(ev.get(key) is False for key in ("forced","deleted","created")),"wrong one-shot transition")
    need(git(repo,"rev-list","--parents","-n","1","HEAD").split()==[head,HEAD] and
         git(repo,"rev-parse","HEAD^^{tree}")==TREE,"wrong direct parent/tree")
    rows={tuple(x.split("\t")) for x in git(repo,"diff","--name-status","--no-renames","HEAD^","HEAD").splitlines()}
    need(rows=={("A",p) for p in {WF}|{PREFIX+f for f in FILES|{"manifest.json"}}},"unapproved commit scope")

def source(repo):
    need(git(repo,"rev-parse","HEAD")==HEAD and git(repo,"rev-parse","HEAD^{tree}")==TREE,"wrong product")
    need(all((repo/p).is_file() and sha(repo/p)==d for p,d in INSTALLER.items()),"incomplete or changed sparse installer dependencies")
    need((repo/"game/project.godot").is_file(),"missing game directory")

def stage(root,receipt):
    expected={"head":HEAD,"tree":TREE,"archive_sha256":ARCHIVE,"fixture_sha256":FIXTURE,
              "project_sha256":PROJECT,"probe_sha256":sha(HERE/"probe.gd"),"tree_proof_local_only":False}
    need(json.loads(receipt.read_bytes())==expected,"stage receipt mismatch")
    need(sha(root/"game/project.godot")==PROJECT and sha(root/"game/ll397_stock_residual.gd")==expected["probe_sha256"],"diagnostic stage mismatch")
    need(sha(root/"private/data/godot/app_userdata/Little Leaf Cafe/little_leaf_cafe_layout_motion_v15.json")==FIXTURE,"fixture live stage mismatch")

def base():
    return {"product":HEAD,"tree":TREE,"archive_sha256":ARCHIVE,"fixture_sha256":FIXTURE,"engine_sha256":ENGINE}

def write(out,result):
    raw=(json.dumps(result,sort_keys=True,allow_nan=False)+"\n").encode()
    need(len(raw)<=8192,"summary exceeded max safe size")
    out.parent.mkdir(parents=True,exist_ok=True)
    tmp=out.with_suffix(".writing")
    with tmp.open("xb") as f:f.write(raw)
    tmp.replace(out)

def fail(out,label):
    need(label in FAIL,"unexpected status")
    write(out,{"schema":"ll397-stock-residual-hosted-v1","status":"not_qualified","stage":label,**base()})

def package(raw,out):
    need(raw.stat().st_size<=128*1024,"overflowing capture")
    x=assess(json.loads(raw.read_bytes()))
    # Assess constructs this fixed shape from validated values; neither guest IDs,
    # raw frames, debug output, environment details, nor profile bytes leave.
    need(set(x)=={"schema","status","counts","query_off_same_frame","query_overhead","viewport_status","viewport_body","scope"},"bad aggregate shape")
    write(out,{"schema":"ll397-stock-residual-hosted-v1",**base(),"measurement":x,"status":x["status"]})

if __name__=="__main__":
    op=sys.argv[1]
    if op=="event":event(Path(sys.argv[2]),json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_bytes()),os.environ)
    elif op=="source":source(Path(sys.argv[2]))
    elif op=="stage":stage(Path(sys.argv[2]),Path(sys.argv[3]))
    elif op=="fail":fail(Path(sys.argv[2]),sys.argv[3])
    elif op=="package":package(Path(sys.argv[2]),Path(sys.argv[3]))
    else:raise SystemExit("unknown guard operation")
