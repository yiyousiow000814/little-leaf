extends SceneTree
## Native GL captures of the real HUD. No original save is loaded or written.
class TestMain extends "res://scripts/main.gd":
 var saves=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():saves+=1;return true
var game
var records=[]
func _initialize():run.call_deferred()
func rect_data(control:Control):
 var r=control.get_global_rect()
 return {"x":r.position.x,"y":r.position.y,"w":r.size.x,"h":r.size.y}
func run():
 seed(8246)
 game=TestMain.new();root.add_child(game);game.set_process(false);game.paused=true
 await process_frame
 var hud=game.compact_ui.hud
 for view in [Vector2i(1360,880),Vector2i(800,600),Vector2i(390,844)]:
  root.size=view
  for editing in [false,true]:
   game.editing=editing;game._update_ui();game.illustration.queue_redraw()
   for frame in 6:await process_frame
   await RenderingServer.frame_post_draw
   var label="%dx%d-%s"%[view.x,view.y,"edit" if editing else "play"]
   var output=OS.get_environment("OUTPUT")+"/"+OS.get_environment("PHASE")+"-"+label
   var shot=root.get_texture().get_image();shot.save_png(output+".png")
   var crop_height=150 if view.x<566 else 116
   shot.get_region(Rect2i(0,0,view.x,crop_height)).save_png(output+"-toolbar.png")
   records.append({"label":label,"decorate_art":rect_data(hud.action_art.decorate),"staff_art":rect_data(hud.action_art.staff),"settings_art":rect_data(hud.action_art.settings),"decorate_target":rect_data(game.edit_button),"staff_target":rect_data(game.compact_ui.staff_access),"settings_target":rect_data(game.compact_ui.settings_button),"save_writes":game.saves,"save_writes_suppressed":game.save_writes_suppressed})
 FileAccess.open(OS.get_environment("OUTPUT")+"/"+OS.get_environment("PHASE")+"-geometry.json",FileAccess.WRITE).store_string(JSON.stringify(records,"  "))
 print("HUD_OPTICAL_CAPTURE ",JSON.stringify(records))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;await create_timer(.1).timeout;quit()
