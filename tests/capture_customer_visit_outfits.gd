extends SceneTree
class CaptureGame extends "res://scripts/main.gd":
 func _load_startup():
  save_writes_suppressed=true;fresh_start=false
class FixedArt extends "res://scripts/illustrated_cafe.gd":
 var review_zoom=1.0
 func update_projection(_clamp_camera:bool=true):
  ui_scale=.88;zoom=review_zoom;tile=Vector2(34.32,17.16)*zoom;origin=Vector2(650,205) if zoom==1.0 else Vector2(750,160)
var game
func _initialize():_run.call_deferred()
func _run():
 seed(8124);root.size=Vector2i(1360,880)
 game=CaptureGame.new();root.add_child(game);game.set_process(false);game.paused=true;game.editing=false
 game.model.reset_new();game.model._spawn_customer()
 for guest in game.model.customers:
  var chair=game.model.get_item(int(guest.chair_id))
  guest.x=chair.x+.5;guest.z=chair.z+.5;guest.phase="ordering";guest.seated=true;guest.admitted=true;guest.elapsed=0.0;guest.duration=game.model.PHASE_SECONDS.ordering;guest.route_index=guest.route.size()
 game.model._spawn_walkers(4)
 for visitor in game.model.outside_queue:
  var target=game.model.OutsideQueue.target(int(visitor.slot))
  visitor.x=target.x;visitor.z=target.y;visitor.route_index=visitor.route.size();visitor.waiting=true;visitor.heading=Vector2.DOWN
 game.illustration.free();game.illustration=FixedArt.new();game.illustration.game=game;game.add_child(game.illustration);game.illustration.set_process(false)
 game._update_ui();game.paused=false
 for i in range(4):
  game.illustration.queue_redraw();await process_frame;await RenderingServer.frame_post_draw
 var output=OS.get_environment("OUTFIT_OUTPUT")
 root.get_texture().get_image().save_png(output+"/gameplay.png")
 var outfits=[]
 if game.model.has_method("appearance_for"):
  for visitor in game.model.customers+game.model.outside_queue:
   outfits.append(game.model.appearance_for(int(visitor.id)))
 game.illustration.review_zoom=1.35;game.illustration.queue_redraw()
 await process_frame;await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(output+"/gameplay-detail.png")
 var report={"outfits":outfits,"synthetic":true,"player_save_used":false,"viewport":[1360,880],"customers":game.model.customers,"outside_queue":game.model.outside_queue,"renderer":RenderingServer.get_current_rendering_method()}
 FileAccess.open(output+"/capture.json",FileAccess.WRITE).store_string(JSON.stringify(preload("res://scripts/cafe_runtime_codec.gd").new().encode(report),"  "))
 game.free()
 print("CUSTOMER_VISIT_GAMEPLAY_CAPTURE_OK");quit(0)
