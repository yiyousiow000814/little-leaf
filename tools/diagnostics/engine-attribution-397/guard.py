"""Read and validate build-only inputs; no installer, linker, runtime or upload."""
import hashlib,json,math,os,pathlib,platform,re,shlex,shutil,subprocess,sys,tarfile,zipfile

H=pathlib.Path(__file__).resolve().parent
BASE="ce1435afb2329a6c1d2d77a8a19923dfd96bd205"; TREE="03632a0d56e4294f5664859656c8809541766d1b"
TAG="35e80b3a8822a9df9be390814b62f44c0a9c69e8"; STAMP="7d41c59c457bd5a245092b4e7eb2d833e3b3f8c3"
REPO="yiyousiow000814/little-leaf"; REF="refs/heads/qa/engine-attribution-397"
PREFIX="tools/diagnostics/engine-attribution-397/"; WF=".github/workflows/engine-attribution-397.yml"
FILES={"inputs.json","engine-scopes.review.patch","source.sha256","partial_targets.py","guard.py","run.sh","prepare.py","probe.gd","measure.sh","qualify.py","product.json","stage.py","fixture.json"}
STAGES={
"source_guard","capacity","host_base_tools","host_deb_tool","accesskit_root","patch",
"sdk_relocate","sdk_compiler","sdk_pkg_config","scanner_download","scanner_checksum","scanner_dependency",
"scanner_smoke","db","feature_mode","dry_run","partial_compile","object_verify",
"full_capacity","full_compile","binary_abi","stage_binding","official_binary","import","display","session","qualification","workload","stock_noise","rebuild_match","marker_overhead","native_accounting","dominant_not_repeatable"}
ASSETS=("source","sdk","accesskit","scons")
STAGES.update(f"{asset}_{phase}" for asset in ASSETS for phase in ("download","checksum","manifest","extract"))
SDK_HASH="b89f173b1f2f2f35f3090bc4efad732f1c0c1c1206e5480cfcb141977010bc94"
SDK_ROOT="x86_64-godot-linux-gnu_sdk-buildroot"
SDK_SYSROOT=SDK_ROOT+"/x86_64-godot-linux-gnu/sysroot"
SDK_FONT_NAMES="""10-hinting-slight 10-scale-bitmap-fonts 10-yes-antialias 10-sub-pixel-none
11-lcdfilter-default 20-unhint-small-vera 30-metric-aliases 40-nonlatin 45-generic 45-latin
48-spacing 49-sansserif 50-user 51-local 60-generic 60-latin 65-fonts-persian 65-nonlatin
69-unifont 80-delicious 90-synthetic""".split()
SDK_OMIT={f"{SDK_SYSROOT}/etc/fonts/conf.d/{n}.conf":
          (f"/usr/share/fontconfig/conf.avail/{n}.conf",tarfile.SYMTYPE) for n in SDK_FONT_NAMES}

def req(ok,msg):
    if not ok: raise ValueError(msg)
def sha(p):
    with p.open("rb") as f:return hashlib.file_digest(f,"sha256").hexdigest()
def git(root,*a):
    return subprocess.check_output(["git","-C",str(root),*a]).decode().strip()
def locked():
    vals=json.loads((H/"seal.json").read_bytes())
    req(set(vals)==FILES and {p.name for p in H.iterdir()}==FILES|{"seal.json"} and
        all((H/name).is_file() and sha(H/name)==digest for name,digest in vals.items()),"bad seal")
    return json.loads((H/"inputs.json").read_bytes())
def event(root,ev,environ):
    locked();head=environ["GITHUB_SHA"]
    req(environ["GITHUB_ACTIONS"]=="true" and environ["GITHUB_REPOSITORY"]==REPO and
        environ["GITHUB_ACTOR"]==REPO.split("/")[0] and environ["GITHUB_REF"]==REF and
        environ["GITHUB_EVENT_NAME"]=="push" and environ["GITHUB_RUN_ATTEMPT"]=="1","wrong launch context")
    req(ev.get("before")==BASE and ev.get("after")==head and ev.get("ref")==REF and
        all(ev.get(key) is False for key in ("created","deleted","forced")),"wrong one-shot transition")
    req(git(root,"rev-list","--parents","-n","1","HEAD").split()==[head,BASE] and
        git(root,"rev-parse","HEAD^^{tree}")==TREE,"wrong direct parent")
    actual={tuple(line.split("\t")) for line in git(root,"diff","--name-status","--no-renames","HEAD^","HEAD").splitlines()}
    req(actual=={("A",p) for p in {WF}|{PREFIX+f for f in FILES|{"seal.json"}}},"wrong scope")
def capacity(root,phase):
    kib=int(re.search(r"^MemAvailable:\s+(\d+)",pathlib.Path("/proc/meminfo").read_text(),re.M)[1])
    avail=kib*1024
    cgroup=pathlib.Path("/sys/fs/cgroup")
    if (cgroup/"memory.max").is_file():
        max_mem=(cgroup/"memory.max").read_text().strip()
        if max_mem!="max":avail=min(avail,int(max_mem)-int((cgroup/"memory.current").read_text()))
    cpus=len(os.sched_getaffinity(0))
    if (cgroup/"cpu.max").is_file():
        quota,period=(cgroup/"cpu.max").read_text().split()
        if quota!="max":cpus=min(cpus,int(quota)//int(period))
    free=shutil.disk_usage(root).free
    minimum=12 if phase in {"initial","staged","full"} else 4
    req(phase in {"initial","staged","full"} and platform.machine()=="x86_64" and cpus>=4 and avail>=12*1024**3 and free>=minimum*1024**3,"worker capacity below gate")
    return {"cpus":cpus,"ram_mib":avail//1024**2,"disk_mib":free//1024**2}
def verify_asset(key,archive):
    lock=json.loads((H/"inputs.json").read_bytes())[key]
    req(archive.stat().st_size==lock["bytes"] and sha(archive)==lock["sha256"],"bad official asset checksum or size")
def sdk_members(items, verified_sha):
    req(verified_sha==SDK_HASH,"unexpected SDK for omission")
    req(len({m.name for m in items})==len(items),"duplicate SDK member")
    seen=set()
    kept=[]
    for m in items:
        if m.name in SDK_OMIT:
            req((m.linkname,m.type)==SDK_OMIT[m.name],"changed pinned SDK font link")
            seen.add(m.name)
        else:
            kept.append(m)
    req(seen==set(SDK_OMIT),"missing pinned SDK font link")
    return kept

def verify_unpack(key,archive,dst,manifest_only):
    # Verify again in the extraction process; never rely on prior manifest/checksum invocations.
    verify_asset(key,archive)
    req(not dst.exists() and not dst.is_symlink(),"destination already exists")
    if key in {"source","sdk"}:
        cap=600*1024**2 if key=="source" else 1024**3
        with tarfile.open(archive,"r:*") as t:
            items=t.getmembers()
            req(len(items)<100000 and sum(m.size for m in items if m.isfile())<=cap,"unpacked asset cap")
            if key=="source":
                req(t.pax_headers.get("comment")==TAG and t.extractfile("godot-4.6.3-stable/.git/HEAD").read().decode().strip()==STAMP,
                    "wrong source metadata")
            else:
                items=sdk_members(items,sha(archive))
            if manifest_only:
                for m in items: tarfile.data_filter(m,dst)
            else:
                dst.mkdir(mode=0o700)
                # A preflight alone cannot see links created by earlier entries. Filter at extraction too.
                t.extractall(dst,members=items,filter="data")
    else:
        with zipfile.ZipFile(archive) as z:
            entries=z.infolist()
            req(len(entries)<50000 and sum(i.file_size for i in entries)<=800*1024**2 and
                all(not i.filename.startswith("/") and ".." not in pathlib.PurePosixPath(i.filename).parts and
                    ((i.external_attr>>16)&0o170000)!=0o120000 for i in entries),"unsafe/unbounded zip")
            if not manifest_only:
                dst.mkdir(mode=0o700)
                z.extractall(dst)
def loader_paths(raw):
    expected={"libexpat.so.1","libxml2.so.2","libc.so.6"}
    seen=set()
    req("not found" not in raw and len(raw)<8192,"unsupported loader result")
    for line in raw.splitlines():
        match=re.fullmatch(r"\s*([^\s]+) => (/[^\s]+) \(0x[0-9a-f]+\)\s*",line)
        if match:
            so,path=match.groups()
            req(re.fullmatch(r"/(?:usr/)?lib/x86_64-linux-gnu/[^/]+",path),"nonstock shared library")
            seen.add(so)
        else:
            req(re.fullmatch(r"\s*(?:linux-vdso\.so\.1|/(?:usr/)?lib64/ld-linux-x86-64\.so\.2) \(0x[0-9a-f]+\)\s*",line),"nonstock loader output")
    req(expected<=seen,"missing named library")
def dry(raw,targets,compiler):
    expected=set(targets);seen=[]
    req(len(expected)==5,"expected five")
    for line in raw.splitlines():
        try:args=shlex.split(line)
        except ValueError: continue
        if not args:continue
        head=pathlib.Path(args[0]).name
        if (head==compiler or re.search(r"(?:gcc|g\+\+|clang|clang\+\+|(?:^|-)ar|(?:^|-)ld)$",head)) and ("-o" in args or head.endswith(("ar","ld"))):
            req(head==compiler and "-c" in args and args.count("-o")==1,"dry run would link or use wrong compiler")
            seen.append(args[args.index("-o")+1])
    req(len(seen)==5 and set(seen)==expected,"dry run wasn't exactly the five objects")
def summary(out,state,stage,cap=None):
    req(state=="not_qualified" and stage in STAGES,"bad result")
    info={"schema":"ll397-engine-full-v1","stage":stage,"status":state,"product":BASE,"tree":TREE,
          "upstream_source_tag":TAG,"upstream_build_stamp":STAMP,"patch_sha256":sha(H/"engine-scopes.review.patch"),
          "executables_uploaded":False}
    b=(json.dumps(info,sort_keys=True)+"\n").encode();req(len(b)<=4096,"overlong evidence")
    out.parent.mkdir(parents=True,exist_ok=True);out.write_bytes(b)
if __name__=="__main__":
    cmd=sys.argv[1]
    if cmd=="event":event(pathlib.Path(sys.argv[2]),json.loads(pathlib.Path(os.environ["GITHUB_EVENT_PATH"]).read_bytes()),os.environ)
    elif cmd=="capacity":print(json.dumps(capacity(pathlib.Path(sys.argv[2]),sys.argv[3])))
    elif cmd=="asset_check":verify_asset(sys.argv[2],pathlib.Path(sys.argv[3]))
    elif cmd=="loader":loader_paths(pathlib.Path(sys.argv[2]).read_text())
    elif cmd in {"manifest","extract"}:verify_unpack(sys.argv[2],pathlib.Path(sys.argv[3]),pathlib.Path(sys.argv[4]),cmd=="manifest")
    elif cmd=="asset":print(json.loads((H/"inputs.json").read_bytes())[sys.argv[2]]["url"])
    elif cmd=="dry":dry(pathlib.Path(sys.argv[2]).read_text(),pathlib.Path(sys.argv[3]).read_text().splitlines(),sys.argv[4])
    elif cmd=="summary":summary(pathlib.Path(sys.argv[2]),sys.argv[3],sys.argv[4],json.loads(pathlib.Path(sys.argv[5]).read_bytes()) if len(sys.argv)==6 else None)
    else:raise SystemExit("unknown operation")
