"""Split exact residual into disjoint wall zones and nonadditive CPU clocks."""
import json
import math
from pathlib import Path
import sys

ZONES=['prior_post_to_process','process_to_pre_draw','pre_to_post_draw']
COLS=12
def metrics(vals):
    vals=list(vals)
    ordered=sorted(vals)
    return {'mean_ms':sum(vals)/len(vals), 'p50_ms':ordered[math.ceil(.5*len(vals))-1],
            'p95_ms':ordered[math.ceil(.95*len(vals))-1], 'max_ms':ordered[-1]}

def report(raw):
    b=raw['residual']
    p=raw['phase']
    assert raw['stage']=='active-first-cooking' and raw['lost']==0
    assert p['accounting_faults']==b['faults']==0 and b['thread_id_matches_pid']
    n=len(raw['stamps_us'])
    assert n>=5 and b['cols']==COLS and len(b['rows'])==n*COLS and b['zones']==ZONES
    n_scopes=len(p['phase_names'])
    assert len(p['exclusive_us'])==n*n_scopes
    rows=[b['rows'][i*COLS:(i+1)*COLS] for i in range(n)]
    fields=('wall','main_thread_cpu','main_thread_not_running','process_all_thread_cpu',
            'other_threads_cpu','known_scope_wall','unassigned_wall')
    matrix={name:{field:[] for field in fields} for name in ZONES}
    totals=[]
    for i in range(1,n):
        prev,here=rows[i-1],rows[i]
        assert here[6]==raw['stamps_us'][i] and prev[6]==raw['stamps_us'][i-1]
        assert sum(here[9:])==sum(p['exclusive_us'][i*n_scopes:(i+1)*n_scopes]),'Loss or overlap in classified script scope'
        moments=[prev[6:9],here[0:3],here[3:6],here[6:9]]
        wall_total=0
        for z,name in enumerate(ZONES):
            a,c=moments[z:z+2]
            wall=(c[0]-a[0])/1000
            cpu=(c[1]-a[1])/1e6
            cpu_all=(c[2]-a[2])/1e6
            scoped=here[9+z]/1000
            assert wall>=0 and 0<=cpu<=wall+0.10 and cpu_all>=0 and cpu_all+0.10>=cpu,'Clock drift, cross-thread reading or order failure'
            assert 0<=scoped<=wall+0.003,'Scope time crosses a boundary'
            # Sampling order introduces microseconds of boundary skew. Keep
            # small negatives visible; do not floor them and break accounting.
            values=(wall,cpu,wall-cpu,cpu_all,cpu_all-cpu,scoped,wall-scoped)
            for k,v in zip(fields,values):
                matrix[name][k].append(v)
            wall_total+=wall
        assert abs(wall_total-(here[6]-prev[6])/1000)<0.0001
        totals.append(wall_total)
    summary={z:{k:metrics(v) for k,v in m.items()} for z,m in matrix.items()}
    zone=max(ZONES,key=lambda x:summary[x]['unassigned_wall']['mean_ms'])
    total_residual=sum(summary[x]['unassigned_wall']['mean_ms'] for x in ZONES)
    return {'scope':'Same-current instrumented native GL on cloud; not GPU, Web or hardware-device acceptance',
            'complete_intervals':n-1,'total_frame_wall_ms':metrics(totals),
            'unassigned_mean_ms':total_residual,'largest_residual_zone':zone,
            'largest_residual_zone_fraction':summary[zone]['unassigned_wall']['mean_ms']/max(total_residual,1e-9),
            'zones':summary,
            'limits':'Only wall columns are a disjoint frame partition. Thread CPU is not additive to wall; other threads CPU may overlap and exceed wall. Main-thread nonexecution includes waits or descheduling. Pre→post includes driver, synchronization, swap and elapsed native rendering, not pure GPU. Classified script elapsed and main CPU are not subtracted from one another.'}

if __name__=='__main__':
    print(json.dumps(report(json.loads(Path(sys.argv[1]).read_text())),indent=2))
