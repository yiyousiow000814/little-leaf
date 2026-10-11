"""Prepare a disposable instrumented project without launching an engine."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess
import sys


def sha(data):
    return hashlib.sha256(data).hexdigest()


def prepare(repo, output):
    sys.path.insert(0, str(repo / 'tools'))
    from project_layout import stage_project
    output.mkdir(parents=True, exist_ok=False)
    project = output / 'project'
    stage_project(repo, project, tests=True,
                  ignore=shutil.ignore_patterns('.godot', '__pycache__'))
    artist = project / 'scripts/illustrated_cafe.gd'
    original = artist.read_bytes()
    eol = '\r\n' if b'\r\n' in original else '\n'
    text = original.decode('utf-8').replace('\r\n', '\n')
    hooks = (repo / 'tests/diagnostics/depth_occlusion_probe_hooks.gd.txt').read_text(encoding='utf-8')
    text += '\n' + hooks

    def replace(old, new):
        nonlocal text
        assert text.count(old) == 1, (old, text.count(old))
        text = text.replace(old, new)

    replace('func _draw():\n', 'func _draw():\n\t_depth_probe_reset()\n')
    replace('\tfor entry in entries:\n\t\tif bool(entry.get("parking_car",false)):',
            '\tfor entry in entries:\n\t\t_depth_probe_begin("street_actor",str(entry.get("key",entry.get("guest",{}).get("id",""))),entry.position,entry.position.x+entry.position.y)\n\t\tif bool(entry.get("parking_car",false)):')
    replace('\nfunc _draw_bus_stop_people(under_roof:bool,show_people:bool=true):',
            '\n\tdepth_probe_context={}\n\nfunc _draw_bus_stop_people(under_roof:bool,show_people:bool=true):')
    replace('\t_scenery_tree(Vector2(13.5,-.5),1.10)\n',
            '\t_depth_probe_begin("rear_tree","rear_tree",Vector2(13.5,-.5),13.0)\n\t_scenery_tree(Vector2(13.5,-.5),1.10)\n')
    replace('\tfor e in entities:\n', '\tfor e in entities:\n\t\t_depth_probe_entity(e)\n')
    replace('\tnode.configure(self, callback, appearance, placement)\n\treturn true\n',
            '\tnode.configure(self, callback, appearance, placement)\n\t_depth_probe_submit("native_object",order,node)\n\treturn true\n')
    replace('\tshape.configure(method, arguments, placement)\n',
            '\tshape.configure(method, arguments, placement)\n\t_depth_probe_submit("native_shape",order,shape)\n')
    replace('\t_finish_native_objects()\n\tcanvas_stream.finish()\n',
            '\t_finish_native_objects()\n\t_depth_probe_finish()\n\tcanvas_stream.finish()\n')
    artist.write_bytes(text.replace('\n', eol).encode('utf-8'))
    # Freeze the exact diagnostic-only changes before requesting any runtime.
    import difflib
    diff = ''.join(difflib.unified_diff(original.decode('utf-8').replace('\r\n', '\n').splitlines(True),
                                     text.splitlines(True),
                                     fromfile='tracked/illustrated_cafe.gd',
                                     tofile='staged/illustrated_cafe.gd'))
    (output / 'instrumentation.diff').write_text(diff, encoding='utf-8', newline='\n')
    command = ['git', '-c', 'safe.directory=' + repo.as_posix(), '-C', str(repo)]
    identity = subprocess.check_output(command + ['log', '-1', '--format=%H %T'], text=True).strip().split()
    files = ['tests/diagnostics/capture_depth_occlusion.gd',
             'tests/diagnostics/depth_occlusion_probe_hooks.gd.txt',
             'tests/diagnostics/prepare_depth_occlusion.py',
             'tests/diagnostics/run_depth_occlusion.py',
             'tests/role_fixture.gd', 'game/scripts/illustrated_cafe.gd',
             'game/scripts/cafe_native_draw_node.gd', 'game/scripts/cafe_interaction.gd',
             'game/scripts/exterior_tree_art.gd', 'game/scripts/street_pedestrians.gd']
    record = {'head': identity[0], 'tree': identity[1],
              'player_profiles_accessed': False, 'engine_launched': False,
              'release_eligible': False, 'instrumentation_diff_sha256': sha(diff.encode()),
              'original_artist_sha256': sha(original),
              'staged_artist_sha256': sha(artist.read_bytes()),
              'files': {name: sha((repo / name).read_bytes()) for name in files}}
    (output / 'identity.json').write_text(json.dumps(record, indent=2) + '\n', encoding='utf-8')
    return record


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(prepare(Path(__file__).resolve().parents[2], args.output.resolve())))
