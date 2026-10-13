from pathlib import Path
import importlib.util,sys
from xml.etree import ElementTree as E
HERE=Path(__file__).resolve().parent.parent
sp=importlib.util.spec_from_file_location('original_score',HERE/'source/original_create_corner_cafe.py');v=importlib.util.module_from_spec(sp);sys.modules[sp.name]=v;sp.loader.exec_module(v)
B=[[(0,'C6')],[(0,'Am7')],[(0,'Dm7')],[(0,'G7')],[(0,'Em7'),(2,'Am7')],[(0,'Dm7'),(2,'G7')],[(0,'Cmaj7'),(2,'Am7')],[(0,'Dm7'),(2,'G7')],[(0,'C6')]]
KINDS={'C6':('C','major-sixth'),'Am7':('A','minor-seventh'),'Dm7':('D','minor-seventh'),'G7':('G','dominant'),'Em7':('E','minor-seventh'),'Cmaj7':('C','major-seventh'),'C69':('C','major-sixth'),'A7b9':('A','dominant'),'A7':('A','dominant'),'Dm9':('D','minor-ninth'),'G13':('G','dominant-13th'),'Cmaj9':('C','major-ninth')}
def txt(parent,tag,text,**kw):el=E.SubElement(parent,tag,**kw);el.text=str(text);return el
def note(ms,p,d):
 n=E.SubElement(ms,'note')
 if p is None:E.SubElement(n,'rest')
 else:
  pp=E.SubElement(n,'pitch');txt(pp,'step',p[0])
  if p[1:2] in ['#','b']:txt(pp,'alter',1 if p[1]=='#' else -1)
  txt(pp,'octave',p[-1])
 txt(n,'duration',round(d*4))
 typ,dot={.5:('eighth',False),1:('quarter',False),1.5:('quarter',True),2:('half',False),3:('half',True),4:('whole',False)}[d]
 txt(n,'type',typ)
 if dot:E.SubElement(n,'dot')
for rev in [False,True]:
 title='B - Reduced harmony study' if rev else 'A - V2 control study'
 root=E.Element('score-partwise',version='4.0');work=E.SubElement(root,'work');txt(work,'work-title','Corner Cafe / '+title)
 idn=E.SubElement(root,'identification');txt(idn,'creator','Little Leaf original composition study',type='composer');txt(idn,'rights','Original Little Leaf study. No YouTube music transcribed or sampled.')
 pl=E.SubElement(root,'part-list');s=E.SubElement(pl,'score-part',id='P1');txt(s,'part-name','Electric piano theme (concert pitch)')
 ii=E.SubElement(s,'score-instrument',id='I1');txt(ii,'instrument-name','Electric piano')
 mi=E.SubElement(s,'midi-instrument',id='I1');txt(mi,'midi-channel',1);txt(mi,'midi-program',5)
 part=E.SubElement(root,'part',id='P1');bars=[list(m) for m in v.M[:8]]+[[(0,'C5',1.5)]];hh=B if rev else v.HARM[:8]+[[(0,'C6')]]
 for b,seq in enumerate(bars):
  ms=E.SubElement(part,'measure',number=str(b+1)); beats=2 if b==8 else 4
  if b in [0,8]:
   att=E.SubElement(ms,'attributes')
   if b==0:
    txt(att,'divisions',4);key=E.SubElement(att,'key');txt(key,'fifths',0)
   time=E.SubElement(att,'time');txt(time,'beats',beats);txt(time,'beat-type',4)
   if b==0:
    clef=E.SubElement(att,'clef');txt(clef,'sign','G');txt(clef,'line',2)
    dr=E.SubElement(ms,'direction');ty=E.SubElement(dr,'direction-type');txt(ty,'words','Quarter = 112. Eight-bar comparison plus common two-beat ending.');E.SubElement(dr,'sound',tempo='112')
  for at,sym in hh[b]:
   h=E.SubElement(ms,'harmony');rr=E.SubElement(h,'root');p,k=KINDS[sym];txt(rr,'root-step',p);txt(h,'kind',k,text=sym) if False else None
   ki=E.SubElement(h,'kind',text=sym);ki.text=k
   if sym=='C69':
    dg=E.SubElement(h,'degree');txt(dg,'degree-value',9);txt(dg,'degree-alter',0);txt(dg,'degree-type','add')
   if sym=='A7b9':
    dg=E.SubElement(h,'degree');txt(dg,'degree-value',9);txt(dg,'degree-alter',-1);txt(dg,'degree-type','add')
   if at:txt(h,'offset',round(at*4))
  cur=0
  for at,p,d in seq:
   if at>cur:note(ms,None,at-cur)
   if rev and b in [1,4] and p=='C#5':p='C5'
   note(ms,p,d);cur=at+d
  if cur<beats:note(ms,None,beats-cur)
  if b==8:bl=E.SubElement(ms,'barline',location='right');txt(bl,'bar-style','light-heavy')
  assert sum(int(n.findtext('duration')) for n in ms.findall('note'))==beats*4
 E.indent(root);E.ElementTree(root).write(HERE/('B_reduced_harmony_lead.musicxml' if rev else 'A_V2_control_lead.musicxml'),encoding='utf-8',xml_declaration=True)
