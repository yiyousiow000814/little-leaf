extends SceneTree
## Generated preferences and cafe only; the optional display never owns progress.
const Settings=preload("res://scripts/cafe_settings.gd")
class TestMain extends "res://scripts/main.gd":
 var saves=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():saves+=1;return true
class TestSettings extends Settings:
 func _review_mode():return false
var game
var checks=0
var failures=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func progress_snapshot():return JSON.stringify([game.model.coins,game.model.items,game.model.customers,game.model.served,game.model.payroll_elapsed,game._service_save_snapshot()])
func settle():
 game._update_ui()
 for frame in 5:await process_frame
func capture(name:String):
 if DisplayServer.get_name()=="headless" or OS.get_environment("OUTPUT")=="":return
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(OS.get_environment("OUTPUT")+"/"+name+".png")
func run():
 root.size=Vector2i(390,844)
 game=TestMain.new();root.add_child(game);game.set_process(false);game.paused=true
 await settle()
 var settings=game.settings_controls;var hud=game.compact_ui.hud
 check(not settings.show_stats and not hud.stats_label.visible and hud.stats_timer.is_stopped(),"default off has no sampling timer")
 var prefs=TestSettings.new();prefs.config_path="user://show-stats-generated.cfg"
 var cfg=ConfigFile.new();cfg.set_value("display","frame_rate",30);cfg.save(prefs.config_path);prefs.load_preferences()
 check(not prefs.show_stats and prefs.frame_rate==30,"legacy preferences default stats off and retain cap")
 prefs.set_show_stats(true)
 var saved=ConfigFile.new();saved.load(prefs.config_path)
 check(saved.get_value("display","show_stats")==true and saved.get_value("display","frame_rate")==30,"preference save stores stats independently")
 prefs.show_stats=false;prefs.load_preferences();check(prefs.show_stats,"enabled preference reloads")
 cfg.set_value("display","show_stats","invalid");cfg.save(prefs.config_path);prefs.load_preferences()
 check(not prefs.show_stats,"invalid preference fails closed")
 var original=progress_snapshot();var timer_id=hud.stats_timer.get_instance_id()
 for rate in [30,60]:
  settings.set_frame_rate(rate);settings.stats_toggle.pressed.emit();await settle()
  check(settings.show_stats and hud.stats_label.visible and not hud.stats_timer.is_stopped(),"button enables display")
  check(Engine.max_fps==rate and settings.frame_rate_choice.get_selected_id()==rate,"stats leaves selected cap unchanged")
  hud.stats_label.text="waiting for sample"
  await create_timer(1.1).timeout
  check(hud.stats_label.text!="waiting for sample","timer refreshes the live display")
  hud._update_stats();check(hud.stats_label.text=="%d FPS"%Engine.get_frames_per_second(),"display uses actual measured FPS")
  settings.stats_toggle.pressed.emit();await settle()
  check(not settings.show_stats and not hud.stats_label.visible and hud.stats_timer.is_stopped(),"button disables display and sampling")
  check(hud.stats_timer.get_instance_id()==timer_id,"repeated toggle reuses one timer")
 settings.set_show_stats(true);await create_timer(1.1).timeout
 game.settings.show();await settle();await capture("settings-stats-on-390x844")
 game.settings.hide()
 for view in [Vector2i(390,844),Vector2i(568,360)]:
  root.size=view;await settle()
  check(Rect2(Vector2.ZERO,Vector2(view)).encloses(hud.stats_label.get_global_rect()),"stats stays inside viewport "+str(view))
  check(hud.stats_label.mouse_filter==Control.MOUSE_FILTER_IGNORE,"stats does not intercept gameplay input")
  await capture("live-fps-"+str(view.x)+"x"+str(view.y))
 check(game.saves==0 and progress_snapshot()==original,"display does not save or mutate progress")
 var label_ref=weakref(hud.stats_label);var timer_ref=weakref(hud.stats_timer)
 for player in game.audio_players.values():player.stop();player.stream=null
 settings.sfx_player.stop();settings.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame
 check(label_ref.get_ref()==null and timer_ref.get_ref()==null,"scene teardown releases display and timer")
 print("SHOW_STATS_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 quit(0 if failures.is_empty() else 1)
