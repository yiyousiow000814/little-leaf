#!/usr/bin/env python3
"""Preserved synthesis, voicing and engraving helpers from the approved closed mix.
Imported by build_loop.py. No CLI, installation or network operations.
"""
from __future__ import annotations
import argparse
import ctypes as ct
import ctypes.util
import hashlib
import json
import math
import platform
import shutil
import subprocess
from pathlib import Path
from xml.etree import ElementTree as ET
import mido
import numpy as np
import soundfile as sf
import pyloudnorm as pyln
from scipy.signal import butter, sosfilt, fftconvolve, resample_poly

SR=44100
TPQ=960
PARTS={
 'rhodes':dict(name='Electric piano - theme', program=4, bank=0, channel=0, pan=-.08, rms_db=-23.8, hp=130, lp=7200, wet=.095),
 'guitar':dict(name='Nylon guitar - light comping', program=24, bank=0, channel=1, pan=-.30, rms_db=-28.5, hp=160, lp=6400, wet=.065),
 'bass':dict(name='Upright bass - two feel', program=32, bank=0, channel=2, pan=0., rms_db=-25.2, hp=44, lp=3000, wet=.012),
 'drums':dict(name='Brush kit - restrained pulse', program=40, bank=128, channel=9, pan=0., rms_db=-31.4, hp=65, lp=7800, wet=.027),
}

def performance(n:dict,bpm:float)->tuple[float,float]:
    start=max(0.,n['beat']*60/bpm+n.get('delay_ms',0)/1000)
    return start,start+max(.025,n['duration']*60/bpm*n.get('gate',1))

class Synth:
    def __init__(self,bank:Path,cfg:dict):
        name=ctypes.util.find_library('fluidsynth')
        if not name: raise RuntimeError('Install libfluidsynth before rendering.')
        self.lib=ct.CDLL(name);l=self.lib;P=ct.c_void_p;I=ct.c_int
        signatures={
          'new_fluid_settings':([],P),'fluid_settings_setnum':([P,ct.c_char_p,ct.c_double],I),
          'fluid_settings_setint':([P,ct.c_char_p,I],I),'new_fluid_synth':([P],P),
          'fluid_synth_sfload':([P,ct.c_char_p,I],I),'fluid_synth_program_select':([P,I,I,I,I],I),
          'fluid_synth_cc':([P,I,I,I],I),'fluid_synth_noteon':([P,I,I,I],I),'fluid_synth_noteoff':([P,I,I],I),
          'fluid_synth_write_float':([P,I,P,I,I,P,I,I],I),
          'delete_fluid_synth':([P],None),'delete_fluid_settings':([P],None)}
        for k,(a,r) in signatures.items():
            getattr(l,k).argtypes=a;getattr(l,k).restype=r
        self.settings=l.new_fluid_settings()
        if not self.settings: raise RuntimeError('FluidSynth settings allocation failed')
        l.fluid_settings_setnum(self.settings,b'synth.sample-rate',float(SR))
        l.fluid_settings_setnum(self.settings,b'synth.gain',.60)
        l.fluid_settings_setint(self.settings,b'synth.reverb.active',0)
        l.fluid_settings_setint(self.settings,b'synth.chorus.active',0)
        l.fluid_settings_setint(self.settings,b'synth.polyphony',192)
        l.fluid_settings_setint(self.settings,b'synth.cpu-cores',1)
        self.synth=l.new_fluid_synth(self.settings)
        if not self.synth: raise RuntimeError('FluidSynth allocation failed')
        sfid=l.fluid_synth_sfload(self.synth,str(bank).encode(),1)
        if sfid<0: self.close();raise RuntimeError('Could not load SoundFont')
        self.ch=9 if cfg['bank']==128 else 0
        ok=l.fluid_synth_program_select(self.synth,self.ch,sfid,cfg['bank'],cfg['program'])
        if ok: self.close();raise RuntimeError('Requested SoundFont preset is absent')
        l.fluid_synth_cc(self.synth,self.ch,7,100)
        l.fluid_synth_cc(self.synth,self.ch,10,64)
    def close(self):
        if getattr(self,'synth',None):self.lib.delete_fluid_synth(self.synth);self.synth=None
        if getattr(self,'settings',None):self.lib.delete_fluid_settings(self.settings);self.settings=None
    def render(self,notes:list[dict],seconds:float,bpm:float)->np.ndarray:
        events=[]
        for n in notes:
            a,z=performance(n,bpm)
            events.extend([(round(a*SR),1,n['pitch'],n['velocity']),(round(z*SR),0,n['pitch'],0)])
        events.sort();total=round(seconds*SR);pcm=np.zeros((total,2),np.float32)
        left=np.zeros(2048,np.float32);right=np.zeros(2048,np.float32);at=0
        def advance(end):
            nonlocal at
            while at<min(end,total):
                count=min(min(end,total)-at,len(left))
                if self.lib.fluid_synth_write_float(self.synth,count,left.ctypes.data,0,1,right.ctypes.data,0,1):
                    raise RuntimeError('FluidSynth render error')
                pcm[at:at+count,0]=left[:count];pcm[at:at+count,1]=right[:count];at+=count
        try:
            for when,on,key,vel in events:
                if when>total:break
                advance(when)
                if on:self.lib.fluid_synth_noteon(self.synth,self.ch,key,vel)
                else:self.lib.fluid_synth_noteoff(self.synth,self.ch,key)
            advance(total)
            return pcm
        finally:self.close()

def room_ir()->np.ndarray:
    # Reproducible room-noise seed is acoustics, not random musical humanization.
    rng=np.random.default_rng(1037);n=round(.85*SR);ir=np.zeros((n,2),np.float32)
    for ch,early in enumerate([[.017,.031,.047,.071],[.023,.037,.053,.079]]):
        for i,t in enumerate(early):ir[round(t*SR),ch]=[.21,.17,.11,.07][i]
        noise=sosfilt(butter(2,4600,fs=SR,output='sos'),rng.normal(size=n))
        env=np.exp(-np.arange(n)/(SR*.15));env[:round(.022*SR)]=0
        ir[:,ch]+=noise*env*.017
        ir[:,ch]=sosfilt(butter(1,180,'highpass',fs=SR,output='sos'),ir[:,ch])
    return ir

def process(raw:np.ndarray,cfg:dict,calibration_seconds:float)->tuple[np.ndarray,float]:
    mono=raw.mean(axis=1).astype(np.float64)
    mono=sosfilt(butter(2,cfg['hp'],'highpass',fs=SR,output='sos'),mono)
    mono=sosfilt(butter(2,cfg['lp'],fs=SR,output='sos'),mono)
    # Calibrate from the preserved first eight bars, not from middle-section silence.
    segment=mono[:round(calibration_seconds*SR)];block=SR//10
    powers=np.array([np.mean(segment[i:i+block]**2) for i in range(0,len(segment),block)])
    active=powers[powers>max(powers.max()*.003,1e-12)]
    rms=math.sqrt(float(active.mean())) if active.size else 1.
    gain=10**(cfg['rms_db']/20)/max(rms,1e-9)
    mono=np.tanh(mono*gain*1.15)/1.15
    theta=(cfg['pan']+1)*math.pi/4
    result=np.stack([mono*math.cos(theta),mono*math.sin(theta)],axis=1)
    ir=room_ir()
    for ch in [0,1]:result[:,ch]+=cfg['wet']*fftconvolve(mono,ir[:,ch])[:len(mono)]
    return result.astype(np.float32),gain

def write_midi(score:dict,path:Path)->None:
    bpm=score['bpm'];mid=mido.MidiFile(type=1,ticks_per_beat=TPQ)
    meta=mido.MidiTrack();mid.tracks.append(meta)
    meta.extend([mido.MetaMessage('track_name',name=score['title']),
      mido.MetaMessage('set_tempo',tempo=mido.bpm2tempo(bpm)),
      mido.MetaMessage('time_signature',numerator=4,denominator=4),
      mido.MetaMessage('key_signature',key='C')])
    for part,cfg in PARTS.items():
        tr=mido.MidiTrack();mid.tracks.append(tr);ch=cfg['channel']
        tr.append(mido.MetaMessage('track_name',name=cfg['name']))
        tr.append(mido.Message('program_change',channel=ch,program=cfg['program']))
        tr.append(mido.Message('control_change',channel=ch,control=10,value=round(64+63*cfg['pan'])))
        tr.append(mido.Message('control_change',channel=ch,control=91,value=0))
        events=[]
        for n in score['notes']:
            if n['part']!=part:continue
            a,z=performance(n,bpm)
            events.extend([(round(a*bpm/60*TPQ),1,n['pitch'],n['velocity']),
                           (round(z*bpm/60*TPQ),0,n['pitch'],0)])
        last=0
        for t,on,pitch,velocity in sorted(events):
            tr.append(mido.Message('note_on' if on else 'note_off',channel=ch,note=pitch,velocity=velocity,time=t-last));last=t
        tr.append(mido.MetaMessage('end_of_track',time=max(0,96*TPQ-last)))
    mid.save(path)

def write_lead_sheet(score:dict,path:Path)->None:
    root=ET.Element('score-partwise',version='4.0')
    work=ET.SubElement(root,'work');ET.SubElement(work,'work-title').text=score['title']
    ident=ET.SubElement(root,'identification')
    ET.SubElement(ident,'creator',type='composer').text='Little Leaf original theme; Harmony Study rearrangement'
    ET.SubElement(ident,'rights').text='Original Little Leaf theme. Approved parent mix; loop ending is a new revision for review.'
    lst=ET.SubElement(root,'part-list');sp=ET.SubElement(lst,'score-part',id='P1')
    ET.SubElement(sp,'part-name').text='Electric piano theme (lead sheet)'
    inst=ET.SubElement(sp,'score-instrument',id='I1');ET.SubElement(inst,'instrument-name').text='Electric piano'
    mi=ET.SubElement(sp,'midi-instrument',id='I1');ET.SubElement(mi,'midi-channel').text='1';ET.SubElement(mi,'midi-program').text='5'
    part=ET.SubElement(root,'part',id='P1');div=4
    kinds={'C6':('C','major-sixth'),'Cmaj7':('C','major-seventh'),'F6':('F','major-sixth'),
           'Fmaj7':('F','major-seventh'),'Dm7':('D','minor-seventh'),'Em7':('E','minor-seventh'),
           'Am7':('A','minor-seventh'),'G7':('G','dominant')}
    names={0:('C',0),1:('C',1),2:('D',0),3:('E',-1),4:('E',0),5:('F',0),6:('F',1),7:('G',0),8:('A',-1),9:('A',0),10:('B',-1),11:('B',0)}
    types={1:('16th',False),2:('eighth',False),3:('eighth',True),4:('quarter',False),6:('quarter',True),8:('half',False),12:('half',True),16:('whole',False)}
    def event(ms,pitch,duration,velocity=None):
        ticks=round(duration*div)
        if ticks<=0:return
        n=ET.SubElement(ms,'note')
        if pitch is None:ET.SubElement(n,'rest')
        else:
            nn=ET.SubElement(n,'pitch');step,alter=names[pitch%12]
            ET.SubElement(nn,'step').text=step
            if alter:ET.SubElement(nn,'alter').text=str(alter)
            ET.SubElement(nn,'octave').text=str(pitch//12-1)
        ET.SubElement(n,'duration').text=str(ticks)
        if ticks in types:
            ty,dot=types[ticks];ET.SubElement(n,'type').text=ty
            if dot:ET.SubElement(n,'dot')
    for b in range(score['bars']):
        ms=ET.SubElement(part,'measure',number=str(b+1))
        if b==0:
            att=ET.SubElement(ms,'attributes');ET.SubElement(att,'divisions').text=str(div)
            key=ET.SubElement(att,'key');ET.SubElement(key,'fifths').text='0'
            tm=ET.SubElement(att,'time');ET.SubElement(tm,'beats').text='4';ET.SubElement(tm,'beat-type').text='4'
            clef=ET.SubElement(att,'clef');ET.SubElement(clef,'sign').text='G';ET.SubElement(clef,'line').text='2'
            d=ET.SubElement(ms,'direction');dt=ET.SubElement(d,'direction-type');mt=ET.SubElement(dt,'metronome')
            ET.SubElement(mt,'beat-unit').text='quarter';ET.SubElement(mt,'per-minute').text=str(score['bpm'])
            ET.SubElement(d,'sound',tempo=str(score['bpm']))
            d=ET.SubElement(ms,'direction');dt=ET.SubElement(d,'direction-type')
            ET.SubElement(dt,'words').text='Light, rounded tone. Keep the recurring groove; do not rush the short notes.'
        if b in [0,8,16]:
            d=ET.SubElement(ms,'direction');dt=ET.SubElement(d,'direction-type')
            ET.SubElement(dt,'rehearsal').text={0:'A - preserved',8:'B - answer',16:'A return'}[b]
        for onset,symbol in score['harmony'][b]:
            h=ET.SubElement(ms,'harmony');r=ET.SubElement(h,'root')
            rt,kind=kinds[symbol];ET.SubElement(r,'root-step').text=rt
            ET.SubElement(h,'kind',text=symbol).text=kind
            if onset:ET.SubElement(h,'offset').text=str(round(onset*div))
        notes=sorted([n for n in score['notes'] if n['part']=='rhodes' and b*4<=n['beat']<(b+1)*4],key=lambda n:n['beat'])
        cursor=0.
        for n in notes:
            onset=n['beat']-b*4
            if onset>cursor:event(ms,None,onset-cursor)
            assert onset>=cursor-1e-8
            event(ms,n['pitch'],n['duration'],n['velocity']);cursor=onset+n['duration']
        if cursor<4:event(ms,None,4-cursor)
        assert sum(int(n.findtext('duration')) for n in ms.findall('note'))==16
        if b==score['bars']-1:
            bl=ET.SubElement(ms,'barline',location='right');ET.SubElement(bl,'bar-style').text='light-heavy'
    ET.indent(root)
    ET.ElementTree(root).write(path,encoding='utf-8',xml_declaration=True)

