"""Compare visible action-row ink with the painted inset, not Control rectangles."""
import argparse
import json
from pathlib import Path

FILES = ("placement-warm_oak-tile-stroke.png", "placement-price-390x844.png", "placement-price-844x390.png")

def ink_bounds(image, rect, kind):
    x, y, width, height = rect
    inset_x, inset_y = (8, 10) if kind == "cancel" else (0, 0)
    rows = []
    for py in range(int(y + inset_y), int(y + height - inset_y)):
        for px in range(int(x + inset_x), int(x + width - inset_x)):
            red, green, blue = image.getpixel((px, py))
            ink = (red > 150 and green - blue > 55 and red - green > 15) if kind == "coin" else (red < 120 and green < 110 and blue < 90 and red >= green >= blue)
            if ink:
                rows.append(py)
    if not rows:
        raise AssertionError(f"No {kind} ink in expected control")
    return [min(rows), max(rows)]

def main():
    from PIL import Image
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--before", type=Path, required=True)
    parser.add_argument("--after", type=Path, required=True)
    parser.add_argument("--geometry", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    frames = {r["file"]: r for r in json.loads(args.geometry.read_text()) if "file" in r}
    result = {"checks": 0, "failures": [], "frames": []}
    for filename in FILES:
        geometry = frames[filename]
        # At native1x, the shop_frame inset rules are22px from the top and17px
        # from the bottom. Its visual center is therefore2.5px below rect center.
        board = geometry["board"]
        target = board[1] + (22 + board[3] - 17) / 2
        row = {"file": filename, "painted_inset_center_y": target, "ink": {}}
        images = {stage: Image.open(path / filename).convert("RGB") for stage, path in [("before", args.before), ("after", args.after)]}
        for kind in ("quantity", "price", "coin", "cancel"):
            bounds = {stage: ink_bounds(image, geometry[kind], kind) for stage, image in images.items()}
            centers = {stage: sum(value) / 2 for stage, value in bounds.items()}
            errors = {stage: abs(value - target) for stage, value in centers.items()}
            row["ink"][kind] = {"bounds": bounds, "centers": centers, "distance_from_inset_center": errors}
            for ok, message in [(errors["after"] <= 1, "after ink within1px"), (errors["after"] < errors["before"], "optical centering improved")]:
                result["checks"] += 1
                if not ok:
                    result["failures"].append(f"{filename} {kind}: {message}")
        result["frames"].append(row)
    args.report.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"checks": result["checks"], "failures": result["failures"]}))
    raise SystemExit(bool(result["failures"]))

if __name__ == "__main__":
    main()
