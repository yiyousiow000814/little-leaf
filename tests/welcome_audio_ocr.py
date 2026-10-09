"""Extract the existing welcome hint from the original PNG, after capture stops."""
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image


def crop_hint(source: Path, output: Path, region: str = 'hint') -> dict:
    with Image.open(source) as image:
        if image.size != (1360, 880):
            raise ValueError('Welcome OCR requires the unchanged 1360x880 viewport')
        # cafe_intro.gd puts the hint at y=view.y-58, height=40, x=16.
        # Include vertical padding and retain the exact captured pixels.
        boxes = {'hint': (16, 810, 1344, 870), 'title': (540, 140, 820, 185)}
        if region not in boxes:
            raise ValueError('Unknown welcome text region')
        box = boxes[region]
        image.crop(box).save(output)
    digest = lambda file: hashlib.sha256(file.read_bytes()).hexdigest()
    return {'source': source.name, 'source_sha256': digest(source),
            'file': output.name, 'sha256': digest(output), 'box': list(box), 'region': region,
            'processing': 'Unscaled exact-pixel crop of the original capture; no new screenshot'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--region', choices=['hint', 'title'], default='hint')
    args = parser.parse_args()
    print(json.dumps(crop_hint(args.source, args.output, args.region)))
