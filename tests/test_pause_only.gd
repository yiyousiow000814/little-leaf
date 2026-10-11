extends SceneTree
## Isolated synthetic progress/preferences only. No existing profile is loaded.
const Settings=preload("res://scripts/cafe_settings.gd")
const WebPreferences=preload("res://scripts/cafe_web_preferences.gd")
const Model=preload("res://scripts/cafe_model.gd")
class TestMain extends "res://scripts/main.gd":
 var service_seconds=0.0
 var staff_seconds=0.0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _setup_music():pass
 func _save():return true
 func _tick_live_service(delta:float):
  service_seconds+=delta
  super(delta)
 func _animate_staff(delta:float):
  staff_seconds+=delta
  super(delta)
class TestSettings extends Settings:
 func _review_mode():return false
class BrowserApi extends RefCounted:
 var text=""
 var lastError=""
 func writeText(value):text=value;return true
class LocalMarker extends RefCounted:
 var localCallbacksAuthority=true
class HiddenAuthorityFixture extends RefCounted:
 var api=LocalMarker.new()
 var ready=true
 var platform_managed=false
 var recovery_busy=false
 var update_busy=false
 var retrying=false
 var bridge_present=false
 var snapshot={}
 func recovery_snapshot():return snapshot
 func _recovery_bridge():return api if bridge_present else null
var checks=0
var failures=[]
var game
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func snapshot():
 return JSON.stringify([game.paused,game.editing,game.model.operating_open,game.model.coins,game.model.served,game.model.payroll_elapsed,game.model.payroll_accrued,game.model.wages_due,game.model.total_wages_paid,game.model.customers,game._service_save_snapshot()])
func inspect_controls(node:Node):
 if node is Control:
  check(node.name!="SpeedSelector","no speed selector in scene tree")
  check(not "speed" in node.accessibility_name.to_lower() and not "speed" in node.accessibility_description.to_lower(),"no hidden speed accessibility route")
  if node is Button:check(node.text not in ["1×","2×","1x","2x"],"no speed button")
 for child in node.get_children():inspect_controls(child)
func _initialize():run.call_deferred()
func run():
 root.size=Vector2i(1360,880)
 game=TestMain.new();root.add_child(game);game.set_process(false)
 game.illustration.set_process(false)
 if game.cafe_intro!=null:game.cafe_intro.finish()
 game.compact_ui.viewport_too_small=false
 var settings=TestSettings.new();settings.game=game;settings.config_path="user://pause-only-preferences.cfg"
 var cfg=ConfigFile.new();cfg.set_value("play","speed",2);cfg.set_value("audio","bgm_enabled",false);cfg.set_value("audio","sfx_volume",37);cfg.set_value("display","frame_rate",120);cfg.set_value("updates","last_seen_version","0.1.10")
 check(cfg.save(settings.config_path)==OK,"synthetic legacy preferences created")
 var original=FileAccess.get_file_as_string(settings.config_path)
 game.model.payroll_elapsed=23.5;game.model.payroll_accrued=19.25;game.model.wages_due=7;game.model.total_wages_paid=91
 for paused in [false,true]:
  for opened in [false,true]:
   game.paused=paused;game.model.operating_open=opened
   var before=snapshot();settings.load_preferences()
   check(snapshot()==before,"legacy speed normalization preserves pause/admissions/progress")
   check(FileAccess.get_file_as_string(settings.config_path)==original,"load leaves original preference bytes unchanged")
 check(not settings.bgm_enabled and settings.sfx_volume==37 and settings.last_seen_update_version=="0.1.10","unrelated settings preserved")
 check(settings.frame_rate==60,"legacy 120 FPS preference migrates to supported 60 FPS")
 check(not settings.has_method("set_speed") and not game.get_property_list().any(func(p):return p.name=="speed"),"global speed mutation API removed")
 check(not settings.save_preferences() and FileAccess.get_file_as_string(settings.config_path)==original,"recovery/review progress write suppression respected")
 game.save_writes_suppressed=false
 var before=snapshot();check(settings.save_preferences(),"permitted preference save succeeds")
 check(snapshot()==before,"preference save never advances service or payroll")
 var saved=ConfigFile.new();check(saved.load(settings.config_path)==OK and saved.get_value("play","speed")==1,"legacy 2x canonicalized to 1x on save")
 check(saved.get_value("audio","sfx_volume")==37 and saved.get_value("updates","last_seen_version")=="0.1.10","canonical save retains unrelated preferences")
 check(saved.get_value("display","frame_rate")==60,"canonical save persists migrated 60 FPS cap")
 game.save_writes_suppressed=true
 var web=WebPreferences.new();web.api=BrowserApi.new();web.usable=true
 check(web.save_from(saved),"browser adapter accepts canonical preferences")
 var browser_cfg=ConfigFile.new();check(browser_cfg.parse(web.api.text)==OK and browser_cfg.get_value("play","speed")==1,"browser payload persists normal speed")
 var controls=game.compact_ui.play_controls
 check(controls.get_child_count()==1 and controls.get_child(0)==game.pause_button,"play controls contain Pause only")
 game._update_ui();await process_frame;await process_frame
 check(is_equal_approx(controls.size.x,44.0),"no empty former speed slot")
 inspect_controls(game.ui)
 game.pause_button.grab_focus();before=snapshot()
 for code in [KEY_LEFT,KEY_RIGHT,KEY_HOME,KEY_END,KEY_1,KEY_2]:
  for pressed in [true,false]:
   var event=InputEventKey.new();event.keycode=code;event.pressed=pressed;root.push_input(event,true)
 check(snapshot()==before,"former speed keys do not change play state")
 game.pause_button.grab_focus();var old_pause=game.paused
 for pressed in [true,false]:
  var event=InputEventKey.new();event.keycode=KEY_SPACE;event.pressed=pressed;root.push_input(event,true)
 check(game.paused!=old_pause,"keyboard activation toggles Pause/Resume")
 game._update_ui()
 check(game.pause_button.accessibility_name==("Resume service" if game.paused else "Pause service"),"Pause accessibility name tracks state")
 # All authoritative callbacks and payroll use one unscaled elapsed-time step.
 game.paused=false;game.model.operating_open=true;game.model.wages_due=0
 var service=game.service_seconds;var staff=game.staff_seconds;var payroll=game.model.payroll_elapsed
 game._process(.25)
 check(is_equal_approx(game.service_seconds-service,.25) and is_equal_approx(game.staff_seconds-staff,.25),"live service and staff receive normal delta once")
 check(is_equal_approx(game.model.payroll_elapsed-payroll,.25),"payroll advances only normal elapsed time")
 for gate in ["paused","editing","save_recovery_blocked","browser_suspended"]:
  game.set(gate,true);before=snapshot();service=game.service_seconds;staff=game.staff_seconds
  game._process(2.0)
  check(snapshot()==before and game.service_seconds==service and game.staff_seconds==staff,"blocked time cannot advance work or payroll: "+gate)
  game.set(gate,false)
 game._resume_frame=Engine.get_process_frames()+1;before=snapshot();game._process(300)
 check(snapshot()==before,"resume frame cannot apply background time")
 # 10a hidden candidate: synthetic economy only; no original saves.
 game.paused=false;game.model.operating_open=true
 var mode=game.process_mode
 game.set_browser_hidden(true)
 check(game.process_mode==mode and not game.paused,"hide does not disable subtree or press Pause")
 var boundary=game._resume_frame
 game.set_browser_hidden(true)
 check(game._resume_frame==boundary,"duplicate hide leaves boundary unchanged")
 game._resume_frame=-1;game._hidden_local_callbacks=true
 service=game.service_seconds;staff=game.staff_seconds;payroll=game.model.payroll_elapsed
 game._process(.1)
 check(is_equal_approx(game.service_seconds-service,.1) and is_equal_approx(game.staff_seconds-staff,.1) and is_equal_approx(game.model.payroll_elapsed-payroll,.1),"hidden guest service/staff/payroll exactly once")
 service=game.service_seconds;payroll=game.model.payroll_elapsed
 game._process(3600)
 check(game.service_seconds==service and game.model.payroll_elapsed==payroll,"throttled hidden gap earns no payroll or service")
 for gate in ["paused","editing","save_recovery_blocked"]:
  game.set(gate,true);payroll=game.model.payroll_elapsed
  game._process(.1)
  check(game.model.payroll_elapsed==payroll,"hidden callback retains safety gate: "+gate)
  game.set(gate,false)
 game._hidden_local_callbacks=false;payroll=game.model.payroll_elapsed
 game._process(.1)
 check(game.model.payroll_elapsed==payroll,"cloud/unknown hidden callback earns nothing")
 game.paused=true;game.set_browser_hidden(false)
 boundary=game._resume_frame;game.set_browser_hidden(false)
 check(game.paused and game._resume_frame==boundary,"duplicate visible preserves manual Pause and return boundary")
 game._process(3600)
 check(game.model.payroll_elapsed==payroll,"return frame cannot replay hidden economy")
 # Resolve adapter markers against live observations; no bridge/network I/O.
 var original_web_save=game.web_save
 var authority=HiddenAuthorityFixture.new();game.web_save=authority
 check(game._hidden_callbacks_eligible(),"bridge-free explicit local marker eligible")
 authority.bridge_present=true
 check(not game._hidden_callbacks_eligible(),"local marker cannot override missing live observation")
 for observation in [{"serverOwnership":true,"status":"active"},{"serverOwnership":false,"accountChanged":true},{"serverOwnership":false,"choicesAvailable":true},{"serverOwnership":false,"busy":true}]:
  authority.snapshot=observation
  check(not game._hidden_callbacks_eligible(),"local marker cannot override safety observation: "+str(observation))
 authority.snapshot={"serverOwnership":false}
 check(game._hidden_callbacks_eligible(),"explicit current guest observation eligible")
 for gate in ["ready","platform_managed","recovery_busy","update_busy","retrying"]:
  authority.set(gate,gate!="ready")
  check(not game._hidden_callbacks_eligible(),"adapter transition fails closed: "+gate)
  authority.set(gate,gate=="ready")
 game.web_save=original_web_save
 game.set_browser_hidden(true);game.set_browser_suspended(true)
 check(game.process_mode==Node.PROCESS_MODE_DISABLED and game.paused,"pagehide still suspends and preserves manual Pause")
 game.set_browser_hidden(false)
 check(game.process_mode==Node.PROCESS_MODE_DISABLED,"visibility alone cannot restore pagehide process mode")
 game.set_browser_suspended(false)
 check(game.process_mode==mode and game.paused,"pageshow restores original process mode and preserves Pause")
 game._resume_frame=-1;game.paused=true;game.model.operating_open=false
 for level in [1,2,3]:
  var multiplier=Model.stove_speed_multiplier({"level":level})
  check(is_equal_approx(multiplier,1.0+.4*(level-1)) and is_equal_approx(Model.cooking_seconds(multiplier),45.0/multiplier),"stove upgrade retains recipe-only multiplier")
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 print("PAUSE_ONLY_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
