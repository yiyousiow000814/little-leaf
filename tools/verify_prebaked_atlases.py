"""Guard lossless atlas resources against stale procedural-source snapshots.

Regeneration: use the native rendered parity job, inspect exact RGBA equality,
copy its three PNGs, then --write-manifest with that verified parity receipt.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct

ROOT = Path(__file__).resolve().parents[1] / 'game'
MANIFEST = ROOT / 'data/prebaked_atlas_manifest.json'
SEEDS = ['scripts/furniture_atlas_painter.gd','scripts/moving_art_painter.gd','scripts/character_head_painter.gd']
NAMES = ['furniture','moving','heads']

def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def sources():
    pending = list(SEEDS); found = {}
    while pending:
        name = pending.pop()
        if name in found:continue
        path = ROOT / name
        found[name] = digest(path)
        # Include every statically named GDScript dependency, including inherited
        # artist primitives. Recompute closure so new dependencies cannot escape.
        if path.suffix in {'.gd','.gdshader','.tscn','.tres','.json'}:
            pending.extend(n for n in re.findall(r'res://([^"\'\s]+)',path.read_text()) if (ROOT/n).is_file())
    return dict(sorted(found.items()))

def asset(name):
    path = ROOT / f'assets/cache/{name}-atlas.png'
    data = path.read_bytes()
    assert data[:8] == b'\x89PNG\r\n\x1a\n'
    width,height = struct.unpack('>II',data[16:24])
    settings = Path(str(path)+'.import')
    content = settings.read_text()
    for setting in ['compress/mode=0','mipmaps/generate=false','process/fix_alpha_border=false','process/premult_alpha=false','process/size_limit=0']:
        assert setting in content, f'{name}: lossless import setting missing: {setting}'
    return {'png_sha256':digest(path),'import_sha256':digest(settings),'encoded_bytes':len(data),'width':width,'height':height,'rgba_bytes':width*height*4}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write-manifest',type=Path,help='Verified rendered atlas-parity.json receipt')
    parser.add_argument('--provenance',help='Exact producing run/commit reference')
    args = parser.parse_args()
    current_sources = sources()
    assets = {name:asset(name) for name in NAMES}
    if args.write_manifest:
        receipt = json.loads(args.write_manifest.read_text())
        assert receipt['checks'] == 3 and not receipt['failures']
        assert receipt['baseline_sha256'] == receipt['candidate_sha256'] and args.provenance
        for i,name in enumerate(NAMES):assets[name]['rgba_sha256'] = receipt['baseline_sha256'][i]
        MANIFEST.write_text(json.dumps({'version':1,'engine':'4.6.3','provenance':args.provenance,'source_sha256':current_sources,'atlases':assets},indent=2)+'\n')
    manifest = json.loads(MANIFEST.read_text())
    assert manifest['version'] == 1 and manifest['engine'] == '4.6.3'
    assert current_sources == manifest['source_sha256'], 'Atlas procedural dependencies changed: regenerate and verify RGBA before updating manifest'
    for name, info in assets.items():
        assert all(manifest['atlases'][name][key] == value for key,value in info.items()), f'{name} pixels/imports changed: regenerate and verify'
    print(json.dumps({'status':'passed','sources':len(current_sources),'atlases':3,'encoded_bytes':sum(a['encoded_bytes'] for a in assets.values()),'rgba_bytes':sum(a['rgba_bytes'] for a in assets.values())}))

if __name__ == '__main__':main()
