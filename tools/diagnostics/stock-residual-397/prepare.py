"""Stage only: exact #397 archive, one diagnostic autoload, pinned synthetic fixture."""
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

HERE=Path(__file__).resolve().parent
SOURCE=HERE
FIXTURE=HERE/"fixture.json"
FIXTURE_SHA="ed6fcfc1e4a3396389eff71b09f60740d099de9c046eb0e37eabe900e8c1cf4f"

def load_verify():
    spec=importlib.util.spec_from_file_location("exact_source_397", SOURCE/"stage.py")
    mod=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def prepare(repo,target):
    mod=load_verify()
    require=mod.require
    require(digest(FIXTURE)==FIXTURE_SHA,"fixture bytes changed")
    archive_hash=mod.extract_verified(repo,json.loads((SOURCE/"input.json").read_bytes()),target)
    project=target/"game"
    cfg=project/"project.godot"
    data=cfg.read_bytes()
    require(b"[autoload]" not in data and data.count(b"\n[display]\n")==1,"unexpected autoload")
    probe=project/"ll397_stock_residual.gd"
    with probe.open("xb") as out:
        out.write((HERE/"probe.gd").read_bytes())
    cfg.write_bytes(data.replace(b"\n[display]\n",b'\n[autoload]\n\nLL397StockResidual="*res://ll397_stock_residual.gd"\n\n[display]\n'))
    profile=target/"private/data/godot/app_userdata/Little Leaf Cafe"
    profile.mkdir(parents=True)
    (profile/"little_leaf_cafe_layout_motion_v15.json").write_bytes(FIXTURE.read_bytes())
    for name in ("home","cache","config"):
        (target/"private"/name).mkdir()
    print(json.dumps({"head":mod.COMMIT,"tree":mod.TREE,"archive_sha256":archive_hash,
        "fixture_sha256":FIXTURE_SHA,"project_sha256":digest(cfg),"probe_sha256":digest(probe),
        "tree_proof_local_only":False},sort_keys=True))

if __name__=="__main__":
    if len(sys.argv)!=3:
        raise SystemExit("usage: prepare.py EXACT_SOURCE FRESH_EXTERNAL_STAGE")
    prepare(Path(sys.argv[1]).resolve(strict=True),Path(sys.argv[2]).resolve())
