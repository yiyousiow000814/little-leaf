"""Reconcile Latest after independent release publication; never create a tag/release.

Only this job is serialized. Every run rereads all pages, so delayed/backfill runs
converge on the highest eligible published release rather than their own tag.
"""
import datetime,json,os,re,subprocess
PATTERN=r'v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)([a-z]?)'
def key(tag):
 m=re.fullmatch(PATTERN,tag) if isinstance(tag,str) else None
 return (*map(int,m.groups()[:3]),ord(m[4])-96 if m[4] else 0) if m else None
def run(*args):return subprocess.check_output(args,text=True).strip()
def latest(repo):
 result=subprocess.run(['gh','api','--include',f'repos/{repo}/releases/latest'],text=True,capture_output=True)
 text=result.stdout.replace('\r\n','\n')
 if result.returncode and re.match(r'^HTTP/[^ ]+ 404(?:\s|$)',text):return None
 if result.returncode or not re.match(r'^HTTP/[^ ]+ 200(?:\s|$)',text):raise ValueError('Cannot establish current Latest')
 return json.loads(text.split('\n\n',1)[1])
def select(pages,current):
 if not isinstance(pages,list) or any(not isinstance(page,list) for page in pages):raise ValueError('Incomplete release pagination')
 candidates=[]
 for page in pages:
  for item in page:
   if not isinstance(item,dict) or type(item.get('draft')) is not bool or type(item.get('prerelease')) is not bool:raise ValueError('Incomplete release inventory')
   if not item['draft'] and not item['prerelease'] and key(item.get('tag_name')) is not None:candidates.append(item)
 if current is not None:
  if not isinstance(current,dict) or current.get('draft') is not False or current.get('prerelease') is not False or key(current.get('tag_name')) is None:raise ValueError('Unrecognized Latest requires review')
 if not candidates:return None
 candidate=max(candidates,key=lambda item:key(item['tag_name']))
 if current and key(candidate['tag_name'])<=key(current['tag_name']):return None
 return candidate

def qualify(tag,git=run):
 if key(tag) is None:raise ValueError('Unsupported release tag')
 ref='refs/tags/'+tag;obj=git('git','rev-parse','--verify',ref);sha=git('git','rev-parse','--verify',ref+'^{commit}')
 if not re.fullmatch('[0-9a-f]{40}',obj) or not re.fullmatch('[0-9a-f]{40}',sha):raise ValueError('Invalid tag identity')
 git('git','merge-base','--is-ancestor',sha,'origin/main')
 project=git('git','show',sha+':project.godot');notes=json.loads(git('git','show',sha+':data/release_notes.json'))
 if re.findall(r'^config/version="([^"]+)"$',project,re.M)!=[tag[1:]]:raise ValueError('Tag/project mismatch')
 if notes.get('schema_version')!=1 or notes.get('version')!=tag[1:] or notes.get('status')!='released':raise ValueError('Unqualified release metadata')
 if datetime.date.fromisoformat(notes['date'])>datetime.datetime.now(datetime.timezone.utc).date():raise ValueError('Future release date')
 return obj

def reconcile(repo):
 pages=json.loads(run('gh','api','--paginate','--slurp',f'repos/{repo}/releases?per_page=100'))
 candidate=select(pages,latest(repo))
 if candidate is None:return 'Latest already at or above every eligible published release.'
 tag=candidate['tag_name'];obj=qualify(tag)
 if run('gh','api',f'repos/{repo}/git/ref/tags/{tag}','--jq','.object.sha')!=obj:raise ValueError('Tag moved before Latest promotion')
 # Recheck Latest after qualification. Serialized jobs protect workflow races;
 # an external maintainer can still mutate releases outside this job's lock.
 current=latest(repo)
 if select([[candidate]],current) is None:return 'Latest advanced during validation; unchanged.'
 run('gh','release','edit',tag,'--repo',repo,'--latest')
 if run('gh','api',f'repos/{repo}/git/ref/tags/{tag}','--jq','.object.sha')!=obj:raise ValueError('Tag moved during promotion; inspect without automatic retry')
 confirmed=latest(repo)
 if not confirmed or confirmed.get('tag_name')!=tag:raise ValueError('Latest promotion not confirmed; inspect without automatic retry')
 return 'Latest confirmed: '+tag
if __name__=='__main__':
 message=reconcile(os.environ['GH_REPO']);print(message)
 if os.environ.get('GITHUB_STEP_SUMMARY'):
  with open(os.environ['GITHUB_STEP_SUMMARY'],'a') as f:f.write(message+'\n')
