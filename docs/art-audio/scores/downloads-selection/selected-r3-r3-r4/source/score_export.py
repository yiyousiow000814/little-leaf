"""Export the frozen performed events and a concert-pitch lead sheet.
MusicXML is NOT a full orchestral score. MIDI does not embed the SoundFont,
custom drums, room/EQ or mix gains; the audio renderer reproduces those.
"""
from pathlib import Path
import re, json, copy
import numpy as np
import mido
from xml.etree.ElementTree import Element,SubElement,ElementTree,indent
TPQ=960

def export_midi(d,path):
    points={float(b):float(t) for b,t in d['beat_time_map']}
    bs=np.array(sorted(points));ts=np.array([points[b] for b in bs])
    duration=float(d['duration_seconds'])
    if ts[-1] < duration:
        rate=(ts[-1]-ts[-2])/(bs[-1]-bs[-2])
        bs=np.r_[bs,bs[-1]+(duration-ts[-1])/rate];ts=np.r_[ts,duration]
    else:
        lastbeat=float(np.interp(duration,ts,bs));keep=ts<duration-1e-9
        bs=np.r_[bs[keep],lastbeat];ts=np.r_[ts[keep],duration]
    assert np.all(np.diff(bs)>0) and np.all(np.diff(ts)>0)
    def ticks(t):return round(float(np.interp(t,ts,bs))*TPQ)
    f=mido.MidiFile(type=1,ticks_per_beat=TPQ)
    conductor=mido.MidiTrack();f.tracks.append(conductor)
    conductor.append(mido.MetaMessage('track_name',name=d['title']+' | performance tempo map'))
    num,den=d['score']['meter'];conductor.append(mido.MetaMessage('time_signature',numerator=num,denominator=den))
    prevtick=0;prevtempo=None
    for i in range(len(bs)-1):
        tempo=round((ts[i+1]-ts[i])/(bs[i+1]-bs[i])*1e6)
        if tempo!=prevtempo:
            tick=round(bs[i]*TPQ);conductor.append(mido.MetaMessage('set_tempo',tempo=tempo,time=tick-prevtick));prevtick=tick;prevtempo=tempo
    conductor.append(mido.MetaMessage('end_of_track',time=max(0,round(bs[-1]*TPQ)-prevtick)))
    for part,cfg in d['parts'].items():
        tr=mido.MidiTrack();f.tracks.append(tr);ch=cfg['channel']
        tr.append(mido.MetaMessage('track_name',name=part))
        tr.append(mido.Message('program_change',program=cfg['program'],channel=ch))
        tr.append(mido.Message('control_change',channel=ch,control=7,value=100))
        tr.append(mido.Message('control_change',channel=ch,control=10,value=round((cfg['pan']+1)*63.5)))
        ev=[]
        for n in d['notes']:
            if n['part']!=part:continue
            ev.append((ticks(n['start_seconds']),2,mido.Message('note_on',channel=ch,note=n['pitch'],velocity=n['velocity'])))
            ev.append((ticks(n['end_seconds']),0,mido.Message('note_off',channel=ch,note=n['pitch'],velocity=0)))
        for c in d['continuous_controls'].get(part,[]):
            msg=mido.Message('control_change',channel=ch,control=11,value=c['value']) if c['type']=='expression' else mido.Message('pitchwheel',channel=ch,pitch=c['value']-8192)
            ev.append((ticks(c['time']),1,msg))
        ev.sort(key=lambda x:(x[0],x[1]));prev=0
        for tick,_,msg in ev:tr.append(msg.copy(time=tick-prev));prev=tick
        tr.append(mido.MetaMessage('end_of_track',time=0))
    f.save(path)

def export_score(d,path):
    cfg=d['score'];root=Element('score-partwise',version='4.0')
    SubElement(SubElement(root,'work'),'work-title').text=d['title'].replace('_',' ')
    ident=SubElement(root,'identification');SubElement(ident,'creator',type='composer').text='Little Leaf original music / selected-version production package'
    SubElement(ident,'rights').text='Original study; no Restaurant City recording or transcribed melody used.'
    plist=SubElement(root,'part-list');p=SubElement(plist,'score-part',id='P1');SubElement(p,'part-name').text='Concert-pitch melody and harmony (not full score)'
    body=SubElement(root,'part',id='P1')
    def words(m,s):
        dr=SubElement(m,'direction',placement='above');SubElement(SubElement(dr,'direction-type'),'words').text=s;return dr
    def add_note(m,name,dur,tie=None):
        no=SubElement(m,'note')
        if name=='R':SubElement(no,'rest')
        else:
            ma=re.fullmatch(r'([A-G])([#b]?)(-?\d+)',name);pp=SubElement(no,'pitch');SubElement(pp,'step').text=ma[1]
            if ma[2]:SubElement(pp,'alter').text='1' if ma[2]=='#' else '-1'
            SubElement(pp,'octave').text=ma[3]
        SubElement(no,'duration').text=str(round(dur*4))
        if tie:SubElement(no,'tie',type=tie)
        typ,dot={.25:('16th',0),.5:('eighth',0),.75:('eighth',1),1.:('quarter',0),1.5:('quarter',1),2.:('half',0),3.:('half',1),4.:('whole',0)}[dur]
        SubElement(no,'type').text=typ
        if dot:SubElement(no,'dot')
        if tie:SubElement(SubElement(no,'notations'),'tied',type=tie)
    m=SubElement(body,'measure',number='0',implicit='yes');at=SubElement(m,'attributes');SubElement(at,'divisions').text='4'
    ky=SubElement(at,'key');SubElement(ky,'fifths').text=str(cfg['key_fifths'])
    ti=SubElement(at,'time');SubElement(ti,'beats').text=str(cfg['meter'][0]);SubElement(ti,'beat-type').text=str(cfg['meter'][1]);cl=SubElement(at,'clef');SubElement(cl,'sign').text='G';SubElement(cl,'line').text='2'
    dr=words(m,('Light shared eighth-note lilt, 55:45. ' if d.get('tempo_clock',{}).get('performed_eighth_ratio') else '')+'Soft, continuous phrasing. Nominal quarter = '+str(cfg['bpm'])+'. Performance timing/expression is in the MIDI/event ledger.');SubElement(dr,'sound',tempo=str(cfg['bpm']))
    for tk in cfg['pickup']:na,du=tk.split(':');add_note(m,na,float(du))
    last=None
    for i,bar in enumerate(cfg['bars']):
        m=SubElement(body,'measure',number=str(i+1))
        if cfg['lead_parts'][i]!=last:words(m,'Lead: '+cfg['lead_parts'][i]);last=cfg['lead_parts'][i]
        for beat,label in cfg['harmonies'][i]:
            h=SubElement(m,'harmony');r=SubElement(h,'root');lab=label.split('/')[0];SubElement(r,'root-step').text=lab[0]
            if len(lab)>1 and lab[1] in '#b':SubElement(r,'root-alter').text='1' if lab[1]=='#' else '-1'
            SubElement(h,'kind',text=label).text=('major-seventh' if lab.endswith('maj7') else 'minor-seventh' if lab.endswith('m7') else 'minor' if lab.endswith('m') else 'dominant' if lab.endswith('7') else 'major-sixth' if lab.endswith('6') else 'major')
            if '/' in label:
                bb=label.split('/')[1];ba=SubElement(h,'bass');SubElement(ba,'bass-step').text=bb[0]
                if len(bb)>1:SubElement(ba,'bass-alter').text='1' if bb[1]=='#' else '-1'
            SubElement(h,'offset').text=str(round(beat*4))
        for tk in bar.split():
            na,du=tk.split(':');du=float(du)
            if du==2.5:add_note(m,na,2.,'start');add_note(m,na,.5,'stop')
            else:add_note(m,na,du)
        if i==len(cfg['bars'])-1:SubElement(SubElement(m,'barline',location='right'),'bar-style').text='light-heavy'
    indent(root);ElementTree(root).write(path,encoding='utf-8',xml_declaration=True)
