"""Stage exact source archive with the Main scene entry disabled. No game or input/save code is invoked."""
import base64,gzip,hashlib,json,sys
from pathlib import Path
import guard,source,wall_verify
D=Path(__file__).resolve().parent
WALL_SHA='55abd21e9305293539b88327c9cd1b3dbc46d5a38fe44f77664243851cb42490'
CONFIG='09a15b9558d981fe31f4a0fe4b83c6c98bbad4cd7bbc03d840e76ad7da87bf93'
def prepare(repo,target):
    names=guard.immutable()
    b=json.loads((D/'source-input.json').read_text())
    guard.need(source.extract_verified(repo,b,target)==source.ARCHIVE_SHA)
    game=target/'game'; cfg=game/'project.godot';first=cfg.read_bytes()
    guard.need(guard.sha(cfg)==CONFIG and first.count(b'run/main_scene="res://main.tscn"')==1 and b'[autoload]' not in first and b'run/max_fps=60' in first)
    cfg.write_bytes(first.replace(b'run/main_scene="res://main.tscn"',b'; diagnostic: no main scene'))
    guard.need(b'run/main_scene' not in cfg.read_bytes() and not (game/'mechanism.gd').exists())
    assert guard.sha(D/'mechanism.gd')=='179f937702614a17fddbd1846715a463761faf527394bcab8f4d0277abc91c16'
    guard.need(not (game/'backdrop.gd').exists())
    for n in ('mechanism.gd','backdrop.gd'):(game/n).write_bytes((D/n).read_bytes())
    raw=gzip.decompress(base64.b64decode((D/'walls.gz.b64').read_text().strip(),validate=True))
    guard.need(len(raw)==145397 and hashlib.sha256(raw).hexdigest()==WALL_SHA)
    gp=json.loads((D/'geometry-provenance.json').read_text())
    guard.need(gp['tree']==source.TREE and gp['scene_sha256']==WALL_SHA)
    for p,hash_ in gp['sources'].items():guard.need(guard.sha(game/p)==hash_)
    (target/'walls.json').write_bytes(raw)
    normalized=wall_verify.verify(target/'walls.json')
    guard.need(normalized['slots']==84 and normalized['triangles']==660)
    # No user patterns, system path or profile copied. Physical source stage stays on the private runner.
    return game
if __name__=='__main__':prepare(*[Path(x).resolve() for x in sys.argv[1:3]])
