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

ROOT = Path(__file__).resolve().parents[2] / 'game'
MANIFEST = ROOT / 'data/prebaked_atlas_manifest.json'
SEEDS = ['scripts/rendering/furniture_atlas_painter.gd','scripts/rendering/moving_art_painter.gd','scripts/rendering/character_head_painter.gd']
NAMES = ['furniture','moving','heads']
RESOURCE_PATH = re.compile(r'res://([^"\'\s]+)')
GDSCRIPT_TOKENS = re.compile(r'#[^\n]*|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'')
IDENTITY_LEFT = re.compile(r'\.\s*resource_path\s*(?:==|!=)\s*&?\s*$')
IDENTITY_RIGHT = re.compile(r'^\s*(?:==|!=)\s*(?:[A-Za-z_]\w*\s*(?:\([^()\n]*\)\s*)?\.\s*)+resource_path\b')

def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def resource_references(path):
    text = path.read_text(encoding='utf-8')
    if path.suffix != '.gd':return RESOURCE_PATH.findall(text)
    # A script's resource_path is its identity, not an instruction to load that
    # file. Keep other literals conservatively, including dynamic-load constants.
    # Tokenize strings before comments so a '#' inside a resource name survives.
    code = GDSCRIPT_TOKENS.sub(lambda m:' '*len(m[0]) if m[0].startswith('#') else m[0],text)
    found = []
    for token in GDSCRIPT_TOKENS.finditer(code):
        if token[0].startswith('#'):continue
        references = RESOURCE_PATH.findall(token[0])
        if not references:continue
        if IDENTITY_LEFT.search(code[:token.start()]) or IDENTITY_RIGHT.match(code[token.end():]):continue
        found.extend(references)
    return found

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
            pending.extend(n for n in resource_references(path) if (ROOT/n).is_file())
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
