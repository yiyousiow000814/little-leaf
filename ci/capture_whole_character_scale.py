"""Bounded opt-in baseline/1.25/1.40 native study. No production default or save writes."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import tempfile
import time
import zipfile
ROOT=Path(__file__).resolve().parents[1]
FIXTURE="tests/capture_whole_character_scale.gd"
def git(*args):return subprocess.check_output(["git","-C",str(ROOT),*args])
def sha(data):return hashlib.sha256(data).hexdigest()
def run_stage(command,env,log):
    with log.open("wb") as stream:
        process=subprocess.Popen(command,env=env,stdout=stream,stderr=subprocess.STDOUT,start_new_session=True)
        start=time.monotonic();reason=None
        while process.poll() is None:
            time.sleep(.5);text=log.read_text(errors="replace")
            if "SCRIPT ERROR" in text or "ERROR:" in text:reason="engine error"
            elif time.monotonic()-start>300:reason="stage exceeded300s"
            if reason:
                os.killpg(process.pid,signal.SIGTERM)
                try:process.wait(timeout=10)
                except subprocess.TimeoutExpired:os.killpg(process.pid,signal.SIGKILL);process.wait()
                break
    text=log.read_text(errors="replace")
    if reason or process.returncode or "SCRIPT ERROR" in text or "ERROR:" in text:
        print(text[-14000:],flush=True);raise RuntimeError(reason or "engine failed")
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument("--expected-head",required=True);p.add_argument("--output",type=Path,required=True);a=p.parse_args()
    if not re.fullmatch(r"[0-9a-f]{40}",a.expected_head):p.error("exact commit required")
    head=git("rev-parse","HEAD").decode().strip()
    if head!=a.expected_head:raise RuntimeError("unexpected checkout")
    out=a.output.resolve();out.mkdir(parents=True,exist_ok=True)
    if any(out.iterdir()):raise RuntimeError("output must be new")
    report={"status":"running","source_commit":head,"source_tree":git("rev-parse","HEAD^{tree}").decode().strip(),"production_default_changed":False,"player_save_used":False}
    def save():(out/"source-variant-receipt.json").write_text(json.dumps(report,indent=2)+"\n")
    save()
    try:
        with tempfile.TemporaryDirectory(prefix="character-proportions-") as folder:
            root=Path(folder);project=root/"project";project.mkdir()
            with zipfile.ZipFile(io.BytesIO(git("archive","--format=zip",head))) as archive:
                for name in archive.namelist():
                    if Path(name).is_absolute() or ".." in Path(name).parts:raise RuntimeError("unsafe archive path")
                archive.extractall(project)
            report["source_sha256"]={str(f.relative_to(project)):sha(f.read_bytes()) for f in sorted(project.rglob("*")) if f.is_file()}
            report["variant_definition_sha256"]=sha((project/"scripts/illustrated_cafe.gd").read_bytes())
            stage=project/"scripts/cafe_web_save.gd";code=stage.read_text();old='const STAGING_FILE="/tmp/little_leaf_vault_staging.json"'
            if old not in code:raise RuntimeError("review staging isolation")
            stage.write_text(code.replace(old,'const STAGING_FILE="user://generated_proportion_stage.json"'))
            env=os.environ.copy()
            for key in ("HOME","APPDATA","LOCALAPPDATA","XDG_DATA_HOME","XDG_CONFIG_HOME","XDG_CACHE_HOME"):
                path=root/"profile"/key.lower();path.mkdir(parents=True);env[key]=str(path)
            env["WHOLE_SCALE_CAPTURE_OUTPUT"]=str(out);env["LIBGL_ALWAYS_SOFTWARE"]="1"
            godot=os.environ.get("GODOT_BIN","godot")
            run_stage([godot,"--headless","--path",str(project),"--editor","--import","--quit"],env,out/"import.log")
            run_stage([godot,"--headless","--path",str(project),"--script","tests/test_whole_character_scale.gd","--","--visual-qa","--skip-intro","--skip-tutorial"],env,out/"variant-tests.log")
            run_stage(["xvfb-run","-a","-s","-screen 0 1600x1000x24",godot,"--path",str(project),"--audio-driver","Dummy","--rendering-method","gl_compatibility","--script",FIXTURE,"--","--skip-intro","--visual-qa"],env,out/"capture.log")
            study=json.loads((out/"study.json").read_text());frames=study["frames"]
            expected={f"{v}-{z}.png" for v in ("baseline","scale125","scale140") for z in ("normal","review","door")}
            if len(frames)!=9 or {f["file"] for f in frames}!=expected:raise RuntimeError("missing comparison frame")
            if not study.get("renderer") or study.get("head_art_scaled") is not True:raise RuntimeError("invalid render/profile receipt")
            report["frames"]={}
            for frame in frames:
                data=(out/frame["file"]).read_bytes()
                if not data.startswith(b"\x89PNG\r\n\x1a\n") or len(data)<1000:raise RuntimeError("invalid native PNG")
                report["frames"][frame["file"]]={"sha256":sha(data),"bytes":len(data),"variant":frame["variant"]}
            report["status"]="rendered_pending_user_review"
    except Exception as error:report["status"]="failed";report["error"]=str(error);raise
    finally:save()
if __name__=="__main__":main()
