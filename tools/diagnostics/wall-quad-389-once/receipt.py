"""Publish bounded counters/hashes only (not a raw fixture, image, engine/host log or profile)."""
from pathlib import Path
import json,os,sys
from guard import SRC,PATCH,need
OUT=Path(os.environ.get('RUNNER_TEMP','.'))/'wall-quad-public'/'summary.json'
STAGES={'source_binding','source_staging','tool_provision','engine_digest','display_or_decoder','control_import','candidate_import','control_stills','candidate_stills','pixel_qualification','canvas_counter','complete'}
def write(stage,extra=None):
 need(stage in STAGES);OUT.parent.mkdir(parents=True,exist_ok=True)
 d=dict(schema='ll-wall-quad-native-v1',source=SRC,patch_sha256=PATCH,status='unqualified',stage=stage,native_pixels_verified=False,web_qualified=False,game_timing_measured=False,historical_comparison=False)
 d.update(extra or {});OUT.write_text(json.dumps(d,indent=2)+'\n')
def verify(private):
 import verify as v
 path=Path(private);a=[];b=[];counts={}
 for arm,record in [('control',a),('candidate',b)]:
  folder=path/arm/'output';r=json.loads((folder/'capture.json').read_text())
  e=r['engine'];need(e['hash']=='7d41c59c457bd5a245092b4e7eb2d833e3b3f8c3' and e['build']=='official' and r['display'].lower()=='x11' and r['renderer']=='gl_compatibility' and 'llvmpipe' in r['adapter'].lower())
  record.extend(v.load(folder,arm));counts[arm]=[x['quad_command_owners'] for x in r['frames']]
 need(a==b and len(a[0])==len(v.LABELS)==8)
 source=json.loads((path/'staged/source.json').read_text());need(source['source']==SRC and source['patch']==PATCH)
 write('canvas_counter',dict(native_pixels_verified=True,qualified_stills=8,rgba_sha256=dict(zip(v.LABELS,a[0])),candidate_tree=source['candidate_tree'],packed_wall_owners=counts))
if __name__=='__main__':
 if sys.argv[1]=='verify':verify(sys.argv[2])
 else:write(sys.argv[1])
