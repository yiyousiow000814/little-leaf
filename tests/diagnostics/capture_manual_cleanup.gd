extends SceneTree
var game
var output=""
var frames=[]
var audio_events=[]
var capture_zoom=""
var capture_effect_frame=0
func record_audio_cue(kind:String,volume_db:float,voice_id:int):
 var event={"zoom":capture_zoom,"effect_frame":capture_effect_frame,"effect_seconds":float(capture_effect_frame)/60.0,"kind":kind,"gain_db":volume_db,"voice_id":voice_id,"stream":game.settings_controls.effects[kind].resource_path}
 audio_events.append(event);print("CLEANUP_AUDIO_EVENT ",JSON.stringify(event))
func _initialize():run.call_deferred()
func capture(name:String,elapsed:float,point:Vector2):
 # Hold the simulated effect age across three submitted frames. A single
 # post-draw wait could return the previous retained painter at normal zoom.
 for settled_frame in range(3):
  game.illustration.queue_redraw()
  await process_frame
  await RenderingServer.frame_post_draw
 var image=root.get_texture().get_image()
 if image.save_png(output+"/"+name)!=OK:push_error("Cannot save native frame");quit(1);return
 frames.append({"file":name,"elapsed":elapsed,"point":str(point),"remaining_messes":game.floor_tasks.messes.size(),"coins":game.model.coins,"hover":not game.interaction.manual_cleanup.hovered.is_empty(),"effect_age":game.interaction.manual_cleanup.puffs[0].age if not game.interaction.manual_cleanup.puffs.is_empty() else -1.0,"dimensions":str(image.get_size())})
func run():
 # Load the game fixture after the SceneTree exists for editor-attached runs.
 var Fixture=load("res://tests/fixtures/role_fixture.gd")
 output=OS.get_environment("MANUAL_CAPTURE_OUTPUT")
 if output=="" or DisplayServer.get_name()=="headless":push_error("Native renderer and isolated output required");quit(2);return
 root.size=Vector2i(1360,880);game=Fixture.new();root.add_child(game)
 await process_frame
 game.set_process(false);game.illustration.set_process(false)
 if game.cafe_intro!=null:game.cafe_intro.finish()
 game.paused=false;game.model.operating_open=false;game.model.customers.clear();game.service_guests.clear()
 for staff in game.staff_states:game._clear_service_job(staff)
 game._update_ui()
 # The generated native movie records the actual 60Hz effect, not interpolated
 # stills. Keep background music quiet so both supplied coin sounds are reviewable.
 game.music_enabled=false
 for player in game.audio_players.values():player.stop()
 game.interaction.manual_cleanup.coin_audio.cue_started.connect(record_audio_cue)
 var movie="--cleanup-motion" in OS.get_cmdline_user_args()
 for zoom_name in (["normal","detail"] if movie else ["normal","detail","max"]):
  capture_zoom=zoom_name;capture_effect_frame=0
  game.floor_tasks.messes.clear()
  if game.interaction.get("manual_cleanup")!=null:game.interaction.manual_cleanup.puffs.clear()
  game.illustration.zoom=1.15 if zoom_name=="normal" else (2.5 if zoom_name=="detail" else game.illustration.camera_zoom_limits().y)
  game.illustration.pan_offset=Vector2.ZERO;game.illustration.update_projection()
  # Fixed generated identity/seed gives identical mess geometry at both zooms.
  game.floor_tasks.next_id=1
  var id=game.floor_tasks.spawn(Vector2i(4,6),"crumbs")
  if id<0:push_error("Synthetic visible litter failed to spawn");quit(1);return
  var entry=game.floor_tasks.messes[id];var world:Vector2=entry.mess_shape.pieces[0].center
  var point:Vector2=game.illustration.iso(world.x,world.y)
  game.interaction._pan_by(game.illustration.camera_safe_rect().get_center()-point)
  point=game.illustration.iso(world.x,world.y)
  await capture(zoom_name+"-before.png",-1,point)
  if movie:
   for hold_frame in range(24):
    await process_frame
    await RenderingServer.frame_post_draw
  if game.interaction.get("manual_cleanup")!=null and game.interaction.manual_cleanup.hit(point,false).is_empty():push_error("Synthetic target is not visibly clickable");quit(1);return
  var motion=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;root.push_input(motion,true)
  await capture(zoom_name+"-hover.png",-1,point)
  if movie:
   for hold_frame in range(30):
    await process_frame
    await RenderingServer.frame_post_draw
  game.interaction.manual_cleanup.coin_rng.seed=20261013 if zoom_name=="normal" else (20261014 if zoom_name=="detail" else 20261015)
  var before_wallet=game.model.coins
  for pressed in [true,false]:
   var event=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
  await process_frame
  await RenderingServer.frame_post_draw
  for settle_frame in range(3):
   if not game.floor_tasks.messes.has(id):break
   game.illustration.queue_redraw()
   await process_frame
   await RenderingServer.frame_post_draw
  if game.floor_tasks.messes.has(id) or game.model.coins!=before_wallet+1:push_error("Native click must clean once and award exactly one coin");quit(1);return
  print("CLEANUP_COIN_EMISSION ",JSON.stringify({"zoom":zoom_name,"world_start":str(game.interaction.manual_cleanup.puffs[0].at),"motion":game.interaction.manual_cleanup.puffs[0].coin_motion}))
  if movie:
   for movie_frame in range(int(ceil(game.interaction.manual_cleanup.EFFECT_SECONDS*60.0))+24):
    capture_effect_frame=movie_frame+1
    game.interaction.manual_cleanup.tick(1.0/60.0)
    game.illustration.queue_redraw()
    await process_frame
    await RenderingServer.frame_post_draw
   continue
  var previous=0.0
  for elapsed in [.18,.35,.50,.65,.80,1.15,1.37,1.59,1.75,1.91,2.05,2.15,2.30,2.45,2.70]:
   if game.interaction.get("manual_cleanup")!=null:game.interaction.manual_cleanup.tick(elapsed-previous)
   await capture("%s-t%.2f.png"%[zoom_name,elapsed],elapsed,point)
   previous=elapsed
 FileAccess.open(output+"/capture.json",FileAccess.WRITE).store_string(JSON.stringify({"generated_profile":true,"renderer":DisplayServer.get_name(),"frames":frames,"audio_events":audio_events,"player_save_used":false},"  "))
 print("COIN_MESH_CAPTURE_RECEIPT ",JSON.stringify(game.interaction.manual_cleanup.coin_renderer.receipt()))
 print("MANUAL_CAPTURE_RESULT ",JSON.stringify({"frames":frames.size(),"generated_profile":true,"renderer":DisplayServer.get_name()}))
 quit(0)
