extends SceneTree
const Fixture=preload("res://tests/role_fixture.gd")
var game
var output=""
var frames=[]
func _initialize():run.call_deferred()
func capture(name:String,elapsed:float,point:Vector2):
 game.illustration.queue_redraw()
 await process_frame
 await RenderingServer.frame_post_draw
 var image=root.get_texture().get_image()
 if image.save_png(output+"/"+name)!=OK:push_error("Cannot save native frame");quit(1);return
 frames.append({"file":name,"elapsed":elapsed,"point":str(point),"remaining_messes":game.floor_tasks.messes.size()})
func run():
 output=OS.get_environment("MANUAL_CAPTURE_OUTPUT")
 if output=="" or DisplayServer.get_name()=="headless":push_error("Native renderer and isolated output required");quit(2);return
 root.size=Vector2i(1360,880);game=Fixture.new();root.add_child(game)
 await process_frame
 game.set_process(false);game.illustration.set_process(false)
 if game.cafe_intro!=null:game.cafe_intro.finish()
 game.paused=false;game.model.operating_open=false;game.model.customers.clear();game.service_guests.clear()
 for staff in game.staff_states:game._clear_service_job(staff)
 game._update_ui()
 for zoom_name in ["normal","max"]:
  game.floor_tasks.messes.clear()
  if game.interaction.get("manual_cleanup")!=null:game.interaction.manual_cleanup.puffs.clear()
  game.illustration.zoom=1.15 if zoom_name=="normal" else game.illustration.camera_zoom_limits().y
  game.illustration.pan_offset=Vector2.ZERO;game.illustration.update_projection()
  # Fixed generated identity/seed gives identical mess geometry at both zooms.
  game.floor_tasks.next_id=1
  var id=game.floor_tasks.spawn(Vector2i(4,6),"crumbs")
  if id<0:push_error("Synthetic visible litter failed to spawn");quit(1);return
  var entry=game.floor_tasks.messes[id];var world:Vector2=entry.mess_shape.pieces[0].center
  var point:Vector2=game.illustration.iso(world.x,world.y)
  game.interaction._pan_by(game.illustration.camera_safe_rect().get_center()-point)
  point=game.illustration.iso(world.x,world.y)
  if game.interaction.get("manual_cleanup")!=null and game.interaction.manual_cleanup.hit(point).is_empty():push_error("Synthetic target is not visibly clickable");quit(1);return
  await capture(zoom_name+"-before.png",-1,point)
  for pressed in [true,false]:
   var event=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
  var previous=0.0
  for elapsed in [0.0,.12,.28,.5]:
   if game.interaction.get("manual_cleanup")!=null:game.interaction.manual_cleanup.tick(elapsed-previous)
   await capture("%s-t%.2f.png"%[zoom_name,elapsed],elapsed,point)
   previous=elapsed
 FileAccess.open(output+"/capture.json",FileAccess.WRITE).store_string(JSON.stringify({"generated_profile":true,"renderer":DisplayServer.get_name(),"frames":frames,"player_save_used":false},"  "))
 print("MANUAL_CAPTURE_RESULT ",JSON.stringify({"frames":frames.size(),"generated_profile":true,"renderer":DisplayServer.get_name()}))
 quit(0)
