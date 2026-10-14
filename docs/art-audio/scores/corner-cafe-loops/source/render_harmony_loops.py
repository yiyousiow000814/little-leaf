"""Bounded CPU source adaptation: exclude the six closing events, keep the phrase.

No network, installers, live audio device, GPU, game process or original writes.
The selected reviewed original helpers are extracted without running their CLI
or importing unused MIDI/mastering dependencies. Exact source hashes are pinned.
"""
from pathlib import Path
from dataclasses import dataclass
import argparse
import array
import ast
import ctypes as ct
import ctypes.util
import hashlib
import importlib.util
import json
import math
import os
import struct
import sys

import numpy as np
import soundfile as sf
from scipy.signal import butter, sosfilt, fftconvolve, resample_poly

ROOT=Path(__file__).resolve().parent
BANK=None
FLUID_BIN=None
FLUID_DLL=None
HELPER_SOURCE=ROOT/'original_create_corner_cafe.py'
ENCODER_SOURCE=ROOT/'obs_mp3_trial.py'
METRICS_SOURCE=ROOT/'metrics.json'
EVENT_PATHS={'A':ROOT.parent/'original_A.json','B':ROOT.parent/'original_B.json'}
ORIGINAL_AUDIO_SHAS={'A':'61c546fe04d10e295cd69eaea98a101734c01e817985517b3f588f56c9b00a7c',
                     'B':'9b14a25312169ff8668159ac77c0c3c3564c85bab9f030d7588f762b01ec7ba6'}
BANK_SHA='c5378b62028c920cb11e4803327983fee2f2cdff5dc89c708e39da417e51c854'
FLUID_SHA='d5a8382dabf8f3d9e43eb733afc31ea8477ecb86b2b6ff2a6d1e11f60f982126'

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def original_helpers():
    source=HELPER_SOURCE
    expected='b75b9ecda7ef67a68e23685a7193891f48f4d1257dc44a805353b6603f004d90'
    assert sha(source)==expected
    assert sha(BANK)==BANK_SHA and sha(FLUID_DLL)==FLUID_SHA
    module=ast.parse(source.read_text(encoding='utf-8'))
    assignments={'BPM','SR','SPB','N_BARS','PARTS'}
    definitions={'Note','apply_performance','Synth','room_ir','make_shaker'}
    selected=[]
    for node in module.body:
        if isinstance(node,ast.Assign) and any(isinstance(t,ast.Name) and t.id in assignments for t in node.targets):
            selected.append(node)
        elif isinstance(node,(ast.FunctionDef,ast.ClassDef)) and node.name in definitions:
            if node.name=='Synth':
                init=next(n for n in node.body if isinstance(n,ast.FunctionDef) and n.name=='__init__')
                statement=init.body[0]
                assert isinstance(statement,ast.Assign) and ast.unparse(statement.value)=="ctypes.util.find_library('fluidsynth')"
                statement.value=ast.Name(id='fluid_dll',ctx=ast.Load())
            selected.append(node)
    assert len(selected)==len(assignments)+len(definitions)
    tree=ast.fix_missing_locations(ast.Module(body=selected,type_ignores=[]))
    scope={'Path':Path,'ct':ct,'ctypes':ctypes,'np':np,'math':math,'dataclass':dataclass,
           'butter':butter,'sosfilt':sosfilt,'fftconvolve':fftconvolve,'fluid_dll':str(FLUID_DLL)}
    exec(compile(tree,str(source)+'[reviewed-selected-definitions]','exec'),scope)
    return scope,{'source_sha256':expected,'selected_helpers':sorted(definitions),
                  'portable_adapter':'Synth library lookup only changed to the pinned absolute DLL',
                  'selected_adapted_ast_sha256':hashlib.sha256(ast.dump(tree).encode()).hexdigest()}

def filter_mono(raw,cfg,sr):
    mono=sosfilt(butter(2,cfg['hp'],'highpass',fs=sr,output='sos'),raw.mean(axis=1).astype(np.float64))
    return sosfilt(butter(2,cfg['lp'],fs=sr,output='sos'),mono)

def stem_gain(raw,cfg,sr):
    mono=filter_mono(raw,cfg,sr)
    block=sr//10
    powers=np.array([np.mean(mono[i:i+block]**2) for i in range(0,len(mono),block)])
    active=powers[powers>max(powers.max()*.003,1e-12)]
    rms=math.sqrt(float(active.mean())) if active.size else 1
    return 10**(cfg['rms_db']/20)/max(rms,1e-9)

def processed(raw,cfg,gain,v,period_frames=None):
    if period_frames is None:
        filtered=filter_mono(raw,cfg,v['SR'])
    else:
        # Only the surviving phrase's release is folded. No closing note-ons
        # exist in raw. Match the supplied fourth-loop's periodic DSP method.
        period=np.zeros((period_frames,2),np.float64)
        for offset in range(0,len(raw),period_frames):
            chunk=raw[offset:offset+period_frames];period[:len(chunk)]+=chunk
        mono=period.mean(axis=1)
        hp=butter(2,cfg['hp'],'highpass',fs=v['SR'],output='sos')
        lp=butter(2,cfg['lp'],fs=v['SR'],output='sos')
        repeated=sosfilt(lp,sosfilt(hp,np.tile(mono,3)))
        filtered=repeated[period_frames:2*period_frames]
        assert np.max(np.abs(filtered-repeated[2*period_frames:]))<1e-10
    mono=np.tanh(filtered*gain*1.15)/1.15
    angle=(cfg['pan']+1)*math.pi/4
    result=np.stack([mono*math.cos(angle),mono*math.sin(angle)],axis=1)
    ir=v['room_ir']()
    for channel in range(2):
        wet=fftconvolve(mono,ir[:,channel])
        selected=wet[:len(mono)].copy()
        if period_frames is not None:selected[:len(wet)-len(mono)]+=wet[len(mono):]
        result[:,channel]+=cfg['wet']*selected
    return result.astype(np.float32)

def vlq(n):
    assert n>=0
    result=[n&127]
    while n>>7:
        n>>=7;result.insert(0,128|(n&127))
    return bytes(result)

def write_midi(notes,target,v):
    # Performance MIDI starts once; the JSON preserves negative first-onset delay.
    # DAW replay needs a loop region/preroll, as with the supplied original MIDI.
    ticks=960
    tempo=round(60_000_000/v['BPM'])
    tracks=[b'\x00\xff\x51\x03'+tempo.to_bytes(3,'big')+b'\x00\xff\x58\x04\x04\x02\x18\x08\x00\xff\x2f\x00']
    for part,cfg in v['PARTS'].items():
        chosen=[n for n in notes if n['part']==part]
        if not chosen:continue
        channel=cfg['channel'];name=part.encode()
        data=b'\x00\xff\x03'+vlq(len(name))+name
        data+=bytes([0,0xB0|channel,0,1 if cfg['bank']==128 else 0,0,0xC0|channel,cfg['program']])
        events=[]
        for n in chosen:
            a,z=v['apply_performance'](v['Note'](**n))
            events.extend([(round(a/v['SPB']*ticks),1,n['pitch'],n['velocity']),
                           (round(z/v['SPB']*ticks),0,n['pitch'],0)])
        previous=0
        for at,on,pitch,velocity in sorted(events):
            data+=vlq(at-previous)+bytes([(0x90 if on else 0x80)|channel,pitch,velocity]);previous=at
        data+=vlq(max(0,32*ticks-previous))+b'\xff\x2f\x00';tracks.append(data)
    target.write_bytes(b'MThd'+struct.pack('>IHHH',6,1,len(tracks),ticks)+b''.join(b'MTrk'+struct.pack('>I',len(t))+t for t in tracks))

def signal(data):
    assert np.isfinite(data).all() and np.max(np.abs(data))<1
    return {'sample_peak':float(np.max(np.abs(data))),
            'rms':float(np.sqrt(np.mean(data.astype(np.float64)**2))),
            'seam_adjacent_sample_step':float(np.max(np.abs(data[0]-data[-1]))),
            'ordinary_adjacent_step_p99_9':float(np.quantile(np.abs(np.diff(data,axis=0)),.999)),
            'finite':True,'full_scale_clipping':False}

def preview_mp3(data,target):
    encoder=ENCODER_SOURCE
    # Previously inspected retained ABI-pinned OBS libmp3lame encoder, no CLI/install.
    spec=importlib.util.spec_from_file_location('retained_obs_encoder',encoder)
    module=importlib.util.module_from_spec(spec);sys.modules[spec.name]=module;spec.loader.exec_module(module)
    output=resample_poly(data,160,147,axis=0).astype(np.float32)
    module.encode([array.array('f',output[:,i]) for i in range(2)],target)
    decoded,sr=sf.read(target,dtype='float32',always_2d=True)
    assert sr==48000 and len(decoded)==len(output) and np.isfinite(decoded).all()
    return {'resample':'scipy resample_poly 160/147; no tempo or pitch change',
            'encoder':'retained OBS FFmpeg n8.1.2 libmp3lame; 320k stereo 48000; gapless metadata',
            'encoder_source_sha256':sha(encoder),'decoded_frames':len(decoded),'sample_rate':sr,'signal':signal(decoded)}

def main():
    global BANK,FLUID_DLL,FLUID_BIN
    parser=argparse.ArgumentParser();parser.add_argument('--out',type=Path,required=True)
    parser.add_argument('--soundfont',type=Path,required=True)
    parser.add_argument('--fluidsynth-dll',type=Path,required=True)
    parser.add_argument('--only',choices=['A','B','both'],default='both');args=parser.parse_args()
    BANK=args.soundfont.resolve();FLUID_DLL=args.fluidsynth_dll.resolve();FLUID_BIN=FLUID_DLL.parent
    assert not args.out.exists(), 'Fresh output required'
    args.out.mkdir(parents=True)
    with os.add_dll_directory(str(FLUID_BIN)):
        v,helper_identity=original_helpers()
        N=v['Note'];sr=v['SR'];period=32*v['SPB'];frames=round(period*sr)
        assert frames==756000
        names={'A':'A_V2_control','B':'B_reduced_harmony'}
        originals={k:json.loads(EVENT_PATHS[k].read_text()) for k in names}
        for source in originals.values():
            assert source['bpm']==112 and source['duration_beats']==34
            ending=[n for n in source['notes'] if n['beat']>=32]
            assert len(ending)==6 and all(n['beat']==32 for n in ending)
            assert sorted((n['part'],n['pitch']) for n in ending)==[('bass',48),('guitar',52),('guitar',55),('guitar',57),('guitar',60),('rhodes',72)]
        full_seconds=34*v['SPB']+1.8
        gains={}
        # Derive the EXACT original shared A calibration with its closing notes.
        for part,cfg in v['PARTS'].items():
            notes=[N(**n) for n in originals['A']['notes'] if n['part']==part]
            if not notes:continue
            print('Original A calibration',part,flush=True)
            raw=v['Synth'](BANK,cfg['program'],cfg['bank']).render(notes,full_seconds)
            gains[part]=stem_gain(raw,cfg,sr)
        master_metrics=json.loads(METRICS_SOURCE.read_text())['audio']
        receipts=[]
        for key in names:
            if args.only not in ['both',key]:continue
            name=names[key];source=originals[key]
            notes=[n for n in source['notes'] if n['beat']<32]
            removed=[n for n in source['notes'] if n['beat']>=32]
            loop_source={**source,'duration_beats':32,'notes':notes,
                         'loop':{'bars':8,'start_sample':0,'end_sample_exclusive':frames,'sample_rate':sr,
                                 'change':'Six shared closing events removed before synthesis; phrase events unchanged'}}
            (args.out/(key+'_loop_events.json')).write_text(json.dumps(loop_source,indent=2)+'\n')
            write_midi(notes,args.out/(key+'_loop.mid'),v)
            mixed=np.zeros((frames,2),np.float32)
            master_gain_db=master_metrics[name]['normalization_gain_db']
            master_gain=10**(master_gain_db/20)
            stem_dir=args.out/(key+'_stems');stem_dir.mkdir()
            for part,cfg in v['PARTS'].items():
                part_notes=[n for n in notes if n['part']==part]
                if not part_notes:continue
                print('Render source loop',key,part,flush=True)
                raw=v['Synth'](BANK,cfg['program'],cfg['bank']).render([N(**n) for n in part_notes],period+4)
                assert np.max(np.abs(raw[-sr//10:]))<1e-8, 'Release tail exceeds declared capture'
                stem=processed(raw,cfg,gains[part],v,frames)*master_gain
                sf.write(stem_dir/(part+'.flac'),stem,sr,subtype='PCM_24')
                mixed+=stem
            if key=='A':
                # Keep the accepted A's separately authored procedural shaker.
                shaker=v['make_shaker'](full_seconds)[:frames]*master_gain
                sf.write(stem_dir/'shaker.flac',shaker,sr,subtype='PCM_24');mixed+=shaker
            assert np.isfinite(mixed).all() and np.max(np.abs(mixed))<1
            lossless=args.out/(key+'_harmony_loop.flac')
            sf.write(lossless,mixed,sr,subtype='PCM_24')
            quantized,_=sf.read(lossless,dtype='float32',always_2d=True)
            sf.write(args.out/(key+'_harmony_loop.wav'),quantized,sr,subtype='PCM_24')
            ogg=args.out/(key+'_harmony_loop.ogg')
            # Bulk sf.write triggered a native Windows Vorbis stack overflow;
            # bounded streaming writes retain every PCM sample and avoid it.
            with sf.SoundFile(ogg,'w',samplerate=sr,channels=2,format='OGG',subtype='VORBIS') as encoded:
                for offset in range(0,len(quantized),4096):encoded.write(quantized[offset:offset+4096])
            decoded,ogg_sr=sf.read(ogg,dtype='float32',always_2d=True)
            assert ogg_sr==sr and len(decoded)==frames
            preview=np.tile(decoded,(2,1));preview[-sr:]*=np.linspace(1,0,sr)[:,None]
            mp3=args.out/(key+'_Harmony_Study_Loop_Two_Cycles_Preview.mp3')
            preview_receipt=preview_mp3(preview,mp3)
            receipt={'id':'harmony-study-'+key,'original_audio_sha256':ORIGINAL_AUDIO_SHAS[key],
                     'original_events_sha256':sha(EVENT_PATHS[key]),'removed_closing_events':removed,
                     'preserved_phrase_events':len(notes),'phrase_events_exactly_unchanged':notes==[n for n in source['notes'] if n['beat']<32],
                     'bpm':112,'loop_beats':32,'sample_rate':sr,'frames':frames,'period_seconds':period,
                     'first_note_rule':'Original max(0, beat time + delay); initial bass -4ms is clamped to zero as in the accepted source, identically each cycle',
                     'processing':'Only surviving phrase release folded; periodic original HP/LP, saturation and pan; seeded circular room convolution; no phrase crossfade/fade',
                     'calibration':'Original full A shared per-part gains retained for both; not independently normalized short loops',
                     'stem_gains':gains,'original_master_gain_db_preserved':master_gain_db,
                     'soundfont_sha256':BANK_SHA,'fluidsynth_dll_sha256':FLUID_SHA,'fluidsynth_version':'2.3.1',
                     'helpers':helper_identity,'lossless_signal':signal(quantized),'ogg_signal':signal(decoded),
                     'ogg_encoder':'libsndfile '+sf.__libsndfile_version__+' default Vorbis encoder through soundfile '+sf.__version__,
                     'preview':preview_receipt,'preview_join_seconds':period,
                     'auditory_review':'UNASSESSED','actual_godot_web_loop':'PENDING',
                     'files':[{'path':str(p.relative_to(args.out)),'bytes':p.stat().st_size,'sha256':sha(p)} for p in args.out.rglob('*') if p.is_file() and (p.name.startswith(key+'_') or p.parent==stem_dir)]}
            (args.out/(key+'_DERIVATION_RECEIPT.json')).write_text(json.dumps(receipt,indent=2)+'\n')
            receipts.append(receipt)
            print(json.dumps({'id':receipt['id'],'frames':frames,'period_seconds':period,'ogg':sha(ogg),'preview_mp3':sha(mp3),'lossless_signal':receipt['lossless_signal']}),flush=True)
        (args.out/'DERIVATION_RECEIPTS.json').write_text(json.dumps(receipts,indent=2)+'\n')

if __name__=='__main__':main()
