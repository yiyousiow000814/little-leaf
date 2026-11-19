"""Create the current-only native phase overlay in a disposable diagnostic clone."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil

HERE=Path(__file__).resolve().parent
UI='scripts/rendering/illustrated_cafe.gd'
GAME='scripts/main.gd'
MODEL='scripts/core/cafe_model.gd'
PROBE='ll_native_draw_probe.gd'
EXPECTED='2e3c7f6be9a633fff8e05450033ccdb3a2959c5f'
EXPECTED_TREE='3f76c412ecd12e4782b53ce037be378b019d7270'
def pinwrite(path,value):
    path.write_bytes(value.encode('utf-8'))
def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
def exactly(data, old, new):
    assert data.count(old)==1, f'Expected one exact hook, found {data.count(old)}: {old[:120]!r}'
    return data.replace(old,new,1)
def wrap(data, name, declaration, values, phase, returns=False, predicate='true'):
    original='func '+name+'('+declaration+':\n'
    assert data.count(original)==1, f'Unique declaration for {name}'
    body=(f'func {name}({declaration}:\n'
          f'\tvar ll_token=LLNativeDrawProbe.phase_begin({phase}) if {predicate} else -1\n'
          f'\t{"var ll_value=" if returns else ""}_ll_original{name}({values})\n'
          f'\tLLNativeDrawProbe.phase_end(ll_token)\n'
          + ('\treturn ll_value\n' if returns else '') + '\n'
          f'func _ll_original{name}({declaration}:\n')
    # Explicitly not a production refactor: model behavior is unchanged.
    return exactly(data,original,body)

def inject(game,ui,model,probe):
    # Scope IDs are a checked interface with ll_phase_probe_snippet.gd.txt.
    game=wrap(game,'_process','delta)','delta',0)
    game=wrap(game,'_autosave',')','',1,True)
    model=exactly(model,'func save_data()->Dictionary:\n',
        'func save_data()->Dictionary:\n\tvar ll_token=LLNativeDrawProbe.phase_begin(2)\n\tvar value=_ll_original_save_data()\n\tLLNativeDrawProbe.phase_end(ll_token)\n\treturn value\n\nfunc _ll_original_save_data()->Dictionary:\n')
    ui=wrap(ui,'_draw',')','',5,False,'is_instance_valid(game) and icon_kind==""')
    ui=wrap(ui,'character','p:Vector2,id:int,staff=false,moving=false,seated=false,action="idle",progress=0.0,reach=Vector2(18,-28),look=Vector2(1,0),payload="none",tool="none",pose={},role="chef")',
        'p,id,staff,moving,seated,action,progress,reach,look,payload,tool,pose,role',3,False,'is_instance_valid(game) and icon_kind==""')
    ui=wrap(ui,'_paint_native_character','p: Vector2, id: int, staff: bool, moving: bool, species: int, away: bool, phase: float, action: String, progress: float, reach: Vector2, payload: String, options: Dictionary) -> Dictionary',
        'p,id,staff,moving,species,away,phase,action,progress,reach,payload,options',3,True,'is_instance_valid(game) and icon_kind==""')
    ui=exactly(ui,'\tvar openings=[]\n\tfor attachment in render_wall_attachments if show_objects else []:', '\tvar ll_aperture=LLNativeDrawProbe.phase_begin(4)\n\tvar openings=[]\n\tfor attachment in render_wall_attachments if show_objects else []:')
    ui=exactly(ui,'\t\tif not opening.is_empty():opening["preview"]=bool(attachment.get("preview",false));openings.append(opening)\n\tupdate_projection()',
        '\t\tif not opening.is_empty():opening["preview"]=bool(attachment.get("preview",false));openings.append(opening)\n\tLLNativeDrawProbe.phase_end(ll_aperture)\n\tupdate_projection()')
    ui=exactly(ui,'\tfor opening in openings:entities.append_array(OpeningArt.depth_entries(opening))',
        '\tvar ll_slices=LLNativeDrawProbe.phase_begin(4)\n\tfor opening in openings:entities.append_array(OpeningArt.depth_entries(opening))')
    ui=exactly(ui,'\t\t\tpiece["wall_preview"]=true;piece.depth+=.001;entities.append(piece)\n\tfor entry in render_items:',
        '\t\t\tpiece["wall_preview"]=true;piece.depth+=.001;entities.append(piece)\n\tLLNativeDrawProbe.phase_end(ll_slices)\n\tfor entry in render_items:')
    ui=exactly(ui,'\tvar preparation=OpeningArt.built_preparation(self,piece,render_wall_attachments)',
        '\tvar ll_preparation=LLNativeDrawProbe.phase_begin(4)\n\tvar preparation=OpeningArt.built_preparation(self,piece,render_wall_attachments)\n\tLLNativeDrawProbe.phase_end(ll_preparation)')
    # Actor placement/pose work directly leading to character(), without
    # furniture or scenery; the nested character scope is not double counted.
    ui=exactly(ui,'\t\telse:\n\t\t\tvar d=e.entry\n\t\t\tvar key=("staff_%s"%e.index)', '\t\telse:\n\t\t\tvar ll_actors=LLNativeDrawProbe.phase_begin(3)\n\t\t\tvar d=e.entry\n\t\t\tvar key=("staff_%s"%e.index)')
    ui=exactly(ui,'\t\t\tart_transform(Vector2.ZERO)\n\tif ground_occlusion_start>=0 and canvas_stream.active and use_native_object_nodes:', '\t\t\tart_transform(Vector2.ZERO)\n\t\t\tLLNativeDrawProbe.phase_end(ll_actors)\n\tif ground_occlusion_start>=0 and canvas_stream.active and use_native_object_nodes:')
    probe=exactly(probe,'\t_stamps.resize(LIMIT)','\t_stamps.resize(LIMIT)\n\t_phase_setup()')
    probe=exactly(probe,'\t_started = Time.get_ticks_usec()', '\t_phase_reset()\n\t_started = Time.get_ticks_usec()')
    probe=exactly(probe,'\t\t"engine": Engine.get_version_info(),','\t\t"phase": _phase_result(ended),\n\t\t"engine": Engine.get_version_info(),')
    probe=exactly(probe,'\t_stamps[_count] = Time.get_ticks_usec()','\t_stamps[_count] = Time.get_ticks_usec()\n\t_phase_complete(_count)')
    probe+=(HERE/'ll_phase_probe_snippet.gd.txt').read_text()
    return game,ui,model,probe

def main():
    p=argparse.ArgumentParser()
    p.add_argument('--staged-base',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    a=p.parse_args()
    source=a.staged_base/'diagnostic-source.json'
    info=json.loads(source.read_text())
    assert info['source']['commit']==EXPECTED and info['source']['tree']==EXPECTED_TREE,'Current exact source only; do not rerun historical baseline'
    assert not a.output.exists()
    project=a.output/info['staged_project']
    # All staged product bytes plus the already-reviewed draw probe. Ignore
    # generated caches, private XDG profiles and temporary evidence.
    shutil.copytree(a.staged_base/info['staged_project'],project,ignore=shutil.ignore_patterns('.godot','check-profile'))
    tracked=[GAME,UI,MODEL,PROBE]
    original=[(project/name).read_text() for name in tracked]
    before={name:digest(project/name) for name in tracked}
    for path,data in zip(tracked,inject(*original)):
        pinwrite(project/path,data)
    info['phase_overlay']={'input_sha256': before,'output_sha256':{name:digest(project/name) for name in tracked},
        'source_unchanged_outside_four_files':True,'scope':'current-only, nonoverlapping coarse GDScript windows, not acceptance'}
    info['diagnostic_patch']['probe_sha256']=digest(project/PROBE)
    info['scope']='instrumented current-only diagnostic, not a baseline/candidate FPS comparison'
    (a.output/'diagnostic-source.json').write_text(json.dumps(info,indent=2)+'\n')
    print(project)

if __name__=='__main__':main()
