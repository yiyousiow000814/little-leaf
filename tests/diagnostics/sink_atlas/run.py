"""Bounded exact canonical atlas qualification; never changes assets or manifest."""
import argparse, hashlib, json, os, shutil, subprocess, sys, tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT/'tools'))
from project_layout import stage_project
EXPECTED=['31cee6b9d6bac22c11b23e6f6e5f89a8aa09b1569cb3e6e6fd37ef8efc14c732','6dc71a1bde51fc5c514356e5188736d24b6edc54acfa15185091b31cfce69bbc','d16a8ea4064eb3aa5fa1daa90f61731e1288aa1e5089b0a8b3d9b381b106c1d7']
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def git(*args):return subprocess.check_output(['git','-C',str(ROOT),*args]).decode().strip()
def main():
 p=argparse.ArgumentParser();p.add_argument('--godot',required=True);p.add_argument('--expected-head',required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
 assert git('rev-parse','HEAD')==a.expected_head and not git('status','--porcelain')
 out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
 env=os.environ.copy();env['LIBGL_ALWAYS_SOFTWARE']='1'
 gl=subprocess.run(['glxinfo','-B'],env=env,capture_output=True,text=True,check=True);(out/'glxinfo.txt').write_text(gl.stdout+gl.stderr)
 assert '25.2.8' in gl.stdout and 'llvmpipe (LLVM 20.1.2, 256 bits)' in gl.stdout,'Canonical renderer fingerprint mismatch'
 files=git('ls-files').splitlines()
 binding={'commit':a.expected_head,'tree':git('rev-parse','HEAD^{tree}'),'source_sha256':{n:sha(ROOT/n) for n in files},'godot_member_sha256':sha(Path(a.godot)),'helpers':{n:sha(HERE/n) for n in ['run.py','parity.gd','check_saved.gd']},'reference_run':38069841730,'runner_image':os.environ.get('ImageVersion'),'manifest_updated':False,'assets_changed':False,'game_instance_created':False}
 (out/'source-binding.json').write_text(json.dumps(binding,indent=2)+'\n')
 with tempfile.TemporaryDirectory(prefix='sink-atlas-saveguard-') as temporary:
  temp=Path(temporary);project=temp/'project'
  stage_project(ROOT,project,tests=True,ignore=shutil.ignore_patterns('.git','.godot','__pycache__'))
  config=project/'project.godot';runtime=config.read_text().replace('[application]','[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="sink-atlas-saveguard"',1)
  assert '[editor]' not in runtime
  config.write_text(runtime+'\n[editor]\nimport/use_multiple_threads=false\n')
  helper=project/'qa/sink_atlas';helper.mkdir(parents=True)
  for n in ['parity.gd','check_saved.gd']:shutil.copy2(HERE/n,helper/n)
  (helper/'parity.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://qa/sink_atlas/parity.gd" id="1"]\n[node name="ZeroGameParity" type="Node"]\nscript=ExtResource("1")\n')
  env.update(XDG_DATA_HOME=str(temp/'data'),XDG_CONFIG_HOME=str(temp/'config'),XDG_CACHE_HOME=str(temp/'cache'),LL_ATLAS_SOURCE=a.expected_head,LL_ATLAS_OUTPUT=str(out))
  def run(label,args):
   result=subprocess.run([a.godot,'--path',str(project),*args],env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=120)
   (out/(label+'.log')).write_bytes(result.stdout);assert result.returncode==0,label+' failed: retain log and stop'
  run('import',['--headless','--editor','--import','--quit']);config.write_text(runtime)
  run('native',['--audio-driver','Dummy','--rendering-method','gl_compatibility','res://qa/sink_atlas/parity.tscn'])
  r=json.loads((out/'atlas-parity.json').read_text());log=(out/'native.log').read_text()
  assert r['checks']==3 and not r['failures'] and r['source_commit']==a.expected_head
  assert r['baseline_sha256']==r['candidate_sha256']==EXPECTED
  assert len(r['runtime_requests'])==3 and all(row['prebaked'] and row['rgba_sha256']==EXPECTED[i] for i,row in enumerate(r['runtime_requests']))
  assert r['display_server']=='X11' and r['renderer']=='gl_compatibility' and r['engine']=='4.6.3-stable (official)'
  assert '7d41c59c4' in log and 'Mesa 25.2.8-0ubuntu0.24.04.4' in log and 'llvmpipe (LLVM 20.1.2, 256 bits)' in r['adapter']
  run('saved-png',['--headless','--script','res://qa/sink_atlas/check_saved.gd'])
  saved=json.loads((out/'saved-png-check.json').read_text())
  assert len(saved['rows'])==3 and not saved['failures'] and all(row['passed'] and row['regenerated_rgba']==row['imported_rgba']==EXPECTED[i] for i,row in enumerate(saved['rows']))
 assert not git('status','--porcelain')
 (out/'qualification.json').write_text(json.dumps({'status':'passed','commit':a.expected_head,'tree':binding['tree'],'checks':3,'dependency_rebind_only':True,'atlas_parity_sha256':sha(out/'atlas-parity.json'),'source_binding_sha256':sha(out/'source-binding.json'),'player_save_used':False},indent=2)+'\n')
if __name__=='__main__':main()
