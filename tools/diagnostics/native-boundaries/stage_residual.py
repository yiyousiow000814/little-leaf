"""Extend only this current diagnostic autoload with disjoint timing boundaries."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

HERE=Path(__file__).resolve().parent
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def hook(code, old, new):
    assert code.count(old)==1, f'Unexpected existing probe hook: {old!r}'
    return code.replace(old,new,1)
def main():
    p=argparse.ArgumentParser()
    p.add_argument('--phase-stage',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    a=p.parse_args()
    src=a.phase_stage/'diagnostic-source.json'
    meta=json.loads(src.read_text())
    assert meta['source']['commit']=='2e3c7f6be9a633fff8e05450033ccdb3a2959c5f'
    assert meta['source']['tree']=='3f76c412ecd12e4782b53ce037be378b019d7270'
    assert 'phase_overlay' in meta and not a.output.exists()
    project=a.output/meta['staged_project']
    shutil.copytree(a.phase_stage/meta['staged_project'],project,ignore=shutil.ignore_patterns('.godot','check-profile'))
    probe=project/'ll_native_draw_probe.gd'
    before=digest(probe)
    code=probe.read_text()
    # Hook boundaries only after setup; post is first action of that signal.
    code=hook(code,'\t_phase_setup()\n','\t_phase_setup()\n\t_boundary_setup()\n')
    code=hook(code,'\t_stamps[_count] = Time.get_ticks_usec()\n','\t_boundary_post(_count)\n\t_stamps[_count] = _b_stamps[6]\n')
    code=hook(code,'\t\t"phase": _phase_result(ended),','\t\t"phase": _phase_result(ended),\n\t\t"residual": _boundary_result(),')
    code=hook(code,'\t_phase_cost[kind] += own\n','\t_phase_cost[kind] += own\n\t_boundary_add_scope(own)\n')
    # The first interval may already have begun before the timer enabled capture.
    probe.write_text(code+(HERE/'residual_probe_snippet.gd.txt').read_text())
    for name,sha in [('frame_clock.c','d56ffc80d17b282782c81a83592f749cc1274204483b34ad7db3034fd3018237'),
                     ('gdextension_interface.h','6228db9a0be9bb154a89911a69ee7ec767f2d40004b3ed5b1d08eebf90bcd16b')]:
        assert digest(HERE/'clock'/name)==sha
    subprocess.run(['gcc','-shared','-fPIC','-O2','-Wall','-Wextra','-Werror','-Wno-cast-function-type',
          str(HERE/'clock/frame_clock.c'),'-o',str(project/'libframe_clock.so')],check=True)
    shutil.copyfile(HERE/'clock/frame_clock.gdextension',project/'frame_clock.gdextension')
    meta['diagnostic_patch']['probe_sha256']=digest(probe)
    meta['residual_overlay']={'input_probe_sha256':before,'output_probe_sha256':digest(probe),
            'clock_sha256':digest(project/'libframe_clock.so'),'clock_config_sha256':digest(project/'frame_clock.gdextension'),
            'compiler':subprocess.check_output(['gcc','--version'],text=True).splitlines()[0],
            'scope':'current-only, nonadditive thread CPU and disjoint elapsed boundaries, no game changes'}
    (a.output/'diagnostic-source.json').write_text(json.dumps(meta,indent=2)+'\n')
    print(project)
if __name__=='__main__':main()
