#!/usr/bin/env python3
"""Targeted Shop rhythm revision; approved Main Street must never be rerendered.

Reuses the original Shop's marimba, celesta and bass FLAC stems byte for byte.
Only kalimba and percussion note events and per-part target level are changed.
No networking, package installation, repository, account or save access.

Example, from anywhere, after unpacking the complete delivery:
 python source/revise_shop.py --out /path/to/new-shop-output \
     --soundfont /usr/share/sounds/sf2/TimGM6mb.sf2

The default --preserved-stems points to ../02_Shop_Rhythm_Fix/stems. Initial
production used the original scene-variants archive's Shop/stems instead.
"""
from __future__ import annotations
import argparse
import copy
import csv
import hashlib
import json
import platform
import shutil
import subprocess
from collections import Counter
from pathlib import Path

import numpy as np
import soundfile as sf
import audio_engine as eng
import build_scene_variants as base

HERE = Path(__file__).resolve().parent
PRESERVED = ('wood_theme', 'bell_theme', 'bass')
CHANGED = ('kalimba', 'percussion')
PRESERVED_STEM_HASHES = {
    'wood_theme':'3fc1865d53f7474fc7c9cb5392fd90f5d67afa55c156ed3718c28cf99517b2f6',
    'bell_theme':'4e29da3761118880c4729b584e7cd9661a51ef8e0f67342c62dca42d2098cc79',
    'bass':'65d2af3096870323446a4bf7db5b69f91b67d15ee8110ac95f90a990bc49b06e',
}
SR, N, BPM = base.SR, base.N, base.BPM
BASENAME = 'Corner_Cafe_Shop_112bpm_Rhythm_Fix'


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rewrite_events(old: dict) -> dict:
    new = copy.deepcopy(old)
    new['title'] = 'Corner Cafe - Shop Rhythm Revision 02'
    new['status'] = 'RHYTHM_REVISION_AWAITING_USER_LISTENING'
    new['revision_parent_sha256'] = digest(HERE / 'shop_v1_events.json')
    new['preserved'] = (
        'All original Shop wood_theme, bell_theme and bass events and processed '
        'FLAC stems unchanged; harmony, 24 bars and 112 BPM unchanged.'
    )
    new['changes'] = [
        'Kalimba: one shared beat-1/beat-3 pulse rather than alternating syncopated templates.',
        'Kalimba: omit beat 3 at each four-bar phrase handoff; no new countermelody or sixteenth-note pickup.',
        'Kalimba: reuse only the first two notes of each original bar, with beat-3 choice corrected to its current harmony.',
        'Percussion: one low wood-block timbre, beat 2/4 pulse; no added bongo interjection or displaced last hit.',
        'Percussion: omit beat 4 at phrase handoffs, except a quiet regular beat 4 in the loop turnaround.',
        'Both revised layers have a slightly lower target level; original theme/bass stem levels and master gain are fixed.',
    ]
    new['parts']['kalimba']['name'] = 'Kalimba - stable two-pulse harmonic support'
    new['parts']['percussion']['name'] = 'Low wood block - steady light backbeat'
    new['parts']['kalimba']['rms_db'] = -35.5  # 1.5 dB lower active target than V1.
    new['parts']['percussion']['rms_db'] = -39.0  # 2.5 dB lower active target than V1.
    new['notes'] = [copy.deepcopy(n) for n in old['notes'] if n['part'] in PRESERVED]

    def add(part: str, bar: int, offset: float, pitch: int,
            duration: float, velocity: int, delay_ms: float, gate: float = 1.0) -> None:
        note = dict(part=part, beat=float(bar*4+offset), pitch=int(pitch),
                    duration=float(duration), velocity=int(velocity),
                    delay_ms=float(delay_ms), gate=float(gate))
        assert 0 <= note['beat'] < 96 and note['beat'] + duration <= 96
        assert 1 <= velocity <= 127
        new['notes'].append(note)

    # Original harmony retained. A sounding second pulse must belong to the
    # current chord rather than holding the old harmony across the half-bar.
    pcs = {'C6':{0,4,7,9}, 'Cmaj7':{0,4,7,11}, 'Am7':{9,0,4,7},
           'Dm7':{2,5,9,0}, 'Em7':{4,7,11,2}, 'G7':{7,11,2,5},
           'F6':{5,9,0,2}, 'Fmaj7':{5,9,0,4}}
    for bar in range(24):
        old_k = sorted([n for n in old['notes'] if n['part']=='kalimba'
                        and 4*bar <= n['beat'] < 4*bar+4], key=lambda n:n['beat'])
        first = old_k[0]['pitch']
        quiet_middle = 8 <= bar < 16
        reduction = 3 if quiet_middle else 0
        add('kalimba', bar, 0, first, .58, 49-reduction, 5.0, .90)
        phrase_tail = bar % 4 == 3
        if not phrase_tail:
            # Preserve the original lower contour; no freshly generated arpeggio.
            second = old_k[1]['pitch']
            symbol = [symbol for on,symbol in old['harmony'][bar] if on <= 2][-1]
            if second % 12 not in pcs[symbol]:
                candidates = [n['pitch'] for n in old_k if n['pitch']%12 in pcs[symbol]]
                if not candidates:
                    raise ValueError(f'No inherited chord tone for bar {bar+1}')
                second = min(candidates, key=lambda p:(abs(p-second),p))
            add('kalimba', bar, 2, second, .42, 42-reduction, 5.0, .90)
        # The two parts now share a simple underlying quarter-note frame.
        # This is specific to this revision, not a rule forbidding syncopation.
        add('percussion',bar,1,77,.10,31-(3 if quiet_middle else 0),11.0)
        if not phrase_tail or bar == 23:
            add('percussion',bar,3,77,.10,(23 if bar==23 else 27)-(2 if quiet_middle else 0),11.0)

    new['notes'].sort(key=lambda n:(n['beat'],n['part'],n['pitch']))
    for part in PRESERVED:
        assert [n for n in old['notes'] if n['part']==part] == [n for n in new['notes'] if n['part']==part]
    assert new['harmony'] == old['harmony']
    assert all(float(n['beat']).is_integer() for n in new['notes'] if n['part'] in CHANGED)
    new['loop'] = copy.deepcopy(old['loop'])
    return new


def write_grid(score: dict, path: Path) -> None:
    with path.open('w',newline='',encoding='utf-8') as f:
        w=csv.writer(f)
        w.writerow(['bar','harmony','kalimba_beats_1based','kalimba_midi_pitches',
                    'percussion_beats_1based','percussion_GM_keys'])
        for bar in range(24):
            events=lambda p:[n for n in score['notes'] if n['part']==p and 4*bar<=n['beat']<4*bar+4]
            k,p=events('kalimba'),events('percussion')
            times=lambda ns:' / '.join(f"{n['beat']-4*bar+1:g}" for n in ns)
            w.writerow([bar+1,str(score['harmony'][bar]),times(k),
                        ' / '.join(str(n['pitch']) for n in k),times(p),
                        ' / '.join(str(n['pitch']) for n in p)])


def main() -> None:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,required=True)
    parser.add_argument('--soundfont',type=Path,required=True)
    parser.add_argument('--preserved-stems',type=Path,
                        default=HERE.parent/'02_Shop_Rhythm_Fix'/'stems')
    args=parser.parse_args()
    if not args.soundfont.is_file() or digest(args.soundfont)!=base.BANK_HASH:
        parser.error('The original, checksum-matching TimGM6mb.sf2 is required.')
    if args.out.exists() and any(args.out.iterdir()):
        parser.error('Use a new empty output directory; do not overwrite approved audio.')
    if not shutil.which('ffmpeg'):
        parser.error('ffmpeg is required; it is not automatically installed.')
    old=json.loads((HERE/'shop_v1_events.json').read_text())
    previous=json.loads((HERE/'shop_v1_validation.json').read_text())
    score=rewrite_events(old)
    args.out.mkdir(parents=True,exist_ok=True)
    stems_dir=args.out/'stems';stems_dir.mkdir(exist_ok=True)
    proof={};stems={};master_gain=previous['master_gain']
    for part in PRESERVED:
        src=args.preserved_stems/f'{part}.flac'
        if not src.is_file():raise FileNotFoundError(src)
        if digest(src) != PRESERVED_STEM_HASHES[part]:
            raise ValueError(f'Preserved {part} audio differs from the original; refuse silent replacement.')
        pcm,sr=sf.read(src,dtype='float32',always_2d=True)
        if sr!=SR or pcm.shape!=(N,2):raise ValueError(f'Invalid original stem {part}')
        shutil.copy2(src,stems_dir/src.name)
        stems[part]=pcm
        proof[part]={'mode':'copied_processed_original_without_reencoding',
                     'sha256':digest(src),'identical_bytes':digest(src)==digest(stems_dir/src.name)}
    for part in CHANGED:
        print('Render changed part:',part,flush=True)
        cfg=score['parts'][part]
        notes=[n for n in score['notes'] if n['part']==part]
        raw=eng.Synth(args.soundfont,cfg).render(notes,N/SR+6,BPM)
        pcm,details=base.process(raw,cfg)
        # DO NOT normalize the new whole mix: the retained three stems keep
        # exactly the original level. Per-part process() sets the revised target.
        pcm*=master_gain
        dest=stems_dir/f'{part}.flac'
        sf.write(dest,pcm,SR,subtype='PCM_24')
        stems[part],_=sf.read(dest,dtype='float32',always_2d=True)
        proof[part]={'mode':'rerendered',**details,'sha256':digest(dest),'note_count':len(notes)}
    mix=np.sum(np.stack(list(stems.values())),axis=0,dtype=np.float64).astype(np.float32)
    if not np.isfinite(mix).all() or np.max(np.abs(mix))>=.93:
        raise RuntimeError('Review unexpected output/headroom; do not silently rescale preserved stems.')
    name=BASENAME;master=args.out/(name+'_Master.flac')
    sf.write(master,mix,SR,subtype='PCM_24')
    metadata={'title':score['title'],'artist':'Little Leaf','BPM':BPM}
    loop_meta={**metadata,'LOOPSTART':0,'LOOPEND':N,'LOOPLENGTH':N}
    base.encode(master,args.out/(name+'_Loop.ogg'),'libvorbis',['-q:a','7'],loop_meta)
    base.encode(master,args.out/(name+'.mp3'),'libmp3lame',['-b:a','320k'],metadata)
    base.midi(score,args.out/(name+'.mid'))
    # The lead sheet is truly unchanged: no new note/phrase wording to review.
    shutil.copy2(HERE/'unchanged_theme_lead_sheet.musicxml',args.out/'Theme_Lead_Sheet.musicxml')
    (args.out/'music_events.json').write_text(json.dumps(score,ensure_ascii=False,indent=2)+'\n')
    write_grid(score,args.out/'rhythm_grid.csv')
    decoded,sr=sf.read(args.out/(name+'_Loop.ogg'),dtype='float32',always_2d=True)
    assert sr==SR and decoded.shape==(N,2)
    two=np.tile(decoded,(2,1));two[-SR:]*=np.linspace(1,0,SR)[:,None]
    temp=args.out/'_two.wav';sf.write(temp,two,SR,subtype='PCM_24')
    base.encode(temp,args.out/(name+'_Two_Cycles.mp3'),'libmp3lame',['-b:a','320k'],metadata);temp.unlink()
    eight=round(8*60/BPM*SR)
    temp=args.out/'_seam.wav';sf.write(temp,np.concatenate((decoded[-eight:],decoded[:eight])),SR,subtype='PCM_24')
    base.encode(temp,args.out/(name+'_Seam_Check.mp3'),'libmp3lame',['-b:a','320k'],metadata);temp.unlink()
    written,_=sf.read(master,always_2d=True,dtype='float32')
    report={
        'status':'TECHNICAL_CHECKS_ONLY; SHOP_REVISION_USER_LISTENING_PENDING',
        'original_events_sha256':digest(HERE/'shop_v1_events.json'),
        'original_validation_sha256':digest(HERE/'shop_v1_validation.json'),
        'source_sha256':digest(Path(__file__)),
        'soundfont_sha256':digest(args.soundfont),
        'tempo_bpm':BPM,'bars':24,'fixed_original_master_gain':master_gain,
        'preserved_stems':proof,
        'old_event_counts':dict(Counter(n['part'] for n in old['notes'])),
        'new_event_counts':dict(Counter(n['part'] for n in score['notes'])),
        'preserved_event_identity':{p:True for p in PRESERVED},
        'preserved_harmony':score['harmony']==old['harmony'],
        'master':base.measure(written),'decoded_ogg':base.measure(decoded),
        'sum_stems_master_max_error':float(np.max(np.abs(mix-written))),
        'paid_services_used':False,'runtime_game_tested':False,
        'limitations':['No Godot or browser runtime tested.',
                       'Signal/event checks do not prove perceptual improvement.',
                       'Main Street is copied unchanged, not rerendered or newly normalized.',
                       'No font or SoundFont file is distributed.'],
    }
    (args.out/'validation.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2),flush=True)

if __name__=='__main__':main()
