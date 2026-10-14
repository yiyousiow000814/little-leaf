#!/usr/bin/env python3
"""Sunshine Skip / 晴日蹦跳 — new 176 BPM cheerful acoustic theme.

This is newly written material, not Pinwheel Parade sped up or reharmonized.
Single accordion lead; eight-bar hook, rising answer, light-footed bridge,
varied hook return and two-bar coda. Source input: none; no network or paid API.
All performed notes and phrase/expression controls are exported in a ledger.
"""
from __future__ import annotations
import argparse
import json
import math
import re
from pathlib import Path
import numpy as np

BPM = 176.0
SPB = 60.0 / BPM
PICKUP = .5
TITLE = 'Sunshine_Skip_176bpm_New_Theme'
SR = 44100
BANK_SHA = 'c5378b62028c920cb11e4803327983fee2f2cdff5dc89c708e39da417e51c854'

# The opening 0.5 / 0.25 / 0.25 / 0.5 / 0.5 cell returns recognizably;
# the answer, bridge, final return and endings are separately composed.
A = [
 'G4:.5 A4:.25 B4:.25 D5:.5 B4:.5 G5:.75 E5:.25 D5:.5 B4:.5',
 'C5:.75 E5:.25 G5:.5 E5:.5 D5:.5 C5:.5 B4:.5 G4:.5',
 'B4:.5 D5:.5 G5:1 F#5:.5 E5:.5 D5:.5 B4:.5',
 'A4:.5 D5:.5 F#5:.5 E5:.5 D5:.75 A4:.25 R:.5 D5:.5',
 'E5:.5 G5:.25 F#5:.25 E5:.5 B4:.5 D5:.5 E5:.5 G5:.5 F#5:.5',
 'E5:.75 G5:.25 A5:.5 G5:.5 E5:.5 D5:.5 C5:.5 E5:.5',
 'C5:.5 B4:.25 A4:.25 E5:.5 C5:.5 A4:.5 D5:.5 F#5:.5 A5:.5',
 'G5:1.5 D5:.5 B4:.5 G4:.5 R:.5 B4:.5',
]
B = [
 'E5:1 G5:.5 A5:.5 G5:.75 E5:.25 D5:.5 C5:.5',
 'D5:.5 G5:.5 B5:1 A5:.5 G5:.5 D5:1',
 'C5:.5 E5:.5 A5:.75 G5:.25 E5:.5 C5:.5 B4:.5 A4:.5',
 'A4:.5 D5:.25 E5:.25 F#5:.5 A5:.5 G5:.5 F#5:.5 E5:.5 D5:.5',
 'D5:1 B4:.5 D5:.5 F#5:1 E5:.5 D5:.5',
 'E5:.5 B4:.5 G5:1 F#5:.5 E5:.5 B4:.5 G4:.5',
 'C5:.5 E5:.5 G5:.5 E5:.5 A5:.75 G5:.25 E5:.5 C5:.5',
 'F#5:1 E5:.5 D5:.5 A4:.5 C5:.5 D5:.75 R:.25',
]
C = [
 'E5:.5 R:.5 G5:1 E5:.5 D5:.5 C5:1',
 'F#5:.5 R:.5 A5:1 F#5:.5 E5:.5 D5:1',
 'B4:.5 D5:.5 G5:1 D5:.5 B4:.5 A4:.5 G4:.5',
 'E5:1 D5:.5 B4:.5 G4:.5 B4:.5 E5:.75 R:.25',
 'A4:.5 C5:.5 E5:.5 C5:.5 A5:1 G5:.5 E5:.5',
 'G5:1 D5:.5 B4:.5 D5:.5 G5:.5 A5:.5 B5:.5',
 'G5:.5 E5:.5 C5:.5 E5:.5 G5:.5 A5:.5 G5:.5 E5:.5',
 'F#5:.5 A5:.5 F#5:.5 E5:.5 D5:.5 C5:.5 A4:.25 B4:.25 C5:.25 D5:.25',
]
AR = [
 'G4:.5 A4:.25 B4:.25 D5:.5 B4:.5 G5:.75 A5:.25 B5:.5 G5:.5',
 'E5:.5 G5:.25 A5:.25 G5:.5 E5:.5 C5:.75 D5:.25 E5:.5 G5:.5',
 'B4:.5 D5:.5 G5:.75 A5:.25 B5:.5 A5:.5 G5:.5 D5:.5',
 'F#5:.5 A5:.5 D6:.5 C6:.5 A5:.5 F#5:.5 E5:.5 D5:.5',
 'E5:.5 G5:.25 F#5:.25 E5:.5 B4:.5 G5:.75 F#5:.25 E5:.5 B4:.5',
 'E5:.5 G5:.5 A5:.5 G5:.5 E5:.5 D5:.5 C5:.5 E5:.5',
 'C5:.5 E5:.5 A5:1 F#5:.5 A5:.5 C6:.5 A5:.5',
 'G5:1 D5:.5 B4:.5 G4:.5 B4:.5 D5:.5 G5:.5',
]
CODA = [
 'A5:.5 F#5:.5 D5:.5 C5:.5 B4:.5 A4:.5 D5:1',
 'B4:.5 D5:.5 G5:2 R:1',
]
MELODY = A + B + C + AR + CODA
HARMONIES = [
 [(0,'G')],[(0,'C')],[(0,'G/B')],[(0,'D7')],[(0,'Em')],[(0,'C')],[(0,'Am'),(2,'D7')],[(0,'G')],
 [(0,'C')],[(0,'G/D')],[(0,'Am')],[(0,'D7')],[(0,'Bm')],[(0,'Em')],[(0,'C')],[(0,'D7')],
 [(0,'C')],[(0,'D')],[(0,'G')],[(0,'Em')],[(0,'Am')],[(0,'G/B')],[(0,'C')],[(0,'D7')],
 [(0,'G')],[(0,'C')],[(0,'G/B')],[(0,'D7')],[(0,'Em')],[(0,'C')],[(0,'Am'),(2,'D7')],[(0,'G')],
 [(0,'D7')],[(0,'G6')],
]
VOICINGS = {
 'G':['B3','D4','G4'], 'G/B':['B3','D4','G4'], 'G/D':['B3','D4','G4'], 'G6':['B3','D4','E4','G4'],
 'C':['C4','E4','G4'], 'D':['A3','D4','F#4'], 'D7':['C4','D4','F#4'],
 'Em':['B3','E4','G4'], 'Am':['C4','E4','A4'], 'Bm':['B3','D4','F#4'],
}
BASS_NOTES = {
 'G':['G2','D3','B2','D3'], 'G/B':['B2','D3','G2','B2'], 'G/D':['D3','B2','G2','D3'],
 'G6':['G2','D3','B2','E3'], 'C':['C3','G2','E3','G2'],
 'D':['D3','A2','F#2','A2'], 'D7':['D3','A2','C3','F#2'],
 'Em':['E2','B2','G2','B2'], 'Am':['A2','E3','C3','E3'], 'Bm':['B2','F#2','D3','F#2'],
}


def pitch(name: str) -> int:
    m = re.fullmatch(r'([A-G])([#b]?)(-?\d+)', name)
    if not m:
        raise ValueError(f'Bad scientific pitch: {name}')
    return 12*(int(m[3])+1)+{'C':0,'D':2,'E':4,'F':5,'G':7,'A':9,'B':11}[m[1]]+{'':0,'#':1,'b':-1}[m[2]]


def tokens(text: str):
    result = [(n,float(t)) for n,t in (x.split(':') for x in text.split())]
    if abs(sum(t for _,t in result)-4)>1e-9:
        raise ValueError(f'Bar duration is not 4: {text}')
    return result


def chord_at(bar: int, beat: float) -> str:
    return next(name for start,name in reversed(HARMONIES[bar]) if start<=beat+1e-8)


def compose() -> dict:
    assert len(MELODY)==len(HARMONIES)==34
    parts = {
        'accordion': dict(label='Warm accordion - buoyant principal hook throughout', program=21, channel=0, pan=-.025, hp=165, lp=6200, wet=.055, mode='sustained'),
        'guitar': dict(label='Nylon guitar - compact syncopated chord brushes', program=24, channel=1, pan=-.28, hp=125, lp=5400, wet=.035, mode='plucked'),
        'pizzicato': dict(label='Pizzicato strings - light, short harmonic answers', program=45, channel=2, pan=.28, hp=170, lp=6300, wet=.045, mode='plucked'),
        'bass': dict(label='Upright bass - stepping and connecting foundation', program=32, channel=3, pan=.025, hp=44, lp=2600, wet=.02, mode='plucked'),
        'brushes': dict(label='Soft kick / crisp brushed snare / light hat - common pulse', program=0, channel=9, pan=.10, hp=48, lp=6800, wet=.015, mode='percussion'),
    }
    notes=[]
    def add(part,b,name,d,v,gate=.9,delay=0.,**extra):
        start=b*SPB+delay
        end=start+d*SPB*gate
        if start<0 or d<=0 or gate<=0: raise ValueError('Invalid note timing')
        notes.append(dict(part=part,beat=round(b,8),duration=float(d),pitch=pitch(name) if isinstance(name,str) else name,
          velocity=int(np.clip(v,1,127)),start_seconds=round(start,8),end_seconds=round(end,8),gate=float(gate),delay_ms=delay*1000,**extra))
    add('accordion',0,'D5',.25,66,.92,role='pickup',bar=0)
    add('accordion',.25,'E5',.25,72,.96,role='pickup',bar=0)
    sections=['hook']*8+['rising_answer']*8+['light_bridge']*8+['varied_hook_return']*8+['coda']*2
    arcs=[76,78,81,74,78,82,84,74, 77,81,79,82,75,78,81,72, 68,71,74,70,73,78,80,83, 81,83,84,85,80,83,85,80,78,68]
    for bar,text in enumerate(MELODY):
        seq=tokens(text);cursor=0.;ob=PICKUP+bar*4;section=sections[bar]
        sounding=[i for i,(p,_) in enumerate(seq) if p!='R']
        for i,(p,d) in enumerate(seq):
            if p!='R':
                n=pitch(p);strong=cursor in (0.,2.)
                v=arcs[bar]+(3 if strong else -2)+(2 if d>=1 else -3 if d==.25 else 0)
                # Higher register gets less velocity, not greater attack simply because high.
                if n>=84:v-=7
                nxt=next((q for q,_ in seq[i+1:] if q!='R'),None)
                close=nxt is not None and abs(pitch(nxt)-n)<=2
                gate=.97 if close else .87
                if d>=1:gate=.965
                if d==.25:gate=.93
                if i+1<len(seq) and seq[i+1][0]=='R':gate=.84;v-=4
                if i==sounding[-1]:v-=3
                if bar==33 and d==2:gate=1.0;v=64
                add('accordion',ob+cursor,p,d,v,gate,role='melody',bar=bar+1,note_index=i,section=section)
            cursor+=d
        # One coherent rhythm section, with texture changes across phrases rather
        # than unrelated per-part fills. All intentional onsets share the beat grid.
        if bar==33:
            for j,n in enumerate(VOICINGS['G6']):add('guitar',ob,n,2.8,47-j*2,1.,j*.003,role='harmony',bar=bar+1)
            add('bass',ob,'G2',2.8,65,1.,role='foundation',bar=bar+1)
            for j,n in enumerate(VOICINGS['G'][:2]):add('pizzicato',ob,n,.6,39-j*2,.95,role='cadence',bar=bar+1)
            continue
        # Guitar: light brush patterns. Avoid synchronized double-chord strikes
        # with pizzicato unless it is a deliberate final accent.
        if section=='light_bridge':
            pattern=[(.5,.6,46),(2.5,.5,43)] if bar%2==0 else [(1.5,.5,45),(3.,.45,43)]
        elif bar%8==7:
            pattern=[(.5,.42,50),(2.5,.40,46)]
        elif bar%2==0:
            pattern=[(.5,.40,51),(2.,.38,49),(3.5,.28,43)]
        else:
            pattern=[(.5,.40,50),(1.5,.32,44),(3.,.36,48)]
        for t,du,v in pattern:
            for j,n in enumerate(VOICINGS[chord_at(bar,t)]):
                add('guitar',ob+t,n,du,v-j*2,.93,j*.0028,role='harmony',bar=bar+1)
        # Pizzicato is not a second tune: narrow voicings, brief gaps and answers.
        if section=='light_bridge': pp=[(0.,.55,37)] if bar%2==0 else []
        elif bar%8==7: pp=[(1.,.40,43)]
        elif bar%2==0: pp=[(1.,.38,45),(3.,.32,40)]
        else: pp=[(0.,.35,42),(2.5,.34,40)]
        for t,du,v in pp:
            vo=VOICINGS[chord_at(bar,t)]
            for j,n in enumerate(vo[:2]):add('pizzicato',ob+t,n,du,v-j*3,.92,role='harmonic_answer',bar=bar+1)
        # Bass step changes are selected as chord tones / diatonic approaches.
        if section=='light_bridge': bt=[0.,2.] if bar<22 else [0.,1.,2.,3.]
        elif section=='varied_hook_return' and bar%4!=3:bt=[0.,1.,2.,3.]
        elif bar%2==0:bt=[0.,1.5,2.5,3.5]
        else:bt=[0.,2.,3.]
        if bar%8==7:bt=[0.,2.,3.5]
        for k,t in enumerate(bt):
            h=chord_at(bar,t);arr=BASS_NOTES[h]
            idx=0 if t==0 or (len(HARMONIES[bar])>1 and t==2.) else (1 if k%2 else 2)
            note=arr[idx]
            # Written diatonic links to the next bar, no root-minus-semitone rule.
            if t==3.5:
                choices={0:'B2',2:'C3',4:'B2',6:'F#2',7:'B2',10:'C3',14:'C3',15:'B2',22:'C3',23:'F#2',24:'B2',26:'C3',28:'B2',30:'F#2',31:'C3'}
                note=choices.get(bar,note)
            following=bt[k+1]-t if k+1<len(bt) else 4-t
            du=min(.85,following*.90)
            add('bass',ob+t,note,du,63 if k==0 else 53 if t==3.5 else 58,.94,role='foundation' if t==0 else 'step',bar=bar+1)
        # Brushed backbeat and quiet high pulses: density builds/backs away with sections.
        active=bar!=32
        if active:
            if section=='light_bridge' and bar<20:
                drum=[(0,36,33,'kick'),(3,38,30,'brush')]
            else:
                drum=[(0,36,40,'kick'),(1,38,40,'brush'),(2,36,30,'kick'),(3,38,44,'brush')]
                if bar%8==7:drum=[(0,36,35,'kick'),(1,38,36,'brush')]
            for t,n,v,tone in drum:add('brushes',ob+t,n,.14,v,1.,tone=tone,role='pulse',bar=bar+1)
            hat=[.5,1.5,2.5,3.5] if section in ['rising_answer','varied_hook_return'] else [.5,2.5]
            if section=='light_bridge' and bar<20:hat=[]
            if bar%8==7:hat=[.5]
            for t in hat:add('brushes',ob+t,42,.08,22 if t in (1.5,3.5) else 26,1.,tone='hat',role='subdivision',bar=bar+1)
    notes.sort(key=lambda n:(n['start_seconds'],n['part'],n['pitch']))
    length=(PICKUP+len(MELODY)*4)*SPB+2.0
    # Smooth phrase expression plus note-specific articulation. No global
    # identical triangle envelope and no whole-mix pumping.
    controls={p:[] for p in parts}
    ns=[n for n in notes if n['part']=='accordion']
    times=np.arange(0,length+.001,.0125)
    gesture=[(0,.88),(PICKUP,.92),(PICKUP+12,.98),(PICKUP+28,.86),
             (PICKUP+32,.91),(PICKUP+42,1.0),(PICKUP+60,.85),
             (PICKUP+64,.81),(PICKUP+76,.88),(PICKUP+84,.98),(PICKUP+94,1.0),
             (PICKUP+96,.97),(PICKUP+112,1.0),(PICKUP+124,.91),
             (PICKUP+128,.88),(PICKUP+132,.84),(PICKUP+136,.30)]
    gb=np.array([x for x,y in gesture]);gv=np.array([y for x,y in gesture])
    values=[];index=0
    for time in times:
        while index+1<len(ns) and ns[index+1]['start_seconds']<=time:index+=1
        n=ns[index];st=n['start_seconds'];en=n['end_seconds'];age=time-st;du=en-st
        phrase=float(np.interp(time/SPB,gb,gv));level=.9
        if st<=time<=en:
            u=age/max(du,1e-5)
            if n['duration']>=1:
                contour=([.83,.97,1.,.94,.78] if n['bar']%4 in (1,2) else [.94,1.,.97,.84,.70])
                if n['bar']==34:contour=[.91,.98,.88,.65,.36]
                level=float(np.interp(u,[0,.12,.37,.78,1],contour))
            elif n['duration']==.25:
                level=float(np.interp(u,[0,.14,.68,1],[.95,1.,.96,.86]))
            else:
                level=float(np.interp(u,[0,.15,.63,1],[.9,1.,.95,.79]))
        elif time>en:
            level=.76 if time-en<.10 else .85
            if n['bar']==34:level=.34
        values.append(int(np.clip(round(108*phrase*level),25,115)))
    previous=None
    for t,v in zip(times,values):
        if v!=previous:controls['accordion'].append({'time':round(float(t),7),'type':'expression','value':v});previous=v
    score=dict(bpm=BPM,meter=[4,4],key_fifths=1,pickup=['D5:.25','E5:.25'],bars=MELODY,harmonies=HARMONIES,lead_parts=['accordion']*len(MELODY))
    return dict(title=TITLE,title_zh='晴日蹦跳',revision='R5 new replacement fourth theme',status='NEW_FOURTH_AWAITING_USER_LISTENING',
       notes=notes,continuous_controls=controls,parts=parts,
       tempo_clock=dict(bpm=BPM,constant_quarter_clock=True,performed_eighth_ratio=None,audio_time_stretch=False,audio_pitch_shift=False),
       beat_time_map=[[0.,0.],[(PICKUP+len(MELODY)*4),(PICKUP+len(MELODY)*4)*SPB]],
       score=score,duration_seconds=length,sample_rate=SR,master_gain=5.524237257635934,
       part_gains=dict(accordion=.94,guitar=.68,pizzicato=1.,bass=.62,brushes=.12),
       high_shelf_settings={'accordion':[3100,-3.5]},stem_trim_db={},tail_fade_seconds=.12,
       soundfont_sha256=BANK_SHA,reference_audio_used=False,initial_master_calibration={'target_lufs': -20.5, 'max_oversampled_peak_dbfs': -2.8, 'no_compression': True},
       sections=[{'name':n,'first_bar':a,'last_bar':b,'start_seconds':(PICKUP+(a-1)*4)*SPB} for n,a,b in [('Hook',1,8),('Rising answer',9,16),('Light bridge',17,24),('Varied hook return',25,32),('Coda',33,34)]],
       musical_changes=['Newly composed 34-bar theme at 176 BPM, not reusing Pinwheel Parade notes or audio.',
         'Same principal accordion voice for every melody section; no mid-track lead swap.',
         'Recognizable dotted/short-step hook, a rising answer, lighter bridge and varied return.',
         'Shared straight pulse with restrained rhythm-section density changes; no random onset jitter.',
         'Phrase-scale and note-level expression survives in the audio and MIDI controller timeline.'],
       midi_limit='MIDI contains notes, CC11 and tempo. SoundFont, custom brush/hat synthesis, EQ/room and mix gains are not embedded; use renderer for matching audio.',
       loop_status='Closed complete audition with natural release; not a seamless loop-qualified asset.')

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('output',type=Path)
    a=p.parse_args();a.output.parent.mkdir(parents=True,exist_ok=True)
    d=compose();a.output.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(f'{len(d["notes"])} note events; {len(d["continuous_controls"]["accordion"])} expression points; {d["duration_seconds"]:.3f}s')
