"""Deterministic, locally synthesised percussion; copied from the source studies."""

import numpy as np

from scipy.signal import butter, sosfilt

SR=44100



def frame_drum(notes,seconds):
    out=np.zeros(round(seconds*SR),np.float64)
    # Seed is physical noise texture only, not random note placement.
    rng=np.random.default_rng(48022)
    for n in notes:
        dur=.38 if n['tone']=='bass' else .15;t=np.arange(round(dur*SR))/SR
        if n['tone']=='bass':
            phase=2*np.pi*(82*t+5*.026*(1-np.exp(-t/.026)))
            sig=(np.sin(phase)+.29*np.sin(1.51*phase+.3)+.13*np.sin(2.2*phase+.5))*np.exp(-t/.115)
            noise=sosfilt(butter(2,1700,fs=SR,output='sos'),rng.standard_normal(len(t)))
            sig+=.16*noise*np.exp(-t/.026)
        else:
            noise=sosfilt(butter(2,[180,2100],btype='bandpass',fs=SR,output='sos'),rng.standard_normal(len(t)))
            sig=.72*noise*np.exp(-t/.026)+.23*np.sin(2*np.pi*220*t)*np.exp(-t/.040)
        sig*=np.minimum(1,t/.0025)*(n['velocity']/127)**1.5
        pos=round(n['start_seconds']*SR);end=min(len(out),pos+len(sig));out[pos:end]+=sig[:end-pos]
    return np.column_stack([out,out]).astype(np.float32)

def percussion(notes,seconds):
    out=np.zeros(round(seconds*SR),np.float64)
    rng=np.random.default_rng(126077)
    for n in notes:
        kind=n['tone'];dur=.20 if kind=='shake' else .12
        t=np.arange(round(dur*SR))/SR
        if kind=='shake':
            noise=sosfilt(butter(2,[1200,6000],btype='bandpass',fs=SR,output='sos'),rng.standard_normal(len(t)))
            # A rounded friction gesture, no sharp all-band click.
            env=(1-np.exp(-t/.015))*np.exp(-t/.036)
            sound=.9*noise*env
        else:
            noise=sosfilt(butter(2,[360,3100],btype='bandpass',fs=SR,output='sos'),rng.standard_normal(len(t)))
            sound=(.28*np.sin(2*np.pi*430*t)+.12*np.sin(2*np.pi*690*t)+.35*noise)*np.exp(-t/.024)
            sound*=np.minimum(1,t/.003)
        sound*=(n['velocity']/100)**1.35
        a=round(n['start_seconds']*SR);b=min(a+len(sound),len(out))
        out[a:b]+=sound[:b-a]
    return np.column_stack([out,out]).astype(np.float32)
