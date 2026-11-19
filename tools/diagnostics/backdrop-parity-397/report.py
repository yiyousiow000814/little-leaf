"""Report validator for the local no-timing proposal. Only fixed keys and scalar counts; no images, IDs or digests."""
import json,sys
from pathlib import Path
N=1360*880
S={'initial','no_scene','preflight','baseline','sentinel','first_bake','legacy','matched_bake','matched','complete'}
ARMS=('legacy','matched')
NAMES={'stock_0','stock_1','sentinel_on','sentinel_off'}|{a+s for a in ARMS for s in ('_original','_cached','_restored')}
CASES={'gate_env','adapter','scene_wait','preflight','scenario','target_policy','positive_alpha','first_bake','matched_bake','baseline','sentinel','original_restore','read_failure','selection_not_expected','primitive_conservation','cached_composite_pixel_difference','unclassified'}
DEC=CASES|{'exact_parity'}
def req(x):
 if not x: raise ValueError('invalid')
def num(x,lo,hi):
 req(type(x) is int and lo<=x<=hi);return x
def boolean(x):
 req(type(x) is bool);return x
def flags(src,keys):return {k:boolean(src[k]) for k in keys}
CAPB=['target_stable','same_tick','read_present','dimensions_ok','rgba8']
def capture(x):
 r=flags(x,CAPB)
 for k,low,high in [('pre',0,100),('post',0,100),('byte_count',0,N*4),('primitive_count',0,10**9),('draw_calls',0,10**9)]:r[k]=num(x[k],low,high)
 return r
def diff(x):
 r={k:num(x[k],0,N) for k in ['changed','rgb_changed','alpha_changed','alpha_only','one_lsb','outside_sentinel','outside_sentinel_flipped']};r['max_byte_delta']=num(x['max_byte_delta'],0,255)
 req(type(x['quadrants']) is list and len(x['quadrants'])==4)
 r['quadrants']=[num(v,0,N//4) for v in x['quadrants']]
 req(sum(r['quadrants'])==r['changed']==r['rgb_changed']+r['alpha_only'] and r['alpha_only']<=r['alpha_changed']<=r['changed'] and r['one_lsb']<=r['changed'] and (r['max_byte_delta']==0)==(r['changed']==0))
 return r
def classify(c):
 for k,cond in [('root_target_changed',not c['target_stable']),('logical_tick_changed',not c['same_tick']),('force_event_count',(c['pre'],c['post'])!=(1,1)),('readback_null',not c['read_present']),('readback_dimensions',not c['dimensions_ok']),('readback_format_not_rgba8',not c['rgba8']),('readback_byte_count',c['byte_count']!=N*4),('nonpositive_viewport_counter',min(c['primitive_count'],c['draw_calls'])<=0)]:
  if cond:return k
 return 'ok'
def analyze(raw):
 req(raw['schema']=='ll397-backdrop-forensic-v1' and raw['stage'] in S and raw['result'] in ('unqualified','pair_only_no_timing'))
 req(set(raw['captures'])<=NAMES)
 caps={k:capture(x) for k,x in raw['captures'].items()};read={k:classify(c) for k,c in caps.items()}
 o=raw['observations'];clean={};problems=[]
 for k,v in read.items():
  if v!='ok':problems.append([k,v])
 def pair_count(a,b):return all(caps[a][k]==caps[b][k] for k in ('primitive_count','draw_calls'))
 if 'stock_repeat' in o:
  clean['stock_repeat']=diff(o['stock_repeat']);clean['stock_counts_stable']=boolean(o['stock_counts_stable'])
  req(clean['stock_counts_stable']==pair_count('stock_0','stock_1'))
  if clean['stock_repeat']['changed']:problems.append(['baseline','original_A_A_image_mismatch'])
  if not clean['stock_counts_stable']:problems.append(['baseline','original_A_A_counter_mismatch'])
 if 'sentinel' in o:
  t=o['sentinel']; x={'diff':diff(t['diff']),'restore':diff(t['restore']),'counter_restored':boolean(t['counter_restored'])};clean['sentinel']=x
  req(x['counter_restored']==pair_count('stock_0','sentinel_off'))
  if x['diff']['changed']==0:problems.append(['sentinel','target_did_not_change'])
  if min(x['diff']['outside_sentinel'],x['diff']['outside_sentinel_flipped']) or x['diff']['changed']>43*39:problems.append(['sentinel','outside_known_patch'])
  if x['restore']['changed'] or not x['counter_restored']:problems.append(['sentinel','did_not_restore'])
 for name in ARMS:
  if name+'_decision' in o:
   req(o[name+'_decision'] in DEC);clean[name+'_decision']=o[name+'_decision']
  if name not in o:continue
  t=o[name]; f=flags(t['target_flags'],['producer_transparent','root_transparent','producer_hdr','root_hdr'])
  req(not(f['producer_hdr'] or f['root_hdr'] or f['root_transparent']) and f['producer_transparent']==(name=='legacy'))
  e=t['producer_once_events'];req(type(e) is list and len(e)==2)
  x={'target_flags':f,'producer_once_events':[num(i,0,100) for i in e], 'producer_disabled':boolean(t['producer_disabled']),'producer_alpha_255':boolean(t['producer_alpha_255']), 'producer_primitives':num(t['producer_primitives'],0,10**9)};clean[name]=x
  if e!=[1,1] or not x['producer_disabled']:problems.append([name,'producer_event_or_mode'])
  if not x['producer_alpha_255']:problems.append([name,'opaque_coverage_rejected'])
  for key,reason in [('after_bake_stock','source_changed_by_bake'),('cached_diff','cached_composite_pixel_difference'),('restored_diff','original_restore_mismatch')]:
   if key in t:
    x[key]=diff(t[key])
    if key=='after_bake_stock' and not pair_count('stock_0',name+'_original'):problems.append([name,'bake_changed_original_counters'])
    if x[key]['changed']:problems.append([name,reason])
  if 'counter_ok' in t:
   x.update(flags(t,['counter_ok','restore_counter_ok']))
   actual=num(t['actual_removed'],-10**9,10**9);expected=num(t['expected_removed'],-2,10**9-2)
   req(expected==x['producer_primitives']-2 and actual==caps[name+'_original']['primitive_count']-caps[name+'_cached']['primitive_count'])
   req(x['restore_counter_ok']==pair_count(name+'_original',name+'_restored'))
   x.update(actual_removed=actual,expected_removed=expected)
   req(x['counter_ok']==(actual==expected and x['producer_primitives']>2))
   if not x['counter_ok']:problems.append([name,'independent_primitive_equation'])
   if not x['restore_counter_ok']:problems.append([name,'original_restore_counts'])
 outcome='unqualified'
 if raw['result']=='pair_only_no_timing':
  req(raw['stage']=='complete' and set(caps)==NAMES and clean['stock_repeat']['changed']==0 and clean['stock_counts_stable'] and 'sentinel' in clean)
  req(all(x[1]=='cached_composite_pixel_difference' for x in problems))
  for a in ARMS:
   d=clean[a]
   req(d['counter_ok'] and d['restore_counter_ok'] and d['producer_alpha_255'] and d['producer_disabled'] and d['producer_once_events']==[1,1] and d['after_bake_stock']['changed']==0 and d['restored_diff']['changed']==0)
   req(clean[a+'_decision']==('exact_parity' if d['cached_diff']['changed']==0 else 'cached_composite_pixel_difference'))
  old=clean['legacy']['cached_diff']['changed'];new=clean['matched']['cached_diff']['changed']
  outcome=('old_differs_matched_exact' if old and not new else 'neither_differs' if not old and not new else 'matched_differs')
 else:
  req(raw['failure'] in CASES);problems.append([raw['stage'],raw['failure']])
 return {'schema':'ll397-forensic-bounded-summary-v1','outcome':outcome,'stage':raw['stage'],'checks':clean,'captures':caps,'flags':problems,'timing':False}
def read(raw):
 def pairs(kvs):
  result={}
  for k,v in kvs:
   req(k not in result);result[k]=v
  return result
 def bad(v):raise ValueError('nonfinite')
 req(len(raw)<65536);return analyze(json.loads(raw,object_pairs_hook=pairs,parse_constant=bad))
if __name__=='__main__':
 try:result=read(Path(sys.argv[1]).read_bytes())
 except (ValueError,TypeError,KeyError,IndexError,OSError):result={'schema':'ll397-forensic-bounded-summary-v1','outcome':'invalid_evidence','timing':False}
 b=json.dumps(result,sort_keys=True,allow_nan=False).encode()+b'\n';req(len(b)<16384);Path(sys.argv[2]).write_bytes(b)
