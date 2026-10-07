"""Copy a source checkout and the same fixture into a disposable native/Web project."""
import argparse,shutil
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--web-template',type=Path);a=p.parse_args()
shutil.copytree(a.source,a.output,ignore=shutil.ignore_patterns('.git','.godot','qa-project','__pycache__','export_templates'),dirs_exist_ok=False)
fixture=Path(__file__).with_name('performance_profile.gd').read_text()
if a.web_template:
 fixture=fixture.replace('extends SceneTree','extends Node').replace('func _initialize():','func _ready():').replace('await process_frame','await get_tree().process_frame').replace('quit()','get_tree().quit()')
 fixture=fixture.replace('# Identical deterministic workload','var root:Window:\n\tget:return get_tree().root\n# Identical deterministic workload')
 (a.output/'qa/performance_entry.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://qa/performance_profile.gd" id="1"]\n[node name="Performance" type="Node"]\nscript = ExtResource("1")\n')
 project=a.output/'project.godot';code=project.read_text(encoding='utf-8-sig')
 code=code.replace('run/main_scene="res://main.tscn"','run/main_scene="res://qa/performance_entry.tscn"')
 project.write_text(code)
 (a.output/'export_templates').mkdir();shutil.copyfile(a.web_template,a.output/'export_templates/web_nothreads_release.zip')
(a.output/'qa/performance_profile.gd').write_text(fixture)
