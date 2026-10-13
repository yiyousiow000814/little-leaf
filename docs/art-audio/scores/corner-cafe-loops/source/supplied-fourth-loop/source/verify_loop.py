#!/usr/bin/env python3
"""Small offline verification; no game, browser, account or listening claim."""
import argparse
import json
import subprocess
from pathlib import Path
import numpy as np
import soundfile as sf
import mido
from xml.etree import ElementTree as ET

p=argparse.ArgumentParser();p.add_argument('folder',type=Path);args=p.parse_args();root=args.folder
base='Corner_Cafe_Reference_Rearrangement_112bpm_Loop'
n=2268000
x,sr=sf.read(root/(base+'.flac'),dtype='float32',always_2d=True)
assert x.shape==(n,2) and sr==44100 and np.isfinite(x).all() and abs(x).max()<1
for ext in ['wav','ogg']:
    y,ss=sf.read(root/(base+'.'+ext),dtype='float32',always_2d=True)
    assert y.shape==x.shape and ss==sr and np.isfinite(y).all() and abs(y).max()<1
    if ext=='wav':assert np.array_equal(x,y)
stems=sum(sf.read(f,dtype='float32',always_2d=True)[0] for f in sorted((root/'stems').glob('*_loop.flac')))
assert np.max(abs(stems-x))<5e-7
b=subprocess.check_output(['ffmpeg','-v','error','-stream_loop','1','-i',str(root/(base+'.ogg')),'-f','f32le','-'])
y=np.frombuffer(b,dtype='<f4').reshape(-1,2)
assert len(y)==2*n and np.array_equal(y[:n],y[n:])
assert len(mido.MidiFile(root/(base+'.mid')).tracks)==5
xml=ET.parse(root/'Lead_Sheet_Loop.musicxml')
measures=xml.findall('.//part/measure');assert len(measures)==24
for bar in measures:assert sum(int(e.findtext('duration')) for e in bar.findall('note'))==16
assert measures[0].find('barline/repeat').get('direction')=='forward'
assert measures[-1].find('barline/repeat').get('direction')=='backward'
print(json.dumps({'status':'PASS technical only','sample_rate':sr,'samples':n,'period_seconds':n/sr,'two_ogg_cycles_identical':True,'stems_sum_within_24bit_quantization':True,'notation_bars':len(measures)},indent=2))
