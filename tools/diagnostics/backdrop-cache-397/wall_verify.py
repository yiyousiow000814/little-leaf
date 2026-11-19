"""Verify the immutable standalone #397 wall fixture; no engine or game runtime."""
import hashlib
import json
import math
from pathlib import Path
import struct
import sys

HERE = Path(__file__).resolve().parent
EXPECTED = "55abd21e9305293539b88327c9cd1b3dbc46d5a38fe44f77664243851cb42490"


def need(value):
    if not value:
        raise ValueError("exact #397 starter geometry did not verify")


def verify(source):
    candidate = source.read_bytes()
    need(hashlib.sha256(candidate).hexdigest() == EXPECTED)
    doc = json.loads(candidate)
    need(len(doc["scenes"]) == 1 and doc["scenes"][0]["name"] == "starter")
    slots = doc["scenes"][0]["slots"]
    need(len(slots) == len({s["id"] for s in slots}) == 84)
    counters = {2:0,4:0,5:0}
    order = hashlib.sha256()
    primitives = quads = 0
    xs,ys = [],[]
    for slot in slots:
        items = slot["quads"]
        need(len(items) in counters)
        counters[len(items)] += 1
        offset = 0
        order.update(slot["id"].encode()+b"\0"+struct.pack("<I",len(items)))
        for q in items:
            xy,rgba,ids = q["xy"],q["rgba"],q["indices"]
            need(len(xy) == len(rgba) == 4 and len(ids)==6 and all(type(i) is int and 0<=i<4 for i in ids))
            for p,c in zip(xy,rgba):
                need(len(p)==2 and len(c)==4 and all(type(x) in (float,int) and math.isfinite(x) for x in p+c))
                need(0<=p[0]<1360 and 0<=p[1]<880 and all(0<=x<=1 for x in c))
                xs.append(p[0]);ys.append(p[1]);order.update(struct.pack("<6f",*p,*c))
            order.update(struct.pack("<6I",*[i+offset for i in ids]))
            offset+=4;quads+=1;primitives+=2
    need((quads,primitives,counters)==(330,660,{2:4,4:78,5:2}))
    return {"scene_sha256":EXPECTED,"ordered_packed_slots_sha256":order.hexdigest(),"slots":len(slots),
            "quads":quads,"triangles":primitives,"frame":[1360,880],"quads_per_slot":counters,
            "projected_bounds_xy":[[min(xs),min(ys)],[max(xs),max(ys)]]}


if __name__=="__main__":
    print(json.dumps(verify(Path(sys.argv[1]) if len(sys.argv)>1 else HERE/"starter.json"),indent=2))
