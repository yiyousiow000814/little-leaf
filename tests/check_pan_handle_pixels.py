"""Check actual native handle/cheek separation against the unchanged before view."""
from pathlib import Path
from PIL import Image
import argparse,json,sys
p=argparse.ArgumentParser()
p.add_argument('--before',required=True,type=Path)
p.add_argument('--after',required=True,type=Path)
p.add_argument('--output',required=True,type=Path)
a=p.parse_args()
before=json.loads((a.before/'before-runtime.json').read_text())
after=json.loads((a.after/'after-runtime.json').read_text())
before={(r['rotation'],r['frame']):r for r in before}
rows=[r for r in after if r['rotation'] in [1,2]]
failures=[];results=[]
for rot in [1,2]:
 if len([r for r in rows if r['rotation']==rot])!=144:failures.append(f'Rotation {rot} lacks the full 144-frame front cycle')
for row in rows:
 key=(row['rotation'],row['frame']);old=before[key]
 for name in ['seconds','unit','camera_zoom']:
  if abs(row[name]-old[name])>.0001:failures.append(f'Unmatched {name} at {key}')
 if any(abs(x-y)>.001 for x,y in zip(row['chef_screen'],old['chef_screen'])):failures.append(f'Unmatched camera/chef anchor at {key}')
 b=Image.open(a.before/'before'/f'rot{key[0]}-{key[1]:03d}.png').convert('RGB')
 f=Image.open(a.after/'after'/f'rot{key[0]}-{key[1]:03d}.png').convert('RGB')
 x,y=old['chef_screen'];u=old['unit'];mirror=old['mirror']
 xx=[x+4.0*mirror*u,x+16.0*mirror*u]
 box=(int(min(xx)),int(y-35*u),int(max(xx))+1,int(y-24*u)+1)
 overlaps=[]
 for py in range(box[1],box[3]):
  for px in range(box[0],box[2]):
   c=b.getpixel((px,py));d=f.getpixel((px,py))
   # Light cheek pixels are fixed-source evidence, not a guessed ellipse.
   # Ignore sub-8-bit rounding; detect even modest new dark-stroke coverage.
   skin=c[0]>=235 and c[1]>=223 and c[2]>=190
   if skin and c[0]-d[0]>=12 and c[1]-d[1]>=8:overlaps.append([px,py])
 results.append({'rotation':key[0],'frame':key[1],'cheek_pixels_darkened':len(overlaps),'first_pixels':overlaps[:8]})
 if overlaps:failures.append(f'Rotation {key[0]} frame {key[1]} has {len(overlaps)} darkened cheek pixels')
report={'status':'passed' if not failures else 'failed','criterion':'Zero new handle-darkened light-cheek pixels throughout 144 native frames in each front view; before/after clocks and anchors matched','front_frames_checked':len(results),'total_darkened_pixels':sum(r['cheek_pixels_darkened'] for r in results),'max_darkened_pixels_in_one_frame':max((r['cheek_pixels_darkened'] for r in results),default=0),'failures':failures,'frames':results}
a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({k:v for k,v in report.items() if k not in ['frames','failures']}))
if failures:print('\n'.join(failures[:10]))
sys.exit(0 if not failures else 1)
