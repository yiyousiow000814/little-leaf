extends SceneTree
## Real frame-rate option control, generated cafe, no player preferences/saves.
class TestMain extends "res://scripts/main.gd":
 var saves=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():saves+=1;return true
var game
var checks=0
var failures=[]
var geometry=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func settle():
 game._update_ui()
 for frame in 5:await process_frame
func run():
 game=TestMain.new();root.add_child(game);game.set_process(false);game.paused=true
 await process_frame
 var settings=game.settings_controls;var choice=settings.frame_rate_choice
 var file_existed=FileAccess.file_exists(settings.config_path)
 for view in [Vector2i(1360,880),Vector2i(960,540),Vector2i(566,360),Vector2i(390,844),Vector2i(344,680),Vector2i(844,390)]:
  root.size=view;game.settings.show();await settle()
  for record in game.compact_ui.themed_popups:
   if record.panel==game.settings:record.scroll.ensure_control_visible(choice)
  await settle()
  for rate in [60,30,60]:
   settings.set_frame_rate(rate);await settle()
   var label="%s %d FPS"%[str(view),rate]
   var font=choice.get_theme_font("font");var font_size=choice.get_theme_font_size("font_size")
   var text_width=font.get_string_size(choice.text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
   var arrow_width=choice.get_theme_icon("arrow").get_width()
   var gap=choice.get_theme_constant("h_separation")
   var left=(choice.size.x-text_width-arrow_width-gap)*.5
   var right=float(choice.get_theme_constant("arrow_margin"))
   var arrow_left=choice.size.x-right-arrow_width
   check(choice.alignment==HORIZONTAL_ALIGNMENT_CENTER,label+" label centered beside native arrow")
   check(choice.size==Vector2(112,44),label+" original 112 by 44 control preserved")
   check(left>=14 and right>=14,label+" both ends safely inset from painted border")
   check(absf(left-right)<=.5,label+" text and arrow group has balanced outer margins")
   check(absf(arrow_left-left-text_width-8)<=.5,label+" readable eight pixel text/arrow gap")
   check(choice.text=="%d FPS"%rate and choice.get_selected_id()==rate and Engine.max_fps==rate,label+" selection and frame rate still work")
   check(game.settings.get_global_rect().encloses(choice.get_global_rect()),label+" selector stays inside Settings")
   geometry.append({"viewport":str(view),"text":choice.text,"width":choice.size.x,"font_size":font_size,"text_width":text_width,"left_inset":left,"right_inset":right,"gap":arrow_left-left-text_width})
  # Use the real popup's signal route to change each option, retaining keyboard support.
  choice.get_popup().index_pressed.emit(1);await settle()
  check(settings.frame_rate==60 and choice.get_selected_id()==60,str(view)+" native menu selection routes to60")
  choice.get_popup().index_pressed.emit(0);await settle()
  check(settings.frame_rate==30 and choice.get_selected_id()==30,str(view)+" repeated native selection routes back to30")
 check(game.saves==0 and game.save_writes_suppressed,"no gameplay save writes")
 check(FileAccess.file_exists(settings.config_path)==file_existed,"no preference file created")
 print("FRAME_RATE_ALIGNMENT_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"geometry":geometry}))
 for player in game.audio_players.values():player.stop();player.stream=null
 settings.sfx_player.stop();settings.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
