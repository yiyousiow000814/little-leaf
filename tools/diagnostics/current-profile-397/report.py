"""Publish only fixed-schema bounded metrics. No host identities, raw stamps, scene IDs or logs."""
import json, math, statistics, sys
from pathlib import Path
COMMIT = "ce1435afb2329a6c1d2d77a8a19923dfd96bd205"
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
 need(type(raw['cap']) is int and type(raw['cap_at_end']) is int and raw['cap']==raw['cap_at_end']==cap,'cap_changed');need(type(raw['boundary_faults']) is int and raw['boundary_faults']==0,'signal_or_thread_fault');need(type(raw['lost']) is int and raw['lost']==0,'buffer_overflow')
 t=raw['stamps_us'];start=raw['start_us'];end=raw['end_us']
 need(type(start) is int and type(end) is int and 0<=start<end<=10**15 and minimum<=end-start<=minimum+2000000 and isinstance(t,list) and 3<=len(t)<=8192 and all(type(v) is int for v in t),'incomplete_window')
 need(start<=t[0]<t[-1]<=end and all(x<y for x,y in zip(t,t[1:])), 'unordered_stamps');gaps=[b-a for a,b in zip(t,t[1:])];p95=pct(gaps,.95)
 return {'window_s':metric((end-start)/1e6),'completed_draws':len(t),'complete_intervals':len(gaps),'complete_interval_draws_per_s':metric(len(gaps)*1e6/(t[-1]-t[0])),'callbacks_per_sample_wall_s':metric(len(t)*1e6/(end-start)),'gap_ms':{'p50':metric(pct(gaps,.5)/1000),'p95':metric(p95/1000),'p99':metric(pct(gaps,.99)/1000),'max':metric(max(gaps)/1000)},'same_recorded_endpoints':raw['state_start']==raw['state_end']},p95
# Fixed, source-reviewed IDs. No private/raw category keys can become labels.
SCOPES = {
 'main_dispatch':'Main frame dispatch',
 'duty_sync':'Staff duty synchronization',
 'input_hud':'Pointer, build input and earnings HUD',
 'service_coordination':'Service coordination and payroll',
 'model_tick':'Guest and cafe model simulation',
 'staff_runtime':'Staff simulation (excluding scoped assignments/routes)',
 'task_assignment':'Job assignment (excluding scoped routes)',
 'navigation':'Routes and navigation fingerprints',
 'autosave':'Autosave script',
 'ui_refresh':'Periodic HUD refresh',
 'roster':'Staff roster updates',
 'audio':'Music callback',
 'renderer_update':'Renderer redraw control',
 'street_motion':'Pedestrian and traffic updates',
 'actor_motion':'On-screen actor interpolation',
 'draw_prepare':'Draw preparation and projection lookup',
 'ground_draw':'Ground, props and preview draw commands',
 'exterior_draw':'Street actors and trees draw commands',
 'depth_sort':'Entity list assembly and depth sorting',
 'entity_draw':'Entity draw command emission',
 'draw_finish':'Draw overlays and finalization',
 'native_redraw':'Deferred native object redraw callbacks',
}
RESIDUAL = dict(zip(('outside_process_markers','before_draw_unattributed','draw_boundary_unattributed'), (
    'After draw to next process (unattributed elapsed)',
    'Process to draw start (unattributed elapsed)',
    'Draw boundary remainder (rendering, driver and waits not isolated)',
)))
LABELS = SCOPES | RESIDUAL
def zones(raw):
 ticks=raw['stamps_us'];rows=raw['boundary_rows_us'];cuts=raw['scope_rows'];n=len(ticks)-1
 need(type(raw['scope_faults']) is int and raw['scope_faults']==0,'scope_fault')
 need(n>=30 and isinstance(rows,list) and len(rows)==4*n and all(type(v) is int for v in rows),'unreconciled_rows')
 need(isinstance(cuts,list) and len(cuts)==n and bool(SCOPES),'unreconciled_scopes')
 stage=[[],[],[]];groups={key:[0]*n for key in LABELS};calls={key:0 for key in SCOPES}
 for i in range(n):
  a,b,c,d=rows[4*i:4*i+4];need(a==ticks[i] and d==ticks[i+1] and a<b<c<d,'unreconciled_rows')
  need(isinstance(cuts[i],list) and len(cuts[i])==3,'unreconciled_scopes')
  values=(b-a,c-b,d-c)
  for k,(v,r,cut) in enumerate(zip(values,RESIDUAL,cuts[i])):
   stage[k].append(v);assigned=0
   need(isinstance(cut,dict) and cut.keys()<=SCOPES.keys(),'unknown_scope')
   for key,record in cut.items():
    need(isinstance(record,dict) and set(record)=={'usec','calls'},'invalid_scope_record')
    usec,count=record['usec'],record['calls']
    need(type(usec) is int and 0<=usec<=v and type(count) is int and 1<=count<=1000000,'invalid_scope_record')
    assigned+=usec;groups[key][i]+=usec;calls[key]+=count
   need(assigned<=v,'scope_overlap_or_clock_fault')
   groups[r][i]=v-assigned
  need(sum(v[i] for v in groups.values())==d-a,'partition_failed')
 totals={key:sum(v) for key,v in groups.items()};total=ticks[-1]-ticks[0]
 need(sum(totals.values())==total,'partition_failed')
 need(sum(calls.values())>0 and any(totals[key]>0 for key in SCOPES),'no_measured_scopes')
 order=sorted((k for k in SCOPES if totals[k]>0),key=lambda k:(-totals[k],k))
 top=order[:10];tail=order[10:]
 other=[sum(groups[k][i] for k in tail) for i in range(n)]
 def stats(values):
  return {'mean_ms':metric(sum(values)/n/1000),'p95_ms':metric(pct(values,.95)/1000),
          'share_pct':metric(100*sum(values)/total)}
 ranked=[]
 for key in top:
  row={'id':key,'label':LABELS[key], 'nonzero_frames':sum(v>0 for v in groups[key]),**stats(groups[key])}
  if key in calls:row['scope_segment_entries']=calls[key]
  ranked.append(row)
 return {'rows':n,'whole_interval':stats([b-a for a,b in zip(ticks,ticks[1:])]),
         'ranked_exclusive_elapsed':ranked,
         'unassigned_elapsed_by_boundary':{k:{'label':LABELS[k],**stats(groups[k])} for k in RESIDUAL},
         'largest_partition_id':min(totals,key=lambda k:(-totals[k],k)),
         'other_measured_groups':{'group_count':len(tail),**stats(other)},
         'engine_boundary_totals_not_additive_to_ranking':{name:stats(stage[i]) for i,name in enumerate(ZONES)},
         'partition_verified_per_frame':True,
         'interpretation':'Own-time of tagged script sections plus unassigned elapsed time. Callsite timings are elapsed, not CPU-busy; remaining draw time does not isolate GPU, driver, waits, or presentation. Means are additive before rounding; p95s are not additive.'}
def summarize(raw):
 need(raw.get('schema')=='little-leaf-current-native-profile-v1' and raw.get('scenario')=='active-first-cooking','bad_schema')
 e=raw['environment'];version=e['engine'];need(version['hash']=='7d41c59c457bd5a245092b4e7eb2d833e3b3f8c3' and version['build']=='official' and (version['major'],version['minor'],version['patch'])==(4,6,3),'engine_mismatch')
 need(e['display_server']=='X11' and e['window']=='(1360, 880)' and 'llvmpipe' in e['video_adapter'].lower() and 'mesa' in (e['video_api']+' '+e['video_vendor']).lower(),'unexpected_renderer')
 c=raw['capped'];need(live(c['state_start']),'bad_start_state');normal,p95=cadence(c,60,12000000);normal['p95_within_60hz_interval']=p95<=1e6/60
 result={'schema':'ll-current-native-profile-summary-v1','status':'capped_valid','product':COMMIT,'class':'current GitHub-hosted Linux / X11 / 1360×880 / Mesa llvmpipe / official Godot 4.6.3 Compatibility','historical_comparison':False,'cadence':'engine-completed draw intervals; not presented FPS','normal_capped':normal,'headroom':'CPU/GPU busy-work and 15% headroom not measured. Uncapped elapsed gaps still include driver, VSync, scheduling, and other waits.','phase_comparison':'sequential live scene; capped scopes disabled, later uncapped scopes enabled. Instrumentation overhead not calibrated or subtracted; not a controlled A/B or historical speedup','uncapped':None}
 if raw.get('restored_cap')!=60:result['uncapped_status']='cap_not_restored';return result
 u=raw.get('uncapped');status=raw.get('uncapped_status')
 if u is None:
  result['uncapped_status']=status if status in ('skipped_scene_changed','skipped_warmup_changed') else 'no_diagnostic_window';return result
 try:
  need(status=='captured' and c['state_start']==c['state_end']==u['state_start'] and live(u['state_start']),'different_start_state')
  need(live(u['state_end']),'bad_end_state')
  need(u['start_us']>=c['end_us']+1000000,'phases_overlap_or_no_settle')
  diag,up95=cadence(u,0,6000000);z=zones(u);stable=diag['same_recorded_endpoints'];diag.update(z)
  diag['p95_elapsed_proxy_within_14p1667ms']=up95<=TARGET
  need(stable,'different_end_state')
  diag['same_recorded_endpoints_across_phases']=stable
  diag['attribution_context']='later active-cooking endpoints match, not identical frame content' if stable else 'later live workload changed; broad stage timing is this window only'
  result['uncapped_status']='valid_distinct_window';result['uncapped']=diag
 except Invalid as x:result['uncapped_status']=str(x)
 except (KeyError,TypeError,ValueError,IndexError):result['uncapped_status']='invalid_diagnostic_shape'
 return result
def _pairs(items):
 result={}
 for k,v in items:
  need(k not in result,'invalid_measurement_shape')
  result[k]=v
 return result
def _invalid_number(_):
 raise Invalid('invalid_measurement_shape')
def publish(path,out):
 raw={}
 try:
  need(path.stat().st_size<=16_000_000,'invalid_measurement_shape')
  raw=json.loads(path.read_text(),object_pairs_hook=_pairs,parse_constant=_invalid_number);result=summarize(raw)
 except (Invalid,KeyError,TypeError,ValueError,IndexError,OSError) as exc:
  reason=str(exc) if isinstance(exc,Invalid) else 'invalid_measurement_shape'
  if reason not in {'bad_schema','engine_mismatch','unexpected_renderer','bad_start_state','cap_changed','signal_or_thread_fault','buffer_overflow','incomplete_window','unordered_stamps','invalid_measurement_shape'}:reason='invalid_measurement_shape'
  capped=raw.get('capped',{}) if isinstance(raw,dict) else {}
  if not isinstance(capped,dict):capped={}
  nums={k:min(10000,max(0,capped[k])) for k in ('lost','boundary_faults') if type(capped.get(k)) is int}
  if isinstance(capped.get('stamps_us'),list):nums['recorded_callbacks']=min(8192,len(capped['stamps_us']))
  out.write_text(json.dumps(dict(schema='ll-current-native-profile-summary-v1',product=COMMIT,status='not_qualified',stage=reason,bounded_counters=nums,historical_comparison=False,measurements_published=False),indent=2)+'\n');return 2
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
