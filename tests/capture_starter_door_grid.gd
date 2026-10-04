extends SceneTree
const Geometry=preload("res://scripts/cafe_wall_openings.gd")
class CaptureGame extends "res://scripts/main.gd":
 var input_hash=""
 func _load_startup():
  save_writes_suppressed=true;fresh_start=false;MinimalStart.apply(model);model.coins=100000
  var state=OS.get_environment("DOOR_STATE")
  if state!="fresh":
   model.wall_attachments[0].width=1.5
   if state=="crossing":
    model._spawn_customer();model.customers.resize(1)
    model.customers[0].x=-.12;model.customers[0].z=5.05
    model.customers[0].route=[Vector2(.5,5.05),Vector2(.5,5.5)]
   assert(model.save("user://synthetic-old.json"),model.last_error)
   input_hash=FileAccess.get_sha256("user://synthetic-old.json")
   assert(model.load_save("user://synthetic-old.json"),model.last_error)
   assert(FileAccess.get_sha256("user://synthetic-old.json")==input_hash)
class FixedArt extends "res://scripts/illustrated_cafe.gd":
 func update_projection(_clamp_camera:bool=true):
  ui_scale=.88;zoom=1.0;tile=Vector2(34.32,17.16);origin=Vector2(576,226)
var game
func _initialize():_run.call_deferred()
func _run():
 seed(8124);root.size=Vector2i(1360,880)
 game=CaptureGame.new();root.add_child(game);game.set_process(false);game.paused=true;game.editing=false;game._toggle_edit()
 game.illustration.free();game.illustration=FixedArt.new();game.illustration.game=game;game.add_child(game.illustration);game.illustration.set_process(false)
 game._choose("table_set");game.rotation_step=0;game._update_ui();game.interaction.refresh(Vector2(0,0));game.interaction.preview_active=false;game.status_text.hide();game.toast_lifetime=0
 for n in range(12):game.illustration.queue_redraw();await process_frame
 await RenderingServer.frame_post_draw
 var phase=OS.get_environment("DOOR_PHASE");var output=OS.get_environment("DOOR_OUTPUT")
 root.get_texture().get_image().save_png(output+"/"+phase+".png")
 var door=game.model.wall_openings()[0]
 var report={"phase":phase,"fixture":OS.get_environment("DOOR_STATE"),"synthetic":true,"source_hash_unchanged":game.input_hash,"viewport":[1360,880],"projection":{"origin":[576,226],"tile":[34.32,17.16],"zoom":1.0},"door":game.model.wall_attachments[0],"aperture_a":str(door.a),"aperture_b":str(door.b),"center_crosses":not game.model.segment_blocked(Vector2(-.5,5.5),Vector2(.5,5.5)),"entrance":str(game.model.ENTRANCE),"landing":str(game.model.ENTRY_LANDING),"coins":game.model.coins,"customers":game.model.customers,"items":game.model.items}
 FileAccess.open(output+"/"+phase+".json",FileAccess.WRITE).store_string(JSON.stringify(preload("res://scripts/cafe_runtime_codec.gd").new().encode(report),"  "))
 print("DOOR_GRID_CAPTURE_COMPLETE ",phase);quit()
