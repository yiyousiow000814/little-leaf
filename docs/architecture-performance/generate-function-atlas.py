#!/usr/bin/env python3
"""Conservative, reproducible lexical call graph for production Godot scripts."""
from pathlib import Path
import argparse, collections as co, csv, json, re, hashlib, posixpath
P=argparse.ArgumentParser()
P.add_argument('root',type=Path)
P.add_argument('output',type=Path)
P.add_argument('--revision',default='unspecified source snapshot')
A=P.parse_args()
root=A.root.resolve()
if (root/'game/scripts').is_dir(): root=root/'game'
scope=root/'scripts'
if not scope.is_dir(): P.error('root must contain scripts/ or game/scripts/')
A.output.mkdir(exist_ok=True,parents=True)
files=sorted(scope.rglob('*.gd'))
if not files: P.error('no .gd found')
def rel(p):return p.relative_to(root).as_posix()
def indent(s): return len(s[:len(s)-len(s.lstrip())].expandtabs(4))
ID=r'[A-Za-z_][A-Za-z0-9_]*'
FUNCTION=re.compile(r'^\s*(?:(?:@\w+(?:\([^\n]*?\))?)[ \t]+)*(?:static\s+)?func\s+('+ID+r')\s*\(')
CLASS=re.compile(r'^\s*class\s+('+ID+r')\s*(?:extends\s+.*)?:')
CLASS_NAME=re.compile(r'^\s*class_name\s+('+ID+r')')
# Keep offsets and newlines. Double/triple quoted strings and comments aren't code.
TOKEN=re.compile(r'''\#.*?$|"""[\s\S]*?"""|\x27\x27\x27[\s\S]*?\x27\x27\x27|"(?:\\.|[^"\\])*"|\x27(?:\\.|[^\x27\\])*\x27''',re.M)
def mask(s):return TOKEN.sub(lambda m:re.sub(r'[^\r\n]',' ',m.group()),s)
BIND=re.compile(r'(?:(?:static|@\w+)\s+)*(?:const|var)\s+('+ID+r')\s*(?::\s*('+ID+r'(?:\.'+ID+r')*))?\s*(?:(?::=|=)[ \t]*(.*))?$')
LOAD=re.compile(r'''(?:preload|load)\(\s*["\x27]([^"\x27]+\.gd)["\x27]\s*\)''')
CTOR=re.compile(r'^('+ID+r'(?:\.'+ID+r')*)\.new\s*\(')
CALL=re.compile(r'(?<![\w.])('+ID+r'(?:[ \t]*\.[ \t]*'+ID+r')*)[ \t]*\(')
SKIP={'if','elif','while','for','match','return','func','assert','await','true','false'}
DYNAMIC={'call','callv','call_deferred','call_thread_safe','rpc','rpc_id','emit','emit_signal','connect','bind','bindv'}
KNOWN_CALLBACKS={'_ready','_init','_enter_tree','_exit_tree','_process','_physics_process','_input','_unhandled_input','_unhandled_key_input','_shortcut_input','_input_event','_gui_input','_draw','_notification','_get','_set','_get_property_list','_validate_property','_get_configuration_warnings','_to_string','_iter_init','_iter_next','_iter_get'}
data={}; symbols={}; by_scope={}; globals_=co.defaultdict(list); scope_binds=co.defaultdict(dict); scope_types=co.defaultdict(set); parents={}; contexts={}
for p in files:
 path=rel(p); src=p.read_text(encoding='utf-8-sig'); lines=src.splitlines(); clean=mask(src).splitlines()
 data[path]=(lines,clean)
 stack=[]; active=None
 scopes={():-1}
 for i,(line,cl) in enumerate(zip(lines,clean),1):
  if not cl.strip():continue
  n=indent(cl)
  while stack and n<=stack[-1][0]:stack.pop()
  cls=tuple(x[1] for x in stack);ctx=(path,cls);contexts[path,i]=ctx
  if active is not None and n<=active['indent']:
   active['last_line']=i-1;active=None
  cm=CLASS.match(cl)
  if cm and active is None:
   topic=cls+(cm[1],);stack.append((n,cm[1]));scopes[topic]=n;scope_types[path,cls].add(cm[1])
   base=re.search(r'\bextends\s+(.*?)\s*:\s*$',line)
   if base:parents[path,topic]=base[1]
   continue
  cln=CLASS_NAME.match(cl)
  if cln and n==0:globals_[cln[1]].append(ctx)
  if cl.startswith('extends '):
   parents[ctx]=line.strip()[8:].split('#')[0].strip()
  if active is None:
   fm=FUNCTION.match(cl)
   if fm:
    fn=fm[1];sid='f'+hashlib.sha1(f'{path}:{i}:{cls}:{fn}'.encode()).hexdigest()[:16]
    active=dict(id=sid,file=path,owner='.'.join(cls),name=fn,line=i,indent=n,last_line=len(lines),engine_name=fn in KNOWN_CALLBACKS)
    symbols[sid]=active
    by_scope.setdefault(ctx,{}).setdefault(fn,[]).append(sid)
    continue
   bm=BIND.match(cl.strip())
   if bm:
    orig=BIND.match(line.strip())
    scope_binds[ctx][bm[1]]=(bm[2],orig[3] if orig else bm[3])
def file_ref(value,path):
 if value.startswith('res://'): candidate=value[6:]
 else:candidate=posixpath.normpath(posixpath.join(posixpath.dirname(path),value))
 return (candidate,()) if candidate in data else None
def lexical(ctx,name):
 path,cls=ctx
 for k in range(len(cls),-1,-1):
  point=path,cls[:k]
  if name in scope_binds[point]: return scope_binds[point][name],point
 return None
def type_of(expr,ctx,depth=0):
 if not expr or depth>8:return None
 m=LOAD.match(expr.strip())
 if m:return file_ref(m[1],ctx[0])
 m=CTOR.match(expr)
 if m:return resolve_type(m[1],ctx,depth+1)
 return None
def resolve_type(name,ctx,depth=0):
 if not name or depth>8:return None
 parts=name.split('.');name=parts.pop(0)
 if name=='self':out=ctx
 else:
  out=None
  for k in range(len(ctx[1]),-1,-1):
   owner=ctx[0],ctx[1][:k]
   if name in scope_types[owner]:
    out=owner[0],owner[1]+(name,);break
  b=lexical(ctx,name) if out is None else None
  if b:
   (decl,value),point=b
   out=resolve_type(decl,point,depth+1) or type_of(value,point,depth+1)
  if out is None and not b and len(globals_[name])==1:out=globals_[name][0]
 if out and parts:
  for part in parts:
   if part not in scope_types[out]:return None
   out=out[0],out[1]+(part,)
 return out
def base_type(ctx):
 v=parents.get(ctx)
 if not v:return None
 if v.startswith(('"',"'")) and v[-1:]==v[:1]:return file_ref(v[1:-1],ctx[0])
 return resolve_type(v,ctx)
def method(ctx,name):
 visited=set()
 while ctx and ctx not in visited:
  visited.add(ctx)
  possible=by_scope.get(ctx,{}).get(name,[])
  if possible:return possible[0] if len(possible)==1 else None
  ctx=base_type(ctx)
 return None
def split_params(clean,orig): # split only depth-1 commas
 start=clean.find('(');level=0;begin=start+1
 if start<0:return
 for j in range(start,len(clean)):
  ch=clean[j]
  if ch in '([{':level+=1
  if ch==',' and level==1:
   yield clean[begin:j],orig[begin:j];begin=j+1
  if ch in ')]}':
   level-=1
   if level==0:yield clean[begin:j],orig[begin:j];break
edge_types={};unknown=co.Counter();unknown_lines={};call_rows=[]
for sid,s in symbols.items():
 p=s['file'];lines,cl=data[p]; i=s['line']-1; end=s['last_line']
 ctx=contexts[p,i+1]; local={};shadow=set()
 hdr_i=i;start=cl[i].find('(',FUNCTION.match(cl[i]).start(1))
 depth=0; body_col=None
 for j in range(i,end):
  for k in range(start if j==i else 0,len(cl[j])):
   if cl[j][k]=='(':depth+=1
   elif cl[j][k]==')':
    depth-=1
    if depth==0:
     hdr_i=j;body_col=cl[j].find(':',k+1);break
  if body_col is not None:break
 for clean_par,orig_par in split_params('\n'.join(cl[i:hdr_i+1])[start:],'\n'.join(lines[i:hdr_i+1])[start:]):
  pm=re.match(r'^\s*('+ID+r')\s*(?::\s*('+ID+r'(?:\.'+ID+r')*))?',clean_par)
  if pm:
   shadow.add(pm[1])
   if pm[2]:local[pm[1]]=resolve_type(pm[2],ctx)
 # Collect explicit one-definition typed/local ctor bindings. Reassigned untyped
 # variables are downgraded so an inner branch cannot invent receiver identity.
 bseen=co.Counter()
 for j in range(hdr_i+1,end):
  raw=cl[j].strip(); bm=BIND.match(raw)
  if bm:
   shadow.add(bm[1]);bseen[bm[1]]+=1
   orig=BIND.match(lines[j].strip())
   local[bm[1]]=resolve_type(bm[2],ctx) or type_of(orig[3] if orig else bm[3],ctx)
  else:
   m=re.match(r'(?:for\s+)?('+ID+r')\s*(?:=(?!=)|\s+in\s+)',raw)
   if m:bseen[m[1]]+=1
 for k,n in bseen.items():
  if n>1:local.pop(k,None)
 for j in range(hdr_i,end):
  raw=cl[j] if j>hdr_i else (cl[j][body_col+1:] if body_col is not None and body_col>=0 else '')
  for m in CALL.finditer(raw):
   if m.start()>0 and raw[:m.start()].rstrip().endswith(('.',')',']')) and raw[:m.start()].rstrip().endswith('.'):continue
   callee=re.sub(r'\s+','',m[1]); names=callee.split('.');name=names[-1]
   if len(names)==1 and name in SKIP:continue
   if re.search(r'\bfunc\s*$',raw[:m.start()]):continue
   target=None; how=''
   if len(names)==1 and name not in shadow and not lexical(ctx,name):
    target=method(ctx,name);how='implicit'
   elif len(names)>1:
    receiver='.'.join(names[:-1])
    if receiver=='super':owner=base_type(ctx);how='super'
    elif receiver=='self':owner=ctx;how='self'
    elif names[0] in shadow:
     owner=local.get(receiver) if len(names)==2 else None;how='typed-local'
    else:
     owner=resolve_type(receiver,ctx);how='declared-receiver'
    if name=='new':name='_init'
    if owner:target=method(owner,name)
   if target:
    edge_types.setdefault((sid,target),co.Counter())[how]+=1
    call_rows.append([sid,j+1,callee,target,how])
   else:
    reason='dynamic dispatch' if names[-1] in DYNAMIC else ('unqualified or external' if len(names)==1 else 'unresolved receiver or external')
    unknown[sid,reason,callee]+=1
    unknown_lines.setdefault((sid,reason,callee),[]).append(j+1)
def tsv(name,headers,rows):
 with (A.output/name).open('w',encoding='utf-8',newline='') as f:
  w=csv.writer(f,delimiter='\t');w.writerow(headers);w.writerows(rows)
def escape(v):return v.replace('&','&amp;').replace('"','&quot;').replace('<','&lt;').replace('>','&gt;')
def make_graph(name,paths):
 paths=set(paths); modules=co.defaultdict(list)
 for path in sorted(paths):modules[str(Path(path).parent)].append(path)
 fns=co.defaultdict(list)
 for s in symbols.values():fns[s['file']].append(s)
 local_ids={s['id'] for s in symbols.values() if s['file'] in paths}
 links=[(a,b,k) for (a,b),k in edge_types.items() if a in local_ids and b in local_ids]
 cfg={'maxTextSize':4000000,'maxEdges':max(1000,len(links)+30),'flowchart':{'defaultRenderer':'elk','htmlLabels':False,'useMaxWidth':False}}
 out=['---','config: '+json.dumps(cfg),'---','%% '+A.revision,'%% Caller → callee. Dashed = statically resolved cross-file. Omitted: dynamic calls and engine scheduling.', 'flowchart LR','classDef hook fill:#fff1dc,stroke:#a36a28,color:#303030']
 for mi,(folder,ps) in enumerate(modules.items()):
  out.append(f'  subgraph mod{mi}["{escape(folder)}"]')
  for fi,path in enumerate(ps):
   out.append(f'    subgraph grp{mi}p{fi}["{escape(Path(path).name)}"]')
   for s in fns[path]:
    lbl=(s['owner']+'.' if s['owner'] else '')+s['name']+' · L'+str(s['line'])
    out.append(f'      {s["id"]}["{escape(lbl)}"]'+(':::hook' if s['engine_name'] else ''))
   out.append('    end')
  out.append('  end')
 for a,b,k in links:out.append(f'  {a} '+('-.->' if symbols[a]['file']!=symbols[b]['file'] else '-->')+f' {b}')
 (A.output/name).write_text('\n'.join(out)+'\n',encoding='utf-8')
make_graph('little-leaf-all-functions.mmd',[p for p in data if any(ctx[0]==p for ctx in by_scope)])
tsv('functions.tsv',['id','file','line','last_line','nested_class','function','engine_hook_name'],([s['id'],s['file'],s['line'],s['last_line'],s['owner'],s['name'],int(s['engine_name'])] for s in symbols.values()))
tsv('calls.tsv',['caller_id','call_line','expression','callee_id','resolution'],call_rows)
tsv('unresolved.tsv',['caller_id','reason','expression','occurrences','call_lines'],([a,b,c,k,','.join(map(str,unknown_lines[a,b,c]))] for (a,b,c),k in sorted(unknown.items())))
summary={'revision':A.revision,'scope':'game/scripts/**/*.gd','source_files':len(data),'function_definitions':len(symbols),'engine_hook_name_candidates':sum(x['engine_name'] for x in symbols.values()),'distinct_static_edges':len(edge_types),'cross_file_edges':sum(symbols[a]['file']!=symbols[b]['file'] for a,b in edge_types),'resolved_call_sites':len(call_rows),'unresolved_or_external_call_sites':sum(unknown.values()),'dynamic_dispatch_candidates':sum(v for k,v in unknown.items() if k[1]=='dynamic dispatch'),'functions_by_folder':dict(sorted(co.Counter(str(Path(s['file']).parent) for s in symbols.values()).items()))}
(A.output/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
graph={
 'meta':summary,
 'nodes':[{'id':s['id'],'file':s['file'],'line':s['line'],'last_line':s['last_line'],'nested_class':s['owner'],'function':s['name'],'engine_hook_name':s['engine_name'],'module':str(Path(s['file']).parent)} for s in symbols.values()],
 'edges':[{'src':src,'dst':dst,'kind':kind,'line':line,'expression':expr} for src,line,expr,dst,kind in call_rows],
 'unresolved':[{'src':src,'kind':reason,'expression':expr,'count':count,'lines':unknown_lines[src,reason,expr]} for (src,reason,expr),count in sorted(unknown.items())],
}
(A.output/'graph.json').write_text(json.dumps(graph,ensure_ascii=False,separators=(',',':'))+'\n',encoding='utf-8')
print(json.dumps(summary,indent=2))
