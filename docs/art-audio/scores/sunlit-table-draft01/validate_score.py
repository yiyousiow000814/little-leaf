import json,xml.etree.ElementTree as ET,hashlib
from pathlib import Path
R=Path(__file__).parent
s=json.loads((R/'score_events.json').read_text());root=ET.parse(R/'sunlit_table_draft01.musicxml').getroot();checks=[]
def check(ok,label):
 checks.append({'check':label,'pass':bool(ok)})
 if not ok:raise AssertionError(label)
def midi(p):return 12*(int(p[-1])+1)+{'C':0,'D':2,'E':4,'F':5,'G':7,'A':9,'B':11}[p[0]]
ranges={};alloff=[]
for p,xmlp in zip(s['parts'],root.findall('part')):
 check(len(p['bars'])==len(xmlp.findall('measure'))==8,p['id']+' has eight measures')
 held=None;slur=False;pitches=[]
 for bi,(bar,m) in enumerate(zip(p['bars'],xmlp.findall('measure'))):
  check(sum(e['duration_eighths'] for e in bar)==8,f'{p["id"]} m{bi+1} exact 4/4 sum')
  reconstructed=[];total=0
  for no in m.findall('note'):
   dur=int(no.findtext('duration'));pitch=no.find('pitch');pt=None if pitch is None else pitch.findtext('step')+pitch.findtext('octave')
   if no.find('unpitched') is not None:pt='C2'
   if no.find('chord') is None:reconstructed.append({'pitches':[pt] if pt else [],'duration_eighths':dur});total+=dur
   else:check(dur==reconstructed[-1]['duration_eighths'],'XML chord durations match');reconstructed[-1]['pitches'].append(pt)
   ty=no.findtext('type');base={'eighth':1,'quarter':2,'half':4,'whole':8}[ty];actual=base*(1.5 if no.find('dot') is not None else 1)
   check(actual==dur,f'{p["id"]} m{bi+1} XML rhythmic type matches duration')
   check(no.findtext('voice')=='1',p['id']+' only declared voice 1')
   for typ in ['tie','slur']:
    if typ=='tie':
     a=no.find('tie');b=no.find('notations/tied');check((a is None and b is None) or (a is not None and b is not None and a.attrib==b.attrib),'MusicXML sounding and displayed ties agree')
  check(total==8,f'{p["id"]} m{bi+1} XML measure duration')
  check(reconstructed==[{k:e[k] for k in ['pitches','duration_eighths']} for e in bar],f'{p["id"]} m{bi+1} XML matches source pitches and rhythms')
  t=0
  for e in bar:
   if held is not None:check(e.get('tie')=='stop' and e['pitches']==held,'Tie continues immediately with identical pitch');held=None
   elif e.get('tie')=='stop':raise AssertionError('Orphan tie stop')
   if e.get('tie')=='start':held=e['pitches']
   if e.get('slur')=='start':check(not slur,'No overlapping same-number slurs');slur=True
   if e.get('slur')=='stop':check(slur,'Slur stop has start');slur=False
   if e['pitches']:alloff.append((bi*8+t+e['duration_eighths'])/2*60/84)
   pitches.extend(e['pitches']);t+=e['duration_eighths']
 check(held is None,p['id']+' no dangling tie');check(not slur,p['id']+' no dangling phrase slur')
 if p['id']!='P4':ranges[p['id']]={'lowest':min(pitches,key=midi),'highest':max(pitches,key=midi),'lowest_midi':min(map(midi,pitches)),'highest_midi':max(map(midi,pitches))}
 check(p['bars'][-1][-1]['pitches']==[],p['id']+' ends with an explicit rest')
check(abs(s['notated_duration_seconds']-22.857142857)<1e-6,'8 bars at quarter 84 last 22.857143 seconds')
check(abs(max(alloff)-22.142857143)<1e-6,'All written sounding events end by 22.142857 seconds')
check(ranges['P1']['lowest_midi']>=71 and ranges['P1']['highest_midi']<=84,'Melody bounded B4-C6')
anchors=json.loads((R/'render_anchors.json').read_text())
check(len(anchors)==sum(len(b) for part in s['parts'] for b in part['bars']),'PDF anchor count equals source event count')
for part in s['parts']:
 for mi,b in enumerate(part['bars'],1):
  t=0;aa=[v for v in anchors if v['part']==part['id'] and v['measure']==mi]
  check(len(aa)==len(b),f'{part["id"]} m{mi} PDF event count')
  for a,e in zip(aa,b):
   check(a['beat']==1+t/2 and a['duration_beats']==e['duration_eighths']/2 and a['pitches']==e['pitches'],'PDF event agrees with XML-validated source')
   check(abs(a['x']-(147+((mi-1)%4)*165+12+t*153/8))<1e-8,'PDF x position agrees with metrical onset')
   t+=e['duration_eighths']
report={'result':'PASS','checks_passed':len(checks),'checks':checks,'ranges':ranges,'last_written_note_off_seconds':max(alloff),'notated_duration_seconds':s['notated_duration_seconds'],'limitations':['No external MusicXML XSD or notation-app import validation performed; XML was structurally parsed and cross-checked against event data.','PDF is hand-laid-out reference staff notation, not output from a notation engraver.','No MIDI or audio rendered. Mechanical checks do not establish aesthetic quality or instrument realism.','Independent musical review remains pending; excerpt is not a seamless-loop claim.']}
(R/'validation.json').write_text(json.dumps(report,indent=2)+'\n')
files=['sunlit_table_draft01.musicxml','sunlit_table_draft01_score.pdf','score_events.json','score_readme.txt','build_score.py','validate_score.py','validation.json','provenance_review.json','render_anchors.json','INTEGRATION.txt']
(R/'SHA256SUMS.txt').write_text('\n'.join(hashlib.sha256((R/f).read_bytes()).hexdigest()+'  '+f for f in files)+'\n')
print(json.dumps({k:v for k,v in report.items() if k!='checks'},indent=2))
