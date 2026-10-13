"""Local FluidSynth renderer / room processing reused from the Cloverlight study.
SoundFont binaries are not distributed. These routines do not load references.
"""
from __future__ import annotations
import ctypes as ct
import ctypes.util
import numpy as np
from scipy.signal import butter, sosfilt, fftconvolve
SR=44100

class Fluid:
    def __init__(self,bank,program):
        name=ctypes.util.find_library('fluidsynth')
        if not name:raise RuntimeError('libfluidsynth is required')
        self.lib=ct.CDLL(name);l=self.lib;P=ct.c_void_p;I=ct.c_int
        spec={
          'new_fluid_settings':([],P),'fluid_settings_setnum':([P,ct.c_char_p,ct.c_double],I),
          'fluid_settings_setint':([P,ct.c_char_p,I],I),'new_fluid_synth':([P],P),
          'fluid_synth_sfload':([P,ct.c_char_p,I],I),'fluid_synth_program_select':([P,I,I,I,I],I),
          'fluid_synth_cc':([P,I,I,I],I),'fluid_synth_noteon':([P,I,I,I],I),'fluid_synth_noteoff':([P,I,I],I),
          'fluid_synth_pitch_bend':([P,I,I],I),'fluid_synth_pitch_wheel_sens':([P,I,I],I),
          'fluid_synth_write_float':([P,I,P,I,I,P,I,I],I),
          'delete_fluid_synth':([P],None),'delete_fluid_settings':([P],None)}
        for k,(a,r) in spec.items():getattr(l,k).argtypes=a;getattr(l,k).restype=r
        self.settings=l.new_fluid_settings()
        l.fluid_settings_setnum(self.settings,b'synth.sample-rate',float(SR))
        l.fluid_settings_setnum(self.settings,b'synth.gain',.6)
        l.fluid_settings_setint(self.settings,b'synth.reverb.active',0)
        l.fluid_settings_setint(self.settings,b'synth.chorus.active',0)
        l.fluid_settings_setint(self.settings,b'synth.polyphony',96)
        self.synth=l.new_fluid_synth(self.settings)
        sid=l.fluid_synth_sfload(self.synth,str(bank).encode(),1)
        if sid<0:raise RuntimeError('SoundFont load failed')
        l.fluid_synth_program_select(self.synth,0,sid,0,program)
        l.fluid_synth_cc(self.synth,0,7,100);l.fluid_synth_cc(self.synth,0,10,64)
        l.fluid_synth_pitch_wheel_sens(self.synth,0,2)
    def close(self):
        if self.synth:self.lib.delete_fluid_synth(self.synth);self.synth=None
        if self.settings:self.lib.delete_fluid_settings(self.settings);self.settings=None
    def render(self,notes,seconds,controls):
        out=np.zeros((round(seconds*SR),2),np.float32);ev=[]
        for n in notes:
            ev += [(round(n['start_seconds']*SR),2,'on',n['pitch'],n['velocity']),
                   (round(n['end_seconds']*SR),0,'off',n['pitch'],0)]
        for c in controls:
            ev.append((round(c['time']*SR),1,c['type'],c['value'],0))
        ev.sort();pos=0;buf=np.zeros((2048,2),np.float32)
        def advance(end):
            nonlocal pos
            while pos<min(end,len(out)):
                count=min(2048,end-pos,len(out)-pos)
                self.lib.fluid_synth_write_float(self.synth,count,buf.ctypes.data,0,2,buf.ctypes.data,1,2)
                out[pos:pos+count]=buf[:count];pos+=count
        try:
            for t,_,kind,x,y in ev:
                if t>len(out):break
                advance(t)
                if kind=='on':self.lib.fluid_synth_noteon(self.synth,0,x,y)
                elif kind=='off':self.lib.fluid_synth_noteoff(self.synth,0,x)
                elif kind=='expression':self.lib.fluid_synth_cc(self.synth,0,11,x)
                elif kind=='bend':self.lib.fluid_synth_pitch_bend(self.synth,0,x)
            advance(len(out))
        finally:self.close()
        return out

def room_ir():
    rng=np.random.default_rng(99173);dur=1.3;n=round(dur*SR);t=np.arange(n)/SR
    ir=np.zeros((n,2))
    for ch,delays in enumerate([[.019,.039,.061,.086],[.027,.047,.070,.093]]):
        for delay,amp in zip(delays,[.34,.22,.16,.11]):ir[round(delay*SR),ch]+=amp
        noise=sosfilt(butter(2,3900,fs=SR,output='sos'),rng.standard_normal(n))
        env=np.exp(-t/.23)*(t>.035)
        ir[:,ch]+=noise*env*.012
        ir[:,ch]=sosfilt(butter(1,180,btype='highpass',fs=SR,output='sos'),ir[:,ch])
    return ir

def process(raw,cfg,ir,gain=1.):
    mono=raw.mean(axis=1).astype(np.float64)
    mono=sosfilt(butter(2,cfg['hp'],'highpass',fs=SR,output='sos'),mono)
    mono=sosfilt(butter(2,cfg['lp'],fs=SR,output='sos'),mono)
    pan=cfg['pan'];theta=(pan+1)*np.pi/4
    y=mono[:,None]*np.array([np.cos(theta),np.sin(theta)])[None,:]
    for ch in (0,1):y[:,ch]+=fftconvolve(mono,ir[:,ch])[:len(mono)]*cfg['wet']
    return y*gain
