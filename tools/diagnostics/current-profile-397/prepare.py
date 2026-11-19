"""Prepare a private, non-exportable instrumented copy of one immutable source."""
import hashlib, json, sys
from pathlib import Path
import guard, instrument, stage

D=Path(__file__).resolve().parent
sha=guard.sha
def finalize(dst,archive):
    g=dst/'game'
    b=guard.data()
    # Check extraction immutable before adding any diagnostic marker.
    guard.need(archive==b['archive_sha256'])
    for k,h in b['reviewed_game_files'].items():
        guard.need(sha(dst/k)==h)
    guard.need(not any((g/n).exists() for n in ('ll397_scopes.gd','ll_native_draw_probe.gd')))
    cfg=g/'project.godot'
    initial_sha=sha(cfg)
    report=instrument.prepare(g,g)
    fixed=json.loads((D/'markers-binding.json').read_text())
    guard.need(report==fixed)
    anchor=b'LL397Scopes="*res://ll397_scopes.gd"'
    probe=b'LLNativeDrawProbe="*res://ll_native_draw_probe.gd"'
    content=cfg.read_bytes()
    guard.need(content.count(anchor)==1 and b'LLNativeDrawProbe' not in content)
    cfg.write_bytes(content.replace(anchor,anchor+b'\n'+probe))
    (g/'ll_native_draw_probe.gd').write_bytes((D/'probe.gd').read_bytes())
    r={'source':{'commit':guard.COMMIT,'tree':guard.TREE,'allowed_project_paths':['game'],'archive_sha256':archive},
       'staged_project':'game','diagnostic_patch':{'project_before_sha256':initial_sha,'project_after_sha256':sha(cfg),
       'probe_sha256':sha(g/'ll_native_draw_probe.gd')}}
    (dst/'diagnostic-source.json').write_text(json.dumps(r)+'\n')
    guard.staged(dst)
    return g
if __name__=='__main__':
    repo,dst=map(lambda x:Path(x).resolve(),sys.argv[1:3])
    guard.immutable()
    finalize(dst,stage.extract_verified(repo,guard.data(),dst))
