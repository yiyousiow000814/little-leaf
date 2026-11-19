"""Exact #394 disposable workflow gate; no source changes outside staging."""
import hashlib,json,os,subprocess,sys
from pathlib import Path
KIT=Path(__file__).resolve().parent
OWNER="yiyousiow000814"
REPO=OWNER+"/little-leaf"
REF="refs/heads/qa/wall-atlas-394"
BASE="bcf98740388339c8be25112d0cbc4b06dd0220a3"
BASE_TREE="af80122978a453a01a13312a2c9512a4a818a3f7"
CAND="a06ad8262c03ef41413680108568c0d805eeed80"
TREE="12bcc8de40a3418bdd30aba7821ae34a6924265a"
PATCH="ed6c2b1affbfebf76df67c9548900be4ca37607738d9d95963d0517c0afa1512"
WORKFLOW=".github/workflows/wall-atlas-394.yml"
FILES={WORKFLOW,*("tools/diagnostics/wall-atlas-394/"+name for name in ("gate.py","run.sh","binding.json","qualify.py","png_rgba.py","receipt.py","candidate.commit","candidate.patch"))}
def require(condition):
 if not condition:raise ValueError("Exact wall atlas diagnostic gate failed")
def git(repo,*args):
 return subprocess.check_output(["git","-C",str(repo),*args],text=True).strip()
def event(repo,ev,env):
 head=env["GITHUB_SHA"]
 require(env["GITHUB_REPOSITORY"]==REPO and env["GITHUB_ACTOR"]==OWNER and env["GITHUB_REF"]==REF and env["GITHUB_RUN_ATTEMPT"]=="1")
 require(env["GITHUB_EVENT_NAME"]=="push" and ev["ref"]==REF and ev["before"]==BASE and ev["after"]==head and not any(ev.get(k) for k in ("created","deleted","forced")))
 require(git(repo,"rev-parse","HEAD")==head and git(repo,"show","-s","--format=%P",head)==BASE)
 require(set(git(repo,"diff","--name-only","--no-renames",BASE,head).splitlines())==FILES)
def stage(repo):
 require(git(repo,"rev-parse","HEAD")==BASE and git(repo,"rev-parse","HEAD^{tree}")==BASE_TREE)
 require(not git(repo,"status","--porcelain","--untracked-files=all"))
 patch=KIT/"candidate.patch"; raw=KIT/"candidate.commit"
 require(hashlib.sha256(patch.read_bytes()).hexdigest()==PATCH and raw.stat().st_size<4096)
 require(git(repo,"hash-object","-t","commit",str(raw))==CAND)
 assert_dependencies(repo)
 git(repo,"-c","core.whitespace=cr-at-eol","apply","--index","--check",str(patch))
 git(repo,"-c","core.whitespace=cr-at-eol","apply","--index",str(patch))
 require(git(repo,"write-tree")==TREE and git(repo,"hash-object","-w","-t","commit",str(raw))==CAND)
 git(repo,"checkout","--detach",CAND)
 require(git(repo,"rev-parse","HEAD")==CAND and not git(repo,"status","--porcelain","--untracked-files=all"))
def assert_dependencies(repo):
 for directory in ("game","platform/web","tests/diagnostics","tests/building","tools"):
  tracked=git(repo,"ls-tree","-r","--name-only","-z",BASE,directory).split("\0")[:-1]
  require(tracked and all((repo/name).is_file() or (repo/name).is_symlink() for name in tracked))
if __name__=="__main__":
 repo=Path(sys.argv[2]).resolve()
 if sys.argv[1]=="event":event(repo,json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text()),os.environ)
 elif sys.argv[1]=="stage":stage(repo)
 else:raise ValueError("unknown gate")
