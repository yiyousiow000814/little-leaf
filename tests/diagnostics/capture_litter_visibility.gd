extends SceneTree
const Main=preload("res://scripts/main.gd")
const Illustration=preload("res://scripts/illustrated_cafe.gd")
const BeforeArt=preload("res://tests/fixtures/litter_art_v6/floor_mess_art.gd")
const BeforeGeometry=preload("res://scripts/cafe_floor_geometry.gd")
const BeforeTasks=preload("res://scripts/cafe_floor_tasks.gd")
const AfterTasks=preload("res://scripts/cafe_floor_tasks.gd")
const Codec=preload("res://scripts/cafe_runtime_codec.gd")
class OldIllustration extends Illustration:
 func _draw_floor_mess(record:Dictionary):
  if _floor_mess_active(record):BeforeArt.draw(self,record)
class FixtureMain extends Main:
 func _load_startup():
  save_writes_suppressed=true;fresh_start=false;model.reset_new();paused=true
 func _save():return true
var game
func _initialize():run.call_deferred()
func run():
 var mode=OS.get_environment("LITTER_CAPTURE_MODE")
 game=FixtureMain.new();root.add_child(game);await process_frame
 game.set_process(false);game.paused=true;game.editing=false;game.model.operating_open=true
 if game.compact_ui.has_method("dismiss_starter_hint"):game.compact_ui.dismiss_starter_hint()
 if mode=="before":
  var replaced=game.illustration;game.remove_child(replaced);replaced.queue_free()
  game.illustration=OldIllustration.new();game.illustration.game=game;game.add_child(game.illustration)
 game.illustration.set_process(false)
 game.floor_tasks.game=null;game.floor_tasks.geometry.game=null
 game.floor_tasks=BeforeTasks.new(game) if mode=="before" else AfterTasks.new(game)
 if mode=="before":game.floor_tasks.geometry=BeforeGeometry.new(game)
 game.model.customers.clear();game.model._spawn_customer()
 var guest_template=game.model.customers[0].duplicate(true)
 var visitors=[];var routes=[]
 for route in [{"id":1,"start":Vector2(2.5,6.5)},{"id":18,"start":Vector2(6.5,7.5)},{"id":52,"start":Vector2(1.5,2.5)}]:
  game.model.customers.clear();var guest=guest_template.duplicate(true)
  guest.id=route.id;guest.x=route.start.x;guest.z=route.start.y;guest.heading=Vector2.RIGHT;guest.admitted=true;guest.waiting=false
  game.model.customers.append(guest);game.floor_tasks.observe_walks()
  var points=[route.start]
  for step in range(1,4):
   guest.x=route.start.x+step;points.append(Vector2(guest.x,guest.z));game.floor_tasks.observe_walks()
  routes.append({"guest_id":guest.id,"points":points});visitors.append(guest.duplicate(true))
 game.model.customers.clear()
 for visitor in visitors:game.model.customers.append(visitor)
 game.service_guests.clear()
 var diner=guest_template.duplicate(true)
 diner.id=91;diner.phase="eating";diner.seated=true;diner.waiting=false;diner.table_id=8;diner.chair_id=9;diner.x=6.5;diner.z=6.5;diner.elapsed=0.0;diner.duration=20.0;diner.heading=Vector2.UP
 game.model.customers.append(diner)
 game.animation_time=0;game.visual_timer=0
 root.size=Vector2i(1360,880)
 var cases=[]
 for detail in [false,true]:
  game.illustration.zoom=1.15 if not detail else 2.1
  game.illustration.pan_offset=Vector2(0,-20) if not detail else Vector2(160,-150)
  game.illustration.update_projection();game._update_ui()
  for i in range(12):await process_frame
  game.illustration.queue_redraw();await process_frame;await RenderingServer.frame_post_draw
  var path="res://docs/litter-remnants-visibility/%s-%s.png"%[mode,"detail" if detail else "normal"]
  assert(root.get_texture().get_image().save_png(path)==OK)
  cases.append({"image":path,"zoom":game.illustration.zoom,"pan":game.illustration.pan_offset,"origin":game.illustration.origin,"tile":game.illustration.tile,"viewport":root.size})
 var report={"mode":mode,"fixture":"same furnished game, three observed customer routes; controlled artwork comparison rather than admission simulation","renderer":RenderingServer.get_video_adapter_name(),"routes":routes,"save_writes_suppressed":game.save_writes_suppressed,"items":game.model.items,"customers":game.model.customers,"messes":game.floor_tasks.snapshot(),"cases":cases}
 FileAccess.open("res://docs/litter-remnants-visibility/"+mode+"-native.json",FileAccess.WRITE).store_string(JSON.stringify(Codec.new().encode(report),"  "))
 print("LITTER_ART_CAPTURE_COMPLETE ",mode," messes=",game.floor_tasks.messes.size());quit()
