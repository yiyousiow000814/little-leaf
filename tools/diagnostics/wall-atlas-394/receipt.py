"""Sanitize successful private native output. Never upload the private directory."""
import hashlib
import json
from pathlib import Path
import re
import sys
from qualify import CANDIDATE, CANDIDATE_TREE, RELATIVE

EXPECTED = {
    "furniture": ((1280,3216), "ba615c7535d6e3806d1b6b27abf2c50575e59486c8b9ab8c08d4eadff401b5ac"),
    "moving": ((1024,1908), "6dc71a1bde51fc5c514356e5188736d24b6edc54acfa15185091b31cfce69bbc"),
    "heads": ((1600,1728), "d16a8ea4064eb3aa5fa1daa90f61731e1288aa1e5089b0a8b3d9b381b106c1d7"),
}
PNG = {
    "furniture": "04990f4440c95c1779fadfe7af057ca6ab24d54073932da545e22155512d22aa",
    "moving": "e513c2ecc19809af18f52cca66a9943778a4a21dad3f94299bf5035df77e9f8a",
    "heads": "cc606e0ffa77983ec1b3724cbb74b0ed5c9a65f20aada1e83250140f0ebed34a",
}
PRODUCER = "3bffeb54cce0f5fc43cbd10b323257ff6f5403a264f5882adccf238f2ea5ca89"
ENGINE = "f64d4ed19fc9df9440321653fcc80df8c6e365ba7b6de0a29e2cfa9fa71bfeb3"


def need(ok):
    if not ok:
        raise ValueError("incomplete qualification")


def sanitize(raw):
    need(raw["status"] == "fixed_rgba_equal_pending_review" and raw["head"] == CANDIDATE and raw["tree"] == CANDIDATE_TREE and raw["product"] == CANDIDATE)
    need(raw["engine_sha256"] == ENGINE and all(raw[k] is False for k in ("manifest_written","source_assets_written","player_data_used","game_instance_created")))
    need(len(raw["producer_sha256"]) == 85 and all(k in raw["producer_sha256"] for k in RELATIVE["changed"]))
    is_hash = lambda v: isinstance(v,str) and re.fullmatch(r"[0-9a-f]{64}",v) is not None
    need(raw["producer_closure_sha256"] == PRODUCER == hashlib.sha256(
        json.dumps(raw["producer_sha256"], sort_keys=True, separators=(",", ":")).encode()).hexdigest())
    need(is_hash(raw["atlas_receipt_sha256"]))
    need([s["stage"] for s in raw["steps"]] == ["import","original-three","check_saved","check_source_png"])
    need(all(s["exit_code"] == 0 and not s["reason"] and is_hash(s["log_sha256"]) for s in raw["steps"]))
    checks = {row["file"]:row for row in raw["independent_pngs"]}
    need(len(raw["independent_pngs"]) == len(checks) == 9)
    rows = []
    for name,(dim,digest) in EXPECTED.items():
        for suffix in ("regenerated","atlas","source"):
            filename = f"{name}-{suffix}.png"
            row = checks[filename]
            need(tuple(row["size"]) == dim and row["rgba_sha256"] == digest and row["png_sha256"] == PNG[name])
            rows.append({k:row[k] for k in ("file", "size", "png_sha256", "rgba_sha256")})
    return {"scope":"Original-three atlas qualification only; not gameplay, full visual parity, Web, timing or FPS",
            "status":raw["status"], "source":raw["head"], "source_tree":raw["tree"], "engine_sha256":ENGINE,
            "native_atlas_receipt_sha256":raw["atlas_receipt_sha256"], "producer_count":85, "producer_closure_sha256":raw["producer_closure_sha256"],
            "changed_producers":RELATIVE["changed"], "fresh_import_and_native_ready":True,
            "manifest_written":False, "png_rgba_comparisons":rows}


if __name__ == "__main__":
    try:
        print(json.dumps(sanitize(json.loads(Path(sys.argv[1]).read_text())), indent=2))
    except (ValueError, OSError, KeyError, IndexError, TypeError):
        print("Native atlas qualification output incomplete; private evidence not published",file=sys.stderr)
        raise SystemExit(1)
