#!/usr/bin/env python3
"""Produce a 24-bar circular audio loop from the approved Reference Rearrangement.

Only the last bar's score changes. SoundFont, patches, DSP and mix gains match
its parent. No time stretching, music-length crossfade, fade-out, paid API,
network or game/repository write. A legal local TimGM6mb.sf2 is required.

python source/build_loop.py --out ./rebuilt --soundfont /path/to/TimGM6mb.sf2
Dependencies: numpy scipy soundfile mido pyloudnorm; libfluidsynth; ffmpeg.
"""
from __future__ import annotations
import argparse
import copy
import hashlib
import json
import math
import shutil
import subprocess
from pathlib import Path
from xml.etree import ElementTree as ET
import numpy as np
import soundfile as sf
import pyloudnorm as pyln
from scipy.signal import butter, sosfilt, fftconvolve, resample_poly
import audio_helpers as a

HERE = Path(__file__).resolve().parent
NAME = 'Corner_Cafe_Reference_Rearrangement_112bpm_Loop'
EXPECTED_BANK = 'c5378b62028c920cb11e4803327983fee2f2cdff5dc89c708e39da417e51c854'

def sha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()

def compose(original: dict) -> dict:
    score = copy.deepcopy(original)
    score['title'] = 'Corner Cafe - Reference Rearrangement - Seamless Loop'
    score['status'] = 'APPROVED_PARENT_MIX; LOOP_ENDING_REVISION_AWAITING_USER_REVIEW'
    score['preserved'] = 'All events/harmony in bars 1-23; BPM; instrumentation; original mix gains'
    score['sections'][-1]['label'] = 'A return - open turnaround back to A'
    score['harmony'][23] = [[0, 'Dm7'], [2, 'G7']]
    score['notes'] = [n for n in score['notes'] if n['beat'] < 92]
    def add(part, beat, pitch, duration, velocity, delay, gate):
        score['notes'].append(dict(part=part, beat=92+beat, pitch=pitch,
                                  duration=duration, velocity=velocity,
                                  delay_ms=delay, gate=gate))
    # Gentle descending ii phrase, then a quiet D question; E in the opening
    # answers it. No new timbre or flourish, no final long tonic chord.
    for t,p,d,v in [(0,77,.5,75),(.5,76,.5,74),(1,74,1,73),
                    (2.5,71,.5,72),(3,74,.75,70)]:
        add('rhodes',t,p,d,v,11 if t%1 else 5,.86 if d<=.5 else .92)
    for t,voicing,d,v in [(.5,[53,57,60,62],.8,49),(2,[53,55,59,62],.9,51)]:
        for i,p in enumerate(voicing):
            add('guitar',t,p,d,v+(1 if i==3 else -1),7+i*5.4,.9)
    for t,p,d,v in [(0,50,1.4,74),(2,43,1.05,69),(3.5,47,.38,55)]:
        add('bass',t,p,d,v,-4 if t%1==0 else 2,.86)
    for t,p,d,v in [(0,36,.12,29),(1,38,.22,23),(2,36,.12,24),(3,37,.11,27)]:
        add('drums',t,p,d,v,10 if p!=36 else 0,1)
    score['notes'].sort(key=lambda n:(n['beat'],n['part'],n['pitch']))
    assert [n for n in score['notes'] if n['beat']<92] == [n for n in original['notes'] if n['beat']<92]
    assert score['harmony'][:23] == original['harmony'][:23]
    assert score['bpm']==112 and score['duration_beats']==96 and score['bars']==24
    for n in score['notes']:
        assert 0<=n['beat']<96 and n['beat']+n['duration']<=96
        assert 0<=n['pitch']<128 and 0<n['velocity']<128 and n['gate']>0
    score['loop_render'] = {
        'start_sample':0,'end_sample_exclusive':2268000,'sample_rate':44100,
        'period_seconds':96*60/112,'baked_fades':False,
        'method':'Fold release tails; periodic filter state; circular room convolution',
        'first_note_rule':'Local performance uses original max(0, beat time + delay); identical each cycle.'}
    return score

def periodic_process(raw: np.ndarray, cfg: dict, n: int, gain: float) -> tuple[np.ndarray,dict]:
    # All synthesizer note release tails are folded into the next period, not
    # truncated or hidden by a music-length crossfade.
    period=np.zeros((n,2),np.float64)
    for k in range(0,len(raw),n):
        chunk=raw[k:k+n];period[:len(chunk)]+=chunk
    mono=period.mean(axis=1)
    hp=butter(2,cfg['hp'],'highpass',fs=a.SR,output='sos')
    lp=butter(2,cfg['lp'],fs=a.SR,output='sos')
    filtered=sosfilt(lp,sosfilt(hp,np.tile(mono,3)))
    steady=filtered[n:2*n]
    next_period=filtered[2*n:3*n]
    periodic_error=float(np.max(np.abs(steady-next_period)))
    mono=np.tanh(steady*gain*1.15)/1.15
    theta=(cfg['pan']+1)*math.pi/4
    stereo=np.stack([mono*math.cos(theta),mono*math.sin(theta)],axis=1)
    for c in (0,1):
        convolved=fftconvolve(mono,a.room_ir()[:,c])
        wet=convolved[:n].copy()
        wet[:len(convolved)-n]+=convolved[n:]
        stereo[:,c]+=cfg['wet']*wet
    return stereo.astype(np.float32),{'filter_cycle_max_error':periodic_error,
        'render_tail_last_100ms_peak':float(np.max(np.abs(raw[-4410:]))) }

def encode(src:Path,dest:Path,codec:str,quality:list[str],extra:list[str]|None=None):
    cmd=['ffmpeg','-y','-hide_banner','-loglevel','error','-i',str(src),
         '-c:a',codec,*quality,'-metadata','title=Corner Cafe - Reference Rearrangement - 112 BPM Loop',
         '-metadata','artist=Little Leaf',*(extra or []),str(dest)]
    subprocess.run(cmd,check=True)

def metrics(x:np.ndarray,sr:int)->dict:
    diff=np.diff(x,axis=0)
    return {
        'samples':len(x),'duration_seconds':len(x)/sr,
        'integrated_lufs':float(pyln.Meter(sr).integrated_loudness(x)),
        'sample_peak_dbfs':20*math.log10(max(float(np.max(np.abs(x))),1e-15)),
        'estimated_4x_true_peak_dbtp':20*math.log10(max(float(np.max(np.abs(resample_poly(x,4,1,axis=0)))),1e-15)),
        'boundary_step_peak':float(np.max(np.abs(x[0]-x[-1]))),
        'ordinary_adjacent_step_p99_9':float(np.quantile(np.abs(diff),.999)),
        'start_100ms_rms':float(np.sqrt(np.mean(x[:sr//10]**2))),
        'end_100ms_rms':float(np.sqrt(np.mean(x[-sr//10:]**2))),
        'finite':bool(np.isfinite(x).all()),'full_scale_clipping':bool(np.any(np.abs(x)>=1)),
    }

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--out',type=Path,required=True)
    ap.add_argument('--soundfont',type=Path,required=True)
    args=ap.parse_args();out=args.out
    if not args.soundfont.is_file():ap.error('Missing SoundFont')
    if sha(args.soundfont)!=EXPECTED_BANK:ap.error('SoundFont differs from approved mix; do not silently replace timbres.')
    if not shutil.which('ffmpeg'):ap.error('Missing ffmpeg')
    out.mkdir(parents=True,exist_ok=True);(out/'stems').mkdir(exist_ok=True);(out/'evidence').mkdir(exist_ok=True)
    original=json.loads((HERE/'approved_source_events.json').read_text())
    settings=json.loads((HERE/'approved_mix_settings.json').read_text())
    score=compose(original);n=round(score['duration_beats']*60/score['bpm']*a.SR)
    assert n==2268000
    (out/'music_events.json').write_text(json.dumps(score,ensure_ascii=False,indent=2)+'\n')
    stems={};details={}
    for part,cfg in a.PARTS.items():
        print('Rendering loop stem:',part,flush=True)
        raw=a.Synth(args.soundfont,cfg).render([v for v in score['notes'] if v['part']==part],n/a.SR+4,112)
        pcm,proof=periodic_process(raw,cfg,n,settings['calibration_first_8_bars_linear_gains'][part])
        pcm*=settings['master_linear_gain'];stems[part]=pcm;details[part]=proof
        sf.write(out/'stems'/f'{part}_loop.flac',pcm,a.SR,subtype='PCM_24')
    mix=sum(stems.values()).astype(np.float32)
    assert np.isfinite(mix).all() and abs(mix).max()<1
    sf.write(out/(NAME+'.flac'),mix,a.SR,subtype='PCM_24')
    quantized_master, _ = sf.read(out/(NAME+'.flac'), dtype='float32', always_2d=True)
    sf.write(out/(NAME+'.wav'),quantized_master,a.SR,subtype='PCM_24')
    encode(out/(NAME+'.flac'),out/(NAME+'.ogg'),'libvorbis',['-q:a','7'],[
        '-metadata','LOOPSTART=0','-metadata',f'LOOPEND={n}',
        '-metadata',f'LOOPLENGTH={n}','-metadata','BPM=112'])
    encode(out/(NAME+'.flac'),out/(NAME+'.mp3'),'libmp3lame',['-b:a','320k'])
    a.write_midi(score,out/(NAME+'.mid'))
    a.write_lead_sheet(score,out/'Lead_Sheet_Loop.musicxml')
    xml=ET.parse(out/'Lead_Sheet_Loop.musicxml');part=xml.getroot().find('part')
    # Mark the same 24-bar musical period without altering its notes.
    first=part.find('measure');bl=ET.Element('barline',location='left');ET.SubElement(bl,'repeat',direction='forward');first.insert(1,bl)
    last=part.findall('measure')[-1]
    for e in list(last.findall('barline')):last.remove(e)
    bl=ET.SubElement(last,'barline',location='right');ET.SubElement(bl,'bar-style').text='light-heavy';ET.SubElement(bl,'repeat',direction='backward')
    ET.indent(xml);xml.write(out/'Lead_Sheet_Loop.musicxml',encoding='utf-8',xml_declaration=True)
    decoded,sr=sf.read(out/(NAME+'.ogg'),dtype='float32',always_2d=True)
    assert sr==a.SR and len(decoded)==n
    # Preview is the ACTUAL decoded runtime OGG repeated, not a different synth
    # render. No overlap, crossfade, padding or skip is inserted at its seam.
    preview=np.tile(decoded,(2,1))
    preview[-a.SR:]*=np.linspace(1,0,a.SR)[:,None] # OUTER preview ending only
    temp=out/'evidence/_two_cycles.wav';sf.write(temp,preview,a.SR,subtype='PCM_24')
    encode(temp,out/'Corner_Cafe_Loop_Two_Cycles_Preview.mp3','libmp3lame',['-b:a','320k'])
    temp.unlink()
    # A short join audition starts two bars before the seam and ends two bars after.
    two_bars=189000
    join=np.concatenate([decoded[-two_bars:],decoded[:two_bars]])
    temp=out/'evidence/_join.wav';sf.write(temp,join,a.SR,subtype='PCM_24')
    encode(temp,out/'Corner_Cafe_Loop_Seam_Check.mp3','libmp3lame',['-b:a','320k'])
    temp.unlink()
    validation={
        'status':'LOOP_FILE_TECHNICAL_CHECKS; NEW_TURNAROUND_AND_GAMEPLAY_LISTENING_NOT_YET_USER_APPROVED',
        'parent_audio_approval':'User explicitly approved Reference Rearrangement; requested loop revision',
        'source_events_sha256':sha(HERE/'approved_source_events.json'),
        'soundfont_sha256':sha(args.soundfont),'bpm':112,'meter':'4/4','bars':24,
        'loop_start_sample':0,'loop_end_sample_exclusive':n,'loop_offset_seconds':0,
        'period_seconds':n/a.SR,'seam_in_preview_seconds':n/a.SR,
        'preserved_first_23_bar_events':sum(v['beat']<92 for v in score['notes']),
        'original_first_23_bar_events_exactly_preserved':True,
        'changed_score_bars':[24],'old_final_harmony':'Dm7 / G7 / C6',
        'new_final_harmony':'Dm7 / G7 -> C6 at restart',
        'original_patch_pan_filter_wet_and_gains_preserved':True,
        'render_tail_seconds':4,'stem_processing':details,
        'lossless':metrics(mix,a.SR),'decoded_ogg':metrics(decoded,a.SR),
        'preview_source':'actual OGG decode tiled twice; only outermost last second fades',
        'loop_file_has_fade_in_or_out':False,'boundary_crossfade_seconds':0,
        'no_reference_recording_sampled':True,'no_network_paid_api_or_repository_edit':True,
        'game_engine_runtime_validation':'not executed; import and BGM mixing remain with Dots',
        'subjective_seam_acceptance':'awaiting user listening; numeric checks are not human listening',
    }
    (out/'evidence/loop_validation.json').write_text(json.dumps(validation,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({k:validation[k] for k in ['bars','period_seconds','changed_score_bars','lossless','decoded_ogg']},indent=2))

if __name__=='__main__':main()
