"""Strict native HUD raster comparison. No timing or browser acceptance."""
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image, ImageChops

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output',type=Path)
    args=parser.parse_args(); root=args.output
    receipt=json.loads((root/'captures.json').read_text())
    assert receipt['timing_claim'] is False and receipt['player_data_used'] is False
    indexed={}
    for row in receipt['records']:
        key=(row['pass'],tuple(row['viewport']),row['state'])
        assert key not in indexed and row['save_writes_suppressed']
        assert Path(row['file']).name==row['file']
        indexed[key]=row
    states=['play','settings','staff','decorate','selected-plant']
    views=[(1360,880),(960,540),(390,844),(844,390)]
    assert set(indexed)=={(p,v,s) for p in range(4) for v in views for s in states}
    comparisons=[]
    for a,b in [(0,1),(0,2),(0,3),(1,2)]:
        for view in views:
            for state in states:
                left=indexed[a,view,state];right=indexed[b,view,state]
                x=Image.open(root/left['file']).convert('RGBA'); y=Image.open(root/right['file']).convert('RGBA')
                assert x.size==y.size==view
                diff=ImageChops.difference(x,y)
                changed=sum(any(pixel) for pixel in diff.getdata())
                maximum=max(high for low,high in diff.getextrema())
                comparisons.append({'passes':[a,b],'viewport':view,'state':state,'changed_pixels':changed,
                    'max_channel_delta':maximum,'geometry_exact':left['geometry']==right['geometry'],
                    'left_rgba_sha256':hashlib.sha256(x.tobytes()).hexdigest(),
                    'right_rgba_sha256':hashlib.sha256(y.tobytes()).hexdigest()})
    result={'comparisons':comparisons,'strict_pixel_passes':sum(r['changed_pixels']==0 for r in comparisons),
        'geometry_passes':sum(r['geometry_exact'] for r in comparisons),'count':len(comparisons),
        'scope':'Native untimed same-runtime texture representation comparison, repeated raw/import/import/raw; no Web or speedup claim'}
    (root/'comparison.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k!='comparisons'}))
    raise SystemExit(0 if result['strict_pixel_passes']==result['geometry_passes']==result['count'] else 1)

if __name__=='__main__':main()
