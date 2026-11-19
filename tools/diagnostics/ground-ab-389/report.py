"""Equal-fidelity ground-only comparisons. No raw callbacks or frame images."""
import json,math,statistics as stat,sys
from pathlib import Path
from guard import COMMIT,TREE,need
def quantile(xs,p):return sorted(xs)[math.ceil(len(xs)*p)-1]
def report(raw):
 need(raw['renderer']=='X11_llvmpipe_compatibility' and raw['pairs_exact_rgba']==7)
 schedule=raw['schedule']; slots=raw['slots']; counts=raw['counts']
 need(len(schedule)==6 and set(schedule)=={'ABBA','BAAB'} and len(slots)==24)
 need(''.join(s['label'] for s in slots)==''.join(schedule))
 need(set(counts)=={'original_triangles','candidate_triangles','candidate_chunks','original_chunks'} and all(type(v) is int for v in counts.values()))
 need(counts['original_triangles']==75554 and counts['original_chunks']==1)
 need(0<counts['candidate_triangles']<counts['original_triangles'] and 1<=counts['candidate_chunks']<=99)
 changes=[]; all_times={'A':[],'B':[]}; baseline=[]
 for j in range(0,len(slots),4):
  med={'A':[],'B':[]}
  for row in slots[j:j+4]:
   values=row['us']; need(len(values)==36 and all(type(x) is int and 0<x<=2000000 for x in values))
   med[row['label']].append(stat.median(values)); all_times[row['label']].extend(values)
  a=stat.mean(med['A']); b=stat.mean(med['B']); baseline.append(a)
  changes.append(a-b)
 win=sum(x>0 for x in changes);delta=stat.median(changes);base=stat.median(baseline)
 p95a,p95b=(quantile(all_times[key],.95) for key in ('A','B'))
 status='local_mechanism_supported' if (win>=5 and delta>=max(250,.1*base) and p95b<=p95a+max(100,.05*p95a)) else 'retain_diagnostic_only'
 return dict(schema='ll-ground-ab-389-v1',product=COMMIT,tree=TREE,status=status,
  scope='isolated same-size static GroundNode native X11, pre-to-post elapsed only; no gameplay or FPS',
  exact_rgba_pairs=7,quartets=6,mode_windows=24,probes_per_window=36,counts=counts,
  candidate_wins=win,median_paired_delta_ms=round(delta/1000,4),control_median_ms=round(base/1000,4),
  control_p95_ms=round(p95a/1000,4),candidate_p95_ms=round(p95b/1000,4))
if __name__=='__main__':
 raw=json.loads(Path(sys.argv[1]).read_text())
 result=report(raw);Path(sys.argv[2]).write_text(json.dumps(result,indent=2)+'\n')
