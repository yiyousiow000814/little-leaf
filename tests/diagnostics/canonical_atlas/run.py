"""10a-only exact native parity; never accept changed pixels or write a manifest."""
import argparse,hashlib,json,os,pathlib,shutil,subprocess,tempfile
HERE=pathlib.Path(__file__).resolve().parent
EXPECTED_RGBA=['31cee6b9d6bac22c11b23e6f6e5f89a8aa09b1569cb3e6e6fd37ef8efc14c732','6dc71a1bde51fc5c514356e5188736d24b6edc54acfa15185091b31cfce69bbc','d16a8ea4064eb3aa5fa1daa90f61731e1288aa1e5089b0a8b3d9b381b106c1d7']
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def git(*args):return subprocess.check_output(['git',*args],text=True).strip()
def frozen_targets(inputs):
 assert inputs.get('candidate') is not None,'Combined candidate commit/tree not frozen'
 targets={n:inputs[n] for n in ['control','candidate']}
 assert all(len(v['commit'])==40 and len(v['tree'])==40 for v in targets.values())
 assert len({v['commit'] for v in targets.values()})==2
 return targets
def receipt_passed(r,code):
 return code==0 and r.get('checks')==3 and not r.get('failures',['missing']) and r.get('baseline_sha256')==r.get('candidate_sha256')==EXPECTED_RGBA and r.get('display_server')=='X11' and r.get('renderer')=='gl_compatibility' and r.get('engine')=='4.6.3-stable (official)' and 'llvmpipe (LLVM 20.1.2, 256 bits)' in r.get('adapter','')

def native_fingerprint_passed(log):
 return 'Godot Engine v4.6.3.stable.official.7d41c59c4 -' in log and 'Mesa 25.2.8-0ubuntu0.24.04.4' in log
def native(cmd,env,log):
 with log.open('w') as f:
  p=subprocess.Popen(cmd,env=env,stdout=f,stderr=subprocess.STDOUT)
  try:return p.wait(timeout=120)
  except subprocess.TimeoutExpired:p.kill();p.wait();return -1
def main():
 p=argparse.ArgumentParser();p.add_argument('--godot',required=True);p.add_argument('--expected-head',required=True);p.add_argument('--output',type=pathlib.Path,required=True);a=p.parse_args()
 inputs=json.loads((HERE/'inputs.json').read_text());targets=frozen_targets(inputs)
 root=pathlib.Path.cwd();out=a.output.resolve();out.mkdir(parents=True,exist_ok=True);assert git('rev-parse','HEAD')==a.expected_head
 env=os.environ.copy();env['LIBGL_ALWAYS_SOFTWARE']='1'
 gl=subprocess.run(['glxinfo','-B'],env=env,capture_output=True,text=True);(out/'glxinfo.txt').write_text(gl.stdout+gl.stderr)
 packages=subprocess.run(['dpkg-query','-W','libgl1-mesa-dri','libglx-mesa0','libllvm20','xvfb'],capture_output=True,text=True);(out/'packages.txt').write_text(packages.stdout+packages.stderr)
 binding={'verification_commit':a.expected_head,'verification_tree':git('rev-parse','HEAD^{tree}'),'targets':targets,'godot_member_sha256':sha(pathlib.Path(a.godot)),'helpers':{n:sha(HERE/n) for n in ['inputs.json','run.py','parity.gd','check_saved.gd']},'reference_run':37898956030,'runner_image':os.environ.get('ImageVersion'),'rows':[],'manifest_updated':False,'asset_replacement':False,'scope':'combined camera/FPS only'}
 def save():(out/'summary.json').write_text(json.dumps(binding,indent=2))
 save();assert gl.returncode==0 and '25.2.8' in gl.stdout and 'llvmpipe (LLVM 20.1.2, 256 bits)' in gl.stdout,'Canonical fingerprint mismatch'
 for label,item in targets.items():
  dest=out/label;dest.mkdir()
  with tempfile.TemporaryDirectory(prefix='tena-atlas-saveguard-') as temp:
   work=pathlib.Path(temp)/'source';subprocess.run(['git','fetch','--no-tags','origin',item['commit']],check=True);subprocess.run(['git','worktree','add','--detach',str(work),item['commit']],check=True)
   try:
    assert git('-C',str(work),'rev-parse','HEAD^{tree}')==item['tree']
    copy=pathlib.Path(temp)/'copy';shutil.copytree(work,copy,ignore=shutil.ignore_patterns('.git','.godot'))
    tracked=subprocess.check_output(['git','-C',str(work),'ls-files','-z']).decode().split('\0');inventory={n:sha(work/n) for n in tracked if n}
    (dest/'source-binding.json').write_text(json.dumps({'commit':item['commit'],'tree':item['tree'],'source_sha256':inventory},indent=2))
    project=copy/'game' if (copy/'game/project.godot').exists() else copy
    config=project/'project.godot';text=config.read_text().replace('[application]','[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="tena-atlas-saveguard"',1);config.write_text(text)
    helper=project/'qa/canonical_atlas';helper.mkdir(parents=True,exist_ok=True)
    for n in ['parity.gd','check_saved.gd']:shutil.copy2(HERE/n,helper/n)
    (helper/'parity.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://qa/canonical_atlas/parity.gd" id="1"]\n[node name="ZeroGameParity" type="Node"]\nscript=ExtResource("1")\n')
    env.update(XDG_DATA_HOME=str(pathlib.Path(temp)/'data'),XDG_CONFIG_HOME=str(pathlib.Path(temp)/'config'),LL_ATLAS_OUTPUT=str(dest),LL_ATLAS_SOURCE=item['commit'])
    assert native([a.godot,'--headless','--path',str(project),'--editor','--import'],env,dest/'import.log')==0
    code=native([a.godot,'--path',str(project),'--audio-driver','Dummy','--rendering-method','gl_compatibility','res://qa/canonical_atlas/parity.tscn'],env,dest/'native.log')
    receipt=json.loads((dest/'atlas-parity.json').read_text());log=(dest/'native.log').read_text()
    saved_code=native([a.godot,'--headless','--path',str(project),'--script','res://qa/canonical_atlas/check_saved.gd'],env,dest/'saved-png.log');saved=json.loads((dest/'saved-png-check.json').read_text())
    passed=receipt_passed(receipt,code) and receipt.get('source_commit')==item['commit'] and native_fingerprint_passed(log) and saved_code==0 and len(saved.get('rows',[]))==3 and not saved.get('failures',['missing'])
    binding['rows'].append({'label':label,**item,'passed':passed,'native_exit':code,'receipt_sha256':sha(dest/'atlas-parity.json'),'regenerated_rgba':receipt['baseline_sha256'],'imported_rgba':receipt['candidate_sha256']});save()
    assert passed,f'{label}: exact canonical equality failed; stop without changes'
    assert not git('-C',str(work),'status','--porcelain')
   finally:subprocess.run(['git','worktree','remove','--force',str(work)],check=True)
 assert not git('status','--porcelain')
if __name__=='__main__':main()
