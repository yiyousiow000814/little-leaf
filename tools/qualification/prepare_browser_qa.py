"""Prepare synthetic native coordinates for browser QA: wall or cloud geometry.

Only the selected scenario runs. Wall retains the exact old/new export gate;
cloud retains its six measured layouts. Neither uses player profiles.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
if __name__ == "__main__":
    import sys
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from build.project_layout import source_path, stage_project
from build.build_web import verify_installer_receipt
from qualification.artifacts import sha256
from release.release_metadata import projected_metadata, version

ROOT = Path(__file__).resolve().parents[2]
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


def validate_export(build, source, old=False, *, verify_project=True):
    manifest = json.loads((build / "web/release-manifest.json").read_text())
    commit = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
    if subprocess.check_output(["git", "-C", str(source), "status", "--porcelain", "--untracked-files=no"], text=True).strip():
        raise RuntimeError("Compatibility inputs require clean tracked source")
    tree = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD^{tree}"], text=True).strip()
    if (manifest["source_commit"] != commit or manifest["source_tree"] != tree
            or (old and commit != CONTRACT["old_commit"])):
        raise RuntimeError("Export/source commit mismatch")
    if manifest.get("toolchain_verification") != "checksum-pinned-official-archives":
        raise RuntimeError("Compatibility CI requires the pinned official toolchain")
    if old:
        if manifest["production_sha256"].get("web/little_leaf_vault.js") != CONTRACT["old_vault_sha256"]:
            raise RuntimeError("Historical vault hash differs")
    elif not {name.replace('scripts/cafe_model.gd', 'scripts/core/cafe_model.gd').replace('scripts/cafe_shell_segments.gd', 'scripts/gameplay/cafe_shell_segments.gd').replace('scripts/cafe_web_save.gd', 'scripts/persistence/cafe_web_save.gd')
              for name in CONTRACT["candidate_required_sources"]}.issubset(manifest["production_sha256"]):
        raise RuntimeError("Candidate export is missing required production sources")
    projection = projected_metadata(source, commit)
    projected_hashes = {name: hashlib.sha256(content).hexdigest() for name, content in projection.items()}
    if manifest.get("projected_metadata_sha256", {}) != projected_hashes or manifest["version"] != version(source, source_commit=commit):
        raise RuntimeError("Exact-source metadata projection differs")
    for name, expected in manifest["production_sha256"].items():
        if (sha256(source_path(source, name)) != expected or
                verify_project and sha256(build / "project" / name) != projected_hashes.get(name, expected)):
            raise RuntimeError("Source/export production mismatch: " + name)
    for name, spec in manifest["files"].items():
        file = build / "web" / name
        if file.stat().st_size != spec["bytes"] or sha256(file) != spec["sha256"]:
            raise RuntimeError("Export asset changed: " + name)
    return manifest


def wall_binding(builds):
    """One source-bound recipe for producer and consumer; no native work here."""
    receipt = {"browser_verified": False, "synthetic_only": True,
               "fixture_sha256": CONTRACT["fixture_sha256"], "layouts": {},
               "production_sha256": {}, "export_manifest_sha256": {},
               "workflow_run": os.environ.get("GITHUB_RUN_ID", "local"),
               "workflow_attempt": os.environ.get("GITHUB_RUN_ATTEMPT", "local"),
               "coordinator_source": os.environ.get("GITHUB_SHA", "local"),
               "layout_fixture_sha256": sha256(ROOT / "tests/fixtures/wall_compatibility_layout.gd"),
               "preparer_sha256": sha256(Path(__file__))}
    for label, (build, manifest) in builds.items():
        receipt[label + "_commit"] = manifest["source_commit"]
        receipt[label + "_tree"] = manifest["source_tree"]
        receipt["production_sha256"][label] = manifest["production_sha256"]
        receipt["export_manifest_sha256"][label] = sha256(build / "web/release-manifest.json")
        receipt["toolchain_receipt"] = manifest["toolchain_receipt"]
    return receipt


def layout_record(folder, label):
    result_path, log_path = (folder / (label + suffix) for suffix in ("-layout.json", "-layout.log"))
    result = json.loads(result_path.read_text())
    if result["failures"] or type(result["checks"]) is not int or result["checks"] < 1:
        raise RuntimeError(label + " layout/codec assertions failed")
    if not log_path.is_file() or "ERROR:" in log_path.read_text():
        raise RuntimeError(label + " layout/codec log failed")
    return {"sha256": sha256(result_path), "checks": result["checks"], "log_sha256": sha256(log_path)}


def wall_main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ["old-source", "old-build", "new-build", "output"]:
        parser.add_argument("--" + name, type=Path, required=name == "output")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--prepare-side", choices=["old", "new"])
    mode.add_argument("--merge-only", action="store_true", help="Validate same-run producer layouts without Godot or staged projects")
    args = parser.parse_args(argv)
    labels = [args.prepare_side] if args.prepare_side else ["old", "new"]
    if ("old" in labels and (args.old_source is None or args.old_build is None)
            or "new" in labels and args.new_build is None):
        parser.error("Selected sides require their source/build paths")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    for name, expected in CONTRACT["fixture_sha256"].items():
        if sha256(FIXTURES / name) != expected:
            raise RuntimeError("Fixture changed: " + name)
    builds = {label: (build, validate_export(build, source, old=label == "old", verify_project=not args.merge_only))
              for label, build, source in [("old", args.old_build, args.old_source), ("new", args.new_build, ROOT)]
              if label in labels}
    toolchain = next(iter(builds.values()))[1]["toolchain_receipt"]
    if any(manifest["toolchain_receipt"] != toolchain for _, manifest in builds.values()):
        raise RuntimeError("Old and new exports must use the same pinned toolchain")
    receipt = wall_binding(builds)
    if args.merge_only:
        for label, (build, manifest) in builds.items():
            folder = build / "evidence/wall-layout"
            expected_files = {"preflight.json", label + "-layout.json", label + "-layout.log"}
            if (folder.is_symlink() or any(p.is_symlink() for p in folder.iterdir())
                    or {p.name for p in folder.iterdir()} != expected_files):
                raise RuntimeError("Incomplete or unexpected producer layout files")
            expected = wall_binding({label: (build, manifest)})
            expected["layouts"][label] = layout_record(folder, label)
            expected["status"] = "passed"
            observed = json.loads((folder / "preflight.json").read_text())
            if json.dumps(observed, sort_keys=True) != json.dumps(expected, sort_keys=True):
                raise RuntimeError("Producer layout source, run, toolchain or payload differs: " + label)
            receipt["layouts"][label] = expected["layouts"][label]
            for suffix in ("-layout.json", "-layout.log"):
                shutil.copy2(folder / (label + suffix), output / (label + suffix))
        receipt["status"] = "passed"
        (output / "preflight.json").write_text(json.dumps(receipt, indent=2) + "\n")
        return
    godot = os.environ.get("GODOT_BIN", "godot")
    installed = verify_installer_receipt(
        Path(shutil.which(godot) or godot).resolve(), Path(os.environ["GODOT_TEMPLATE"]),
        Path(os.environ["GODOT_TOOLCHAIN_RECEIPT"]))
    if installed != toolchain:
        raise RuntimeError("Native layout preflight must use the exports' verified toolchain")
    for label, (build, manifest) in builds.items():
        with tempfile.TemporaryDirectory(prefix="wall-layout-saveguard-") as temporary:
            temporary = Path(temporary)
            project = temporary / "project"
            shutil.copytree(build / "project", project)
            tests = project / "tests"
            tests.mkdir(exist_ok=True)
            layout_fixture = tests / "wall_compatibility_layout.gd"
            shutil.copy2(ROOT / "tests/fixtures/wall_compatibility_layout.gd", layout_fixture)
            if label == "old":
                original = layout_fixture.read_bytes()
                current_resource = b'res://scripts/persistence/cafe_web_save.gd'
                if original.count(current_resource) != 1 or not (project / "scripts/cafe_web_save.gd").is_file():
                    raise RuntimeError("Historical layout requires its exact WebSave resource")
                layout_fixture.write_bytes(original.replace(current_resource, b'res://scripts/cafe_web_save.gd'))
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
                # This process uses only fixed public fixtures in an isolated profile.
                # Keep its complete diagnostics in Actions as well as the artifact.
                print(text, file=sys.stderr, end="" if text.endswith("\n") else "\n")
                raise RuntimeError(label + " layout/codec preflight failed; inspect retained log")
            receipt["layouts"][label] = layout_record(output, label)
            for name, expected in manifest["production_sha256"].items():
                if sha256(project / name) != manifest.get("projected_metadata_sha256", {}).get(name, expected):
                    raise RuntimeError("Native preflight changed production source: " + name)
    receipt["status"] = "passed"
    (output / "preflight.json").write_text(json.dumps(receipt, indent=2) + "\n")


def cloud_main(argv):
 p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);a=p.parse_args(argv);out=a.output.resolve()
 if out.exists():raise ValueError('Use a new disposable geometry directory')
 out.mkdir(parents=True);project=out/'project';stage_project(ROOT,project,tests=True,ignore=EXCLUDE)
 shutil.copy2(ROOT/'tests/diagnostics/probe_cloud_recovery_geometry.gd',project/'tests/probe_cloud_recovery_geometry.gd')
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
 receipt={'synthetic_only':True,'source_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),'source_sha256':{n:sha256(source_path(ROOT,n)) for n in ['tests/diagnostics/probe_cloud_recovery_geometry.gd','tests/persistence/test_cloud_recovery_ui.gd','scripts/ui/cafe_compact_ui.gd','scripts/persistence/cafe_web_save.gd']},'project':str(project)}
 (out/'binding.json').write_text(json.dumps(receipt,indent=2)+'\n')

def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('scenario', choices=['wall', 'cloud'])
    args = parser.parse_args(argv[:1])
    {'wall': wall_main, 'cloud': cloud_main}[args.scenario](argv[1:])

if __name__ == '__main__':
    main()
