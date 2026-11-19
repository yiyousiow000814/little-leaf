"""Publish only fixed-schema bounded metrics. No host identities, raw stamps, scene IDs or logs."""
import json, math, statistics, sys
from pathlib import Path
from guard import COMMIT
ZONES=('post_to_process','process_to_pre_draw','pre_to_post_draw')
TARGET=1e6/60*.85
class Invalid(Exception):pass
def need(v,msg):
 if not v:raise Invalid(msg)
def metric(x):
 return round(x,3)
def pct(x,q):return sorted(x)[math.ceil(q*len(x))-1]
def live(s):
 return isinstance(s,dict) and all(s.get(k) is False for k in ('paused','editing','intro_active','recovery_blocked')) and s.get('open') is True and s.get('tracked_seated') is True and s.get('tracked_phase')=='cooking' and isinstance(s.get('tracked_guest_id'),int) and s['tracked_guest_id']>=0 and all(type(s.get(k)) is int and s[k]>=0 for k in ('served','items','guests')) and s['items']==7 and s.get('walls')==21 and s.get('openings')==1 and s['guests']>0
def cadence(raw,cap,minimum):
 need(raw['cap']==raw['cap_at_end']==cap,'cap_changed');need(raw['boundary_faults']==0,'signal_or_thread_fault');need(raw['lost']==0,'buffer_overflow')
 t=raw['stamps_us'];start=raw['start_us'];end=raw['end_us']
 need(type(start) is int and type(end) is int and end-start>=minimum and isinstance(t,list) and 3<=len(t)<=8192 and all(type(v) is int for v in t),'incomplete_window')
 need(start<=t[0]<t[-1]<=end and all(x<y for x,y in zip(t,t[1:])), 'unordered_stamps');gaps=[b-a for a,b in zip(t,t[1:])];p95=pct(gaps,.95)
 return {'window_s':metric((end-start)/1e6),'completed_draws':len(t),'complete_intervals':len(gaps),'complete_interval_draws_per_s':metric(len(gaps)*1e6/(t[-1]-t[0])),'callbacks_per_sample_wall_s':metric(len(t)*1e6/(end-start)),'gap_ms':{'p50':metric(pct(gaps,.5)/1000),'p95':metric(p95/1000),'p99':metric(pct(gaps,.99)/1000),'max':metric(max(gaps)/1000)},'same_recorded_endpoints':raw['state_start']==raw['state_end']},p95
def zones(raw):
 ticks=raw['stamps_us'];rows=raw['boundary_rows_us'];n=len(ticks)-1
 need(isinstance(rows,list) and len(rows)==4*n and all(type(v) is int for v in rows),'unreconciled_rows')
 stage=[[],[],[]];blocks=[[0,0,0] for _ in range(3)];block_n=[0,0,0]
 for i in range(n):
  a,b,c,d=rows[4*i:4*i+4];need(a==ticks[i] and d==ticks[i+1] and a<b<c<d,'unreconciled_rows')
  values=(b-a,c-b,d-c);j=min(2,((a+d-2*ticks[0])*3)//(2*(ticks[-1]-ticks[0])));block_n[j]+=1
  for k,v in enumerate(values):stage[k].append(v);blocks[j][k]+=v
 sums=[sum(v) for v in stage];total=sum(sums);need(total==ticks[-1]-ticks[0],'partition_failed')
 order=sorted(range(3),key=lambda i:-sums[i]);winner=order[0];diff=(sums[winner]-sums[order[1]])/total
 def block_winner(v):return ZONES[v.index(max(v))] if sum(v)>0 and v.count(max(v))==1 else 'mixed'
 leaders=[block_winner(v) for v in blocks];consistent=n>=30 and min(block_n)>=5 and diff>=.05 and all(v==ZONES[winner] for v in leaders)
 return {'rows':n,'stage_elapsed':{name:{'share_pct':metric(100*sums[i]/total),'mean_ms':metric(sums[i]/n/1000),'p95_ms':metric(pct(stage[i],.95)/1000)} for i,name in enumerate(ZONES)},'largest_observed_by_total_wall':ZONES[winner] if diff>0 else 'mixed','leaders_by_three_elapsed_blocks':leaders,'stable_leader_rule_met':consistent,'leader_margin_percentage_points':metric(100*diff),'interpretation':'elapsed engine boundary only; post→process can include pacing, input, physics and scheduling; process→pre is not script-exclusive; pre→post includes render, driver, swap/waits and callbacks, not GPU busy or scanout'}
def summarize(raw):
 need(raw.get('schema')=='little-leaf-current-native-cadence-v1' and raw.get('scenario')=='active-first-cooking','bad_schema')
 e=raw['environment'];version=e['engine'];need(version['hash']=='7d41c59c457bd5a245092b4e7eb2d833e3b3f8c3' and version['build']=='official' and (version['major'],version['minor'],version['patch'])==(4,6,3),'engine_mismatch')
 need(e['display_server']=='X11' and e['window']=='(1360, 880)' and 'llvmpipe' in e['video_adapter'].lower() and 'mesa' in (e['video_api']+' '+e['video_vendor']).lower(),'unexpected_renderer')
 c=raw['capped'];need(live(c['state_start']),'bad_start_state');normal,p95=cadence(c,60,12000000);normal['p95_within_60hz_interval']=p95<=1e6/60
 result={'schema':'ll-current-native-summary-v1','status':'capped_valid','product':COMMIT,'class':'current GitHub-hosted Linux / X11 / 1360×880 / Mesa llvmpipe / official Godot 4.6.3 Compatibility','historical_comparison':False,'cadence':'engine-completed draw intervals; not presented FPS','normal_capped':normal,'headroom':'CPU/GPU busy-work and 15% headroom not measured. Uncapped elapsed gaps still include driver, VSync, scheduling, and other waits.','phase_comparison':'sequential live scene; no controlled cap A/B or historical speedup','uncapped':None}
 if raw.get('restored_cap')!=60:result['uncapped_status']='cap_not_restored';return result
 u=raw.get('uncapped');status=raw.get('uncapped_status')
 if u is None:
  result['uncapped_status']=status if status in ('skipped_scene_changed','skipped_warmup_changed') else 'no_diagnostic_window';return result
 try:
  need(status=='captured' and c['state_start']==c['state_end']==u['state_start'] and live(u['state_start']),'different_start_state')
  need(u['start_us']>=c['end_us']+500000,'phases_overlap_or_no_settle')
  diag,up95=cadence(u,0,6000000);z=zones(u);stable=diag['same_recorded_endpoints'];diag.update(z)
  diag['p95_elapsed_proxy_within_14p1667ms']=up95<=TARGET
  diag['same_recorded_endpoints_across_phases']=stable
  diag['attribution_context']='later active-cooking endpoints match, not identical frame content' if stable else 'later live workload changed; broad stage timing is this window only'
  result['uncapped_status']='valid_distinct_window';result['uncapped']=diag
 except Invalid as x:result['uncapped_status']=str(x)
 except (KeyError,TypeError,ValueError,IndexError):result['uncapped_status']='invalid_diagnostic_shape'
 return result
def publish(path,out):
 raw={}
 try:
  raw=json.loads(path.read_text());result=summarize(raw)
 except (Invalid,KeyError,TypeError,ValueError,IndexError) as exc:
  reason=str(exc) if isinstance(exc,Invalid) else 'invalid_measurement_shape'
  if reason not in {'bad_schema','engine_mismatch','unexpected_renderer','bad_start_state','cap_changed','signal_or_thread_fault','buffer_overflow','incomplete_window','unordered_stamps','invalid_measurement_shape'}:reason='invalid_measurement_shape'
  capped=raw.get('capped',{}) if isinstance(raw,dict) else {}
  if not isinstance(capped,dict):capped={}
  nums={k:min(10000,max(0,capped[k])) for k in ('lost','boundary_faults') if type(capped.get(k)) is int}
  if isinstance(capped.get('stamps_us'),list):nums['recorded_callbacks']=min(8192,len(capped['stamps_us']))
  out.write_text(json.dumps(dict(schema='ll-current-native-summary-v1',product=COMMIT,status='not_qualified',stage=reason,bounded_counters=nums,historical_comparison=False,measurements_published=False),indent=2)+'\n');return 2
 out.write_text(json.dumps(result,indent=2)+'\n')
 return 0 if result['uncapped_status'] in ('valid_distinct_window','skipped_scene_changed','skipped_warmup_changed') else 3
def checkpoint(path,out,reason):
 if reason not in {'candidate_timeout','candidate_session','probe_output_failed','engine_script_error','missing_measurement'}:raise Invalid('invalid_checkpoint_reason')
 code=publish(path,out);s=json.loads(out.read_text())
 if s.get('status')=='capped_valid' and s.get('uncapped_status')=='cap_not_restored' and code==3:
  s['uncapped_status']='interrupted_no_verified_later_phase';s['stop_reason']=reason;s['cap_restoration_verified']=False;out.write_text(json.dumps(s,indent=2)+'\n')
if __name__=='__main__':
 if len(sys.argv)==5 and sys.argv[1]=='--checkpoint':
  checkpoint(Path(sys.argv[2]),Path(sys.argv[3]),sys.argv[4])
 else:sys.exit(publish(*map(Path,sys.argv[1:])))
