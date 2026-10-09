"""Exact-body diagnostic expansion only. Does not modify production source files."""
import argparse
import json
import re
from pathlib import Path

UI = ['ui_header', 'ui_settings', 'ui_catalog', 'ui_build_tools', 'ui_compact']
MUSIC = [f'music_{state}_{part}' for state in ['service', 'busy', 'decorate'] for part in ['load', 'duplicate', 'node']] + ['music_initial_switch']
DETAILS = UI + MUSIC

def method(source, name):
    match = re.search(r'^func ' + re.escape(name) + r'\(\):\n', source, re.M)
    if not match:
        raise ValueError('Missing exact source method: ' + name)
    following = re.search(r'^func ', source[match.end():], re.M)
    end = match.end() + following.start() if following else len(source)
    return source[match.start():end]

def strip_marks(text):
    return ''.join(line for line in text.splitlines(keepends=True)
                   if not re.fullmatch(r'\t+_phase_(?:detail_)?mark\([^\n]*\)\n', line))

def expand(template, source):
    if '_phase_detail_mark(' in source or '_phase_mark(' in source:
        raise ValueError('Production source already contains diagnostic marks')
    generated = template
    for name, outer in [('_build_ui', 6), ('_setup_music', 8)]:
        original = method(source, name)
        lines = original.splitlines(keepends=True)
        marked = [lines[0], f'\t_phase_mark({outer})\n']
        if name == '_build_ui':
            marked += ['\t_phase_detail_mark(0)\n']
            boundaries = {'\tsettings_controls=SettingsControls.new(self,SAVE_FILE)\n':2,
                          '\ttray=PanelContainer.new()\n':4,
                          '\tbuild_panel=build_tools.build();column.add_child(build_panel);build_panel.hide()\n':6,
                          '\tcompact_ui=CompactUI.new(self);compact_ui.setup()\n':8}
            found=[]
            for line in lines[1:]:
                if line in boundaries:
                    code=boundaries[line];found.append(code)
                    marked += [f'\t_phase_detail_mark({code-1})\n',f'\t_phase_detail_mark({code})\n']
                marked.append(line)
            if found != [2,4,6,8]: raise ValueError('UI boundaries changed')
            marked += ['\t_phase_detail_mark(9)\n']
        else:
            anchors = {
                '\t\tvar source=load(files[state]) as AudioStreamMP3\n': ('\t\t_phase_detail_mark(_DETAIL_MUSIC_CODE[state])\n','\t\t_phase_detail_mark(_DETAIL_MUSIC_CODE[state]+1)\n'),
                '\t\tvar stream=source.duplicate() as AudioStreamMP3\n': ('\t\t_phase_detail_mark(_DETAIL_MUSIC_CODE[state]+2)\n',''),
                '\t\tvar player=AudioStreamPlayer.new()\n': ('\t\t_phase_detail_mark(_DETAIL_MUSIC_CODE[state]+3)\n\t\t_phase_detail_mark(_DETAIL_MUSIC_CODE[state]+4)\n',''),
                '\t\taudio_players[state]=player\n': ('','\t\t_phase_detail_mark(_DETAIL_MUSIC_CODE[state]+5)\n'),
                '\t_switch_music("service")\n': ('\t_phase_detail_mark(28)\n','\t_phase_detail_mark(29)\n')}
            found=[]
            for line in lines[1:]:
                if line in anchors:
                    before,after=anchors[line];found.append(line);marked += [before,line,after]
                else:marked.append(line)
            if len(found)!=5:raise ValueError('Music boundaries changed')
        marked += [f'\t_phase_mark({outer+1})\n']
        candidate=''.join(marked)
        if strip_marks(candidate)!=original:raise ValueError('Executable body differs after stripping marks: '+name)
        generated=generated.replace(method(generated,name),candidate+'\n',1)
    return generated

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--source',type=Path,required=True);parser.add_argument('--template',type=Path,required=True)
    args=parser.parse_args();print(expand(args.template.read_text(),args.source.read_text()),end='')
