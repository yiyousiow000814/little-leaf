"""One-shot, read-only #392/#394 Mail/Parking/Storage native supplement."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
from png_rgba import rgba_digest

BASE = "0f04d4c196b48b7f6f41462801477a3accbbf510"
HEAD = "bcf98740388339c8be25112d0cbc4b06dd0220a3"
TREES = {BASE:"737ef9445cc9462cd56b692c5fc9fe5af27e865f", HEAD:"af80122978a453a01a13312a2c9512a4a818a3f7"}
ENGINE = "f64d4ed19fc9df9440321653fcc80df8c6e365ba7b6de0a29e2cfa9fa71bfeb3"
MAIN = "game/scripts/main.gd"
POST = {
 MAIN:"8c61d1056fc19d206d1bfbfeed6d1f746c94cd32d847ca8c66b0ed84e06b847f",
 "game/scripts/core/cafe_model.gd":"d7c8ecd5e727f952910ba930f9f37bd6d8300399f6616f6c1260d726b18b6a76",
 "tests/service/test_order_reach.gd":"1a1267d42c596f5bd9d0d00c199d34dc87dfe0e6bfcbe3126077560c115c967d",
 "docs/development/scaling-hotpaths-12/README.md":"8efcaf7f99efe869cdd2c6917f1ac4f3af50202bb3b52ab93b3925568a405f6b",
 "docs/development/scaling-hotpaths-12/scaling-hotpaths-12.mmd":"df7b4d8a910cd0df6dfa73acb08299f43286926955bc4b8916e8710beceda514",
 "docs/development/scaling-hotpaths-12/scaling-ledger-12.xlsx":"b2a95e6ca4e676ddf181eb532be395fc8c127df7d91426ee4716a274fddab386",
}
BASE_MAIN = "ce5e31dabaa771689227275ab60fc38e66fd0df294a93077c4aa3543922f0473"
MAIL = "tests/persistence/test_support_mail_ui.gd"
PARKING = "tests/world/test_parking_decor_ui.gd"
STORAGE = "tests/presentation/test_storage_ui.gd"
FIXTURES = {
 MAIL:"d6d6d4cffd4482658d22c5f38b4c692ebb0cb704a9dfcc3e60090ec229ca7306",
 PARKING:"747e54edd43a6f150bc5f3f6a2014a4200eeea3bb40560c3332b89225158e5db",
 STORAGE:"d934d9a86331ce368f69655d8297c789aa9d6ab17b8094e30dbf468af5b08355",
}
ARCHIVE_PATHS = ("game", "platform/web", "tests", "tools", "docs/testing")
MAIL_FRAMES = {f"editable-composer-{w}x{h}.png":(w,h) for w,h in [(1360,880),(390,844),(844,390)]}
PARKING_FRAMES = {f"parking-{state}-566x360.png":(566,360) for state in ["unowned","owned"]}
STORAGE_MIN_FRAMES = {f"{slot}-566x360.png" for slot in ["shop","storage","storage-categories","store-action"]}

def need(ok,msg):
    if not ok:raise ValueError(msg)

def digest(data):return hashlib.sha256(data).hexdigest()
def sha(path):return digest(Path(path).read_bytes())
def git(repo,*args):return subprocess.check_output(["git","-C",str(repo),*args])
def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path)
    obj=importlib.util.module_from_spec(spec);spec.loader.exec_module(obj);return obj

def bind(repo):
    for rev,tree in TREES.items():
        need(git(repo,"rev-parse",rev+"^{tree}").decode().strip()==tree,"wrong tree")
    parents=[line.split()[1] for line in git(repo,"cat-file","-p",HEAD).decode().split("\n\n",1)[0].splitlines() if line.startswith("parent ")]
    need(parents==[BASE],"wrong parent")
    need(set(git(repo,"diff","--name-only",BASE,HEAD).decode().splitlines())==set(POST),"unreviewed paths")
    need(all(digest(git(repo,"show",f"{HEAD}:{p}"))==h for p,h in POST.items()),"unexpected head postimage")
    need(digest(git(repo,"show",f"{BASE}:{MAIN}"))==BASE_MAIN,"unexpected base Main")
    for rev in TREES:
        need(all(digest(git(repo,"show",f"{rev}:{p}"))==h for p,h in FIXTURES.items()),"changed fixture")

def archive(repo,rev,dest):
    with tempfile.NamedTemporaryFile(suffix=".tar") as f:
        subprocess.run(["git","-C",str(repo),"archive","--format=tar",rev,*ARCHIVE_PATHS],stdout=f,check=True)
        f.flush();f.seek(0)
        h=hashlib.file_digest(f,"sha256").hexdigest();f.seek(0)
        with tarfile.open(fileobj=f) as t:t.extractall(dest,filter="data")
    return h

def atlas(root):
    mod=module("atlas_guard",root/"tools/qualification/verify_prebaked_atlases.py")
    manifest=json.loads((root/"game/data/prebaked_atlas_manifest.json").read_bytes())
    sources=mod.sources()
    need(len(sources)==85 and sources==manifest["source_sha256"],"unexpected qualified 85-source manifest")
    images={name:mod.asset(name) for name in mod.NAMES}
    for name,v in images.items():
        need(all(manifest["atlases"][name][k]==val for k,val in v.items()),"asset/import mismatch")
    return {"manifest_sha256":sha(root/"game/data/prebaked_atlas_manifest.json"),"sources":sources,"images":images}

def run_command(command,env,output):
    with output.open("wb") as log:
        subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,env=env,check=True,timeout=300)
    data=output.read_text(errors="replace")
    need("ERROR:" not in data,"engined reported ERROR: "+str(output))
    return data

def storage_frames(path,log):
    rows=[json.loads(line.split(" ",1)[1]) for line in log.splitlines() if line.startswith("STORAGE_UI_RESULT ")]
    need(len(rows)==1 and rows[0]["checks"]>=100 and rows[0]["failures"]==[] and rows[0]["player_save_used"] is False,"invalid actual Storage UI receipt")
    present={p.name for p in path.glob("*.png")}
    need(STORAGE_MIN_FRAMES<=present and all(name.endswith("-566x360.png") for name in present),"incomplete actual Storage panel evidence")
    return rows[0]

def read_frames(path, expected):
    present={n.name for n in path.glob("*.png")}
    need(present==set(expected),"missing or extra PNGs")
    result={}
    for name,size in expected.items():
        p=path/name
        dimensions,rgba=rgba_digest(p,size)
        result[name]={"size":list(dimensions),"rgba_sha256":rgba,"png_sha256":sha(p)}
    return result

def compare(control,candidate):
    need(set(control)==set(candidate),"surface set mismatch")
    for scope,frames in control.items():
        need(set(frames)==set(candidate[scope]),"frame set mismatch: "+scope)
        for filename,row in frames.items():
            new=candidate[scope][filename]
            need((row["size"],row["rgba_sha256"])==(new["size"],new["rgba_sha256"]),"pixel mismatch: "+scope+"/"+filename)
    return sum(map(len,control.values()))

def prove_sparse_stage(root,temp):
    stage=module("stage_layout",root/"tools/build/project_layout.py").stage_project
    place=temp/"bind-stage"
    stage(root,place,tests=True,ignore=shutil.ignore_patterns(".git",".godot","__pycache__"))
    need(all(sha(place/p)==h for p,h in FIXTURES.items()),"stage missing fixture or changed bytes")
    need(sha(place/"scripts/main.gd")==sha(root/MAIN),"stage Main changed")
    need((place/"web").is_dir() and (place/"docs/testing").is_dir(),"stage omitted reviewed resources")
    files={p.relative_to(place).as_posix():sha(p) for p in sorted(place.rglob("*")) if p.is_file()}
    return {"file_count":len(files),"file_sha256_map_digest":digest(json.dumps(files,sort_keys=True,separators=(",",":")).encode())}

def capture(root,engine,out,stage_home):
    stage=module("stage_project",root/"tools/build/project_layout.py").stage_project
    mail=module("frozen_mail_checker",root/"tools/diagnostics/mail_native_review.py")
    boundary=module("frozen_storage_checker",root/"tools/diagnostics/storage_native_review.py")
    layout=stage_home/"project"
    stage(root,layout,tests=True,ignore=shutil.ignore_patterns(".git",".godot","__pycache__"))
    original={p.relative_to(layout).as_posix():sha(p) for p in layout.rglob("*") if p.is_file()}
    config=layout/"project.godot"; web=layout/"scripts/persistence/cafe_web_save.gd"
    runtime=config.read_text()
    need("[application]" in runtime and "[editor]" not in runtime,"staging config changed")
    runtime=runtime.replace("[application]",'[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="successor-native-saveguard"',1)
    old='const STAGING_FILE="/tmp/little_leaf_vault_staging.json"'
    need(old in web.read_text(),"staging vault changed")
    web.write_text(web.read_text().replace(old,'const STAGING_FILE="user://generated_supplement_stage.json"',1))
    config.write_text(runtime+"\n[editor]\nimport/use_multiple_threads=false\n")
    def environment(tag):
        env=os.environ.copy()
        for key in ("HOME","APPDATA","LOCALAPPDATA","XDG_DATA_HOME","XDG_CONFIG_HOME","XDG_CACHE_HOME"):
            p=stage_home/"profile"/tag/key.lower();p.mkdir(parents=True);env[key]=str(p)
        env["LIBGL_ALWAYS_SOFTWARE"]="1"
        env["GALLIUM_DRIVER"]="llvmpipe"
        return env
    out.mkdir()
    command=[str(engine),"--path",str(layout),"--audio-driver","Dummy"]
    try:
        run_command(command+["--headless","--editor","--import","--quit"],environment("import"),out/"import.log")
    finally:
        config.write_text(runtime)
    frames={};results={}
    for scope,fixture,flags in [
      ("mail-composer",MAIL,["--capture-composer-only"]),
      ("parking-boundary",PARKING,["--parking-short-boundary"]),
      ("storage-panel-supplement",STORAGE,["--storage-short-boundary"])]:
        place=out/scope;place.mkdir()
        env=environment(scope)
        if fixture==MAIL:flags=flags+["--capture-dir="+str(place)]
        else:env["LL_CAPTURE_OUTPUT"]=str(place)
        log=run_command(command+["--display-driver","x11","--rendering-method","gl_compatibility","--script","res://"+fixture,"--",
            "--visual-qa","--fresh-review","--skip-intro","--skip-tutorial",*flags],env,out/(scope+".log"))
        need("Godot Engine v4.6.3.stable.official.7d41c59c4" in log and "OpenGL API" in log and "Compatibility" in log and "llvmpipe" in log.lower(),"not exact native software GL")
        if fixture==MAIL:
            results[scope]=mail.check_frames(place,log)["result"];expected=MAIL_FRAMES
        elif fixture==PARKING:
            results[scope]=boundary.check_frames(place,log)["result"];expected=PARKING_FRAMES
        else:
            results[scope]=storage_frames(place,log);expected={p.name:(566,360) for p in place.glob("*.png")}
        frames[scope]=read_frames(place,expected)
    overrides={"project.godot":sha(config),"scripts/persistence/cafe_web_save.gd":sha(web)}
    need(all(sha(layout/p)==h for p,h in original.items() if p not in overrides),"staged non-override bytes changed")
    need(not list((stage_home/"profile").rglob("little_leaf_cafe_layout_motion_v15.json")),"normal profile save present")
    return {"frame_results":frames,"native_assertions":results,"disposable_overrides":overrides,"staged_files":len(original)}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo",type=Path,required=True);parser.add_argument("--out",type=Path,required=True)
    parser.add_argument("--engine",type=Path,default=Path("/usr/local/bin/godot"));parser.add_argument("--bind-only",action="store_true")
    args=parser.parse_args()
    need(args.out.is_absolute() and not args.out.exists(),"output must be a fresh absolute directory")
    args.out.mkdir(parents=True);report={"base":BASE,"head":HEAD,"trees":TREES,"main_sha256":{BASE:BASE_MAIN,HEAD:POST[MAIN]},"fixture_sha256":FIXTURES,"adapter_sha256":sha(__file__),"decoder_sha256":sha(Path(__file__).with_name("png_rgba.py")),"synthetic_only":True,"player_save_used":False,"atlas_regenerated":False,"historical_acceptance_changed":False,"historical_scope":{"mail":"original composer footer, 3 sizes","parking":"original Storage-boundary Parking only, 2 frames","storage":"separate actual Storage UI short boundary supplement"},"sources":{}}
    try:
        bind(args.repo);need(sha(args.engine)==ENGINE,"not exact native engine");report["engine_sha256"]=ENGINE
        need(args.bind_only or os.environ.get("DISPLAY"),"Private X11 display required; no headless pixel parity claim")
        for rev in (BASE,HEAD):
            with tempfile.TemporaryDirectory(prefix="successor-native-saveguard-") as temp:
                temp=Path(temp);root=temp/"archive";root.mkdir()
                bound={"archive_sha256":archive(args.repo,rev,root),"atlas":atlas(root)}
                report["sources"][rev]=bound
                if not args.bind_only:
                    bound.update(capture(root,args.engine,args.out/rev,temp))
                else:bound["sparse_project_stage"]=prove_sparse_stage(root,temp)
        need(report["sources"][BASE]["atlas"]==report["sources"][HEAD]["atlas"],"changed atlas closure or assets")
        if not args.bind_only:
            results=[report["sources"][rev] for rev in (BASE,HEAD)]
            report["compared_count"]=compare(*(x["frame_results"] for x in results))
            report["status"]="exact_decoded_rgba_equal_not_user_acceptance"
        else:report["status"]="inputs_bound_only_no_capture"
    except Exception as exc:
        report["status"]="failed";report["error"]=str(exc);raise
    finally:
        (args.out/"summary.json").write_text(json.dumps(report,indent=2)+"\n")

if __name__=="__main__":main()
