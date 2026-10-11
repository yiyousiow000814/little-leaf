import ast,hashlib,json,os,subprocess,sys,time
from pathlib import Path
repo=Path(__file__).resolve().parents[2];out=Path(os.environ['BINDING_WEB_OUTPUT']).resolve();out.mkdir()
sys.path.insert(0,str(repo/'tools'))
from project_layout import stage_project
from optimize_web_present import optimize_presentation
from bound_web_gl_handles import bound_web_gl_handles
project=out/'project';stage_project(repo,project,tests=True,ignore=__import__('shutil').ignore_patterns('.godot','__pycache__'))
web=out/'web';web.mkdir()
template=Path(os.environ['GODOT_WEB_TEMPLATE'])
assert hashlib.sha256(template.read_bytes()).hexdigest()=='1446f79dc12f60ce5d244c39fb6628ec298337ca5c4f91a16491feea72aa1bc9'
(project/'export_templates').mkdir();(project/'export_templates/web_nothreads_release.zip').write_bytes(template.read_bytes())
probe='''extends Node
var callback
func _ready():
 if not OS.has_feature("web"):return
 callback=JavaScriptBridge.create_callback(_query)
 JavaScriptBridge.get_interface("window").__bindingProbe=callback
func _query(args:Array):
 var game=get_tree().current_scene
 if game==null or game.web_save==null:return
 var action=str(args[0]) if not args.is_empty() else "state"
 if action=="fixture":
  if game.cafe_intro!=null and game.cafe_intro.active:game.cafe_intro.finish()
  game.model.first_guest_pending=false;game.model.operating_open=false;game.paused=false
  game.setup_dirty();game.web_save.request_save()
 elif action=="settings":game.settings.show();game._update_ui()
 elif action=="pause":game.paused=true
 var cloud=game.settings_controls.cloud_settings
 var binding=cloud.binding if cloud!=null else null
 var rect=cloud.bind_button.get_global_rect() if cloud!=null and cloud.bind_button!=null else Rect2()
 var value={"ready":game.web_save.ready,"pending":game.web_save.pending,"revision":game.web_save.revision,"profileId":game.web_save.profile_id,"coins":game.model.coins,"paused":game.paused,"input":game.is_processing_input(),"guiHeld":game.get_viewport().gui_disable_input,"bindingActive":binding!=null and binding.active,"bindingFrozen":binding!=null and binding.frozen,"backgroundPhase":game.background_elapsed.phase,"error":game.progress_save_error,"button":{"x":rect.position.x+rect.size.x/2,"y":rect.position.y+rect.size.y/2}}
 JavaScriptBridge.get_interface("window").__bindingState=JSON.stringify(value)
'''
(project/'binding_probe.gd').write_text(probe,encoding='utf-8')
p=project/'project.godot';code=p.read_text(encoding='utf-8');code+='\n[autoload]\nBindingProbe="*res://binding_probe.gd"\n';p.write_text(code,encoding='utf-8')
env=os.environ.copy()
for key in ['APPDATA','LOCALAPPDATA','XDG_DATA_HOME','XDG_CONFIG_HOME','XDG_CACHE_HOME']:env[key]=str(out/'synthetic-profile')
exe=os.environ['GODOT_BIN']
records=[]
def run(label,args):
 t=time.monotonic()
 with (out/(label+'.log')).open('wb') as log:r=subprocess.run([exe,'--audio-driver','Dummy','--path',str(project),*args],env=env,stdout=log,stderr=subprocess.STDOUT,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0),timeout=180)
 records.append({'phase':label,'exit':r.returncode,'seconds':round(time.monotonic()-t,2)});print(records[-1],flush=True)
 if r.returncode:raise SystemExit(r.returncode)
run('import',['--headless','--editor','--import','--quit'])
run('export',['--headless','--export-release','Web',str(web/'index.html')])
patches=[optimize_presentation(web/'index.js'),bound_web_gl_handles(web/'index.js')]
head=subprocess.check_output(['git','-c','safe.directory='+str(repo),'-C',str(repo),'rev-parse','HEAD'],text=True).strip()
(out/'export-receipt.json').write_text(json.dumps({'source_head':head,'scope':'diagnostic QA export, explicit state/control autoload; not release-qualified','records':records,'probe_sha256':hashlib.sha256(probe.encode()).hexdigest(),'template_sha256':hashlib.sha256(template.read_bytes()).hexdigest(),'patches':patches,'files':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in web.iterdir() if p.is_file()}},indent=2),encoding='utf-8')
