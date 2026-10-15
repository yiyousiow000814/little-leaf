"""Bounded A/B from the supplied original Corner Cafe V2; no reference audio used.
Run with --source original_create_corner_cafe.py --out output_directory.
The A control is a re-render, not the original mastered MP3.
"""
from pathlib import Path
import importlib.util,sys,json,argparse,math,subprocess,hashlib,copy
from dataclasses import asdict
import numpy as np
import soundfile as sf
from scipy.signal import resample_poly

p=argparse.ArgumentParser()
p.add_argument('--source',type=Path,required=True)
p.add_argument('--out',type=Path,required=True)
p.add_argument('--soundfont',type=Path,default=Path('/usr/share/sounds/sf2/TimGM6mb.sf2'))
a=p.parse_args(); a.out.mkdir(parents=True,exist_ok=True)
spec=importlib.util.spec_from_file_location('corner_original',a.source)
v=importlib.util.module_from_spec(spec);sys.modules[spec.name]=v;spec.loader.exec_module(v)
N=v.Note
notes=[n for n in v.composition() if n.beat<32]
# Identical written tonic ending to avoid judging an abruptly cut turnaround.
ending=[N('rhodes',32,v.midi_pitch('C5'),1.5,71,5,.92),N('bass',32,v.midi_pitch('C3'),1.5,71,-4,.88)]
for j,s in enumerate(['E3','G3','A3','C4']):ending.append(N('guitar',32,v.midi_pitch(s),1.5,49,7+j*5.4,.92))
control=notes+ending

# Preserve the core E-G-A contour, original tempo, 8-bar form and primary timbres.
mel=[]
for n in notes:
 if n.part!='rhodes':continue
 b=int(n.beat//4)
 # Non-dominant vi harmony uses C natural, not C-sharp.
 pitch=n.pitch-1 if n.pitch==v.midi_pitch('C#5') and b in [1,4] else n.pitch
 # Omit auxiliary double-stop embellishment; retain the actual theme.
 if n.velocity<55:continue
 mel.append(N('rhodes',n.beat,pitch,n.duration,n.velocity,n.delay_ms,n.gate))

harm=[[(0,'C6')],[(0,'Am7')],[(0,'Dm7')],[(0,'G7')],[(0,'Em7'),(2,'Am7')],[(0,'Dm7'),(2,'G7')],[(0,'Cmaj7'),(2,'Am7')],[(0,'Dm7'),(2,'G7')]]
voices={'C6':['E3','G3','A3','C4'],'Am7':['E3','G3','A3','C4'],'Dm7':['F3','A3','C4','D4'],'G7':['F3','G3','B3','D4'],'Em7':['G3','B3','D4','E4'],'Cmaj7':['E3','G3','B3','C4']}
def hs(b,t):return next(s for at,s in reversed(harm[b]) if at<=t+1e-8)
new=mel[:]
# Fixed two-bar comping cell; move chord changes to their true beat.
for b in range(8):
 pts=[(.0,.8,55),(1.5,.48,46),(2.5,.72,52)] if b%2==0 else [(.5,.72,51),(2,.9,54)]
 if len(harm[b])==2:pts=[(.5,.8,51),(2,.9,54)]
 for t,d,vel in pts:
  vv=voices[hs(b,t)]
  for j,s in enumerate(vv):new.append(N('guitar',b*4+t,v.midi_pitch(s),d,vel+(1 if j==3 else -1),7+j*5.4,.9))
 # Restrained drum bed, same GM drum bank; no extra kick/hat/bongo fills.
 for t,pitch,vel,d in [(0,36,30,.12),(1,38,25,.22),(2,36,25,.12),(3,37,28,.11)]:
  new.append(N('drums',b*4+t,pitch,d,vel,10 if pitch!=36 else 0,1.0))
# Hand-selected, diatonic connecting notes; not a next-root +/- constant rule.
bass=[[(0,'C3',1.3,78),(2,'G2',1.0,68),(3.5,'B2',.38,57)],
 [(0,'A2',1.4,76),(2,'E3',.8,66),(3,'B2',.4,54),(3.5,'C3',.38,58)],
 [(0,'D3',1.3,76),(2,'A2',1.0,68),(3.5,'F2',.38,55)],
 [(0,'G2',1.4,75),(2,'D3',1.0,66),(3.5,'D3',.38,56)],
 [(0,'E3',1.4,76),(2,'A2',1.05,70),(3.5,'C3',.38,55)],
 [(0,'D3',1.4,76),(2,'G2',1.05,70),(3.5,'B2',.38,55)],
 [(0,'C3',1.4,76),(2,'A2',1.05,70),(3.5,'C3',.38,55)],
 [(0,'D3',1.4,76),(2,'G2',1.0,69),(3.5,'B2',.38,57)]]
for b,nn in enumerate(bass):
 for t,s,d,vel in nn:new.append(N('bass',b*4+t,v.midi_pitch(s),d,vel,-4 if t%1==0 else 2,.86))
revised=new+ending
for name,nn in [('A_V2_control',control),('B_reduced_harmony',revised)]:
 assert all(0<=x.pitch<=127 and x.duration>0 and 0<x.velocity<128 for x in nn)
 (a.out/f'{name}.json').write_text(json.dumps({'bpm':v.BPM,'duration_beats':34,'notes':[asdict(x) for x in nn]},indent=2))
 v.save_midi(nn,a.out/f'{name}.mid')

# Shared calibration per instrument, derived from the control; do not boost sparse B layers.
seconds=34*v.SPB+1.8
rawA={}; processedA={};stemgains={}
for name,cfg in v.PARTS.items():
 nn=[n for n in control if n.part==name]
 if not nn:continue
 print('Render A',name,flush=True)
 raw=v.Synth(a.soundfont,cfg['program'],cfg['bank']).render(nn,seconds)
 rawA[name]=raw
 processedA[name]=v.process_stem(raw,cfg)
# To preserve the same calibrated gain, obtain it directly from control filtered mono.
from scipy.signal import butter,sosfilt,fftconvolve
for name,raw in rawA.items():
 cfg=v.PARTS[name]; mono=sosfilt(butter(2,cfg['hp'],'highpass',fs=v.SR,output='sos'),raw.mean(axis=1).astype(np.float64))
 mono=sosfilt(butter(2,cfg['lp'],fs=v.SR,output='sos'),mono)
 block=v.SR//10;pw=np.array([np.mean(mono[i:i+block]**2) for i in range(0,len(mono),block)])
 ac=pw[pw>max(pw.max()*.003,1e-12)];rms=math.sqrt(float(ac.mean())) if ac.size else 1
 stemgains[name]=10**(cfg['rms_db']/20)/max(rms,1e-9)
def process_fixed(raw,name):
 cfg=v.PARTS[name];mono=sosfilt(butter(2,cfg['hp'],'highpass',fs=v.SR,output='sos'),raw.mean(axis=1).astype(np.float64))
 mono=sosfilt(butter(2,cfg['lp'],fs=v.SR,output='sos'),mono)*stemgains[name]
 mono=np.tanh(mono*1.15)/1.15;theta=(cfg['pan']+1)*math.pi/4
 out=np.stack([mono*math.cos(theta),mono*math.sin(theta)],axis=1)
 ir=v.room_ir()
 for c in [0,1]:out[:,c]+=cfg['wet']*fftconvolve(mono,ir[:,c])[:len(mono)]
 return out.astype(np.float32)
A=sum(processedA.values())
sh=v.make_shaker(seconds);sh[round(32*v.SPB*v.SR):]=0;A+=sh
B=np.zeros_like(A)
for name in ['rhodes','guitar','bass','drums']:
 cfg=v.PARTS[name]; print('Render B',name,flush=True)
 rr=v.Synth(a.soundfont,cfg['program'],cfg['bank']).render([n for n in revised if n.part==name],seconds)
 B+=process_fixed(rr,name)
metrics={}
for name,pcm in [('A_V2_control',A),('B_reduced_harmony',B)]:
 fade=round(.25*v.SR);pcm[-fade:]*=np.linspace(1,0,fade)[:,None]
 master,mt=v.master(pcm,-18.0);assert np.isfinite(master).all()
 sf.write(a.out/f'{name}.wav',master,v.SR,subtype='PCM_24')
 subprocess.run(['ffmpeg','-y','-hide_banner','-loglevel','error','-i',str(a.out/f'{name}.wav'),'-c:a','libmp3lame','-b:a','320k',str(a.out/f'{name}.mp3')],check=True)
 metrics[name]=mt
# Sequential comparison with an explicitly silent 1 sec separator, A then B.
pa,_=sf.read(a.out/'A_V2_control.wav');pb,_=sf.read(a.out/'B_reduced_harmony.wav')
sf.write(a.out/'AB_comparison.wav',np.vstack([pa,np.zeros((v.SR,2)),pb]),v.SR,subtype='PCM_24')
subprocess.run(['ffmpeg','-y','-hide_banner','-loglevel','error','-i',str(a.out/'AB_comparison.wav'),'-c:a','libmp3lame','-b:a','320k',str(a.out/'AB_comparison.mp3')],check=True)
(a.out/'source'/'metrics.json').write_text(json.dumps({'audio':metrics,'soundfont_sha256':hashlib.sha256(a.soundfont.read_bytes()).hexdigest(),'reference_audio_used':False,'A_definition':'First 8 bars of V2 rerendered plus shared 2-beat ending','B_definition':'Reduced harmonic/arrangement study, same tempo and primary instruments; not RC reference analysis','secondary_audio_notation':'MIDI plus JSON event ledger; no original soundtrack transcription'},indent=2))
print(json.dumps(metrics,indent=2))
