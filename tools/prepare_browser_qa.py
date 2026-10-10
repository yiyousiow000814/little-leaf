"""Prepare synthetic native coordinates for browser QA: wall or cloud geometry.

Only the selected scenario runs. Wall retains the exact old/new export gate;
cloud retains its six measured layouts. Neither uses player profiles.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from project_layout import source_path, stage_project
from build_web import verify_installer_receipt
from artifacts import sha256

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / 'tests/fixtures/wall-compatibility'
CONTRACT = json.loads((FIXTURES / 'contract.json').read_text())
sys.path.insert(0, str(ROOT / 'tests'))
from run_integration_candidate import EXCLUDE

def synthetic_profile(folder):
    env = os.environ.copy()
    for key in ('HOME', 'APPDATA', 'LOCALAPPDATA', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME'):
        path = folder / key.lower()
        path.mkdir(parents=True)
        env[key] = str(path)
    return env


def validate_export(build, source, old=False):
    manifest = json.loads((build / "web/release-manifest.json").read_text())
    commit = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
    if subprocess.check_output(["git", "-C", str(source), "status", "--porcelain", "--untracked-files=no"], text=True).strip():
        raise RuntimeError("Compatibility inputs require clean tracked source")
    if manifest["source_commit"] != commit or (old and commit != CONTRACT["old_commit"]):
        raise RuntimeError("Export/source commit mismatch")
    if manifest.get("toolchain_verification") != "checksum-pinned-official-archives":
        raise RuntimeError("Compatibility CI requires the pinned official toolchain")
    if old:
        if manifest["production_sha256"].get("web/little_leaf_vault.js") != CONTRACT["old_vault_sha256"]:
            raise RuntimeError("Historical vault hash differs")
    elif not set(CONTRACT["candidate_required_sources"]).issubset(manifest["production_sha256"]):
        raise RuntimeError("Candidate export is missing required production sources")
    for name, expected in manifest["production_sha256"].items():
        if sha256(source_path(source, name)) != expected or sha256(build / "project" / name) != expected:
            raise RuntimeError("Source/export production mismatch: " + name)
    for name, spec in manifest["files"].items():
        file = build / "web" / name
        if file.stat().st_size != spec["bytes"] or sha256(file) != spec["sha256"]:
            raise RuntimeError("Export asset changed: " + name)
    return manifest


def wall_main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ["old-source", "old-build", "new-build", "output"]:
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args(argv)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    for name, expected in CONTRACT["fixture_sha256"].items():
        if sha256(FIXTURES / name) != expected:
            raise RuntimeError("Fixture changed: " + name)
    old = validate_export(args.old_build, args.old_source, old=True)
    new = validate_export(args.new_build, ROOT)
    if old["toolchain_receipt"] != new["toolchain_receipt"]:
        raise RuntimeError("Old and new exports must use the same pinned toolchain")
    godot = os.environ.get("GODOT_BIN", "godot")
    installed = verify_installer_receipt(
        Path(shutil.which(godot) or godot).resolve(), Path(os.environ["GODOT_TEMPLATE"]),
        Path(os.environ["GODOT_TOOLCHAIN_RECEIPT"]))
    if installed != new["toolchain_receipt"]:
        raise RuntimeError("Native layout preflight must use the exports' verified toolchain")
    receipt = {"browser_verified": False, "synthetic_only": True, "old_commit": old["source_commit"],
               "new_commit": new["source_commit"], "fixture_sha256": CONTRACT["fixture_sha256"], "layouts": {},
               "production_sha256": {"old": old["production_sha256"], "new": new["production_sha256"]},
               "export_manifest_sha256": {
                   "old": sha256(args.old_build / "web/release-manifest.json"),
                   "new": sha256(args.new_build / "web/release-manifest.json")}}
    for label, build in [("old", args.old_build), ("new", args.new_build)]:
        with tempfile.TemporaryDirectory(prefix="wall-layout-saveguard-") as temporary:
            temporary = Path(temporary)
            project = temporary / "project"
            shutil.copytree(build / "project", project)
            tests = project / "tests"
            tests.mkdir(exist_ok=True)
            shutil.copy2(ROOT / "tests/wall_compatibility_layout.gd", tests / "wall_compatibility_layout.gd")
            shutil.copy2(FIXTURES / "old-format1.json", tests / "wall-fixture-old.json")
            shutil.copy2(FIXTURES / "new-format2.json", tests / "wall-fixture-new.json")
            env = synthetic_profile(temporary / 'saveguard-profile')
            result_path = output / (label + "-layout.json")
            command = [godot, "--headless", "--fixed-fps", "60",
                       "--path", str(project), "--script", "res://tests/wall_compatibility_layout.gd", "--",
                       "--skip-intro", "--fixture=res://tests/wall-fixture-old.json", "--layout-output=" + str(result_path)]
            if label == "new":
                command.append("--new-layout")
            completed = subprocess.run(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
            text = completed.stdout.decode(errors="replace")
            (output / (label + "-layout.log")).write_text(text)
            if completed.returncode or "ERROR:" in text or not result_path.is_file():
                raise RuntimeError(label + " layout/codec preflight failed; inspect retained log")
            result = json.loads(result_path.read_text())
            if result["failures"] or result["checks"] < 1:
                raise RuntimeError(label + " layout/codec assertions failed")
            receipt["layouts"][label] = {"sha256": sha256(result_path), "checks": result["checks"]}
            for name, expected in (old if label == "old" else new)["production_sha256"].items():
                if sha256(project / name) != expected:
                    raise RuntimeError("Native preflight changed production source: " + name)
    receipt["status"] = "passed"
    (output / "preflight.json").write_text(json.dumps(receipt, indent=2) + "\n")


def cloud_main(argv):
 p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);a=p.parse_args(argv);out=a.output.resolve()
 if out.exists():raise ValueError('Use a new disposable geometry directory')
 out.mkdir(parents=True);project=out/'project';stage_project(ROOT,project,tests=True,ignore=EXCLUDE)
 env=synthetic_profile(out/'profile')
 godot=os.environ.get('GODOT_BIN','godot')
 with (out/'import.log').open('w') as log:
  subprocess.run([godot,'--headless','--path',str(project),'--editor','--import'],env=env,stdout=log,stderr=subprocess.STDOUT,timeout=120,check=True)
 regressions=[]
 for width,height in [(1360,880),(390,844)]:
  previous=None
  for label,reason in [('short','Paused.'),('wrapped','Your game was opened on another device. Current progress is protected while you choose where to continue.'),('protected','Your game was opened on another device.')]:
   name=f'{width}-{label}';input_file=out/(name+'-input.json');output_file=out/(name+'-result.json')
   value={'viewport':{'width':width,'height':height},'snapshot':{'available':False,'serverOwnership':True,'ownershipPaused':True,'status':'other-device','canRequestTakeover':True,'reason':reason}}
   if label=='protected':value['nativeCallback']={'method':'preserveOwnerRuntime','result':{'ok':True,'durable':True,'profileId':'synthetic-profile','revision':2}}
   input_file.write_text(json.dumps(value))
   with (out/(name+'.log')).open('w') as log:
    subprocess.run([godot,'--headless','--audio-driver','Dummy','--path',str(project),'--script','res://tests/probe_cloud_recovery_geometry.gd','--',str(input_file),str(output_file)],env=env,stdout=log,stderr=subprocess.STDOUT,timeout=30,check=True)
   result=json.loads(output_file.read_text());x,y,w,h=result['buttons']['switch']
   if reason not in result['text'] or not (0<=x<x+w<=width and 0<=y<y+h<=height):raise ValueError('Exact-message native geometry invalid')
   if label=='protected' and 'Current progress is protected on this device.' not in result['text']:raise ValueError('Native callback message missing')
   if label=='wrapped' and previous is not None and y==previous:raise ValueError('Wrapped-message regression did not change measured button location')
   previous=y;regressions.append({'viewport':value['viewport'],'message':label,'switch':result['buttons']['switch']})
 (out/'regressions.json').write_text(json.dumps(regressions,indent=2)+'\n')
 receipt={'synthetic_only':True,'source_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),'source_sha256':{n:sha256(source_path(ROOT,n)) for n in ['tests/probe_cloud_recovery_geometry.gd','tests/test_cloud_recovery_ui.gd','scripts/cafe_compact_ui.gd','scripts/cafe_web_save.gd']},'project':str(project)}
 (out/'binding.json').write_text(json.dumps(receipt,indent=2)+'\n')

def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('scenario', choices=['wall', 'cloud'])
    args = parser.parse_args(argv[:1])
    {'wall': wall_main, 'cloud': cloud_main}[args.scenario](argv[1:])

if __name__ == '__main__':
    main()
