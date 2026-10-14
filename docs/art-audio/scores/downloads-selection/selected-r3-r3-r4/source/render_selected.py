#!/usr/bin/env python3
"""Re-render the selected three prior tracks and newly composed fourth track from their frozen ledgers. No network/API/game writes.

python source/render_selected.py --package . --out /tmp/ll-r4-new --soundfont /path/TimGM6mb.sf2

For the new fourth composition only, --calibrate-new fixes one master gain from
an initial render. It does not compress, time-stretch or normalise old tracks.
All supplied ledgers already contain the final gains; ordinary rebuilding needs
no calibration. Sources / sound bank notices are supplied, not font or SF2 bytes.
"""
from __future__ import annotations
import argparse,hashlib,json,shutil,subprocess
from pathlib import Path
import numpy as np
import soundfile as sf
from scipy.signal import lfilter,butter,sosfilt,resample_poly
import pyloudnorm as pyln
from audio_engine import Fluid,process,room_ir,SR
from percussion import frame_drum,percussion
from score_export import export_midi,export_score
BANK_SHA='c5378b62028c920cb11e4803327983fee2f2cdff5dc89c708e39da417e51c854'

def high_shelf(data,fc,db):
    A=10**(db/40);w=2*np.pi*fc/SR;c=np.cos(w);s=np.sin(w)
    alpha=s/2*np.sqrt(2);k=2*np.sqrt(A)*alpha
    b=A*np.array([(A+1)+(A-1)*c+k,-2*((A-1)+(A+1)*c),(A+1)+(A-1)*c-k])
    a=np.array([(A+1)-(A-1)*c+k,2*((A-1)-(A+1)*c),(A+1)-(A-1)*c-k])
    return lfilter(b/a[0],a/a[0],data,axis=0)

def brushes(notes,seconds):
    out=np.zeros(round(seconds*SR),np.float64);rng=np.random.default_rng(84421)
    for n in notes:
        kind=n['tone'];dur=.24 if kind=='kick' else .19;t=np.arange(round(dur*SR))/SR
        if kind=='kick':
            phase=2*np.pi*(63*t+1.8*.035*(1-np.exp(-t/.035)))
            wave=(np.sin(phase)+.15*np.sin(phase*1.7))*np.exp(-t/.075)*np.minimum(1,t/.003)
        elif kind=='hat':
            noise=sosfilt(butter(2,[3600,10800],btype='bandpass',fs=SR,output='sos'),rng.standard_normal(len(t)))
            wave=noise*(1-np.exp(-t/.0015))*np.exp(-t/.021)*.26
        else:
            noise=sosfilt(butter(2,[380,6500],btype='bandpass',fs=SR,output='sos'),rng.standard_normal(len(t)))
            wave=noise*(1-np.exp(-t/.004))*np.exp(-t/.035)
        wave*=(n['velocity']/100)**1.45
        a=round(n['start_seconds']*SR);b=min(a+len(wave),len(out))
        out[a:b]+=wave[:b-a]
    return np.column_stack((out,out)).astype(np.float32)

def render(path:Path,out:Path,bank:Path,calibrate=False):
    d=json.loads(path.read_text(encoding='utf-8'));folder=out/path.parent.name
    folder.mkdir(parents=True,exist_ok=False);(folder/'stems').mkdir()
    ir=room_ir();raws={};stems={}
    for part,cfg in d['parts'].items():
        notes=[n for n in d['notes'] if n['part']==part]
        if part=='frame_drum':raw=frame_drum(notes,d['duration_seconds'])
        elif part=='percussion':raw=percussion(notes,d['duration_seconds'])
        elif part=='brushes':raw=brushes(notes,d['duration_seconds'])
        else:raw=Fluid(bank,cfg['program']).render(notes,d['duration_seconds'],d['continuous_controls'].get(part,[]))
        raws[part]=raw
        x=process(raw,cfg,ir,d['part_gains'][part])*d['master_gain']
        if part in d['high_shelf_settings']:x=high_shelf(x,*d['high_shelf_settings'][part])
        if part in d['stem_trim_db']:x*=10**(d['stem_trim_db'][part]/20)
        length=round(d['tail_fade_seconds']*SR)
        x[-length:]*=np.linspace(1,0,length)[:,None]
        if not np.isfinite(x).all():raise RuntimeError('Non-finite audio')
        stems[part]=x
    meter=pyln.Meter(SR);mix=sum(stems.values())
    if calibrate and path.parent.name.startswith('04'):
        # Working loudness follows the quiet previous trio, not loud mastering.
        gain=10**((-20.5-meter.integrated_loudness(mix))/20)
        peak=np.max(abs(resample_poly(mix,4,1,axis=0)))
        gain=min(gain,10**(-2.8/20)/peak)
        d['master_gain']*=float(gain)
        d['initial_master_calibration']={'target_lufs':-20.5,'max_oversampled_peak_dbfs':-2.8,'no_compression':True}
        for p in stems:stems[p]*=gain
        mix=sum(stems.values())
    peak=float(np.max(abs(mix)))
    if peak>=.99:raise RuntimeError(f'Peak {peak} exceeds headroom; no automatic limiter')
    for part in stems:
        sf.write(folder/'stems'/f'{part}_dry.flac',raws[part],SR,subtype='PCM_24')
        sf.write(folder/'stems'/f'{part}_mix.flac',stems[part],SR,subtype='PCM_24')
    master=folder/(d['title']+'.flac');sf.write(master,mix,SR,subtype='PCM_24')
    subprocess.run(['ffmpeg','-v','error','-y','-i',str(master),'-c:a','libmp3lame','-b:a','320k','-metadata','artist=Little Leaf','-metadata','title='+d['title'].replace('_',' '),str(folder/(d['title']+'.mp3'))],check=True)
    export_midi(d,folder/(d['title']+'_Performance.mid'))
    export_score(d,folder/(d['title']+'_Lead_Sheet.musicxml'))
    (folder/'performance_events.json').write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    levels={}
    for p in stems:
        levels[p]=dict(peak_dbfs=float(20*np.log10(np.max(abs(stems[p]))+1e-12)),rms_dbfs=float(20*np.log10(np.sqrt(np.mean(stems[p]**2))+1e-12)))
    checks=dict(sample_rate=SR,sample_count=len(mix),seconds=len(mix)/SR,peak_dbfs=20*np.log10(peak),
      oversampled_4x_peak_dbfs=float(20*np.log10(np.max(abs(resample_poly(mix,4,1,axis=0))))),
      integrated_lufs=float(meter.integrated_loudness(mix)),finite_samples=True,notes=len(d['notes']),
      part_levels=levels,loop_qualified=False,godot_tested=False,user_audition_accepted=False,paid_api_used=False,
      soundfont_sha256=BANK_SHA,reference_recording_used=False)
    (folder/'technical_checks.json').write_text(json.dumps(checks,ensure_ascii=False,indent=2)+'\n')
    print(d['title'],json.dumps(checks),flush=True)
    return folder

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--package',type=Path,default=Path(__file__).resolve().parents[1]);ap.add_argument('--out',type=Path,required=True);ap.add_argument('--soundfont',type=Path,required=True);ap.add_argument('--track',default='all');ap.add_argument('--calibrate-new',action='store_true');a=ap.parse_args()
    if not a.soundfont.is_file() or hashlib.sha256(a.soundfont.read_bytes()).hexdigest()!=BANK_SHA:ap.error('The separately obtained matching TimGM6mb.sf2 is required')
    if not shutil.which('ffmpeg'):ap.error('FFmpeg not found')
    paths=sorted(a.package.glob('0*/performance_events.json'))
    for path in paths:
        if a.track!='all' and not path.parent.name.startswith(a.track):continue
        render(path,a.out,a.soundfont,a.calibrate_new)
if __name__=='__main__':main()
