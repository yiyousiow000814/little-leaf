from pathlib import Path
from fractions import Fraction
import json, hashlib, xml.etree.ElementTree as ET, struct
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
ROOT=Path(__file__).parent
TITLE='Sunlit Table - original score draft 01'
# Durations use eighth-note units: each 4/4 bar totals 8.
def n(p,d,a=None,t=None,s=None):
 return {'pitches':p.split() if p else [],'duration_eighths':d,**({'articulation':a} if a else {}),**({'tie':t} if t else {}),**({'slur':s} if s else {})}
mel=[
[n('E5',1,s='start'),n('G5',1),n('A5',2),n('G5',1),n('E5',1),n('D5',2,s='stop')],
[n('F5',2,s='start'),n('E5',1),n('D5',1),n('B4',2,s='stop'),n('',1),n('D5',1,s='start')],
[n('E5',1),n('G5',1),n('C6',2,'tenuto'),n('A5',2),n('G5',1),n('F5',1,s='stop')],
[n('E5',1,s='start'),n('F5',1),n('D5',2),n('B4',2,s='stop'),n('',2)],
[n('E5',3,s='start'),n('G5',1),n('A5',2),n('C6',1),n('B5',1,s='stop')],
[n('A5',2,s='start'),n('G5',1),n('F5',1),n('E5',2),n('D5',2,t='start')],
[n('D5',1,t='stop'),n('F5',1),n('A5',2,s='stop'),n('G5',3,s='start'),n('B4',1)],
[n('C5',4,'tenuto',t='start'),n('C5',2,t='stop',s='stop'),n('',2)]
]
chords=[['C4 E4 A4']*2,['C4 F4 A4','B3 D4 F4'],['C4 E4 G4','C4 D4 A4'],['C4 F4 A4','B3 D4 F4'],['C4 E4 G4']*2,['C4 E4 A4']*2,['C4 F4 A4','B3 D4 F4'],['C4 E4 A4']*2]
acc=[]
for i,(a,b) in enumerate(chords):
 if i==7: acc.append([n(a,6,'tenuto'),n('',2)])
 elif i==3: acc.append([n('',1),n(a,1,'staccato'),n('',2),n('',1),n(b,1,'staccato'),n('D4',1),n('F4',1)])
 elif i==6: acc.append([n('',1),n(a,1,'staccato'),n('',2),n('',1),n(b,1,'staccato'),n('',2)])
 else: acc.append([n('',1),n(a,1,'staccato'),n('',2),n('',1),n(b,1,'staccato'),n('',2)])
bassp=[['C3','G2'],['D3','G2'],['E3','F2'],['D3','G2'],['A2','E3'],['F2','C3'],['D3','G2'],['C3','C3']]
bass=[[n(a,2,'tenuto'),n('',2),n(b,2,'tenuto'),n('',2)] for a,b in bassp]
bass[7]=[n('C3',6,'tenuto'),n('',2)]
perc=[]
for i in range(8):
 perc.append([n('',8)] if i==7 else ([n('',2),n('C2',1),n('',5)] if i in [3,6] else [n('',2),n('C2',1),n('',3),n('C2',1),n('',1)]))
parts=[{'id':'P1','name':'Melody - warm reed','clef':'G','line':2,'dynamic':'mp','program':72,'channel':1,'bars':mel}, {'id':'P2','name':'Chords - soft pluck','clef':'G','line':2,'dynamic':'p','program':25,'channel':2,'bars':acc}, {'id':'P3','name':'Bass - rounded pluck','clef':'F','line':4,'dynamic':'p','program':33,'channel':3,'bars':bass}, {'id':'P4','name':'Rhythm - soft wood click','clef':'percussion','line':2,'dynamic':'pp','program':None,'channel':10,'bars':perc}]
harm=[[(0,'C','major-sixth',None)],[(0,'D','minor-seventh',None),(4,'G','dominant',None)],[(0,'C','major','E'),(4,'F','major-sixth',None)],[(0,'D','minor-seventh',None),(4,'G','dominant',None)],[(0,'A','minor-seventh',None)],[(0,'F','major-seventh',None)],[(0,'D','minor-seventh',None),(4,'G','dominant',None)],[(0,'C','major-sixth',None)]]
labels=['C6','Dm7 | G7','C/E | F6','Dm7 | G7','Am7','Fmaj7','Dm7 | G7','C6']
intent=[
'The E-G-A cell opens upward; the stepwise fall leaves a question on D. Offbeat chords leave the tune uncluttered.',
'F-E-D contracts the cell; B over G7 creates the dominant question. An eighth rest makes space before the D pickup.',
'The pickup rises to C6, the first crest. C/E turns into F6 under a gentle A-G-F descent.',
'The ii-V answer ends on B, with a whole beat of melody rest. Two quiet accompaniment eighths hand the phrase onward.',
'The opening cell returns with a dotted-quarter start over Am7. C-B is a small upper-neighbour response, not a new tune.',
'Fmaj7 supports the long A-G-F-E-D descent. D is a gentle added-sixth colour, tied across the barline into Dm7.',
'The tie avoids a rigid barline reset. D-F-A outlines ii, then G and leading-tone B explicitly prepare the tonic.',
'C resolves the leading tone. All pitched parts sustain through beat 3 and release at beat 4; percussion stays silent.']
score={'title':TITLE,'status':'Original compositional draft; independent musical review pending; no audio rendered','tempo_quarter_bpm':84,'meter':'4/4','key':'C major','bars':8,'notated_duration_seconds':32*60/84,'parts':parts,'harmony':harm,'bar_intent':intent,'performance':{'melody':'mp; gentle tenuto on m3 C6 and m8 C5; slurs are phrase groupings, not extra ties. Slight breath only at written rests. No tempo changes.','chords':'p; short staccato eighth-note replies; final chord tenuto. No pedal across rests.','bass':'p; tenuto quarter notes, with full written rests; no octave sub-bass.','rhythm':'pp; dry unpitched wood click, no hi-hat bed or continuous shaker. C2 in data maps to GM side stick 37, not a pitched C.','ending':'Final sounding notes end at t=22.142857 s, leaving a written 0.714286 s rest. Future audio must preserve the natural release tail; do not hard-truncate at 22.857143 s. This is a closed excerpt, not a verified seamless loop.','timbres':'Names and GM mappings communicate roles only. Instrument selection and performance remain untested; no sound-quality claim.'}}
(ROOT/'score_events.json').write_text(json.dumps(score,indent=2)+'\n')
# Standard uncompressed MusicXML 4.0: one voice per part; simultaneous chord notes carry <chord/>.
def sub(el,tag,text=None,**attrs):
 e=ET.SubElement(el,tag,{k:str(v) for k,v in attrs.items()})
 if text is not None:e.text=str(text)
 return e
root=ET.Element('score-partwise',version='4.0'); sub(sub(root,'work'),'work-title',TITLE)
ident=sub(root,'identification');sub(ident,'creator','Original composition draft',type='composer');sub(ident,'rights','Original draft for Little Leaf. No reference audio transcription used.')
defs=sub(root,'defaults');sc=sub(defs,'scaling');sub(sc,'millimeters',7);sub(sc,'tenths',40)
pl=sub(root,'part-list')
for p in parts:
 sp=sub(pl,'score-part',id=p['id']);sub(sp,'part-name',p['name']);sub(sp,'part-abbreviation',p['name'].split(' - ')[0]);ins=sub(sp,'score-instrument',id=p['id']+'-I1');sub(ins,'instrument-name',p['name']);mi=sub(sp,'midi-instrument',id=p['id']+'-I1');sub(mi,'midi-channel',p['channel'])
 if p['program']:sub(mi,'midi-program',p['program'])
 else:sub(mi,'midi-unpitched',38)
types={1:('eighth',False),2:('quarter',False),3:('quarter',True),4:('half',False),5:('half',False),6:('half',True),8:('whole',False)}
# Split a five-eighth rest into a quarter + dotted quarter; every note has an exact valid type.
for p in parts:
 for b in p['bars']:
  for i,e in list(enumerate(b))[::-1]:
   if e['duration_eighths']==5:b[i:i+1]=[n('',2),n('',3)]
for p in parts:
 pa=sub(root,'part',id=p['id'])
 for bi,bar in enumerate(p['bars']):
  m=sub(pa,'measure',number=bi+1)
  if bi==0:
   at=sub(m,'attributes');sub(at,'divisions',2);key=sub(at,'key');sub(key,'fifths',0);sub(key,'mode','major');ti=sub(at,'time');sub(ti,'beats',4);sub(ti,'beat-type',4);cl=sub(at,'clef');sub(cl,'sign',p['clef']);
   if p['clef']!='percussion':sub(cl,'line',p['line'])
   if p['clef']=='percussion':sd=sub(at,'staff-details');sub(sd,'staff-lines',1)
   dr=sub(m,'direction',placement='above');dt=sub(dr,'direction-type');sub(dt,'words','Warm, lightly buoyant; straight eighths. Score review before audio.')
   dr=sub(m,'direction',placement='below');dt=sub(dr,'direction-type');sub(sub(dt,'dynamics'),p['dynamic'])
   if p['id']=='P1':
    dr=sub(m,'direction',placement='above');mt=sub(sub(dr,'direction-type'),'metronome');sub(mt,'beat-unit','quarter');sub(mt,'per-minute',84);sub(dr,'sound',tempo='84')
  if p['id']=='P1':
   for off,r,k,ba in harm[bi]:
    h=sub(m,'harmony');sub(sub(h,'root'),'root-step',r);sub(h,'kind',k)
    if ba:sub(sub(h,'bass'),'bass-step',ba)
    sub(h,'offset',off)
  for ev in bar:
   pitches=ev['pitches'] or [None]
   for pi,pitch in enumerate(pitches):
    no=sub(m,'note')
    if pi:sub(no,'chord')
    if not pitch:sub(no,'rest')
    elif p['clef']=='percussion':u=sub(no,'unpitched');sub(u,'display-step','E');sub(u,'display-octave',4)
    else:u=sub(no,'pitch');sub(u,'step',pitch[0]);sub(u,'octave',pitch[-1])
    sub(no,'duration',ev['duration_eighths'])
    if ev.get('tie'):sub(no,'tie',type=ev['tie'])
    if pitch and p['clef']=='percussion':sub(no,'instrument',id=p['id']+'-I1')
    sub(no,'voice',1);ty,dot=types[ev['duration_eighths']];sub(no,'type',ty)
    if dot:sub(no,'dot')
    if pitch and p['clef']=='percussion':sub(no,'notehead','x')
    if ev.get('tie') or ev.get('slur') or ev.get('articulation'):
     nt=sub(no,'notations')
     if ev.get('tie'):sub(nt,'tied',type=ev['tie'])
     if ev.get('slur') and pi==0:sub(nt,'slur',type=ev['slur'],number='1')
     if ev.get('articulation'):sub(sub(nt,'articulations'),ev['articulation'])
  if bi==7:sub(sub(m,'barline',location='right'),'bar-style','light-heavy')
ET.indent(root);ET.ElementTree(root).write(ROOT/'sunlit_table_draft01.musicxml',encoding='utf-8',xml_declaration=True)
# Rewrite normalized exact event source after five-eighth rest splitting.
(ROOT/'score_events.json').write_text(json.dumps(score,indent=2)+'\n')
# Readable conventionally pitched notation, hand-laid out from the same events. No engraver installed.
pdfmetrics.registerFont(TTFont('Music','/usr/share/fonts/truetype/noto/NotoMusic-Regular.ttf'))
pdfmetrics.registerFont(TTFont('Text','/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'))
pdfmetrics.registerFont(TTFont('Bold','/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'))
c=canvas.Canvas(str(ROOT/'sunlit_table_draft01_score.pdf'),pagesize=(842,595),invariant=1)
render_anchors=[]
def txt(x,y,t,size=9,font='Text'):c.setFont(font,size);c.drawString(x,y,t)
def diat(p):return int(p[-1])*7+'CDEFGAB'.index(p[0])
for page in range(2):
 txt(30,562,TITLE,17,'Bold');txt(30,541,'C major | 4/4 | quarter = 84 | straight eighths | 8 bars = 22.86 seconds',10)
 txt(30,523,'DRAFT: musical review pending. Role names are orchestration intent, not demonstrated instrument quality.',8)
 x0=147; bw=165
 for pidx,p in enumerate(parts):
  y=451-pidx*108;lines=[0] if p['clef']=='percussion' else range(5)
  txt(30,y+19,p['name'].split(' - ')[0],10,'Bold');txt(30,y+3,p['name'].split(' - ')[1],8);txt(30,y-15,p['dynamic'],10)
  if p['clef']!='percussion':c.setFont('Music',33);c.drawString(116,y-7 if p['clef']=='G' else y+1,chr(0x1D11E if p['clef']=='G' else 0x1D122))
  else:txt(120,y+9,'||',17)
  pending_tie=None;pending_slur=None
  for bj in range(4):
   bi=page*4+bj;xx=x0+bj*bw
   for line in lines:c.setLineWidth(.45);c.line(xx,y+line*6,xx+bw,y+line*6)
   c.line(xx,y-1,xx,y+25)
   if pidx==0:txt(xx+3,y+56,str(bi+1),10,'Bold');txt(xx+24,y+56,labels[bi],9)
   c.setFillColorRGB(.45,.45,.45)
   for beat in range(4):txt(xx+10+beat*(bw-12)/4,y-39,str(beat+1),6.5)
   c.setFillColorRGB(0,0,0)
   t=0
   for ev in p['bars'][bi]:
    x=xx+12+t*(bw-12)/8;d=ev['duration_eighths'];pit=ev['pitches'];ty,dot=types[d]
    render_anchors.append({'part':p['id'],'measure':bi+1,'beat':1+t/2,'duration_beats':d/2,'pitches':pit,'page':page+1,'x':x,'staff_bottom_y':y})
    if not pit:
     glyph={'eighth':0x1D13E,'quarter':0x1D13D,'half':0x1D13C,'whole':0x1D13B}[ty];c.setFont('Music',20);c.drawString(x-4,y+4,chr(glyph))
     if dot:c.circle(x+7,y+12,1,fill=1,stroke=0)
    else:
     ys=[y if p['clef']=='percussion' else y+(diat(q)-diat('E4' if p['clef']=='G' else 'G2'))*3 for q in pit]
     down=(sum(ys)/len(ys)>y+12) and p['clef']!='percussion';stemx=x-3 if down else x+3
     prev=None
     for q,ny in zip(pit,ys):
      nx=x+(6 if prev is not None and ny-prev==3 else 0);prev=ny
      for ly in range(int(y-6),int(ny)-1,-6) if ny<y else range(int(y+30),int(ny)+1,6):c.line(nx-6,ly,nx+6,ly)
      if p['clef']=='percussion':c.line(nx-3,ny-3,nx+3,ny+3);c.line(nx-3,ny+3,nx+3,ny-3)
      else:
       c.saveState();c.translate(nx,ny);c.rotate(18);c.ellipse(-3.7,-2.6,3.7,2.6,fill=0 if d>=4 else 1,stroke=1);c.restoreState()
      if dot:c.circle(nx+7,ny+1.6,1,fill=1,stroke=0)
     top=max(ys);bot=min(ys);end=bot-23 if down else top+23;c.line(stemx,top if down else bot,stemx,end)
     if d==1:
      path=c.beginPath();path.moveTo(stemx,end);path.curveTo(stemx+8,end+(4 if down else -4),stemx+8,end+(10 if down else -10),stemx+4,end+(13 if down else -13));c.drawPath(path)
     if ev.get('articulation')=='staccato':c.circle(x,top+8,1,fill=1,stroke=0)
     elif ev.get('articulation')=='tenuto':c.line(x-4,top+8,x+4,top+8)
     if ev.get('tie')=='stop':
      sx,sy=pending_tie if pending_tie else (xx-3,ys[0]);path=c.beginPath();path.moveTo(sx+2,sy-6);path.curveTo(sx+5,sy-15,x-5,ys[0]-15,x-2,ys[0]-6);c.drawPath(path)
     if ev.get('tie')=='start':
      pending_tie=(x,ys[0])
      if t+d==8 and bj==3:
       path=c.beginPath();path.moveTo(x+2,ys[0]-6);path.curveTo(x+7,ys[0]-15,xx+bw-5,ys[0]-15,xx+bw,ys[0]-6);c.drawPath(path)
     # Phrasing shown with brackets above staff to avoid accidental tie ambiguity.
     if ev.get('slur')=='start':pending_slur=(x,y+42)
     if ev.get('slur')=='stop':
      sx,sy=pending_slur if pending_slur else (xx-3,y+42);c.setDash(2,2);c.line(sx,sy,x,sy);c.setDash();c.line(sx,sy-3,sx,sy);c.line(x,sy-3,x,sy);pending_slur=None
    t+=d
   if pending_slur is not None and bj==3:c.setDash(2,2);c.line(pending_slur[0],y+42,xx+bw,y+42);c.setDash()
  c.line(x0+4*bw,y-1,x0+4*bw,y+25)
  if page==1:c.setLineWidth(2);c.line(x0+4*bw+3,y-1,x0+4*bw+3,y+25);c.setLineWidth(.45)
 txt(30,63,'Phrase brackets (dashed) correspond to MusicXML slurs. Curved lines below same-pitch notes are ties.',8)
 txt(30,49,'Small numbers mark beats 1-4. Dots = staccato; dashes = tenuto. Percussion: unpitched side stick.',8)
 txt(30,35,'Hand-laid-out reference notation; editable MusicXML and exact event ledger are authoritative. Page '+str(page+1)+'/3',8)
 c.showPage()
txt(32,558,'Phrase and performance review',17,'Bold');txt(32,536,'Original notes were composed directly; no ACE-Step audio was transcribed.',10)
y=504
import textwrap
for i,s in enumerate(intent):
 txt(32,y,f'{i+1}. {labels[i]}',10,'Bold');y-=16
 for line in textwrap.wrap(s,112):txt(46,y,line,9);y-=13
 y-=8
for s in ['Melody mp; chords and bass p; wood clicks pp. Fixed 84 BPM, no random timing or velocity.', 'Final note-offs at 22.142857 s; final notated rest to 22.857143 s. Keep natural release tails in future audio.', 'This excerpt cadences to a stop. It is not yet a production loop, arrangement, mix, or instrument-quality approval.']:
 for line in textwrap.wrap(s,112):txt(32,y,line,9);y-=14
 y-=5
txt(32,30,'Page 3/3 | Score-first review packet | No audio rendering performed',8);c.save()
(ROOT/'render_anchors.json').write_text(json.dumps(render_anchors,indent=2)+'\n')
# A separate plain-text ledger makes every rest, onset, tie and chord reviewable.
lines=[TITLE,'DRAFT - not accepted or rendered.','Tempo quarter=84; C major; 4/4; duration 22.857143 s.','Durations below are in quarter-note beats. Scientific pitch notation; C4 = middle C.','R = rest; comma-separated notes = simultaneous chord.','']
for p in parts:
 lines.append(p['name']+' / '+p['dynamic'])
 for bi,b in enumerate(p['bars']):
  t=0;evs=[]
  for e in b:
   evs.append(f"beat {1+t/2:g}: {','.join(e['pitches']) or 'R'} / {e['duration_eighths']/2:g}"+(' ['+', '.join(k+'='+str(e[k]) for k in ['articulation','tie','slur'] if k in e)+']' if any(k in e for k in ['articulation','tie','slur']) else ''));t+=e['duration_eighths']
  lines.append(f"m{bi+1}: "+'; '.join(evs))
 lines.append('')
lines+=['BAR INTENT']+[f'{i+1}. {labels[i]}: {x}' for i,x in enumerate(intent)]+['','PERFORMANCE']+[k+': '+v for k,v in score['performance'].items()]
(ROOT/'score_readme.txt').write_text('\n'.join(lines)+'\n')
print('Created MusicXML, event JSON, PDF reference notation and precise text ledger.')
with (ROOT/'score_readme.txt').open('a') as f:
 f.write('\nBAR TIMESTAMPS (seconds, 84 BPM)\n')
 for i in range(8):f.write(f'm{i+1}: {i*4*60/84:.6f}-{(i+1)*4*60/84:.6f}\n')
 f.write('\nReviewed AudioBible at commit 17839b5dc4ce4c2767172d2cee6663d9e24cd0dd. This 84 BPM study is a new bounded draft, not acceptance of either proposed direction.\n')
