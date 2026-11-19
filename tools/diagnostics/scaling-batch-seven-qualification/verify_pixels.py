#!/usr/bin/env python3
"""Fail closed on paired rendered evidence. Compare each backend separately."""
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image

LABELS=("initial","warm","changed","changed-warm")

def inspect(folder:Path):
    receipt=json.loads((folder/"runtime.json").read_text())
    if receipt["semantic_only"] is not False or receipt["player_save_used"] is not False or receipt["save_attempts"]!=0:
        raise ValueError("Native/Web rendered synthetic-only receipts required")
    rows=receipt["records"]
    if tuple(row["label"] for row in rows)!=LABELS or any(len(r["objects"])!=6 or r["save_attempts"]!=0 for r in rows):
        raise ValueError("Missing rendered furniture receipt")
    pixels={}
    digests={}
    for label in LABELS:
        png=folder/f"{label}.png"
        with Image.open(png) as image:
            rgba=image.convert("RGBA")
            if rgba.size!=(1360,880) or rgba.getextrema()[3]!=(255,255) or len(rgba.getcolors(128) or []) in range(1,128):
                raise ValueError(f"Blank, insufficient palette or unexpected viewport: {png}")
            pixels[label]=rgba.tobytes()
        digests[label]=hashlib.sha256(pixels[label]).hexdigest()
    if pixels["initial"]!=pixels["warm"] or pixels["changed"]!=pixels["changed-warm"]:
        raise ValueError("Unchanged warmed state repainted differently")
    before=pixels["initial"];after=pixels["changed"]
    changed=sum(before[p:p+4]!=after[p:p+4] for p in range(0,len(before),4))
    if changed < 64:
        raise ValueError("State transition did not produce meaningful visible change")
    return receipt,digests,changed

if __name__=="__main__":
    cli=argparse.ArgumentParser(description=__doc__)
    cli.add_argument("control",type=Path)
    cli.add_argument("candidate",type=Path)
    a=cli.parse_args()
    before,after=inspect(a.control),inspect(a.candidate)
    if before!=after:
        raise SystemExit("Exact paired image/stable renderer receipt mismatch")
    print(json.dumps({"status":"paired exact RGBA","frames":4,"changed_pixels":before[2],"rgba_sha256":before[1]},indent=2))
