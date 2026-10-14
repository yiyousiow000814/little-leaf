#!/usr/bin/env python3
"""Expand the user's positively received Harmony Study B, not the rejected full V2.

The first eight melody bars are preserved exactly. New middle/return material is
original; the Restaurant City recording supplies no pitches or sampled audio.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE.parent
BPM = 112
PC = {'C':0, 'D':2, 'E':4, 'F':5, 'G':7, 'A':9, 'B':11}

def pitch(name: str) -> int:
    return 12 * (int(name[-1]) + 1) + PC[name[0]]

def build() -> dict:
    base_path = HERE / 'B_reduced_harmony_source.json'
    base = json.loads(base_path.read_text())
    notes = [dict(n) for n in base['notes'] if n['beat'] < 32]
    # No selection of A versus B on the user's behalf. B is only this trial's base.
    harmony = [
      [[0,'C6']], [[0,'Am7']], [[0,'Dm7']], [[0,'G7']],
      [[0,'Em7'],[2,'Am7']], [[0,'Dm7'],[2,'G7']],
      [[0,'Cmaj7'],[2,'Am7']], [[0,'Dm7'],[2,'G7']],
      [[0,'F6']], [[0,'Em7']], [[0,'Dm7']], [[0,'G7']],
      [[0,'Fmaj7']], [[0,'Em7'],[2,'Am7']],
      [[0,'Dm7'],[2,'G7']], [[0,'C6'],[2,'G7']],
      [[0,'C6']], [[0,'Am7']], [[0,'Dm7']], [[0,'G7']],
      [[0,'Em7'],[2,'Am7']], [[0,'Dm7'],[2,'G7']],
      [[0,'C6'],[2,'F6']], [[0,'Dm7'],[1,'G7'],[2,'C6']],
    ]
    middle = [
      [(.5,'A4',.5),(1,'C5',.5),(1.5,'D5',1),(2.5,'C5',.5),(3,'A4',.5)],
      [(0,'B4',1),(1.5,'D5',.5),(2,'E5',1),(3,'D5',.5),(3.5,'B4',.5)],
      [(.5,'A4',.5),(1,'C5',.5),(1.5,'D5',1),(2.5,'F5',.5),(3,'E5',.5),(3.5,'D5',.5)],
      [(0,'D5',1),(1.5,'B4',.5),(2,'A4',.5),(2.5,'G4',.5)],
      [(0,'A4',.5),(.5,'C5',.5),(1,'E5',1),(2.5,'D5',.5),(3,'C5',.5),(3.5,'A4',.5)],
      [(.5,'G4',.5),(1,'B4',1),(2,'C5',1),(3.5,'E5',.5)],
      [(0,'F5',1),(1,'E5',.5),(1.5,'D5',.5),(2.5,'B4',.5),(3,'D5',.5)],
      [(0,'E5',1),(1,'G5',.5),(1.5,'E5',.5),(2,'D5',1),(3.5,'B4',.5)],
    ]
    def add(part: str, bar: int, onset: float, p: str | int, duration: float,
            velocity: int, delay: float=0, gate: float=.90) -> None:
        notes.append(dict(part=part, beat=bar*4+onset,
                          pitch=pitch(p) if isinstance(p,str) else p,
                          duration=duration, velocity=velocity,
                          delay_ms=delay, gate=gate))
    # The keyboard remains the same instrument throughout; do not make an abrupt
    # timbre or mood reset in the middle merely to demonstrate "development".
    for bar, phrase in enumerate(middle, 8):
        arch = [-2,1,3,1,-1,-3,-4]
        for i, (onset, p, duration) in enumerate(phrase):
            add('rhodes',bar,onset,p,duration,72+arch[i%len(arch)],
                11 if onset%1 else 5, .85 if duration<=.5 else .94)
    for n in base['notes']:
        if n['part']=='rhodes' and n['beat']<24:
            nn=dict(n); nn['beat']+=64
            notes.append(nn)
    for bar,phrase in [
      (22,[(0,'G5',1.5),(1.5,'E5',.5),(2,'A5',.5),(2.5,'G5',.5),(3,'F5',.75)]),
      (23,[(0,'F5',.5),(.5,'D5',.5),(1,'B4',.5),(1.5,'D5',.5),(2,'C5',1.5)])]:
        for i,(onset,p,duration) in enumerate(phrase):
            add('rhodes',bar,onset,p,duration,[75,74,74,72,71,69][i],
                11 if onset%1 else 5,.86 if duration<=.5 else .95)
    # Use the original B's exact accompaniment in the first statement and most
    # of the return. This preserves what worked instead of treating it as a vague mood.
    for n in base['notes']:
        if n['part']!='rhodes' and n['beat']<24:
            nn=dict(n);nn['beat']+=64;notes.append(nn)
    voices={
      'C6':['E3','G3','A3','C4'], 'Cmaj7':['E3','G3','B3','C4'],
      'Am7':['E3','G3','A3','C4'], 'Dm7':['F3','A3','C4','D4'],
      'G7':['F3','G3','B3','D4'], 'Em7':['E3','G3','B3','D4'],
      'F6':['F3','A3','C4','D4'], 'Fmaj7':['F3','A3','C4','E4'],
    }
    def at(bar,onset):
        return next(s for t,s in reversed(harmony[bar]) if t<=onset)
    for bar in list(range(8,16))+[22,23]:
        pattern=[(.0,.80,51),(1.5,.48,44),(2.5,.72,49)] if bar%2==0 else [(.5,.72,49),(2,.90,51)]
        if len(harmony[bar])==2:pattern=[(.5,.80,49),(2,.90,51)]
        if bar==23:pattern=[(0,.72,48),(1,.72,48),(2,1.5,48)]
        for onset,duration,velocity in pattern:
            for i,p in enumerate(voices[at(bar,onset)]):
                add('guitar',bar,onset,p,duration,velocity+(1 if i==3 else -1),7+i*5.4,.90)
        # Two tiny guitar answers occur only in clear melody rests.
        if bar==11:
            add('guitar',bar,3,'B3',.5,48,12,.90)
            add('guitar',bar,3.5,'D4',.5,47,14,.90)
        if bar==14:
            add('guitar',bar,3.5,'D4',.5,46,12,.90)
        drum_cell=[(0,36,29,.12),(1,38,23,.22),(2,36,24,.12),(3,37,27,.11)]
        if bar==23: drum_cell=[(0,36,28,.12),(1,37,24,.11),(2,36,23,.12)]
        for t,p,v,d in drum_cell:add('drums',bar,t,p,d,v,10 if p!=36 else 0,1)
    bass={
      8:[(0,'F2',1.4,74),(2,'C3',1.0,65)],
      9:[(0,'E3',1.4,74),(2,'B2',1.0,65),(3.5,'C3',.38,55)],
      10:[(0,'D3',1.4,74),(2,'A2',1.0,65),(3.5,'F2',.38,54)],
      11:[(0,'G2',1.4,73),(2,'D3',1.1,64)],
      12:[(0,'F2',1.4,74),(2,'C3',1.0,65),(3.5,'D3',.38,55)],
      13:[(0,'E3',1.4,74),(2,'A2',1.05,68),(3.5,'C3',.38,55)],
      14:[(0,'D3',1.4,74),(2,'G2',1.05,68),(3.5,'B2',.38,55)],
      15:[(0,'C3',1.4,74),(2,'G2',1.05,68),(3.5,'B2',.38,55)],
      22:[(0,'C3',1.4,75),(2,'F2',1.0,67),(3.5,'E2',.38,54)],
      23:[(0,'D3',.72,72),(1,'G2',.72,68),(2,'C3',1.5,70)],
    }
    for bar,events in bass.items():
        for onset,p,duration,velocity in events:
            add('bass',bar,onset,p,duration,velocity,-4 if onset%1==0 else 2,.86)
    notes.sort(key=lambda n:(n['beat'],n['part'],n['pitch']))
    first=lambda nn:[n for n in nn if n['part']=='rhodes' and n['beat']<32]
    assert first(notes)==sorted(first(base['notes']),key=lambda n:(n['beat'],n['part'],n['pitch']))
    assert all(0<=n['beat']<96 and n['duration']>0 and n['beat']+n['duration']<=96 for n in notes)
    assert all(0<=n['pitch']<=127 and 1<=n['velocity']<=127 for n in notes)
    return {
      'title':'Corner Cafe - Reference Rearrangement',
      'status':'NEW_UNACCEPTED_AUDITION', 'bpm':BPM, 'meter':'4/4',
      'bars':24,'duration_beats':96,'key':'C major',
      'base':'Harmony Study B; A and B both remain positive short references',
      'preserved':'First eight melody bars EXACT in pitch, beat, duration, velocity, delay and gate',
      'not_used_as_base':['Full Corner Cafe V2', 'Daybreak Steps 104/112'],
      'reference_use':'Uploaded RC Default: broad instrument roles, repeating light groove and leave-space principle only; no transcription or sample',
      'source_b_json_sha256':hashlib.sha256(base_path.read_bytes()).hexdigest(),
      'sections':[{'bar':1,'label':'A - preserved study phrase'}, {'bar':9,'label':'B - lower answer'}, {'bar':17,'label':'A return - tonic ending'}],
      'harmony':harmony,'notes':notes,
    }

if __name__=='__main__':
    score=build()
    (OUT/'music_events.json').write_text(json.dumps(score,ensure_ascii=False,indent=2)+'\n')
    print(f"Wrote {len(score['notes'])} events, 24 bars, {BPM} BPM")
