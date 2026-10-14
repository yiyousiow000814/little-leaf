#!/usr/bin/env python3
"""Render two scene arrangements of Little Leaf's own Corner Cafe theme.

No reference MP3s are read or sampled by this renderer. It uses the preserved
24-bar Little Leaf event source, local TimGM6mb, libfluidsynth and ffmpeg.
Run from any directory:
  python build_scene_variants.py --out DIRECTORY --soundfont /path/TimGM6mb.sf2
Use --variant street or shop to render one. Source melodies/harmonies are
identical in both arrangements. Tempo is 112 BPM; changes are orchestration,
comping, bass articulation, drums and timbral mix, not a controlled A/B test.
"""
from __future__ import annotations
import argparse,copy,hashlib,json,math,platform,shutil,subprocess
from pathlib import Path
from xml.etree import ElementTree as ET
import mido
import numpy as np
import soundfile as sf
import pyloudnorm as pyln
from scipy.signal import butter,sosfilt,fftconvolve,resample_poly
import audio_engine as eng

SR=44100
TPQ=960
BPM=112
BEATS=96
N=2268000
BANK_HASH='c5378b62028c920cb11e4803327983fee2f2cdff5dc89c708e39da417e51c854'
HERE=Path(__file__).resolve().parent

def sha(path:Path)->str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

def cfg(name,program,channel,pan,rms,hp,lp,wet,bank=0):
    return dict(name=name,program=program,bank=bank,channel=channel,pan=pan,
                rms_db=rms,hp=hp,lp=lp,wet=wet)

SETTINGS={
 'street':dict(folder='01_Main_Street',name='Corner_Cafe_Main_Street_112bpm',
   title='Corner Cafe - Main Street Variation',
   parts={
    'rhodes':cfg('Rounded electric piano - original theme',4,0,-.06,-23.8,130,7200,.065),
    'guitar':cfg('Nylon guitar - syncopated short comping',24,1,-.29,-28.8,180,6300,.043),
    'bass':cfg('Finger electric bass - melodic groove',33,2,.02,-25.8,44,2700,.008),
    'drums':cfg('Light kit - kick, rim and quiet snare',0,9,.02,-32.5,65,7000,.024,128),
    'shaker':cfg('Soft maracas - low-level subdivisions',0,10,.25,-41,450,6800,.018,128),
   }),
 'shop':dict(folder='02_Shop',name='Corner_Cafe_Shop_112bpm',
   title='Corner Cafe - Shop and Decorating Variation',
   parts={
    'wood_theme':cfg('Marimba - original theme',12,0,-.12,-24.7,190,6900,.10),
    'bell_theme':cfg('Celesta - phrase handoffs from the same theme',8,1,.18,-27.5,330,5900,.13),
    'kalimba':cfg('Kalimba - sparse harmonic plucks',108,2,.28,-34,250,5800,.07),
    'bass':cfg('Upright bass - reduced accompaniment',32,3,0,-29,46,2200,.012),
    'percussion':cfg('Wood blocks and soft bongo - sparse pulse',0,9,-.13,-36.5,130,5600,.045,128),
   })
}


def compose(parent:dict,variant:str)->dict:
    s=copy.deepcopy(parent)
    setting=SETTINGS[variant]
    s.update(title=setting['title'],status='NEW_SCENE_VARIANT_AWAITING_USER_LISTENING',
      parent_events_sha256=sha(HERE/'parent_loop_events.json'),
      preserved='All 123 theme pitch/onset/notated-duration events, harmony, 24-bar form and 112 BPM.',
      reference_use='Uploaded Main Street/Shop recordings informed broad orchestration and density only; no original-game melody transcription or sampling.',
      notes=[],parts=setting['parts'])
    for field in ['not_used_as_base','source_b_json_sha256','base','loop_render']:
        s.pop(field,None)
    s['changes']=(['New lighter backbeat and quiet maracas','Shorter guitar comping','Finger-bass patch and occasional repeated-tone pickups'] if variant=='street' else
       ['Melody split between marimba and celesta without adding or removing theme notes','Sparse kalimba harmony','Reduced upright bass and wood-block/bongo percussion','No full snare/hi-hat bed'])
    def add(part,t,p,d,v,delay=0,gate=1):
        if not 0<=t<BEATS:raise ValueError((part,t))
        s['notes'].append(dict(part=part,beat=float(t),pitch=int(p),duration=float(d),
           velocity=int(np.clip(v,1,127)),delay_ms=float(delay),gate=float(gate)))
    melody=[copy.deepcopy(n) for n in parent['notes'] if n['part']=='rhodes']
    for bar in range(24):
        local=sorted([n for n in melody if 4*bar<=n['beat']<4*bar+4],key=lambda n:n['beat'])
        for i,n in enumerate(local):
            if variant=='street':
                # Preserve the parent's lead performance, not just its notes.
                s['notes'].append(n)
            else:
                # Phrase tails change timbre rather than receiving new ornaments.
                bell=(bar%4==3 and i>=len(local)-2)
                n['part']='bell_theme' if bell else 'wood_theme'
                n['velocity']=int(np.clip(n['velocity']-11-(2 if bell else 0),45,86))
                n['gate']=.95 if bell else .91
                n['delay_ms']=8 if n['beat']%1 else 4
                s['notes'].append(n)
        guitar=[n for n in parent['notes'] if n['part']=='guitar' and bar*4<=n['beat']<bar*4+4]
        ons=sorted(set(n['beat']-4*bar for n in guitar))
        groups={t:sorted(n['pitch'] for n in guitar if abs(n['beat']-(4*bar+t))<1e-7) for t in ons}
        def voicing_at(t):
            # Parent voicings, first/second harmonic segment; no reharmonization.
            if len(s['harmony'][bar])==1:return groups[ons[0]]
            return groups[ons[0]] if t<2 else groups[ons[-1]]
        bass=[n for n in parent['notes'] if n['part']=='bass' and bar*4<=n['beat']<bar*4+4]
        if variant=='street':
            pattern=[(.5,.44,49),(1.75,.20,36),(2.5,.51,47)] if bar%2==0 else [(.5,.48,49),(2,.56,51),(3.5,.25,37)]
            if 8<=bar<16:pattern=pattern[:2] # contrasting middle leaves more space
            for t,d,v in pattern:
                pitches=voicing_at(t)
                for i,p in enumerate(pitches):
                    add('guitar',4*bar+t,p+12,d,v+(1 if i==len(pitches)-1 else -1),8+i*4.7,.90)
            for n in bass:
                n=copy.deepcopy(n)
                n['duration']=min(n['duration'],.94 if n['beat']%4<1 else .76)
                n['gate']=.91
                n['velocity']=max(46,n['velocity']-4)
                s['notes'].append(n)
            if bar%2==0 and not 8<=bar<16:
                # Repeat an existing chord/root tone rather than a formulaic chromatic approach.
                root=bass[0]['pitch']
                add('bass',4*bar+1.5,root,.24,48,3,.90)
            # Clear but restrained backbeat. Middle section is thinner, same pulse.
            hits=[(0,36,43),(1,37,45),(2,36,36),(3,38,32)]
            if 8<=bar<16:hits=[(0,36,34),(1,37,36),(3,37,33)]
            if bar in [3,7,19,23]:hits.append((3.5,37,21))
            for t,p,v in hits:add('drums',4*bar+t,p,.13,v,10 if p!=36 else 0,1)
            for step in range(8):
                if 8<=bar<16 and step%2==0:continue
                add('shaker',4*bar+step*.5,70,.08,[21,32,18,28,20,30,18,26][step],8 if step%2 else 1,1)
        else:
            # Plucked harmonic notes are taken from the parent's voicing, quieter
            # and separate from the melody. No ambient synth pad or random fill.
            pattern=[(0,0),(1.5,1),(2.5,2)] if bar%2==0 else [(0,0),(2,1),(3.25,2)]
            if bar%4==3:pattern=pattern[:2]
            for i,(t,idx) in enumerate(pattern):
                pitches=voicing_at(t)
                p=pitches[min(idx,len(pitches)-1)]+12
                add('kalimba',4*bar+t,p,.40 if i else .6,48 if i else 53,5,.94)
            for n in bass:
                local_t=n['beat']-4*bar
                if local_t>=3:continue
                if local_t>=2 and len(s['harmony'][bar])==1 and bar%2==0:continue
                q=copy.deepcopy(n);q['duration']=min(.95,q['duration']);q['gate']=.91;q['velocity']=max(42,q['velocity']-15)
                s['notes'].append(q)
            hits=[(1,76,36),(3,77,31)]
            if bar%4==1:hits.append((2.5,60,24))
            if bar in [7,15,23]:hits=[(1,76,32),(3.5,77,25)]
            for t,p,v in hits:add('percussion',4*bar+t,p,.11,v,11,1)
    s['notes'].sort(key=lambda n:(n['beat'],n['part'],n['pitch']))
    def identity(notes):
        return sorted((n['beat'],n['pitch'],n['duration']) for n in notes)
    leads=[n for n in s['notes'] if n['part'] in ('rhodes','wood_theme','bell_theme')]
    assert identity(leads)==identity(melody)
    assert s['harmony']==parent['harmony']
    for n in s['notes']:
        assert 0<n['duration'] and n['beat']+n['duration']<=BEATS
    s['loop']={'bpm':BPM,'bars':24,'meter':'4/4','sample_rate':SR,'samples':N,
        'start_sample':0,'end_sample_exclusive':N,'seconds':N/SR,'baked_fade':False}
    return s


def process(raw:np.ndarray,c:dict)->tuple[np.ndarray,dict]:
    period=np.zeros((N,2),np.float64)
    for i in range(0,len(raw),N):
        chunk=raw[i:i+N];period[:len(chunk)]+=chunk
    mono=period.mean(axis=1)
    high=butter(2,c['hp'],'highpass',fs=SR,output='sos')
    low=butter(2,c['lp'],fs=SR,output='sos')
    repeated=sosfilt(low,sosfilt(high,np.tile(mono,3)))
    clean=repeated[N:2*N]
    powers=np.mean(clean[:len(clean)//4410*4410].reshape(-1,4410)**2,axis=1)
    active=powers[powers>max(float(powers.max())*.003,1e-12)]
    if not len(active):raise RuntimeError('Silent rendered stem')
    gain=10**(c['rms_db']/20)/math.sqrt(float(active.mean()))
    clean=np.tanh(clean*gain*1.1)/1.1
    angle=(c['pan']+1)*math.pi/4
    out=np.column_stack([clean*math.cos(angle),clean*math.sin(angle)])
    ir=eng.room_ir()
    for ch in range(2):
        wet=fftconvolve(clean,ir[:,ch]);folded=wet[:N].copy();folded[:len(wet)-N]+=wet[N:]
        out[:,ch]+=c['wet']*folded
    return out.astype(np.float32),dict(calibration_gain=gain,
       raw_release_last_100ms_peak=float(np.max(np.abs(raw[-4410:]))),
       periodic_filter_error=float(np.max(np.abs(repeated[N:2*N]-repeated[2*N:3*N]))))


def encode(src:Path,dst:Path,codec,options,metadata=None):
    args=['ffmpeg','-nostdin','-y','-v','error','-i',str(src),'-c:a',codec,*options]
    for k,v in (metadata or {}).items():args+=['-metadata',f'{k}={v}']
    subprocess.run([*args,str(dst)],check=True)


def midi(score:dict,path:Path):
    m=mido.MidiFile(type=1,ticks_per_beat=TPQ)
    meta=mido.MidiTrack();m.tracks.append(meta)
    meta.extend([mido.MetaMessage('track_name',name=score['title']),
      mido.MetaMessage('set_tempo',tempo=mido.bpm2tempo(BPM)),
      mido.MetaMessage('time_signature',numerator=4,denominator=4),mido.MetaMessage('key_signature',key='C'),
      mido.MetaMessage('marker',text='LOOP_START')])
    meta.append(mido.MetaMessage('marker',text='LOOP_END',time=BEATS*TPQ))
    meta.append(mido.MetaMessage('end_of_track'))
    # All percussion resides on the standard GM percussion channel, combined in
    # one MIDI track. Separate rendered stems remain available in the package.
    channels={}
    for part,c in score['parts'].items():
        ch=9 if c['bank']==128 else c['channel']
        channels.setdefault(ch,[]).append(part)
    for ch,parts in channels.items():
        c=score['parts'][parts[0]];track=mido.MidiTrack();m.tracks.append(track)
        track.extend([mido.MetaMessage('track_name',name=' + '.join(parts)),
          mido.Message('program_change',channel=ch,program=c['program']),
          mido.Message('control_change',channel=ch,control=91,value=0)])
        events=[]
        for n in score['notes']:
            if n['part'] not in parts:continue
            start,end=eng.performance(n,BPM)
            events.extend([(round(start*BPM/60*TPQ),1,n['pitch'],n['velocity']),
                           (round(end*BPM/60*TPQ),0,n['pitch'],0)])
        last=0
        for tick,on,p,v in sorted(events):
            track.append(mido.Message('note_on' if on else 'note_off',channel=ch,note=p,velocity=v,time=tick-last));last=tick
        track.append(mido.MetaMessage('end_of_track',time=max(0,BEATS*TPQ-last)))
    m.save(path)


def lead_sheet(score,path):
    root=ET.Element('score-partwise',version='4.0');work=ET.SubElement(root,'work');ET.SubElement(work,'work-title').text=score['title']+' - Theme and Chords'
    ident=ET.SubElement(root,'identification');ET.SubElement(ident,'creator',type='composer').text='Little Leaf original theme; scene arrangement'
    ET.SubElement(ident,'rights').text='No Restaurant City audio samples or melody transcription. Lead sheet only; performance events and MIDI describe the full arrangement.'
    lst=ET.SubElement(root,'part-list');sp=ET.SubElement(lst,'score-part',id='P1');ET.SubElement(sp,'part-name').text='Shared Corner Cafe Theme'
    part=ET.SubElement(root,'part',id='P1')
    pitch_names={0:('C',0),1:('C',1),2:('D',0),3:('E',-1),4:('E',0),5:('F',0),6:('F',1),7:('G',0),8:('A',-1),9:('A',0),10:('B',-1),11:('B',0)}
    kinds={'C6':('C','major-sixth'),'Cmaj7':('C','major-seventh'),'F6':('F','major-sixth'),'Fmaj7':('F','major-seventh'),'Dm7':('D','minor-seventh'),'Em7':('E','minor-seventh'),'Am7':('A','minor-seventh'),'G7':('G','dominant')}
    lengths={1:('16th',False),2:('eighth',False),3:('eighth',True),4:('quarter',False),6:('quarter',True),8:('half',False),12:('half',True),16:('whole',False)}
    def note(ms,p,d):
        ticks=round(d*4)
        if ticks<=0:return
        e=ET.SubElement(ms,'note')
        if p is None:ET.SubElement(e,'rest')
        else:
            pe=ET.SubElement(e,'pitch');name,alter=pitch_names[p%12];ET.SubElement(pe,'step').text=name
            if alter:ET.SubElement(pe,'alter').text=str(alter)
            ET.SubElement(pe,'octave').text=str(p//12-1)
        ET.SubElement(e,'duration').text=str(ticks)
        if ticks not in lengths:raise ValueError(('unsupported notation duration',ticks))
        typ,dot=lengths[ticks];ET.SubElement(e,'type').text=typ
        if dot:ET.SubElement(e,'dot')
    for bar in range(24):
        ms=ET.SubElement(part,'measure',number=str(bar+1))
        if bar==0:
            att=ET.SubElement(ms,'attributes');ET.SubElement(att,'divisions').text='4'
            ky=ET.SubElement(att,'key');ET.SubElement(ky,'fifths').text='0'
            tm=ET.SubElement(att,'time');ET.SubElement(tm,'beats').text='4';ET.SubElement(tm,'beat-type').text='4'
            cl=ET.SubElement(att,'clef');ET.SubElement(cl,'sign').text='G';ET.SubElement(cl,'line').text='2'
            di=ET.SubElement(ms,'direction');dt=ET.SubElement(di,'direction-type');met=ET.SubElement(dt,'metronome');ET.SubElement(met,'beat-unit').text='quarter';ET.SubElement(met,'per-minute').text=str(BPM);ET.SubElement(di,'sound',tempo=str(BPM))
            bl=ET.SubElement(ms,'barline',location='left');ET.SubElement(bl,'repeat',direction='forward')
        if bar in [0,8,16]:
            di=ET.SubElement(ms,'direction');dt=ET.SubElement(di,'direction-type');ET.SubElement(dt,'rehearsal').text={0:'A - theme',8:'B - lower answer',16:'A return and open turnaround'}[bar]
        for on,symbol in score['harmony'][bar]:
            h=ET.SubElement(ms,'harmony');rr=ET.SubElement(h,'root');rt,kind=kinds[symbol];ET.SubElement(rr,'root-step').text=rt;ET.SubElement(h,'kind',text=symbol).text=kind
            if on:ET.SubElement(h,'offset').text=str(round(on*4))
        theme=sorted([n for n in score['notes'] if n['part'] in ('rhodes','wood_theme','bell_theme') and 4*bar<=n['beat']<4*bar+4],key=lambda n:n['beat'])
        cursor=0.
        for n in theme:
            on=n['beat']-4*bar
            if on>cursor:note(ms,None,on-cursor)
            assert on>=cursor-1e-8
            note(ms,n['pitch'],n['duration']);cursor=on+n['duration']
        if cursor<4:note(ms,None,4-cursor)
        assert sum(int(n.findtext('duration')) for n in ms.findall('note'))==16
        if bar==23:
            bl=ET.SubElement(ms,'barline',location='right');ET.SubElement(bl,'repeat',direction='backward')
    ET.indent(root);ET.ElementTree(root).write(path,encoding='utf-8',xml_declaration=True)


def measure(x):
    peak=float(np.max(np.abs(x)))
    return dict(samples=len(x),seconds=len(x)/SR,integrated_lufs=float(pyln.Meter(SR).integrated_loudness(x)),
      peak_dbfs=20*math.log10(max(peak,1e-12)),
      estimated_4x_true_peak_dbtp=20*math.log10(max(float(np.max(np.abs(resample_poly(x,4,1,axis=0)))),1e-12)),
      boundary_step_peak=float(np.max(np.abs(x[0]-x[-1]))),
      ordinary_adjacent_step_p99_9=float(np.quantile(np.abs(np.diff(x,axis=0)),.999)),
      finite=bool(np.isfinite(x).all()),sample_clipping=bool(peak>=1))


def render(parent,variant,out,bank):
    settings=SETTINGS[variant];folder=out/settings['folder'];folder.mkdir(parents=True,exist_ok=True);(folder/'stems').mkdir(exist_ok=True)
    score=compose(parent,variant);(folder/'music_events.json').write_text(json.dumps(score,indent=2)+'\n')
    stems={};proof={}
    for part,c in settings['parts'].items():
        print('Render',variant,part,flush=True)
        raw=eng.Synth(bank,c).render([n for n in score['notes'] if n['part']==part],N/SR+6,BPM)
        stems[part],proof[part]=process(raw,c)
    mix=sum(stems.values()).astype(np.float32)
    lufs=float(pyln.Meter(SR).integrated_loudness(mix))
    gain=10**((-18.5-lufs)/20)
    tp=float(np.max(np.abs(resample_poly(mix,4,1,axis=0))))
    gain=min(gain,10**(-1.6/20)/max(tp,1e-12))
    mix*=gain
    for part in stems:sf.write(folder/'stems'/f'{part}.flac',stems[part]*gain,SR,subtype='PCM_24')
    name=settings['name'];master=folder/(name+'_Master.flac');sf.write(master,mix,SR,subtype='PCM_24')
    meta={'title':settings['title'],'artist':'Little Leaf','BPM':BPM}
    loop_meta=dict(meta,LOOPSTART=0,LOOPEND=N,LOOPLENGTH=N)
    encode(master,folder/(name+'_Loop.ogg'),'libvorbis',['-q:a','7'],loop_meta)
    encode(master,folder/(name+'.mp3'),'libmp3lame',['-b:a','320k'],meta)
    midi(score,folder/(name+'.mid'));lead_sheet(score,folder/'Theme_Lead_Sheet.musicxml')
    dec,sr=sf.read(folder/(name+'_Loop.ogg'),dtype='float32',always_2d=True)
    assert sr==SR and len(dec)==N
    assert np.isfinite(dec).all() and float(abs(dec).max())<1
    preview=np.tile(dec,(2,1))
    preview[-SR:]*=np.linspace(1,0,SR)[:,None] # outer preview ending only
    temp=folder/'_preview.wav';sf.write(temp,preview,SR,subtype='PCM_24')
    encode(temp,folder/(name+'_Two_Cycles.mp3'),'libmp3lame',['-b:a','320k'],meta);temp.unlink()
    eight=round(8*60/BPM*SR)
    seam=np.concatenate([dec[-eight:],dec[:eight]])
    temp=folder/'_seam.wav';sf.write(temp,seam,SR,subtype='PCM_24')
    encode(temp,folder/(name+'_Seam_Check.mp3'),'libmp3lame',['-b:a','320k'],meta);temp.unlink()
    evidence=dict(status='TECHNICAL_FILES_CHECKED; NEW_ARRANGEMENT_USER_LISTENING_AND_GAME_RUNTIME_PENDING',
       variant=variant,parent_events_sha256=sha(HERE/'parent_loop_events.json'),
       source_sha256=sha(Path(__file__)),soundfont_sha256=sha(bank),
       preserved_theme_events=123,preserved_harmony=True,bpm=BPM,bars=24,
       master_gain=gain,stems=proof,master=measure(mix),decoded_ogg=measure(dec),
       no_reference_recording_sampled=True,no_paid_service_used=True,no_repository_write=True,
       validation_limits=['No Godot/browser playback was run','Same tempo and bar boundaries make musical alignment possible, but do not validate a game-state switching implementation','MIDI is dry performance data; the FLAC/OGG contains the documented mix and room','The source SoundFont is not distributed; its package notice is retained, not a blanket rights clearance'])
    (folder/'validation.json').write_text(json.dumps(evidence,indent=2)+'\n')
    print(variant,evidence['master'],evidence['decoded_ogg'],flush=True)


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--out',type=Path,required=True);p.add_argument('--soundfont',type=Path,required=True)
    p.add_argument('--variant',choices=['both','street','shop'],default='both');args=p.parse_args()
    if not args.soundfont.is_file():p.error('Local SoundFont not found')
    if sha(args.soundfont)!=BANK_HASH:p.error('Different bank; use a new named candidate instead of silently replacing source timbres')
    if not shutil.which('ffmpeg'):p.error('ffmpeg unavailable')
    parent=json.loads((HERE/'parent_loop_events.json').read_text())
    assert parent['bars']==24 and parent['bpm']==BPM and parent['duration_beats']==BEATS
    for variant in (['street','shop'] if args.variant=='both' else [args.variant]):
        render(parent,variant,args.out,args.soundfont)

if __name__=='__main__':main()
