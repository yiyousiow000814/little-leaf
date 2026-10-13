extends SceneTree
## Generated frozen-review restaurant only. Never load or write a player save.
class GeneratedMain extends "res://scripts/main.gd":
 var save_calls=0
 func _load_startup():
  save_writes_suppressed=true;fresh_start=true;paused=true;MinimalStart.apply(model)
 func _save():save_calls+=1;return true
var game
var records=[]
func _initialize():run.call_deferred()
func snapshot():return JSON.stringify({"items":game.model.items,"guests":game.model.customers,"service":game._service_save_snapshot(),"coins":game.model.coins})
func capture(label:String,chair:Dictionary,guest:Dictionary,occupied:bool):
 var a=game.illustration
 var state=snapshot()
 game._update_ui();a.queue_redraw()
 for frame in 5:await process_frame
 await RenderingServer.frame_post_draw
 assert(snapshot()==state)
 var path=OS.get_environment("OUTPUT")+"/"+label+".png"
 assert(root.get_texture().get_image().save_png(path)==OK)
 var position=a.iso(chair.x+.5,chair.z+.5)
 records.append({"label":label,"file":path,"occupied":occupied,"chair_position":str(position),"rotation":a._chair_rotation(chair),"scale":a.ui_scale*a.zoom*(1.55 if game.wall_detail else 1.0),"diner_render":str(a._render_position("guest_%s"%guest.id,Vector2(guest.x,guest.z))) if occupied else "none","save_calls":game.save_calls})
func run():
 seed(472);root.size=Vector2i(1360,880)
 assert(OS.get_environment("OUTPUT")!="")
 assert(DisplayServer.get_name()!="headless")
 DisplayServer.window_set_title("Little Leaf chair ground contact review")
 game=GeneratedMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false)
 if game.cafe_intro!=null:game.cafe_intro.finish()
 game.model._spawn_customer();game.model.operating_open=false
 var guest=game.model.customers[0]
 var chair=game.model.get_item(int(guest.chair_id));var table=game.model.get_item(int(guest.table_id))
 table.x=4;table.z=4
 var forwards=[Vector2.UP,Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT]
 for rotation in range(4):
  var forward:Vector2=forwards[rotation]
  chair.x=int(table.x-forward.x);chair.z=int(table.z-forward.y);chair.rot=rotation
  game.model.rebuild_dining_sets()
  guest.x=float(chair.x)+.5;guest.z=float(chair.z)+.5;guest.heading=forward;guest.phase="ordering";guest.seated=true;guest.admitted=true;guest.dismounting=false
  guest.route=[];guest.route_index=0;guest.elapsed=0.0;guest.duration=game.model.PHASE_SECONDS.ordering
  for occupied in [false,true]:
   game.model.customers.clear()
   if occupied:game.model.customers.append(guest)
   game._sync_service_guests();game._update_people()
   var a=game.illustration
   a.motion=a.MotionArt.new();a.seat_blends.clear();a.stance_offsets.clear();a.character_facings.clear()
   game.paused=false
   for frame in 20:a.update_motion(.05)
   game.paused=true
   a.zoom=2.2;a.pan_offset=Vector2.ZERO;a.update_projection()
   a.pan_offset+=Vector2(680,560)-a.iso(chair.x+.5,chair.z+.5);a.update_projection()
   await capture("rotation-%s-%s"%[rotation,"occupied" if occupied else "empty"],chair,guest,occupied)
 assert(game.save_calls==0)
 var report={"synthetic_fixture":true,"player_save_used":false,"save_calls":game.save_calls,"source_label":OS.get_environment("SOURCE_LABEL"),"display":DisplayServer.get_name(),"renderer":RenderingServer.get_video_adapter_name(),"records":records}
 FileAccess.open(OS.get_environment("OUTPUT")+"/capture.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
 print("CHAIR_GROUND_CAPTURE_RESULT ",JSON.stringify(report))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;await process_frame;quit()
