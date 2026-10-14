#!/usr/bin/env python3
"""Synthesis and room helpers reused from the supplied Little Leaf loop source.
No CLI, installation, networking or account access.
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
