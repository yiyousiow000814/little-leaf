extends SceneTree
const Main=preload("res://scripts/main.gd")
const Settings=preload("res://scripts/cafe_settings.gd")
const WebSave=preload("res://scripts/cafe_web_save.gd")
class TestSettings extends Settings:
 var writes=0
 func _review_mode():return false
 func save_preferences():
  writes+=1
  return super.save_preferences()
class QuietMain extends Main:
 var stepped=0.0
 func _ready():
  for node in [world,furnishings,people,camera,ui]:add_child(node)
 func _process(delta):stepped+=effective_frame_delta(delta)
class SyntheticMain extends Main:
 func _load_startup():
  save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _setup_music():pass
 func _save():return true
class Music extends RefCounted:
 var playing=true
 var stops=0
 func get_playback_position():return 12.5
 func stop():playing=false;stops+=1
class Model extends RefCounted:
 var last_error=""
 var last_event=""
 var service_snapshot={}
 var coins=1200
 var payload="synthetic one"
 var validations=0
 var save_ok=true
 func save(path):
  validations+=1
  if not save_ok:last_error="Invalid state";return false
  FileAccess.open(path,FileAccess.WRITE).store_string(payload);return true
class Api extends RefCounted:
 var credit=0
 var writes=0
 var storageKind="indexeddb"
 func creditForSave(_payload):return credit
 func save(_payload,_revision,_profile,_callback):writes+=1
class Game extends Node:
 var background_elapsed=null
 var model=Model.new()
 var save_timer=0.0
 var save_recovery_blocked=false
 var save_writes_suppressed=false
 var progress_unsaved=false
 var progress_save_error=""
 var startup_notice=""
 var paused=false
 var web_lifecycle=null
 func _update_people():pass
 func _service_save_snapshot():return {}
 func _update_ui():pass
 func _save():pass
var checks=0
var failures=[]
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func ack(save,success=true):
 save._on_commit([JSON.stringify({"ok":true,"profileId":"test","revision":save.revision+1,"durable":true,"creditedCoins":0} if success else {"ok":false,"error":"Synthetic write failure","code":"QUOTA"})])
func _init():run.call_deferred()
func run():
 var previous_fps=Engine.max_fps
 var settings=TestSettings.new()
 settings.config_path="user://performance-preferences.cfg"
 check(settings.frame_rate==60 and Engine.max_fps==60,"missing frame preference defaults to sixty")
 settings.set_frame_rate(30)
 check(Engine.max_fps==30 and settings.frame_rate==30,"explicit thirty is applied")
 settings.frame_rate=60;settings.load_preferences()
 check(settings.frame_rate==30,"frame preference survives save/reload")
 settings.set_frame_rate(999)
 check(settings.frame_rate==60 and Engine.max_fps==60,"invalid frame rate falls back to sixty")
 var cfg=ConfigFile.new()
 cfg.set_value("display","frame_rate",120);cfg.save(settings.config_path)
 settings.load_preferences()
 check(settings.frame_rate==60 and Engine.max_fps==60,"legacy one-twenty preference becomes sixty")
 cfg=ConfigFile.new();cfg.set_value("audio","bgm_enabled",false);cfg.save(settings.config_path)
 settings.load_preferences()
 check(settings.frame_rate==60 and not settings.bgm_enabled,"old preferences retain audio and default to sixty")
 settings.preference_timer=Timer.new();settings.preference_timer.one_shot=true;settings.preference_timer.wait_time=.2
 root.add_child(settings.preference_timer);settings.preference_timer.timeout.connect(settings.flush_preferences)
 settings.writes=0
 for n in 100:settings.set_audio_volume("BGM",n)
 check(settings.writes==0 and settings.preferences_dirty,"slider changes apply immediately without synchronous write per event")
 settings.flush_preferences()
 check(settings.writes==1 and not settings.preferences_dirty,"one flush stores final slider value")
 settings.preference_timer.free()
 var game=QuietMain.new();root.add_child(game)
 game.paused=true;game.process_mode=Node.PROCESS_MODE_ALWAYS
 game.set_browser_suspended(true)
 check(game.browser_suspended and game.process_mode==Node.PROCESS_MODE_DISABLED and game.paused,"hidden disables subtree without changing user pause")
 check(game.effective_frame_delta(300)==0,"hidden time discarded")
 var stepped=game.stepped
 await process_frame;await process_frame
 check(game.stepped==stepped,"hidden controller does no processing")
 game.set_browser_suspended(false)
 check(game.process_mode==Node.PROCESS_MODE_ALWAYS and game.paused,"resume restores exact process mode and user pause")
 check(game.effective_frame_delta(300)==0,"resume delta discarded")
 await process_frame;await process_frame;await process_frame
 check(game.effective_frame_delta(.125)==.125,"ordinary delta retained after resume")
 game.music_state="busy";game.audio_players={"service":Music.new(),"busy":Music.new()}
 game._finish_music_crossfade("service")
 check(game.audio_players.busy.stops==0 and game.audio_players.service.stops==0,"stale fade cannot stop new music")
 game._finish_music_crossfade("busy")
 check(game.audio_players.service.stops==1 and game.audio_players.busy.stops==0,"completed fade stops only inaudible outgoing track")
 check(game.music_positions.service==12.5,"outgoing playback position retained")
 game.audio_players.clear();game.free()
 var fake=Game.new();root.add_child(fake)
 var save=WebSave.new(fake);save.api=Api.new();save.ready=true;save.profile_id="test"
 save.request_save(true);ack(save)
 check(save.api.writes==1 and not fake.progress_unsaved,"first periodic save is durable")
 for n in 100:save.request_save(true)
 check(save.api.writes==1 and fake.model.validations==101 and not fake.progress_unsaved,"one hundred identical periodic saves validate but do not rewrite authority")
 save.request_save();ack(save)
 check(save.api.writes==2,"explicit/hide saves still commit unchanged payload")
 fake.model.payload="synthetic changed";save.request_save(true)
 check(save.api.writes==3 and fake.progress_unsaved,"changed payload still writes")
 ack(save,false);save.request_save(true)
 check(save.api.writes==4 and fake.progress_save_error!="","failed writes retry with warning preserved")
 ack(save)
 fake.model.save_ok=false;save.request_save(true)
 check(save.api.writes==4 and fake.progress_save_error=="Invalid state","unchanged payload never bypasses full model validation")
 fake.model.save_ok=true;save.request_save(true);ack(save)
 save.platform_managed=true;save.request_save(true)
 check(save.api.writes==6,"platform cadence is not deduplicated by ordinary Web optimization")
 ack(save);save.platform_managed=false;save.api.credit=3
 save.request_save(true)
 check(save.api.writes==7 and save.pending,"new compensation forces submission even for identical validated payload")
 save._on_commit([JSON.stringify({"ok":true,"profileId":"test","revision":save.revision+1,"durable":true,"creditedCoins":3})])
 check(fake.model.coins==1203 and not fake.paused,"compensation settles and releases hold")
 fake.free()
 var real=SyntheticMain.new();root.add_child(real);real.set_process(false);real.paused=true;real.save_writes_suppressed=false
 if real.cafe_intro!=null:real.cafe_intro.finish()
 var real_save=WebSave.new(real);real_save.api=Api.new();real_save.ready=true;real_save.profile_id="test"
 real_save.request_save(true);ack(real_save)
 var validated_payload=real_save._confirmed_payload
 check(validated_payload!="" and JSON.parse_string(validated_payload) is Dictionary,"actual runtime serializer produces validated save")
 real_save.request_save(true)
 check(real_save.api.writes==1 and not real_save.pending,"unchanged paused real-model snapshot skips periodic authority write")
 real.animation_time+=.5;real_save.request_save(true)
 check(real_save.api.writes==2 and real_save.pending,"actual serialized runtime changes cannot deduplicate")
 ack(real_save);real.model.coins-=1;real_save.request_save(true)
 check(real_save.api.writes==3 and real_save.pending,"actual wallet changes cannot deduplicate")
 ack(real_save)
 real.queue_free();await process_frame
 Engine.max_fps=previous_fps
 print("WEB_PERFORMANCE_RESULT "+JSON.stringify({"checks":checks,"failures":failures,"scope":"synthetic controller/settings/lifecycle; no browser or thermal claim"}))
 quit(0 if failures.is_empty() else 1)
