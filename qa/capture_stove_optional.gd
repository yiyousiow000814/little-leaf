extends SceneTree
class TestMain extends "res://scripts/main.gd":
 var saves=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():saves+=1;return true
var game
var rows=[]
func _initialize():run.call_deferred()
func capture(label):
 game.toast_lifetime=0;game._process(0);game._update_ui();game.illustration.queue_redraw()
 for frame in 5:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(OS.get_environment("OUTPUT")+"/"+OS.get_environment("PHASE")+"-"+label+"-1360x880.png")
 rows.append({"label":label,"editing":game.editing,"warning":game._service_warning(),"issue":game.workface_guidance.access_message(),"chef_action":game.staff_states[0].art_action,"chef_reason":game.staff_states[0].art_block_reason,"saves":game.saves})
func run():
 root.size=Vector2i(1360,880);game=TestMain.new();root.add_child(game);game.set_process(false)
 await process_frame
 game.model.coins=100000;game.model.operating_open=true;game.model._arrival_elapsed=-1000000
 var stove={}
 for item in game.model.items:
  if item.kind=="stove":stove=item;break
 var face=game.model.workface_cell(stove)
 # Deliberately blocked synthetic layout, identical on both code versions.
 # Direct fixture construction avoids relying on the old prohibition.
 game.model.items.append({"id":game.model._next_item_id,"kind":"plant","x":face.x,"z":face.y,"rot":0});game.model._next_item_id+=1;game.model._notify()
 game._rebuild_furniture();game.illustration.zoom=1;game.illustration.pan_offset=Vector2.ZERO;game.illustration.update_projection()
 game._toggle_edit();await capture("decorate-blocked")
 game._toggle_edit()
 for step in 90:game._animate_staff(1.0/30.0);game.animation_time+=1.0/30.0
 await capture("play-blocked")
 FileAccess.open(OS.get_environment("OUTPUT")+"/"+OS.get_environment("PHASE")+"-capture.json",FileAccess.WRITE).store_string(JSON.stringify(rows,"  "))
 print("STOVE_NATIVE_CAPTURE ",JSON.stringify(rows))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;await create_timer(.15).timeout;quit()
