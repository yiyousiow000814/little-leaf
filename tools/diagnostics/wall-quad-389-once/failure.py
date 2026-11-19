"""Decorate a failure with allowlisted checkpoint/state counts; never publish the raw private capture."""
import json,re,sys
from pathlib import Path
from receipt import OUT
LABELS=('full-with-door','half-first','door-mutated-first','half-with-window-first','occluded-first','over-wall-first','door-removed-first','themed-alt-camera-first')
def decorate(priv):
 p=Path(priv)
 if not OUT.is_file():return
 r=json.loads(OUT.read_text());stage=r.get('stage','');detail={}
 if stage.endswith('_stills'):
  arm=stage.split('_')[0]
  if arm not in ('control','candidate'):return
  out=p/arm/'output';done=[(out/f'{i:02d}-{s}.png').is_file() for i,s in enumerate(LABELS)]
  detail['completed_files_before_failure']=sum(done)
  detail['next_expected_state']=next((lab for lab,seen in zip(LABELS,done) if not seen),'all_files_present')
  log=p/arm/'capture.log'
  if log.is_file():
   m=re.search(r'\(res://capture_wall_quad_parity\.gd:(\d{1,5})\)',log.read_text(errors='replace'))
   if m:detail['fixture_line']=int(m[1])
 if stage=='pixel_qualification':
  try:
   from PIL import Image,ImageChops
   differences=[]
   for i,s in enumerate(LABELS):
    images=[]
    for arm in ('control','candidate'):
     with Image.open(p/arm/'output'/f'{i:02d}-{s}.png') as im:
      if im.size!=(1360,880):return
      images.append(im.convert('RGBA'))
    delta=ImageChops.difference(*images)
    bands=delta.split();mx=bands[0]
    for band in bands[1:]:mx=ImageChops.lighter(mx,band)
    n=1360*880-mx.histogram()[0]
    if n:differences.append(dict(label=s,differing_pixels=n,max_channel_delta=mx.getextrema()[1]))
   detail['different_image_pairs']=differences
  except (ValueError,OSError,ImportError):detail['decoded_difference_unavailable']=True
 if detail:
  r['failure_detail']=detail;OUT.write_text(json.dumps(r,indent=2)+'\n')
if __name__=='__main__':decorate(sys.argv[1])
