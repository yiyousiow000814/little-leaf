"""Strict exact-RGBA first-completed wall fixture comparison."""
import hashlib
import json
import sys
from pathlib import Path
from PIL import Image

LABELS=("full-with-door","half-first","door-mutated-first","half-with-window-first","occluded-first",
        "over-wall-first","door-removed-first","themed-alt-camera-first")
SIZE=(1360,880)

def load(directory, arm):
    directory=Path(directory)
    report=json.loads((directory/"capture.json").read_text())
    assert not report["smoke_only"] and report["generated_profile"] and report["save_calls"]==0
    assert report["display"]!="headless" and tuple(report["viewport"])==SIZE
    rows=report["frames"]
    assert tuple(row["label"] for row in rows)==LABELS
    exacts=[]; receipts=[]
    for i, row in enumerate(rows):
        assert row["first_completed_frame"] and len(row["walls"])==21
        openings={a["kind"]:a["wall_ids"] for a in row["attachments"]}
        expected_openings=({"door":["wall:18"]} if i<6 else {})|({"window":["wall:4"]} if i>=3 else {})
        assert openings==expected_openings and len(row["attachments"])==len(expected_openings)
        assert row["walls"][0]["id"]=="wall:1"
        assert row["walls"][0]["material"]==("cream_stripe" if i==7 else "original")
        assert row["walls"][19]["id"]=="wall:20"
        assert row["walls"][19]["height"]==("half" if 1<=i<=3 else "full")
        assert row["arm"]==arm
        textured_n=4 if i==7 else 0
        assert row["quad_command_owners"]==(84-textured_n if arm=="candidate" else 0)
        assert row["legacy_polygon_owners"]==(textured_n if arm=="candidate" else 84)
        assert row["axes"]=={"x":48,"z":36}
        wall=row["wall_owner_order"]; actors=row["actor_owner_order"]
        assert len(wall)==84 and len(wall)==len(set(wall)) and actors and not set(wall)&set(actors)
        assert len(set(row["themed_texture_owners"]))==textured_n and set(row["themed_texture_owners"])<=set(wall)
        assert len(set(row["selected_wall_order"]))==4 and set(row["selected_wall_order"])<=set(wall)
        assert row["selected_actor_order"] in actors
        with Image.open(directory/f"{i:02d}-{row['label']}.png") as png:
            rgba=png.convert("RGBA")
            assert rgba.size==SIZE and rgba.getextrema()[3]==(255,255) and rgba.getcolors(128) is None
            raw=rgba.tobytes()
        exact=hashlib.sha256(raw).hexdigest()
        assert row["rgba_sha256"]==exact
        exacts.append(exact)
        receipts.append({k:v for k,v in row.items() if k not in {"frame","draw_cpu_ms","rgba_sha256","file","arm","quad_command_owners","legacy_polygon_owners"}})
    assert len(set(exacts))==len(exacts),"A requested state did not produce different visible pixels"
    def occlusion_rank(row):
        return sum(slot<row["selected_actor_order"] for slot in row["selected_wall_order"])
    assert occlusion_rank(receipts[4])>occlusion_rank(receipts[5]),"Cook did not cross named wall:20 slice owner(s)"
    assert receipts[7]["pan"]!=receipts[6]["pan"] and receipts[7]["zoom"]!=receipts[6]["zoom"],"Missing alternate camera"

    return exacts, receipts
if __name__=="__main__":
    a=load(sys.argv[1],"control");b=load(sys.argv[2],"candidate")
    assert a==b,"Exact RGBA and actual renderer owner/order receipts must match baseline."
    print(json.dumps(dict(frames=len(a[0]),rgba_sha256=dict(zip(LABELS,a[0]))),indent=2))
