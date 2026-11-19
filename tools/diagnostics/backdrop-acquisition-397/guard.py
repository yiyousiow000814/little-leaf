"""Exact local/hosted admission; only bounded provenance and aggregates escape."""
import hashlib, json, os, subprocess, sys
from pathlib import Path


HERE=Path(__file__).resolve().parent
HEAD="ce1435afb2329a6c1d2d77a8a19923dfd96bd205"
TREE="03632a0d56e4294f5664859656c8809541766d1b"
ARCHIVE="5a236669cca594a1437b289f4b4b8a933a204ddab064844485d2868ce8ee1406"
FIXTURE="ed6fcfc1e4a3396389eff71b09f60740d099de9c046eb0e37eabe900e8c1cf4f"
ENGINE="f64d4ed19fc9df9440321653fcc80df8c6e365ba7b6de0a29e2cfa9fa71bfeb3"
PROJECT="11e9548d8019c2052dd6f8496ab50e47feb70d31e0b885f4e40b379539deec13"
ARTIST="732ee0dc45e2ff38122d719c30721984a5a2649d54bfaf5a6c41935a6ed381d5"
INSTALLER={
 "tools/ci/install_tools.py":"76790d83bd436f73408515d5890763478a027f5645fde883776bcc92db81604f",
 "tools/ci/toolchain.json":"529627e9b964f98b417220ebde30d60388531fc53fc0b1fbad19fa4eb427fc70",
 "tools/ci/chrome.json":"086165986b36e4b03e11c2f590564e54f1dabcd789cca27ec88a1fa8c7b4cfaa",
}
FILES=set(['fixture.json', 'guard.py', 'live.gd', 'll397_active_backdrop.gd', 'll397_forensic_diff.gd', 'matched.gd', 'owner.gd', 'prepare.py', 'probe.gd', 'report.py', 'run.sh'])
MAPPING={'probe.gd': 'll397_gain_probe.gd', 'll397_active_backdrop.gd': 'll397_active_backdrop.gd', 'll397_forensic_diff.gd': 'll397_forensic_diff.gd', 'owner.gd': 'll397_acquire_owner.gd', 'live.gd': 'll397_acquire_live.gd', 'matched.gd': 'll397_acquire_probe.gd'}
REPO="yiyousiow000814/little-leaf"
REF="refs/heads/qa/backdrop-acquisition-397"
PREFIX="tools/diagnostics/backdrop-acquisition-397/"
WF=".github/workflows/backdrop-acquisition-397.yml"
FAIL={"host_class","source_binding","sparse_source","stage_binding","engine_acquisition","engine_sha","import","display",
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
    need(not any(p.is_symlink() for p in HERE.rglob("*")), "symlink not permitted")
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
    paths={WF}|{PREFIX+f for f in FILES|{"manifest.json"}}
    metadata=git(repo,"ls-tree","-r",head,"--",*sorted(paths)).splitlines()
    need(len(metadata)==len(paths) and all(line.startswith("100644 blob ") for line in metadata),"unsafe file mode")
    rows={tuple(x.split("\t")) for x in git(repo,"diff","--name-status","--no-renames","HEAD^","HEAD").splitlines()}
    need(rows=={("A",p) for p in {WF}|{PREFIX+f for f in FILES|{"manifest.json"}}},"unapproved commit scope")

def source(repo):
    need(git(repo,"rev-parse","HEAD")==HEAD and git(repo,"rev-parse","HEAD^{tree}")==TREE,"wrong product")
    need(all((repo/p).is_file() and sha(repo/p)==d for p,d in INSTALLER.items()),"incomplete or changed sparse installer dependencies")
    need((repo/"game/project.godot").is_file(),"missing game directory")

def stage(root,receipt):
    expected=json.loads(receipt.read_bytes())
    need(expected.get('head')==HEAD and expected.get('tree')==TREE and expected.get('game_before_sha256')==ARCHIVE and expected.get('synthetic_fixture')==FIXTURE,'bad source receipt')
    files=expected['staged_postimages']
    checks={'project.godot':PROJECT,'scripts/rendering/illustrated_cafe.gd':ARTIST,**{dst:sha(HERE/src) for src,dst in MAPPING.items()}}
    need(files==checks and all(sha(root/'game'/k)==v for k,v in checks.items()),'wrong bounded staged changes')
    need(sha(root/'private/data/godot/app_userdata/Little Leaf Cafe/little_leaf_cafe_layout_motion_v15.json')==FIXTURE,'not synthetic')

def base():
    return {"product":HEAD,"tree":TREE,"archive_sha256":ARCHIVE,"fixture_sha256":FIXTURE,"engine_sha256":ENGINE}

def write(out,result):
    raw=(json.dumps(result,sort_keys=True,allow_nan=False)+"\n").encode()
    need(len(raw)<24576,"summary exceeded max safe size")
    out.parent.mkdir(parents=True,exist_ok=True)
    tmp=out.with_suffix(".writing")
    with tmp.open("xb") as f:f.write(raw)
    tmp.replace(out)

def fail(out,label):
    need(label in FAIL,"unexpected status")
    write(out,{"schema":"ll397-backdrop-acquisition-hosted-v1","status":"not_qualified","stage":label,**base()})

if __name__=="__main__":
    op=sys.argv[1]
    if op=="event":event(Path(sys.argv[2]),json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_bytes()),os.environ)
    elif op=="source":source(Path(sys.argv[2]))
    elif op=="stage":stage(Path(sys.argv[2]),Path(sys.argv[3]))
    elif op=="fail":fail(Path(sys.argv[2]),sys.argv[3])
    elif op=="package":
        # Report validates & reconstructs fields from input; only validated summary
        # constructed inside runner-private scratch is ever published.
        import tempfile
        from report import publish
        private,out,rc=Path(sys.argv[2]),Path(sys.argv[3]),int(sys.argv[4])
        manifest()
        with tempfile.TemporaryDirectory(dir=private.parent) as tmp:
            validated=Path(tmp)/"validated.json"
            code=publish(private,validated,HEAD,TREE,ENGINE,sha(HERE/'matched.gd'),sha(HERE/'owner.gd'))
            value=json.loads(validated.read_bytes())
        if code==0:
            need(rc==0 and value.get("status")=="valid_observations_no_adoption" and value.get("adoption_qualified") is False and value.get("no_spike_gate_established") is False,"mismatching complete observation")
        else:
            need(code==2 and value.get("status")=="not_qualified" and value.get("measurements_published") is False,"unsafe rejection")
        envelope={"schema":"ll397-backdrop-acquisition-hosted-v1",**base(),"manifest_sha256":sha(HERE/"manifest.json"),"status":value["status"],"summary":value}
        write(out,envelope)
        raise SystemExit(code)
    else:raise SystemExit("unknown guard operation")
