extends SceneTree
## Generated preferences and cafe only; the optional display never owns progress.
const Settings=preload("res://scripts/ui/cafe_settings.gd")
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
func click(button:Button):
 await settle()
 var point=button.get_global_rect().get_center()
 var motion=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;root.push_input(motion,true)
 for pressed in [true,false]:
  var event=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
  await process_frame
 await settle()
func check_help_save_spacing():
 var ui=game.compact_ui
 var initial_unsaved=game.progress_unsaved;var initial_error=game.progress_save_error;var initial_view=root.size
 for view in [Vector2i(1360,880),Vector2i(390,844),Vector2i(844,390)]:
  root.size=view
  for error in ["","Synthetic save failure",""]:
   game.progress_unsaved=true;game.progress_save_error=error
   game.settings.show();ui.settings_help.pressed.emit();await settle()
   var message=game._unsaved_progress_message()
   check(ui.help_text.text.begins_with("View:" if error=="" else message+"\n\nView:"),"Help pending text has no empty paragraph and retains real errors "+str(view)+" "+error)
   if error=="":
    var first_line=Rect2(ui.help_text.get_global_rect().position,Vector2(ui.help_text.size.x,ui.help_text.get_line_height()))
    check(ui.help_scroll.get_global_rect().encloses(first_line),"View first line remains visible without scrolling "+str(view))
    check(ui.help_stats_row.get_global_rect().size.y>=44 and ui.help_scroll.scroll_vertical==0,"Pending help preserves stats touch height and initial scroll "+str(view))
  game.progress_unsaved=false;await settle()
  check(ui.help_text.text.begins_with("View:"),"Settled help keeps instructions without save details "+str(view))
 game.progress_unsaved=initial_unsaved;game.progress_save_error=initial_error;root.size=initial_view
 game.settings.show();ui.settings_help.pressed.emit();await settle()
func run():
 root.size=Vector2i(390,844)
 game=TestMain.new();root.add_child(game);game.set_process(false);game.paused=true
 await settle()
 var settings=game.settings_controls;var ui=game.compact_ui;var hud=ui.hud
 check(not settings.show_stats and not hud.stats_label.visible and hud.stats_timer.is_stopped(),"default off has no sampling timer")
 game.settings.show();ui.settings_help.pressed.emit();await settle()
 check(ui.help_panel.visible and not game.settings.visible and ui.help_panel.is_ancestor_of(settings.stats_toggle),"Show stats belongs to Settings Help")
 check(settings.stats_toggle.text=="Off" and settings.stats_toggle.size.y>=44,"default-off Help toggle is a readable touch target")
 check(ui.help_scroll.get_global_rect().encloses(settings.stats_toggle.get_global_rect()),"Help toggle is visible without scrolling")
 await check_help_save_spacing()
 await capture("help-stats-off-390x844")
 ui.help_scroll.grab_focus();var tab=InputEventKey.new();tab.keycode=KEY_TAB;tab.pressed=true
 ui._help_tab(tab);check(root.gui_get_focus_owner()==settings.stats_toggle,"Help Tab navigation reaches stats")
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
  settings.set_frame_rate(rate);await click(settings.stats_toggle)
  check(settings.show_stats and hud.stats_label.visible and not hud.stats_timer.is_stopped(),"button enables display")
  check(Engine.max_fps==rate and settings.frame_rate_choice.get_selected_id()==rate,"stats leaves selected cap unchanged")
  hud.stats_label.text="waiting for sample"
  await create_timer(1.1).timeout
  check(hud.stats_label.text!="waiting for sample","timer refreshes the live display")
  hud._update_stats();check(hud.stats_label.text=="%d FPS"%Engine.get_frames_per_second(),"display uses actual measured FPS")
  await click(settings.stats_toggle)
  check(not settings.show_stats and not hud.stats_label.visible and hud.stats_timer.is_stopped(),"button disables display and sampling")
  check(hud.stats_timer.get_instance_id()==timer_id,"repeated toggle reuses one timer")
 settings.set_show_stats(true);await create_timer(1.1).timeout
 root.size=Vector2i(566,360);await settle()
 check(ui.help_scroll.get_global_rect().encloses(settings.stats_toggle.get_global_rect()),"short landscape keeps Help toggle inside its scroll viewport")
 check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(ui.help_close.get_global_rect()),"Help fixed X remains in bounds")
 await capture("help-stats-on-566x360")
 ui._close_help();await settle()
 check(game.settings.visible and root.gui_get_focus_owner()==ui.settings_help,"closing Help preserves Settings return focus")
 game.settings.hide()
 for view in [Vector2i(390,844),Vector2i(568,360)]:
  root.size=view;await settle()
  check(Rect2(Vector2.ZERO,Vector2(view)).encloses(hud.stats_label.get_global_rect()),"stats stays inside viewport "+str(view))
  check(hud.stats_label.mouse_filter==Control.MOUSE_FILTER_IGNORE,"stats does not intercept gameplay input")
  if view.x==390:await capture("live-fps-390x844")
 check(game.saves==0 and progress_snapshot()==original,"display does not save or mutate progress")
 var label_ref=weakref(hud.stats_label);var timer_ref=weakref(hud.stats_timer)
 for player in game.audio_players.values():player.stop();player.stream=null
 settings.sfx_player.stop();settings.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame
 check(label_ref.get_ref()==null and timer_ref.get_ref()==null,"scene teardown releases display and timer")
 print("SHOW_STATS_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 quit(0 if failures.is_empty() else 1)
