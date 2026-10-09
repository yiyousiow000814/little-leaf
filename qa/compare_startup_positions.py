"""Compare original production pixels; optional bounded intro-only AA rounding."""
import argparse
import hashlib
import json
from pathlib import Path


def compare_pixels(width, height, a, b, elapsed, allow_rounding=False):
    assert len(a) == len(b) == width * height * 4
    maximum = max(abs(x - y) for x, y in zip(a, b))
    pixels = sum(a[i:i + 4] != b[i:i + 4] for i in range(0, len(a), 4))
    fraction = pixels / (width * height)
    # Settled art must stay exact. During movement only, allow at most one
    # channel step on <=0.025% of pixels. Always retain exact status and counts.
    bounded = (allow_rounding and elapsed < 6.5 and maximum <= 1 and fraction <= .00025)
    return {'rgba_equal': pixels == 0, 'different_pixels': pixels,
            'different_fraction': fraction, 'maximum_channel_difference': maximum,
            'accepted': pixels == 0 or bounded}


def main():
    from PIL import Image
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('baseline', type=Path)
    parser.add_argument('candidate', type=Path)
    parser.add_argument('--allow-intro-aa-rounding', action='store_true')
    args = parser.parse_args()
    left = json.loads((args.baseline / 'captures.json').read_text())['records']
    right = json.loads((args.candidate / 'captures.json').read_text())['records']
    assert left == right and len(left) == 10
    rows = []
    for record in left:
        filename = record['file']
        a, b = args.baseline / filename, args.candidate / filename
        with Image.open(a) as x, Image.open(b) as y:
            assert x.size == y.size
            row = compare_pixels(x.width, x.height, x.convert('RGBA').tobytes(),
                                 y.convert('RGBA').tobytes(), record['intro_elapsed'],
                                 args.allow_intro_aa_rounding)
        row.update(file=filename, baseline_sha256=hashlib.sha256(a.read_bytes()).hexdigest(),
                   candidate_sha256=hashlib.sha256(b.read_bytes()).hexdigest())
        rows.append(row)
    receipt = {'intro_aa_rounding_allowed': args.allow_intro_aa_rounding,
               'maximum_channel_threshold': 1, 'maximum_changed_fraction': .00025,
               'settled_requires_exact': True, 'comparisons': rows}
    (args.candidate / 'capture-parity.json').write_text(json.dumps(receipt, indent=2))
    assert all(row['accepted'] for row in rows), 'Pixels exceed reviewed bound; inspect artifacts'
    print(f"Exact RGBA pairs: {sum(row['rgba_equal'] for row in rows)}/10; "
          f"within requested acceptance bound: 10/10")


if __name__ == '__main__':
    main()
