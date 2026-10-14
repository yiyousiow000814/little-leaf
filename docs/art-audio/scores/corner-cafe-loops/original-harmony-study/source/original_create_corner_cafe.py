#!/usr/bin/env python3
"""Little Leaf: Corner Cafe, an original RC-inspired style study.

No external recording is sampled/transcribed. The opening E-G-A cell develops
Little Leaf's existing Sunlit Table idea; all arrangement/music here is authored.

Requires: Python 3.10+, numpy, scipy, soundfile, mido, pyloudnorm, libfluidsynth,
ffmpeg and a user-supplied GM SoundFont. Tested with the system TimGM6mb bank.
The SoundFont is NOT redistributed. No network, account, API, or game-repo writes.

Run: python source/create_corner_cafe.py --out . --soundfont /path/to/TimGM6mb.sf2
"""
from __future__ import annotations
import argparse
import ctypes as ct
import ctypes.util
from dataclasses import dataclass, asdict
import hashlib
import json
import math
from pathlib import Path
import shutil
import subprocess
from xml.etree import ElementTree as ET
import mido
import numpy as np
import soundfile as sf
from scipy.signal import butter, sosfilt, fftconvolve, resample_poly
import pyloudnorm as pyln

BPM = 112
SR = 44100
SPB = 60.0 / BPM
BAR = 4.0
N_BARS = 32
TICKS = 960
TITLE = 'Little Leaf - Corner Cafe'

@dataclass(frozen=True)
class Note:
    part: str
    beat: float
    pitch: int
    duration: float
    velocity: int
    delay_ms: float = 0.0
    gate: float = 0.90

PARTS = {
    'rhodes': {'name':'Electric piano - main theme', 'program':4, 'bank':0, 'channel':0, 'pan':-0.08, 'rms_db':-23.8, 'hp':130, 'lp':9000, 'wet':0.105},
    'guitar': {'name':'Nylon guitar - bossa comping', 'program':24, 'bank':0, 'channel':1, 'pan':-0.35, 'rms_db':-28.5, 'hp':160, 'lp':7200, 'wet':0.075},
    'bass': {'name':'Upright bass - moving two-feel', 'program':32, 'bank':0, 'channel':2, 'pan':0.0, 'rms_db':-25.2, 'hp':44, 'lp':3200, 'wet':0.012},
    'vibes': {'name':'Vibraphone - phrase answers', 'program':11, 'bank':0, 'channel':3, 'pan':0.29, 'rms_db':-30.4, 'hp':310, 'lp':8500, 'wet':0.12},
    'piano': {'name':'Acoustic piano - middle section', 'program':0, 'bank':0, 'channel':4, 'pan':0.1, 'rms_db':-29.0, 'hp':150, 'lp':8200, 'wet':0.08},
    'flute': {'name':'Flute - short background answers', 'program':73, 'bank':0, 'channel':5, 'pan':-0.21, 'rms_db':-34.0, 'hp':380, 'lp':7000, 'wet':0.12},
    'drums': {'name':'Brush kit and hand percussion', 'program':40, 'bank':128, 'channel':9, 'pan':0.0, 'rms_db':-31.4, 'hp':65, 'lp':10000, 'wet':0.027},
}
PC={'C':0,'D':2,'E':4,'F':5,'G':7,'A':9,'B':11}
def midi_pitch(name: str | int) -> int:
    if isinstance(name,int): return name
    pc=PC[name[0]];acc=0;index=1
    if name[1:2] in ['#','b']:
        acc=1 if name[1]=='#' else -1;index=2
    return (int(name[index:])+1)*12+pc+acc

# Harmonies: (beat within bar, symbol); music is not a progression transcription.
HARM=[
 [(0,'C69')],[(0,'A7b9')],[(0,'Dm9')],[(0,'G13')],
 [(0,'Em7'),(2,'A7')],[(0,'Dm9'),(2,'G13')],[(0,'Cmaj9'),(2,'Am7')],[(0,'Dm9'),(2,'G13')],
 [(0,'C69')],[(0,'E7b9')],[(0,'Am9')],[(0,'D9')],
 [(0,'Fmaj9')],[(0,'Fm6')],[(0,'C6E'),(2,'A7')],[(0,'Dm9'),(2,'G13')],
 [(0,'Fmaj9')],[(0,'G13')],[(0,'Em9')],[(0,'Am9')],
 [(0,'Dm9')],[(0,'D9')],[(0,'G13sus')],[(0,'G13')],
 [(0,'C69')],[(0,'A7b9')],[(0,'Dm9')],[(0,'G13')],
 [(0,'Em7'),(2,'A7')],[(0,'Dm9'),(2,'G13')],[(0,'C69'),(2,'Fmaj9')],[(0,'Dm9'),(2,'G13')],
]
# Close guitar voicings, independent bass. Deliberate minor-IV colour at bar14.
V={
 'C69':['E3','A3','D4','G4'], 'Cmaj9':['E3','B3','D4','G4'],
 'A7b9':['G3','Bb3','C#4','E4'], 'A7':['G3','A3','C#4','E4'],
 'Dm9':['F3','A3','C4','E4'], 'G13':['F3','A3','B3','E4'],
 'Em7':['G3','B3','D4','E4'], 'Em9':['G3','B3','D4','F#4'],
 'Am7':['G3','A3','C4','E4'], 'Am9':['G3','B3','C4','E4'],
 'E7b9':['G#3','B3','D4','F4'], 'D9':['F#3','A3','C4','E4'],
 'Fmaj9':['A3','C4','E4','G4'], 'Fm6':['Ab3','C4','D4','F4'],
 'C6E':['G3','A3','C4','E4'], 'G13sus':['F3','A3','C4','E4'],
}
ROOT={'C69':'C3','Cmaj9':'C3','A7b9':'A2','A7':'A2','Dm9':'D3','G13':'G2',
 'Em7':'E3','Em9':'E3','Am7':'A2','Am9':'A2','E7b9':'E3','D9':'D3','Fmaj9':'F2','Fm6':'F2','C6E':'E3','G13sus':'G2'}
FIFTH={'C69':'G2','Cmaj9':'G2','A7b9':'E3','A7':'E3','Dm9':'A2','G13':'D3',
 'Em7':'B2','Em9':'B2','Am7':'E3','Am9':'E3','E7b9':'B2','D9':'A2','Fmaj9':'C3','Fm6':'C3','C6E':'G2','G13sus':'D3'}

# Each bar is deliberately composed, with answering space and recurring hooks.
# [onset, pitch, written duration]. Retain the E-G-A Little Leaf cell at returns.
M=[
 [(0.5,'E5',.5),(1,'G5',.5),(1.5,'A5',1),(2.5,'G5',.5),(3,'E5',.5),(3.5,'D5',.5)],
 [(0,'C#5',.5),(.5,'E5',.5),(1,'G5',1),(2,'E5',1)],
 [(0.5,'F5',.5),(1,'A5',1),(2,'G5',.5),(2.5,'F5',.5),(3,'E5',.5),(3.5,'D5',.5)],
 [(0,'B4',1),(1.5,'D5',.5),(2,'E5',1),(3.5,'D5',.5)],
 [(0.5,'G5',.5),(1,'B5',1),(2,'A5',.5),(2.5,'G5',.5),(3,'E5',.5),(3.5,'C#5',.5)],
 [(0,'F5',.5),(.5,'E5',.5),(1,'D5',1),(2.5,'B4',.5),(3,'D5',.5),(3.5,'E5',.5)],
 [(0,'G5',1.5),(1.5,'E5',.5),(2,'C5',1.0)],
 [(0.5,'A4',.5),(1,'D5',.5),(1.5,'F5',.5),(2.5,'E5',.5),(3,'D5',.5),(3.5,'B4',.5)],
 # A': the first shape is familiar; answering harmony/ending changes.
 [(0,'E5',.5),(.5,'G5',.5),(1.5,'A5',1),(2.5,'G5',.5),(3,'E5',1)],
 [(0.5,'D5',.5),(1,'F5',.5),(1.5,'E5',1),(2.5,'B4',.5),(3,'G#4',.5),(3.5,'B4',.5)],
 [(0,'C5',.5),(.5,'E5',.5),(1.5,'G5',1),(2.5,'E5',.5),(3,'B4',1)],
 [(0.5,'A4',.5),(1,'C5',.5),(1.5,'E5',1),(2.5,'F#5',.5),(3,'E5',.5),(3.5,'D5',.5)],
 [(0,'C5',.5),(.5,'E5',.5),(1,'G5',1),(2.5,'A5',.5),(3,'G5',1)],
 [(0,'F5',1),(1,'D5',.5),(1.5,'C5',1.5)],
 [(0.5,'E5',.5),(1,'G5',1),(2,'E5',.5),(2.5,'C#5',.5),(3,'B4',.5),(3.5,'A4',.5)],
 [(0,'D5',1),(1.5,'F5',.5),(2,'E5',.5),(2.5,'D5',.5),(3,'B4',.5)],
 # B: acoustic piano leads; lower, longer phrases and a clearer dynamic arch.
 [(0,'A4',1.5),(1.5,'C5',.5),(2,'E5',1),(3,'G5',1)],
 [(0,'F5',.5),(.5,'E5',.5),(1,'D5',1),(2,'B4',1.5)],
 [(0.5,'G4',.5),(1,'B4',1),(2,'D5',1),(3,'F#5',1)],
 [(0,'E5',1.5),(1.5,'C5',.5),(2,'B4',.5),(2.5,'A4',1)],
 [(0,'F5',1.5),(1.5,'E5',.5),(2,'D5',.5),(2.5,'C5',.5),(3,'A4',1)],
 [(0.5,'C5',.5),(1,'D5',.5),(1.5,'E5',.5),(2,'F#5',1),(3,'A5',.5),(3.5,'G5',.5)],
 [(0,'E5',1.5),(1.5,'D5',.5),(2,'C5',1.0)],
 [(0.5,'B4',.5),(1,'D5',.5),(1.5,'E5',.5),(2,'G5',.5),(2.5,'A5',.5),(3,'B5',.5)],
 # A'': return, a single peak, then an open turnaround for a musical loop.
 [(0.5,'E5',.5),(1,'G5',.5),(1.5,'A5',1),(2.5,'G5',.5),(3,'E5',.5),(3.5,'D5',.5)],
 [(0,'C#5',.5),(.5,'E5',.5),(1,'G5',1),(2,'E5',1)],
 [(0.5,'F5',.5),(1,'A5',.5),(1.5,'C6',1),(2.5,'A5',.5),(3,'G5',.5),(3.5,'F5',.5)],
 [(0,'E5',1),(1.5,'D5',.5),(2,'B4',1)],
 [(0.5,'G5',.5),(1,'B5',1),(2,'A5',.5),(2.5,'G5',.5),(3,'E5',.5),(3.5,'C#5',.5)],
 [(0,'F5',.5),(.5,'E5',.5),(1,'D5',1),(2.5,'B4',.5),(3,'D5',.5),(3.5,'E5',.5)],
 [(0,'G5',1),(1.5,'E5',.5),(2,'A5',.5),(2.5,'G5',.5),(3,'E5',1)],
 [(0,'F5',.5),(.5,'E5',.5),(1,'D5',1),(2,'B4',.5),(2.5,'D5',.5),(3,'G4',.5)],
]
assert len(M)==len(HARM)==N_BARS

def harmony_at(b:int,t:float)->str:
    return next(s for onset,s in reversed(HARM[b]) if onset<=t+1e-8)


def composition()->list[Note]:
    out:list[Note]=[]
    def add(part,b,beat,pitch,dur,vel,delay=0.0,gate=.9):
        out.append(Note(part,b*4+beat,midi_pitch(pitch),dur,vel,delay,gate))
    for b,bar in enumerate(M):
        bridge=16<=b<24
        part='piano' if bridge else 'rhodes'
        for i,(bt,p,d) in enumerate(bar):
            arch=[-3,1,4,2,-1,-3,-2][i%7]
            vel=76+arch+(3 if b>=24 else -4 if bridge else 0)
            if midi_pitch(p)>=84: vel-=5
            # A clear pulse with phrase-shaped articulation; no random mistiming.
            delay=(10 if bridge else 5)+(6 if bt%1==.5 else 0)
            gate=.83 if d<=.5 else .92
            add(part,b,bt,p,d,vel,delay,gate)
        # First/last statement gets a soft chord-third note on a few long tones.
        if b in [0,8,24]:
            add('rhodes',b,1.5,'E5',.75,46,9,.91)
        # Middle section isn't a wall of sound; Rhodes provides very sparse warmth.
        if bridge and b in [16,18,20,22]:
            for j,p in enumerate(V[harmony_at(b,0)][1:]):
                add('rhodes',b,0,p,1.5,43-j*2,12+j*2,.93)

        # A two-bar rhythmic cell, varied at cadences. Explicit strum directions.
        patterns=[[(0,.70,58),(1.5,.42,51),(2.5,.60,56),(3.5,.32,45)],
                  [(.5,.62,53),(1.5,.40,48),(2,.66,59),(3.5,.32,48)],
                  [(0,.64,57),(1.5,.45,51),(2.5,.48,54),(3.5,.30,44)],
                  [(.5,.55,51),(1.5,.38,47),(2,.66,57)]]
        pat=patterns[b%4]
        if b in [7,15,23,31]: pat=[(.5,.52,53),(2,.65,56),(3.5,.32,41)]
        if bridge: pat=[(.5,.75,49),(2.5,.65,51)] if b%2==0 else [(0,.72,51),(1.5,.45,44),(3,.65,47)]
        for bt,dur,vel in pat:
            voices=V[harmony_at(b,bt)]
            order=list(range(len(voices))) if bt%1==0 else list(reversed(range(len(voices))))
            for j,idx in enumerate(order):
                add('guitar',b,bt,voices[idx],dur,vel+(2 if idx==3 else -1),7+j*5.4,.90)

        # Bass: keep recognisable pulse, two-bar answers, melodic approaches.
        h=HARM[b];sym=h[0][1];root=ROOT[sym];fifth=FIFTH[sym]
        next_root=midi_pitch(ROOT[HARM[(b+1)%32][0][1]])
        approach=next_root-1 if b%4!=2 else next_root+2
        if len(h)>1:
            p2=ROOT[h[1][1]]
            patb=[(0,root,1.22,78),(1.5,fifth,.44,61),(2,p2,1.12,74),(3.5,approach,.38,57)]
        elif bridge:
            patb=[(0,root,1.75,70),(2,fifth,1.45,65)]
            if b in [17,19,21,23]:patb[-1]=(2,fifth,1.0,65);patb.append((3.5,approach,.38,56))
        elif b%4==0:
            patb=[(0,root,1.30,78),(1.5,fifth,.40,58),(2,root,1.06,71),(3.5,approach,.38,58)]
        elif b%4==1:
            patb=[(0,root,1.5,76),(2,fifth,1.15,68),(3.5,approach,.38,59)]
        elif b%4==2:
            patb=[(0,root,1.28,76),(1.5,fifth,.38,60),(2,root,1.42,73)]
        else:
            patb=[(0,root,1.45,75),(2,fifth,1.02,66),(3.5,approach,.39,58)]
        for bt,p,d,v in patb:add('bass',b,bt,p,d,v,-4 if bt%1==0 else 2,.86)

        # Brushes / rim / bongo: small two-bar bossa pulse, not a rock backbeat.
        for bt,v in [(0,37),(1.75,27),(2,32),(3.5,24)]:
            add('drums',b,bt,36,.12,v-7 if bridge else v,0,1)
        clicks=[(1,36),(2.5,25),(3,30)] if b%2==0 else [(0.5,25),(1.5,31),(3,36)]
        if b%8==7:clicks=[(1,30),(2.5,23)]
        for bt,v in clicks:add('drums',b,bt,37,.11,v-7 if bridge else v,10,1)
        # Swishes at beats two/four with quiet foot-hat rather than bright cymbals.
        for bt,v in [(1,28),(3,25)]:add('drums',b,bt,38,.22,v-6 if bridge else v,12,1)
        for bt,v in [(.5,22),(1.5,18),(2.5,20),(3.5,18)]:
            add('drums',b,bt,44,.12,v-5 if bridge else v,4,1)
        if b%4 in [1,2] and not bridge:
            for bt,k,v in [(2.75,64,30),(3.5,63,35)]:add('drums',b,bt,k,.16,v,4,1)
        if b in [7,15,23,31]:
            for bt,k,v in [(3,60,27),(3.25,61,23),(3.5,64,32)]:add('drums',b,bt,k,.12,v,4,1)

    # Vibe replies occupy gaps in the lead, not every melody note.
    answers={1:[(3,'C#5',.5),(3.5,'E5',.5)],3:[(1,'G4',.5),(3,'B4',.5)],
      6:[(3,'E5',.5),(3.5,'G5',.5)],7:[(0,'D5',.5)],9:[(0,'B4',.5)],
      13:[(3,'Ab4',.5),(3.5,'C5',.5)],15:[(3.5,'D5',.5)],
      17:[(3.5,'D5',.5)],19:[(3.5,'E5',.5)],22:[(3,'A4',.5),(3.5,'C5',.5)],
      23:[(3.5,'D6',.5)],25:[(3,'E5',.5),(3.5,'G5',.5)],27:[(3,'D5',.5),(3.5,'B4',.5)],
      31:[(3.5,'B4',.5)]}
    for b,events in answers.items():
        for i,(bt,p,d) in enumerate(events):add('vibes',b,bt,p,d,62+3*i,16,.95)
    # Signature sparkle only at a few phrase crests (not constant doubling).
    for b,bt,p in [(0,1.5,'A5'),(2,1,'A5'),(8,1.5,'A5'),(12,1,'G5'),(24,1.5,'A5'),(26,1.5,'C6')]:
        add('vibes',b,bt,p,.75,47,11,.9)
    for b,p1,p2 in [(6,'E5','G5'),(13,'Ab4','C5'),(17,'D5','G5'),(22,'A4','C5'),(27,'B4','D5')]:
        for bt,p,d,v in [(3,p1,.5,44),(3.5,p2,.5,41)]:add('flute',b,bt,p,d,v,24,.86)
    return out


def apply_performance(note:Note, shift:float=0.0)->tuple[float,float]:
    start=max(0,(note.beat+shift)*SPB+note.delay_ms/1000)
    end=start+max(.025,note.duration*SPB*note.gate)
    return start,end


def save_midi(notes:list[Note], output:Path, shift:float=0.0)->None:
    mid=mido.MidiFile(ticks_per_beat=TICKS)
    meta=mido.MidiTrack();mid.tracks.append(meta)
    meta.extend([mido.MetaMessage('track_name',name=TITLE),mido.MetaMessage('set_tempo',tempo=mido.bpm2tempo(BPM)),mido.MetaMessage('time_signature',numerator=4,denominator=4)])
    for b,label in [(0,'A - electric piano'),(8,'A variation'),(16,'B - piano answer'),(24,'A return')]:
        pass
    for part,cfg in PARTS.items():
        tr=mido.MidiTrack();mid.tracks.append(tr);ch=cfg['channel']
        tr.append(mido.MetaMessage('track_name',name=cfg['name']))
        tr.append(mido.Message('program_change',channel=ch,program=cfg['program']))
        tr.append(mido.Message('control_change',channel=ch,control=10,value=int(64+cfg['pan']*63)))
        tr.append(mido.Message('control_change',channel=ch,control=91,value=25))
        ev=[]
        for n in notes:
            if n.part!=part:continue
            a,z=apply_performance(n,shift)
            ev.append((round(a/SPB*TICKS),1,n.pitch,n.velocity));ev.append((round(z/SPB*TICKS),0,n.pitch,0))
        previous=0
        for t,on,key,vel in sorted(ev):
            tr.append(mido.Message('note_on' if on else 'note_off',channel=ch,note=key,velocity=vel,time=t-previous));previous=t
        tr.append(mido.MetaMessage('end_of_track'))
    mid.save(output)


class Synth:
    def __init__(self,soundfont:Path,program:int,bank:int):
        libname=ctypes.util.find_library('fluidsynth')
        if not libname:raise RuntimeError('libfluidsynth is required')
        self.l=ct.CDLL(libname);l=self.l;P=ct.c_void_p;I=ct.c_int
        signatures={
          'new_fluid_settings':([],P),'fluid_settings_setnum':([P,ct.c_char_p,ct.c_double],I),
          'fluid_settings_setint':([P,ct.c_char_p,I],I),'new_fluid_synth':([P],P),
          'fluid_synth_sfload':([P,ct.c_char_p,I],I),'fluid_synth_program_select':([P,I,I,I,I],I),
          'fluid_synth_cc':([P,I,I,I],I),'fluid_synth_noteon':([P,I,I,I],I),'fluid_synth_noteoff':([P,I,I],I),
          'fluid_synth_write_float':([P,I,P,I,I,P,I,I],I),
          'delete_fluid_synth':([P],None),'delete_fluid_settings':([P],None)}
        for name,(argtypes,restype) in signatures.items():
            f=getattr(l,name);f.argtypes=argtypes;f.restype=restype
        self.settings=l.new_fluid_settings()
        l.fluid_settings_setnum(self.settings,b'synth.sample-rate',float(SR))
        l.fluid_settings_setnum(self.settings,b'synth.gain',.60)
        l.fluid_settings_setint(self.settings,b'synth.reverb.active',0)
        l.fluid_settings_setint(self.settings,b'synth.chorus.active',0)
        l.fluid_settings_setint(self.settings,b'synth.polyphony',192)
        self.s=l.new_fluid_synth(self.settings)
        sfid=l.fluid_synth_sfload(self.s,str(soundfont).encode(),1)
        if sfid<0:raise RuntimeError('Could not load SoundFont')
        self.ch=9 if bank==128 else 0
        if l.fluid_synth_program_select(self.s,self.ch,sfid,bank,program)!=0:raise RuntimeError(f'Missing bank {bank} preset {program}')
        l.fluid_synth_cc(self.s,self.ch,7,100)
        l.fluid_synth_cc(self.s,self.ch,10,64)
    def render(self,notes:list[Note],seconds:float)->np.ndarray:
        events=[]
        for n in notes:
            a,z=apply_performance(n)
            events.extend([(round(a*SR),1,n.pitch,n.velocity),(round(z*SR),0,n.pitch,0)])
        events.sort();total=round(seconds*SR);pcm=np.zeros((total,2),dtype=np.float32)
        length=2048;lb=np.zeros(length,np.float32);rb=np.zeros(length,np.float32);at=0
        def advance(end):
            nonlocal at
            end=min(end,total)
            while at<end:
                count=min(end-at,length)
                self.l.fluid_synth_write_float(self.s,count,lb.ctypes.data,0,1,rb.ctypes.data,0,1)
                pcm[at:at+count,0]=lb[:count];pcm[at:at+count,1]=rb[:count];at+=count
        for when,on,key,velocity in events:
            if when>total:break
            advance(when)
            if on:self.l.fluid_synth_noteon(self.s,self.ch,key,velocity)
            else:self.l.fluid_synth_noteoff(self.s,self.ch,key)
        advance(total)
        self.l.delete_fluid_synth(self.s);self.l.delete_fluid_settings(self.settings)
        return pcm


def room_ir(length:float=.85)->np.ndarray:
    # Modest stereo room with dark diffuse tail, not audible rhythmic echoes.
    rng=np.random.default_rng(1037)
    n=round(length*SR);ir=np.zeros((n,2),np.float32)
    for ch,early in enumerate([[.017,.031,.047,.071],[.023,.037,.053,.079]]):
        for i,t in enumerate(early):ir[round(t*SR),ch]=[.21,.17,.11,.07][i]
        tail=rng.normal(0,1,n).astype(np.float32)
        tail=sosfilt(butter(2,4600,fs=SR,output='sos'),tail)
        env=np.exp(-np.arange(n)/(SR*.15))
        env[:int(.022*SR)]=0
        ir[:,ch]+=tail*env*.017
        ir[:,ch]=sosfilt(butter(1,180,'highpass',fs=SR,output='sos'),ir[:,ch])
    return ir


def process_stem(raw:np.ndarray,cfg:dict)->np.ndarray:
    mono=raw.mean(axis=1).astype(np.float64)
    mono=sosfilt(butter(2,cfg['hp'],'highpass',fs=SR,output='sos'),mono)
    mono=sosfilt(butter(2,cfg['lp'],fs=SR,output='sos'),mono)
    # Keep sparse instruments sparse: normalize active frames, not full silence.
    size=SR//10;power=np.array([np.mean(mono[i:i+size]**2) for i in range(0,len(mono),size)])
    active=power[power>max(power.max()*0.003,1e-12)]
    rms=math.sqrt(float(active.mean())) if active.size else 1
    gain=10**(cfg['rms_db']/20)/max(rms,1e-9)
    mono*=gain
    # Very gentle instrument bus saturation, no hard clipping.
    mono=np.tanh(mono*1.15)/1.15
    angle=(cfg['pan']+1)*math.pi/4
    dry=np.stack([mono*math.cos(angle),mono*math.sin(angle)],axis=1)
    ir=room_ir();out=dry.copy()
    for ch in [0,1]:out[:,ch]+=cfg['wet']*fftconvolve(mono,ir[:,ch])[:len(mono)]
    return out.astype(np.float32)


def make_shaker(seconds:float,cycles:int=1)->np.ndarray:
    # Original procedural shaker, controlled accents every two bars.
    n=round(seconds*SR);out=np.zeros((n,2),np.float32);rng=np.random.default_rng(61208)
    for cycle in range(cycles):
        for b in range(N_BARS):
            bridge=16<=b<24
            for i in range(8):
                if b in [7,15,23,31] and i==7:continue
                t=(cycle*128+b*4+i*.5)*SPB+.007
                length=round(SR*(.065 if i%2 else .083))
                noise=rng.normal(size=length)
                noise=sosfilt(butter(2,[3600,10500],'bandpass',fs=SR,output='sos'),noise)
                phase=np.linspace(0,1,length);env=np.sin(np.pi*phase)**1.8
                accents=[1.0,.42,.73,.40,.9,.4,.67,.45]
                amp=.016*accents[i]*(.62 if bridge else 1.0)
                wave=(noise*env*amp).astype(np.float32);start=round(t*SR);end=min(n,start+length)
                if end<=start:continue
                pan=.15 if i%2==0 else -.15
                out[start:end,0]+=wave[:end-start]*math.sqrt((1-pan)/2)
                out[start:end,1]+=wave[:end-start]*math.sqrt((1+pan)/2)
    return out


def master(pcm:np.ndarray,target:float=-18.0)->tuple[np.ndarray,dict]:
    meter=pyln.Meter(SR)
    before=float(meter.integrated_loudness(pcm))
    gain=10**((target-before)/20)
    pcm=pcm*gain
    tp=float(np.max(np.abs(resample_poly(pcm,4,1,axis=0))))
    ceiling=10**(-1.5/20)
    if tp>ceiling:pcm*=ceiling/tp
    result=pcm.astype(np.float32)
    return result, {'integrated_lufs':float(meter.integrated_loudness(result)),
      'sample_peak_dbfs':20*math.log10(max(float(np.max(np.abs(result))),1e-12)),
      'estimated_4x_true_peak_dbtp':20*math.log10(max(float(np.max(np.abs(resample_poly(result,4,1,axis=0)))),1e-12)),
      'normalization_gain_db':20*math.log10(gain),'duration_seconds':len(result)/SR}


def lead_xml(out:Path)->None:
    root=ET.Element('score-partwise',version='4.0')
    work=ET.SubElement(root,'work');ET.SubElement(work,'work-title').text='Corner Cafe - Little Leaf'
    ident=ET.SubElement(root,'identification');ET.SubElement(ident,'creator',type='composer').text='Original Little Leaf composition and arrangement study'
    ET.SubElement(ident,'rights').text='Original music; no Restaurant City recording or melody transcription.'
    lst=ET.SubElement(root,'part-list');sp=ET.SubElement(lst,'score-part',id='P1');ET.SubElement(sp,'part-name').text='Theme (concert pitch)'
    si=ET.SubElement(sp,'score-instrument',id='I1');ET.SubElement(si,'instrument-name').text='Electric piano / piano'
    mi=ET.SubElement(sp,'midi-instrument',id='I1');ET.SubElement(mi,'midi-channel').text='1';ET.SubElement(mi,'midi-program').text='5'
    part=ET.SubElement(root,'part',id='P1')
    kinds={'C69':('C','major-sixth','C6/9'),'Cmaj9':('C','major-ninth','Cmaj9'),'A7b9':('A','dominant','A7(b9)'),
      'A7':('A','dominant','A7'),'Dm9':('D','minor-ninth','Dm9'),'G13':('G','dominant-13th','G13'),
      'Em7':('E','minor-seventh','Em7'),'Em9':('E','minor-ninth','Em9'),'Am7':('A','minor-seventh','Am7'),
      'Am9':('A','minor-ninth','Am9'),'E7b9':('E','dominant','E7(b9)'), 'D9':('D','dominant-ninth','D9'),
      'Fmaj9':('F','major-ninth','Fmaj9'),'Fm6':('F','minor-sixth','Fm6'),'C6E':('C','major-sixth','C6/E'),'G13sus':('G','suspended-fourth','G13sus')}
    def add_note(ms,p,d,rest=False):
        note=ET.SubElement(ms,'note')
        if rest:ET.SubElement(note,'rest')
        else:
            pitch=ET.SubElement(note,'pitch');ET.SubElement(pitch,'step').text=p[0]
            if p[1:2] in ['#','b']:ET.SubElement(pitch,'alter').text='1' if p[1]=='#' else '-1'
            ET.SubElement(pitch,'octave').text=p[-1]
        ET.SubElement(note,'duration').text=str(round(d*4))
        types={.25:('16th',False),.5:('eighth',False),.75:('eighth',True),1:('quarter',False),1.5:('quarter',True),2:('half',False),3:('half',True),4:('whole',False)}
        if d in types:
            ty,dotted=types[d];ET.SubElement(note,'type').text=ty
            if dotted:ET.SubElement(note,'dot')
    for b,mel in enumerate(M):
        ms=ET.SubElement(part,'measure',number=str(b+1))
        if b==0:
            att=ET.SubElement(ms,'attributes');ET.SubElement(att,'divisions').text='4'
            key=ET.SubElement(att,'key');ET.SubElement(key,'fifths').text='0'
            tm=ET.SubElement(att,'time');ET.SubElement(tm,'beats').text='4';ET.SubElement(tm,'beat-type').text='4'
            clef=ET.SubElement(att,'clef');ET.SubElement(clef,'sign').text='G';ET.SubElement(clef,'line').text='2'
            di=ET.SubElement(ms,'direction');dt=ET.SubElement(di,'direction-type');words=ET.SubElement(dt,'words');words.text='Light bossa; buoyant, not hurried. Straight eighths.';ET.SubElement(di,'sound',tempo=str(BPM))
        if b in [0,8,16,24]:
            dr=ET.SubElement(ms,'direction');dt=ET.SubElement(dr,'direction-type');ET.SubElement(dt,'rehearsal').text={0:'A',8:"A'",16:'B',24:"A''"}[b]
        for bt,sym in HARM[b]:
            h=ET.SubElement(ms,'harmony');rr=ET.SubElement(h,'root');p,k,display=kinds[sym];ET.SubElement(rr,'root-step').text=p
            ET.SubElement(h,'kind',text=display).text=k
            if sym=='C6E':ba=ET.SubElement(h,'bass');ET.SubElement(ba,'bass-step').text='E'
            if 'b9' in sym:
                de=ET.SubElement(h,'degree');ET.SubElement(de,'degree-value').text='9';ET.SubElement(de,'degree-alter').text='-1';ET.SubElement(de,'degree-type').text='add'
            if bt:ET.SubElement(h,'offset').text=str(round(bt*4))
        cursor=0.
        for bt,p,d in mel:
            if bt>cursor:add_note(ms,'C4',bt-cursor,True)
            add_note(ms,p,d);cursor=bt+d
        if cursor<4:add_note(ms,'C4',4-cursor,True)
        if b==31:
            bl=ET.SubElement(ms,'barline',location='right');ET.SubElement(bl,'bar-style').text='light-light'
    ET.indent(root)
    ET.ElementTree(root).write(out,encoding='utf-8',xml_declaration=True)


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--out',type=Path,default=Path('.'))
    ap.add_argument('--soundfont',type=Path,default=Path('/usr/share/sounds/sf2/TimGM6mb.sf2'))
    args=ap.parse_args();out=args.out.resolve();(out/'stems').mkdir(parents=True,exist_ok=True);(out/'source').mkdir(exist_ok=True)
    if not args.soundfont.is_file():raise FileNotFoundError(args.soundfont)
    if not shutil.which('ffmpeg'):raise RuntimeError('ffmpeg is required for MP3/OGG export')
    notes=composition()
    for n in notes:
        if n.duration<=0 or not 0<=n.pitch<=127 or not 0<n.velocity<=127:raise ValueError(n)
    (out/'source'/'arrangement.json').write_text(json.dumps({'title':TITLE,'bpm':BPM,'meter':'4/4','bars':32,'parts':PARTS,'harmony':HARM,'notes':[asdict(n) for n in notes]},indent=2),encoding='utf-8')
    save_midi(notes,out/'Corner_Cafe_Loop.mid')
    lead_xml(out/'Corner_Cafe_Lead_Sheet.musicxml')
    # Render two full cycles. Extract the second to include natural incoming tails.
    cycle_seconds=128*SPB
    repeated=notes+[Note(n.part,n.beat+128,n.pitch,n.duration,n.velocity,n.delay_ms,n.gate) for n in notes]
    total=cycle_seconds*2+2.0
    mixed=np.zeros((round(total*SR),2),np.float32)
    for name,cfg in PARTS.items():
        print('Rendering',name,flush=True)
        raw=Synth(args.soundfont,cfg['program'],cfg['bank']).render([n for n in repeated if n.part==name],total)
        stem=process_stem(raw,cfg)
        start=round(cycle_seconds*SR);end=round(cycle_seconds*2*SR)
        sf.write(out/'stems'/f'{name}.flac',stem[start:end],SR,subtype='PCM_24')
        mixed+=stem
    shaker=make_shaker(total,cycles=2);mixed+=shaker
    start=round(cycle_seconds*SR);end=round(cycle_seconds*2*SR)
    sf.write(out/'stems'/'shaker.flac',shaker[start:end],SR,subtype='PCM_24')
    loop=mixed[start:end].copy()
    # Resolve last submillisecond DC mismatch only; no phrase crossfade/deletion.
    ramp=min(round(.001*SR),len(loop)//2)
    seam_delta=loop[0]-loop[-1]
    loop[-ramp:]+=np.linspace(0,1,ramp)[:,None]*seam_delta[None,:]
    loop,metrics=master(loop)
    sf.write(out/'Corner_Cafe_Loop.wav',loop,SR,subtype='PCM_24')
    sf.write(out/'Corner_Cafe_Loop.flac',loop,SR,subtype='PCM_24')
    subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-i',str(out/'Corner_Cafe_Loop.wav'),'-c:a','libvorbis','-q:a','6',str(out/'Corner_Cafe_Loop.ogg')],check=True)
    # Listening excerpt: one full cycle + two bars of recognizable return, fade.
    extra=round(8*SPB*SR)
    listen=np.concatenate([loop,loop[:extra]],axis=0)
    listen[:round(.012*SR)]*=np.linspace(0,1,round(.012*SR))[:,None]
    fade=round(2.0*SR);listen[-fade:]*=np.linspace(1,0,fade)[:,None]**1.4
    sf.write(out/'Corner_Cafe_Listen.wav',listen,SR,subtype='PCM_24')
    subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-i',str(out/'Corner_Cafe_Listen.wav'),'-c:a','libmp3lame','-b:a','320k','-metadata','title=Corner Cafe - Little Leaf (V2)','-metadata','artist=Little Leaf - original arrangement study',str(out/'Corner_Cafe_Listen.mp3')],check=True)
    metrics.update({'listen_duration_seconds':len(listen)/SR,'notes':len(notes),'bpm':BPM,'loop_beats':128,'sample_rate':SR,
      'soundfont_file':args.soundfont.name,'soundfont_sha256':hashlib.sha256(args.soundfont.read_bytes()).hexdigest(),
      'loop_first_last_difference':float(np.max(np.abs(loop[0]-loop[-1]))),
      'final_listening_acceptance':'Not established by measurement. User audition required.',
      'reference_audio':'No Restaurant City audio downloaded, transcribed or used in synthesis.'})
    (out/'source'/'render_metrics.json').write_text(json.dumps(metrics,indent=2))
    print(json.dumps(metrics,indent=2),flush=True)

if __name__=='__main__':main()
