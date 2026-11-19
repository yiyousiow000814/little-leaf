extends SceneTree
## Exact-source native paired capture. Generated frozen cafe; no accounts/saves.
const Walls=preload("res://scripts/gameplay/cafe_walls.gd")
class SyntheticMain extends "res://scripts/main.gd":
 var saves=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;assert(model.load_save("res://wall_quad_parity_21walls.json"),model.last_error)
 func _setup_music():pass
 func _save():saves+=1;return true
var game
var frames=[]
var output=OS.get_environment("OUTPUT")
var arm=OS.get_environment("WALL_EXPECT_ARM")
var smoke=OS.get_environment("WALL_CAPTURE_HEADLESS_SMOKE")=="1"
func _initialize():run.call_deferred()
func capture(label:String):
 var art=game.illustration
 var prior_stream_frame:int=art.canvas_stream.frame_id
 art.update_projection();art.queue_redraw()
 # No settling frame after a mutation: inspect its first completed submission.
 if smoke:await process_frame
 else:await RenderingServer.frame_post_draw
 var record={"label":label,"first_completed_frame":not smoke,"frame":Engine.get_process_frames(),"zoom":art.zoom,"origin":str(art.origin),"tile":str(art.tile),"pan":str(art.pan_offset),"walls":game.model.built_walls.duplicate(true),"attachments":game.model.wall_attachments.duplicate(true),"preview":game.build_tools.preview.duplicate(true),"preview_valid":game.build_tools.preview_valid,"editing":game.editing,"staff_pos":str(game.staff_states[0].pos),"draw_cpu_ms":art.playtest_draw_ms}
 var wall_slots=[];var actor_slots=[];var native_count=0;var fallback_count=0;var textured_owners=[];var selected_wall=[];var selected_actor=-1;var axis_count={"x":0,"z":0}
 if not smoke:
  for node in art.native_object_nodes.values():
   if not node.is_visible_in_tree():continue
   if node.appearance.is_empty() or not node.appearance[0] is Array or node.appearance[0].is_empty():continue
   var shape:Array=node.appearance[0]
   if shape[0]=="wall-slice":
    assert(node.painted_revision==node.paint_revision)
    wall_slots.append(node.draw_order)
    var host:Dictionary=shape[4].host
    axis_count[host.axis]+=1
    assert(shape[5]==1.0 and shape[6]==Color.WHITE,"This fixture covers untinted installed walls only")
    if host.host_id=="wall:20":selected_wall.append(node.draw_order)
    var themed:bool=host.host_id=="wall:1" and host.material=="cream_stripe"
    var native_children=0;var old_polygons=0;var textures=0
    for shape_node in node.shapes:
     if not shape_node.is_visible_in_tree():continue
     assert(shape_node.painted_revision==shape_node.paint_revision,"Visible active child did not paint")
     if shape_node.draw_method==&"wall_solid_quads":
      var args:Array=shape_node.draw_arguments
      assert(args.size()==3 and args[0].size()>=6 and args[0].size()%6==0)
      assert(args[1].size()==args[2].size() and args[1].size()*3==args[0].size()*2)
      native_children+=1
     if shape_node.draw_method==&"draw_polygon":
      old_polygons+=1
      if shape_node.draw_arguments[3] is Texture2D:textures+=1
    assert((native_children==1 and old_polygons==0) if arm=="candidate" and not themed else (native_children==0 and old_polygons>0),"Wrong active wall path for "+arm)
    assert(textures>0 if themed else textures==0,"Wrong texture fallback for "+host.host_id)
    if themed:textured_owners.append(node.draw_order)
    native_count+=native_children
    fallback_count+=int(old_polygons>0)
   if shape[0]=="character":
    actor_slots.append(node.draw_order)
    if shape[3] and int(shape[2])==0:
     assert(selected_actor<0 and node.painted_revision==node.paint_revision)
     selected_actor=node.draw_order
  wall_slots.sort();actor_slots.sort();selected_wall.sort();textured_owners.sort()
  assert(art.canvas_stream.frame_id==prior_stream_frame+1,"Only the first completed world draw is admissible")
  assert(selected_actor>=0 and selected_wall.size()==4,"Selected cook and wall:20 must be painted")
  assert(axis_count=={"x":48,"z":36},"Wrong visible slice census by axis")
  assert(textured_owners.size()==(4 if label=="themed-alt-camera-first" else 0))
  assert(wall_slots.size()==84,"All actual 21-wall slices must be retained and painted")
 record["wall_owner_order"]=wall_slots;record["actor_owner_order"]=actor_slots
 record["axes"]=axis_count;record["themed_texture_owners"]=textured_owners
 record["selected_wall_order"]=selected_wall;record["selected_actor_order"]=selected_actor
 record["arm"]=arm;record["quad_command_owners"]=native_count;record["legacy_polygon_owners"]=fallback_count
 if not smoke:
  var img=root.get_texture().get_image();img.convert(Image.FORMAT_RGBA8)
  var digest=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(img.get_data())
  record["rgba_sha256"]=digest.finish().hex_encode()
  record["file"]="%02d-%s.png"%[frames.size(),label]
  assert(img.save_png(output.path_join(record.file))==OK)
 frames.append(record)
func run():
 assert(arm in ["control","candidate"],"An explicit path expectation is required")
 assert(output!="" and "saveguard" in OS.get_user_data_dir())
 assert(smoke or DisplayServer.get_name()!="headless","Native rendering is required for pixels")
 DirAccess.make_dir_recursive_absolute(output)
 root.size=Vector2i(1360,880);seed(13017)
 game=SyntheticMain.new();root.add_child(game);game.paused=true;game.set_process(false)
 for wait_frame in 900:
  if not is_instance_valid(game.startup_readiness) or game.startup_readiness.completed:break
  await process_frame
 assert(smoke or not game.startup_preparation_report.is_empty(),"Startup preparation did not complete")
 assert(smoke or (not game.startup_preparation_report.timed_out and game.startup_preparation_report.ready==3),"Atlas preparation did not load all three existing atlases")
 if game.cafe_intro!=null:game.cafe_intro.finish()
 game.illustration.set_process(false)
 for tween in get_processed_tweens():tween.kill()
 game.ui.visible=false;game.tray.hide();game.animation_time=1.0
 var art=game.illustration;art.zoom=1.15;art.pan_offset=Vector2.ZERO
 assert(game.model.built_walls.size()==21 and game.model.wall_attachments.size()==1)
 var opening=game.model.wall_attachments[0]
 var themed=game.model.built_walls[0]
 assert(opening.kind=="door" and opening.wall_ids==["wall:18"])
 var host=game.model.built_walls[17];var wall=game.model.built_walls[19]
 assert(host.id=="wall:18" and wall.id=="wall:20" and wall.height=="full")
 for worker in game.staff_states:worker.pos=Vector2(100,100);worker.art_action="idle";worker.art_payload="none";worker.art_tool="none"
 var staff=game.staff_states[0]
 staff.pos=Vector2(.2,7.45);art.stance_offsets.clear();art.update_projection()
 for i in range(5):await process_frame
 await capture("full-with-door")
 wall.height="half";game.model.revision+=1;await capture("half-first")
 opening.offset=.44;opening.width=.72;game.model.revision+=1;await capture("door-mutated-first")
 assert(game.model.place_wall_attachment("window","wall:4",.5),game.model.last_error)
 var openings:Array=game.model.wall_openings()
 assert(openings.size()==2 and openings.any(func(row):return row.kind=="window" and row.host_id=="wall:4"))
 await capture("half-with-window-first")
 # The actor crosses the selected host plane; the style/order is measured at
 # actual native owners, not by re-sorting synthetic primitive lists.
 wall.height="full";game.model.revision+=1;await capture("occluded-first")
 staff.pos=Vector2(-.24,7.45);art.motion=art.MotionArt.new();art.stance_offsets.clear();await capture("over-wall-first")
 staff.pos=Vector2(.2,7.45);art.motion=art.MotionArt.new();art.stance_offsets.clear()
 game.model.wall_attachments.erase(opening);game.model.revision+=1;await capture("door-removed-first")
 themed.material="cream_stripe";game.model.revision+=1
 art.pan_offset=Vector2(34,-18);art.zoom=.91;await capture("themed-alt-camera-first")
 assert(frames.size()==8 and game.saves==0)
 var report={"engine":Engine.get_version_info(),"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"viewport":[1360,880],"fixture_seed":13017,"generated_profile":true,"save_calls":game.saves,"smoke_only":smoke,"frames":frames,"native_pixel_acceptance":false,"scope":"eight synthetic stills; first completed frame after each change; no video, browser, FPS or user acceptance"}
 FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
 game.queue_free();await process_frame
 print("WALL_RETENTION_CAPTURE ",JSON.stringify({"frames":frames.size(),"smoke_only":smoke,"saves":0}));quit()
