extends SceneTree
## Exact-source native paired capture. Generated frozen cafe; no accounts/saves.
const Walls=preload("res://scripts/gameplay/cafe_walls.gd")
class SyntheticMain extends "res://scripts/main.gd":
 var saves=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _setup_music():pass
 func _save():saves+=1;return true
var game
var frames=[]
var output=OS.get_environment("OUTPUT")
var smoke=OS.get_environment("WALL_CAPTURE_HEADLESS_SMOKE")=="1"
func _initialize():run.call_deferred()
func capture(label:String):
 var art=game.illustration
 art.update_projection();art.queue_redraw()
 # No settling frame after a mutation: inspect its first completed submission.
 if smoke:await process_frame
 else:await RenderingServer.frame_post_draw
 var record={"label":label,"first_completed_frame":not smoke,"frame":Engine.get_process_frames(),"zoom":art.zoom,"origin":str(art.origin),"tile":str(art.tile),"pan":str(art.pan_offset),"walls":game.model.built_walls.duplicate(true),"attachments":game.model.wall_attachments.duplicate(true),"render_attachments":game.build_tools.get_render_attachments().duplicate(true),"opening_preview":game.build_tools.opening_preview.duplicate(true),"opening_preview_active":game.build_tools._render_preview_active,"preview":game.build_tools.preview.duplicate(true),"preview_valid":game.build_tools.preview_valid,"editing":game.editing,"staff_pos":str(game.staff_states[0].pos),"draw_cpu_ms":art.playtest_draw_ms}
 if not smoke:
  var img=root.get_texture().get_image();img.convert(Image.FORMAT_RGBA8)
  var digest=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(img.get_data())
  record["rgba_sha256"]=digest.finish().hex_encode()
  record["file"]="%02d-%s.png"%[frames.size(),label]
  assert(img.save_png(output.path_join(record.file))==OK)
 frames.append(record)
func run():
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
 var first=Walls.installed("probe-first",Walls.make("x",3,5,"full","original"),0,0)
 var next=Walls.installed("probe-next",Walls.make("x",4,5,"full","original"),0,0)
 game.model.built_walls.append(first);game.model.built_walls.append(next)
 game.model.revision+=1
 for frame in 6:await process_frame
 await capture("baseline")
 var join=Walls.installed("probe-join",Walls.make("z",3,5,"full","original"),0,0)
 game.model.built_walls.append(join);await capture("perpendicular-join-added")
 game.model.built_walls.erase(join);await capture("perpendicular-join-removed")
 art.pan_offset=Vector2(73,-31);await capture("pan-first-frame")
 art.zoom=.65;await capture("zoom-out-first-frame")
 art.zoom=1.5;await capture("zoom-in-first-frame")
 var opening={"id":9901,"kind":"window","wall_ids":["probe-first"],"offset":.5,"width":.7,"paid_cost":0}
 game.model.wall_attachments.append(opening);await capture("opening-added")
 opening.offset=.4;opening.width=.6;await capture("opening-moved")
 game.editing=true;game.catalog_category="Build";game.build_tools.mode="move_opening"
 game.build_tools.opening_source_id=int(opening.id)
 var proposed=opening.duplicate(true);proposed.wall_ids=["probe-next"];proposed.offset=.5;proposed.preview=true
 game.build_tools.opening_preview=proposed;game.build_tools.preview_valid=true
 game.build_tools._render_preview_active=true
 game.build_tools._render_attachments=game.model.wall_attachments.filter(func(a):return int(a.id)!=int(opening.id))
 game.build_tools._render_attachments.append(proposed)
 assert(game.build_tools.get_render_attachments()!=game.model.wall_attachments)
 await capture("opening-draft-replacement")
 game.build_tools.cancel();game.editing=false
 assert(game.build_tools.get_render_attachments()==game.model.wall_attachments)
 await capture("opening-draft-cancelled")
 first.material="cream_stripe";await capture("material-texture")
 next.height="half";await capture("neighbor-height")
 game.model.built_walls.erase(next);await capture("neighbor-deleted")
 first.x=2;first.z=4;await capture("wall-moved")
 game.editing=true;game.catalog_category="Build";game.build_tools.mode="full"
 game.build_tools.preview=Walls.make("z",4,4,"full","leaf_print")
 game.build_tools.preview_valid=true;await capture("draft-valid")
 game.build_tools.preview_valid=false;await capture("draft-invalid")
 game.build_tools.cancel();game.editing=false;await capture("draft-cancelled")
 first.x=3;first.z=5;art.zoom=1.15;art.pan_offset=Vector2.ZERO
 var staff=game.staff_states[0];staff.pos=Vector2(3.5,4.7);staff.art_action="idle";staff.art_payload="none";staff.art_tool="none"
 art.stance_offsets.clear();await capture("actor-behind-wall")
 staff.pos=Vector2(3.5,5.7);await capture("actor-before-wall")
 game.model.wall_attachments.erase(opening);game.model.built_walls.erase(first);await capture("wall-and-opening-removed")
 assert(frames.size()==20 and game.saves==0)
 var report={"engine":Engine.get_version_info(),"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"viewport":[1360,880],"fixture_seed":13017,"generated_profile":true,"save_calls":game.saves,"smoke_only":smoke,"frames":frames,"native_pixel_acceptance":false,"scope":"20 frozen synthetic same-source frames; first completed frame after each change; no video, browser, FPS or user acceptance"}
 FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
 game.queue_free();await process_frame
 print("WALL_RETENTION_CAPTURE ",JSON.stringify({"frames":frames.size(),"smoke_only":smoke,"saves":0}));quit()
