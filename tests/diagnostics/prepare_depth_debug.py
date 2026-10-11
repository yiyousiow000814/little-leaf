"""Opt-in dev view; reuse the frozen no-save depth probe, never edit game source."""
from pathlib import Path
import argparse
import hashlib
import json
from prepare_depth_occlusion import prepare

def prepare_debug(repo, output):
    identity = prepare(repo, output)
    artist = output / 'project/scripts/illustrated_cafe.gd'
    raw = artist.read_bytes()
    eol = '\r\n' if b'\r\n' in raw else '\n'
    text = raw.decode().replace('\r\n', '\n')
    old = '\ts*=ui_scale*zoom*(1.55 if is_instance_valid(game) and game.wall_detail else 1.0)\n\tvar crown_bounds='
    assert text.count(old) == 1
    text = text.replace(old, old.replace('\n\tvar crown_bounds=', '\n\t_depth_probe_tree_contours(p,s,horizontal_scale)\n\tvar crown_bounds='))
    text += '''
func _depth_probe_tree_contours(p:Vector2,s:float,horizontal_scale:float):
	if not depth_probe_active or depth_probe_context.get("part","")!="scenery_tree":return
	var contours=[]
	for index in [1,4]:
		var points=[]
		for point in exterior_tree_art.layers[index][1]:
			var screen=p+point*Vector2(s*horizontal_scale,s)+_presentation_offset
			points.append([screen.x,screen.y])
		contours.append(points)
	depth_probe_context["occlusion_contours"]=contours
'''
    artist.write_bytes(text.replace('\n', eol).encode())
    import difflib
    original = (repo / 'game/scripts/illustrated_cafe.gd').read_text(encoding='utf-8')
    diff = ''.join(difflib.unified_diff(original.splitlines(True), text.splitlines(True), fromfile='tracked/illustrated_cafe.gd', tofile='staged/illustrated_cafe.gd'))
    (output / 'instrumentation.diff').write_text(diff, encoding='utf-8', newline='\n')
    identity['capture_mode'] = 'debug_view'
    identity['staged_artist_sha256'] = hashlib.sha256(artist.read_bytes()).hexdigest()
    identity['instrumentation_diff_sha256'] = hashlib.sha256((output / 'instrumentation.diff').read_bytes()).hexdigest()
    for name in ['capture_depth_debug.gd','depth_debug_overlay.gd','prepare_depth_debug.py']:
        key='tests/diagnostics/'+name
        identity['files'][key]=hashlib.sha256((repo/key).read_bytes()).hexdigest()
    (output/'identity.json').write_text(json.dumps(identity,indent=2)+'\n',encoding='utf-8')
    return identity

if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    print(json.dumps(prepare_debug(Path(__file__).resolve().parents[2],args.output.resolve())))
