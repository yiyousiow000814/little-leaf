extends SceneTree
## Identical generated scene on pinned base/head; never read or write a player save.
class GeneratedMain extends "res://scripts/main.gd":
 var save_calls=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;paused=true;MinimalStart.apply(model)
 func _save():save_calls+=1;return true
class CountingFurniture extends "res://scripts/illustrated_furniture.gd":
 var table_draws=0
 func _cached_part(artist:Node2D,part:String,p:Vector2,rotation:int):
  if part=="table_body":table_draws+=1
  super._cached_part(artist,part,p,rotation)
var game
var records=[]
var output=OS.get_environment("TABLE_CAPTURE_OUTPUT")
var validate_only="--validate-fixture" in OS.get_cmdline_user_args()
func _initialize():run.call_deferred()
func snapshot():return JSON.stringify({"items":game.model.items,"groups":game.model.dining_sets,"guests":game.model.customers,"service":game._service_save_snapshot(),"coins":game.model.coins})
func capture(label:String,style:String,rotation:int,occupied:bool,mode:String):
 var art=game.illustration;var state=snapshot();game._update_ui()
 art.furniture_art.table_draws=0;art.queue_redraw()
 for frame in 5:await process_frame
 if not validate_only:await RenderingServer.frame_post_draw
 assert(snapshot()==state,"Rendering changed generated gameplay state")
 if not validate_only:
  assert(root.get_texture().get_image().save_png(output.path_join(label+".png"))==OK)
  if mode=="cached":assert(art.furniture_art.table_draws>0,"Table silently fell back from the native atlas")
 records.append({"file":label+".png","style":style,"rotation":rotation,"occupied":occupied,"mode":mode,"zoom":art.zoom,"camera_origin":[art.origin.x,art.origin.y],"table_position":[4,4],"cached_table_draws":art.furniture_art.table_draws,"atlas_state":art.furniture_art.static_atlas.state,"state_sha256":state.sha256_text(),"save_calls":game.save_calls})
func run():
 root.size=Vector2i(1360,880)
 assert(validate_only or (DisplayServer.get_name()!="headless" and output!=""))
 if not validate_only:DirAccess.make_dir_recursive_absolute(output)
 seed(472);game=GeneratedMain.new();root.add_child(game)
 game.set_process(false);game.illustration.set_process(false);game.model.tutorial_state.status="skipped";game.tutorial.sync()
 if game.cafe_intro!=null:
  game.cafe_intro.finish()
  for frame in 180:
   if not game.cafe_intro.active:break
   await process_frame
  assert(not game.cafe_intro.active,"Generated scene must finish startup preparation before capture")
 game.model.operating_open=true;game.model._spawn_customer();game.model.operating_open=false
 var guest=game.model.customers[0].duplicate(true)
 var chair=game.model.get_item(int(guest.chair_id));var table=game.model.get_item(int(guest.table_id))
 table.x=4;table.z=4
 for staff in game.staff_states:staff.on_duty=false
 game.illustration.furniture_art=CountingFurniture.new()
 game.illustration.furniture_art.cache_enabled=false
 var forwards=[Vector2.UP,Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT]
 for style in ["basic","cottage","retro","refined"]:
  var variant="oak_single" if style=="basic" else style+"_single"
  for rotation in 4:
   var forward:Vector2=forwards[rotation]
   chair.x=int(table.x-forward.x);chair.z=int(table.z-forward.y);chair.rot=rotation;table.rot=rotation
   table.dining_variant=variant;chair.dining_variant=variant
   game.model.rebuild_dining_sets()
   game.model.dining_set_for(int(table.id)).variant=variant
   guest.x=float(chair.x)+.5;guest.z=float(chair.z)+.5;guest.heading=forward;guest.phase="eating";guest.seated=true;guest.admitted=true;guest.dismounting=false
   guest.route=[];guest.route_index=0;guest.elapsed=.06*game.model.PHASE_SECONDS.eating;guest.duration=game.model.PHASE_SECONDS.eating
   for occupied in [false,true]:
    game.model.customers.clear()
    if occupied:game.model.customers.append(guest)
    game._sync_service_guests()
    if occupied:
     var service=game.service_guests[int(guest.id)];service.plate_owner="table";service.drink_owner="table";service.drink_done=true;service.dishes_collected=false
    game._rebuild_furniture();game._update_people()
    var art=game.illustration
    art.motion=art.MotionArt.new();art.seat_blends.clear();art.stance_offsets.clear();art.character_facings.clear();art.meal_chair_offsets.clear()
    game.paused=false
    for frame in 20:art.update_motion(.05)
    game.paused=true
    for zoom_name in ["normal","medium"]:
     art.zoom=1.0 if zoom_name=="normal" else 2.2;art.pan_offset=Vector2.ZERO;art.update_projection()
     art.pan_offset+=Vector2(680,510)-art.iso(table.x+.5,table.z+.5);art.update_projection()
     var label="%s-r%d-%s-%s"%[style,rotation,"occupied" if occupied else "empty",zoom_name]
     art.furniture_art.cache_enabled=false
     await capture(label,style,rotation,occupied,"source")
     if style=="basic" and zoom_name=="medium" and not validate_only:
      art.furniture_art.cache_enabled=true;art.furniture_art.prepare_cache(art)
      for frame in 180:
       if art.furniture_art.static_atlas.is_ready():break
       await process_frame
      assert(art.furniture_art.static_atlas.is_ready(),"Native table atlas did not warm")
      await capture(label+"-cached",style,rotation,occupied,"cached")
      art.furniture_art.cache_enabled=false
 assert(game.save_calls==0)
 var report={"generated_profile":true,"player_save_used":false,"save_calls":game.save_calls,"renderer":RenderingServer.get_video_adapter_name(),"frames":records}
 if not validate_only:FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
 print("TABLE_CAPTURE_RESULT ",JSON.stringify({"checks":records.size(),"frames":records.size(),"save_calls":game.save_calls,"validate_only":validate_only,"failures":[]}))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;await process_frame;quit()
