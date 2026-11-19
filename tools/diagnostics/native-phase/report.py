"""Report mutually exclusive synchronous scope costs and unexplained frame time."""
import json
import math
from pathlib import Path
import sys

NAMES = ['game_update_except_autosave', 'autosave_except_save_data', 'save_data_preparation',
         'actor_draw_command_generation', 'wall_preparation', 'other_main_cafe_draw_script']

def summarize(raw):
    p=raw['phase']
    assert raw['stage']=='active-first-cooking' and raw['lost']==0 and p['accounting_faults']==0
    assert p['phase_names']==NAMES
    ticks=raw['stamps_us']
    assert len(ticks)>=5 and len(p['exclusive_us'])==len(p['counts'])==len(ticks)*len(NAMES)
    assert all(type(x) is int and x>=0 for x in p['exclusive_us']+p['counts'])
    starts=[j-i for i,j in zip(ticks,ticks[1:])]
    assert all(x>0 for x in starts)
    # Frame 0 may predate the capture marker. Cut off every partial endpoint.
    values=[]; calls=[]
    for i,gap in enumerate(starts,1):
        row=p['exclusive_us'][i*len(NAMES):(i+1)*len(NAMES)]
        counts=p['counts'][i*len(NAMES):(i+1)*len(NAMES)]
        assert sum(row)<=gap+2, (f'Overlap, duplicate scopes or accounting clock mismatch in window {i}',row,gap)
        assert all(c or x==0 for x,c in zip(row,counts)),f'Elapsed phase without a scope call in window {i}'
        values.append([*row,max(0,gap-sum(row))])
        calls.append(counts)
    def metrics(rows, col):
        active=[row[col] for row in rows]
        ordered=sorted(active)
        return {'mean_ms':sum(active)/len(rows)/1000,
                'p50_ms':ordered[math.ceil(.5*len(ordered))-1]/1000,
                'p95_ms':ordered[math.ceil(.95*len(ordered))-1]/1000,
                'max_ms':ordered[-1]/1000}
    def group(rows):
        if not rows:return None
        return {k:metrics(rows,i) for i,k in enumerate(NAMES+['unassigned_frame_wall_time'])}
    active_save=[row for row,c in zip(values,calls) if c[1]>0 or c[2]>0]
    no_save=[row for row,c in zip(values,calls) if not (c[1]>0 or c[2]>0)]
    total=group(values)
    ranking=sorted(NAMES,key=lambda k:total[k]['mean_ms'],reverse=True)
    return {'scope':'Current native instrumented 21-wall first seated cooking; synchronous main-thread elapsed, not CPU busy, software GL or GPU decomposition',
            'frames':len(values),'save_frames':len(active_save),'non_save_frames':len(no_save),
            'frame_wall_mean_ms':sum(starts)/len(starts)/1000,'scoped_rank_by_mean':ranking,
            'largest_measured_scope':ranking[0], 'scope_calls':dict(zip(NAMES,map(sum,zip(*calls)))),
            'all':total,'save_only':group(active_save),'no_save':group(no_save),
            'unknown_explanation':'Residual includes software rendering, native draw work, driver/OS wait, uninstrumented work, and measured probe overhead. It is not a GPU timing or a component.'}

if __name__=='__main__':
    print(json.dumps(summarize(json.loads(Path(sys.argv[1]).read_text())),indent=2))
