"""Summarize valid completed draws; compare only genuinely matching envelopes."""
import hashlib
import json
import math
from pathlib import Path
import sys

def summary(root):
    root=Path(root)
    raw=json.loads((root/'diagnostic-native-draw.json').read_text())
    identity=json.loads((root/'diagnostic-source.json').read_text())
    assert raw['schema']=='little-leaf-native-draw-diagnostic-v1'
    ticks=raw['stamps_us']
    assert len(ticks)>=5 and raw['lost']==0 and all(isinstance(n, int) for n in ticks)
    assert raw['start_us'] <= ticks[0] < ticks[-1] <= raw['end_us']
    assert raw['end_us']-raw['start_us'] >= 12000000
    gaps=[(b-a)/1000 for a,b in zip(ticks,ticks[1:])]
    assert all(p>0 for p in gaps)
    g=sorted(gaps)
    q=lambda p:g[math.ceil(p*len(g))-1]
    envelope={k:raw[k] for k in ['engine','display_server','window','refresh_hz','video_adapter','video_vendor','video_api','processor','platform','max_fps','stage']}
    envelope.update({k:(root/k).read_text().strip() for k in ['engine.sha256','fixture.sha256','runtime-envelope.txt']})
    assert envelope['display_server']!='headless' and envelope['video_adapter']
    assert envelope['window']=='(1360, 880)'
    return {'source':identity['source'],'probe_sha256':identity['diagnostic_patch']['probe_sha256'],'envelope':envelope,
      'count':len(ticks),'sample_seconds':(raw['end_us']-raw['start_us'])/1e6,
      'average_engine_completed_fps':len(ticks)*1e6/(raw['end_us']-raw['start_us']),
      'frame_gap_ms':{'p50':q(.5),'p95':q(.95),'p99':q(.99),'max':max(g)},'state':raw['state_at_end']}
if __name__=='__main__':
    arms=[summary(root) for root in sys.argv[1:]]
    assert len(arms) in [1,2]
    if len(arms)==2:
        a,b=arms
        matching=a['envelope']==b['envelope'] and a['probe_sha256']==b['probe_sha256'] and a['source']['commit']!=b['source']['commit']
        matching=matching and a['envelope']['stage']=='active-first-cooking' and a['state']['items']==b['state']['items'] and a['state']['open'] and b['state']['open']
    else:matching=None
    if matching:
        baseline_dir=Path(sys.argv[1])
        fixed=('diagnostic-source.json','diagnostic-native-draw.json','engine.sha256','fixture.sha256','runtime-envelope.txt')
        seal={'purpose':'Frozen pre-optimization baseline until the measurement envelope changes',
              'source':arms[0]['source'], 'fingerprint':arms[0]['envelope'],
              'sha256':{name:hashlib.sha256((baseline_dir/name).read_bytes()).hexdigest() for name in fixed}}
        out=baseline_dir.parent/'baseline-seal.json'
        if out.is_file():
            assert json.loads(out.read_text())==seal, 'Baseline is immutable; do not replace the existing receipt'
        else:
            with out.open('x') as f:
                f.write(json.dumps(seal,indent=2)+'\n')
    result={'scope':'Native Godot draw completions, not physical presented frames, busy work or Web/device acceptance',
        'comparable_active_service':matching,'arms':arms}
    print(json.dumps(result,indent=2))
    if matching is False:
        raise SystemExit('Source/render/scenario envelope differs; keep single-run observations but do not compute improvement')
