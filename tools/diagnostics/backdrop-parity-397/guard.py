"""Exact local/hosted admission; only bounded provenance and aggregates escape."""
import hashlib, json, os, subprocess, sys
from pathlib import Path


HERE=Path(__file__).resolve().parent
HEAD="ce1435afb2329a6c1d2d77a8a19923dfd96bd205"
TREE="03632a0d56e4294f5664859656c8809541766d1b"
ARCHIVE="5a236669cca594a1437b289f4b4b8a933a204ddab064844485d2868ce8ee1406"
FIXTURE="ed6fcfc1e4a3396389eff71b09f60740d099de9c046eb0e37eabe900e8c1cf4f"
ENGINE="f64d4ed19fc9df9440321653fcc80df8c6e365ba7b6de0a29e2cfa9fa71bfeb3"
PROJECT="b9b4ddbeb2eaf66212a94a58a567027b0d1b7f3f406870e129ae097092780633"
ARTIST="8c64cd0a7ce7db8c1ef5bed11fb518ffce8c509c598a937690a0f491e415d6cd"
INSTALLER={
 "tools/ci/install_tools.py":"76790d83bd436f73408515d5890763478a027f5645fde883776bcc92db81604f",
 "tools/ci/toolchain.json":"529627e9b964f98b417220ebde30d60388531fc53fc0b1fbad19fa4eb427fc70",
 "tools/ci/chrome.json":"086165986b36e4b03e11c2f590564e54f1dabcd789cca27ec88a1fa8c7b4cfaa",
}
FILES={"prepare.py","fixture.json","ll397_active_backdrop.gd","ll397_forensic_owner.gd","ll397_forensic_diff.gd","probe.gd","report.py","run.sh","guard.py"}
REPO="yiyousiow000814/little-leaf"
REF="refs/heads/qa/backdrop-parity-397"
PREFIX="tools/diagnostics/backdrop-parity-397/"
WF=".github/workflows/backdrop-parity-397.yml"
FAIL={"source_binding","sparse_source","stage_binding","engine_acquisition","engine_sha","import","display",
      "session","scene_or_phase","session_timeout","invalid_summary","diagnostic_unqualified"}

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
    expected=json.loads(receipt.read_bytes())
    need(expected.get('head')==HEAD and expected.get('tree')==TREE and expected.get('game_before_sha256')==ARCHIVE and expected.get('synthetic_fixture')==FIXTURE,'bad source receipt')
    files=expected['staged_postimages'];need(set(files)=={'project.godot','scripts/rendering/illustrated_cafe.gd','ll397_forensic_probe.gd','ll397_active_backdrop.gd','ll397_forensic_owner.gd','ll397_forensic_diff.gd'},'unexpected patched scope')
    need(all(sha(root/'game'/k)==v for k,v in files.items()),'changed stage')
    need(files['project.godot']==PROJECT and files['scripts/rendering/illustrated_cafe.gd']==ARTIST and files['ll397_forensic_probe.gd']==sha(HERE/'probe.gd') and all(files[f]==sha(HERE/f) for f in ['ll397_forensic_owner.gd','ll397_forensic_diff.gd']) and files['ll397_active_backdrop.gd']==sha(HERE/'ll397_active_backdrop.gd'),'wrong staged change')
    need(sha(root/'private/data/godot/app_userdata/Little Leaf Cafe/little_leaf_cafe_layout_motion_v15.json')==FIXTURE,'not synthetic')

def base():
    return {"product":HEAD,"tree":TREE,"archive_sha256":ARCHIVE,"fixture_sha256":FIXTURE,"engine_sha256":ENGINE}

def write(out,result):
    raw=(json.dumps(result,sort_keys=True,allow_nan=False)+"\n").encode()
    need(len(raw)<16384,"summary exceeded max safe size")
    out.parent.mkdir(parents=True,exist_ok=True)
    tmp=out.with_suffix(".writing")
    with tmp.open("xb") as f:f.write(raw)
    tmp.replace(out)

def fail(out,label):
    need(label in FAIL,"unexpected status")
    write(out,{"schema":"ll397-backdrop-parity-hosted-v1","status":"not_qualified","stage":label,"timing":False,**base()})

def package(raw,out,exit_code):
    from report import read
    need(raw.stat().st_size<65536,'raw exceeds allowed bytes')
    result=read(raw.read_bytes())
    need(result['timing'] is False,'unexpected time')
    if result['outcome']=='unqualified':need(exit_code==2,'unexpected session status')
    else:need(exit_code==0 and result['outcome'] in ('neither_differs','old_differs_matched_exact','matched_differs'),'session did not complete')
    write(out,{'schema':'ll397-backdrop-parity-hosted-v1','status':result['outcome'],'timing':False,**base(),'manifest_sha256':sha(HERE/'manifest.json'),'measurement':result})
    # A valid mismatch is a useful result, but not a qualified visual replacement.
    return 0 if result['outcome'] in ('neither_differs','old_differs_matched_exact') else 2

if __name__=="__main__":
    op=sys.argv[1]
    if op=="event":event(Path(sys.argv[2]),json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_bytes()),os.environ)
    elif op=="source":source(Path(sys.argv[2]))
    elif op=="stage":stage(Path(sys.argv[2]),Path(sys.argv[3]))
    elif op=="fail":fail(Path(sys.argv[2]),sys.argv[3])
    elif op=="package":raise SystemExit(package(Path(sys.argv[2]),Path(sys.argv[3]),int(sys.argv[4])))
    else:raise SystemExit("unknown guard operation")
