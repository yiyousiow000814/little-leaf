import sys
"""Prepare, but do not launch, isolated cloud-native tutorial screenshot QA.

The resulting project can be imported/run through Godot Project Manager.
Source/game saves are never edited. The harness dispatches ordinary controls
and advances real service in accelerated simulation time, not wall-clock time.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from project_layout import stage_project
EXCLUDE = shutil.ignore_patterns('.git', '.godot', 'qa-project', '__pycache__',
    'build', 'builds', 'export', 'exports', 'export_templates', 'evidence', '*.zip', '*.log')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--preview-only', action='store_true', help='Capture only Open/Staff/Decorate before the service explanation')
    args = parser.parse_args()
    out = args.output.resolve()
    if out.exists():
        raise SystemExit('Use a new output path to preserve previous evidence')
    out.mkdir(parents=True)
    project = out / 'project'
    evidence = out / 'evidence'
    evidence.mkdir()
    stage_project(ROOT, project, tests=True, ignore=EXCLUDE)
    source = subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip()
    name = 'LittleLeaf-saveguard-tutorial-' + out.name
    config = (project / 'project.godot').read_text()
    config = config.replace('config/name="Little Leaf Cafe"', f'config/name="{name}"\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="{name}"')
    config = config.replace('run/main_scene="res://main.tscn"', 'run/main_scene="res://tutorial_qa.tscn"')
    (project / 'project.godot').write_text(config)
    code = (ROOT / 'tests/test_interactive_tutorial.gd').read_text()
    code = code.replace('extends SceneTree', 'extends Node', 1)
    code = code.replace('const Main=preload("res://scripts/main.gd")', '''class FreshMain extends "res://scripts/main.gd":
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _setup_music():pass''')
    code = code.replace('game=Main.new()', 'game=FreshMain.new()')
    code = code.replace(' static var fixture=', ' func _setup_music():pass\n static var fixture=', 1)
    code = code.replace('func _initialize():run.call_deferred()', '''func _ready():
 preload("res://scripts/cafe_intro.gd").shown_this_session=true
 run.call_deferred()''')
    code = re.sub(r'\broot\b', 'get_tree().root', code)
    code = re.sub(r'\bprocess_frame\b', 'get_tree().process_frame', code)
    code = code.replace('get_processed_tweens()', 'get_tree().get_processed_tweens()')
    code = code.replace('quit(', 'get_tree().quit(')
    code = code.replace('OS.get_user_data_dir().begins_with(OS.get_environment("XDG_DATA_HOME"))', '"saveguard" in OS.get_user_data_dir()')
    code = code.replace('OS.get_environment("LL_TUTORIAL_CAPTURE")', json.dumps(str(evidence)))
    code = code.replace('OS.get_environment("LL_UI_RESULT")', json.dumps(str(out / 'native-result.json')))
    if args.preview_only:
        code = code[:code.index(' reload_state("active",State.ORDER)')]
        code += ' var preview={"status":"compact visual preview only","checks":checks,"failures":failures,"captures":captures,"layouts":layouts,"player_save_used":false}\n'
        code += ' var f=FileAccess.open(' + json.dumps(str(out / 'native-result.json')) + ',FileAccess.WRITE);f.store_string(JSON.stringify(preview,"\\t"));f.close()\n'
        code += ' await close_game();get_tree().quit(0 if failures.is_empty() else 1)\n'
    (project / 'tutorial_qa.gd').write_text(code)
    (project / 'tutorial_qa.tscn').write_text('[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://tutorial_qa.gd" id="1"]\n\n[node name="TutorialQA" type="Node"]\nscript = ExtResource("1")\n')
    hashes = {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in ROOT.rglob('*') if p.is_file() and not any(part in
              {'.git', '.godot', 'qa-project', '__pycache__'} for part in p.relative_to(ROOT).parts)}
    receipt = {'source_commit': source, 'source_sha256': hashes, 'project': str(project),
               'evidence': str(evidence), 'profile_name': name, 'player_save_used': False,
               'native_render_verified': False, 'mode': 'prepared; real GUI input, accelerated service ticks'}
    (out / 'preparation.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({k: v for k, v in receipt.items() if k != 'source_sha256'}, indent=2))


if __name__ == '__main__':
    main()
