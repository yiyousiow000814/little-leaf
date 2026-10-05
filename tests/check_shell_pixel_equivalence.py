"""Compare matched native legacy wall renders without changing screenshot pixels."""
import argparse
import json
from pathlib import Path
from PIL import Image, ImageChops

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--captures', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
root = args.captures.resolve()
before = json.loads((root / 'before-records.json').read_text())
after = json.loads((root / 'after-records.json').read_text())
names = ['original-full-false', 'cream_stripe-full-false', 'leaf_print-half-false', 'sage_panels-full-true']
names += ['extension-' + action + '-' + height + '-roundtrip' for height in ['full', 'half'] for action in ['removed', 'moved']]
results = []
for name in names:
    left = next(r for r in before if r['file'] == 'before-' + name + '.png')
    right = next(r for r in after if r['file'] == 'after-' + name + '.png')
    assert all(left[k] == right[k] for k in ['viewport', 'origin', 'tile', 'zoom']), name
    a, b = Image.open(root / left['file']).convert('RGB'), Image.open(root / right['file']).convert('RGB')
    assert a.size == b.size, name
    bounds = ImageChops.difference(a, b).getbbox()
    results.append({'before': left['file'], 'after': right['file'], 'pixel_equivalent': bounds is None, 'difference_bbox': bounds})
report = {'same_viewport_camera_and_scale': True, 'unchanged_legacy_scenes': results,
          'all_pixel_equivalent': all(r['pixel_equivalent'] for r in results)}
args.output.write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report))
raise SystemExit(0 if report['all_pixel_equivalent'] else 1)
