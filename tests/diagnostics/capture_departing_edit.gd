extends SceneTree
class FixtureMain extends "res://scripts/main.gd":
 var saves=0
 func _load_startup():
  save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model);model.coins=100000
  for at in [Vector2i(6,5),Vector2i(9,5),Vector2i(3,6)]:assert(model.place("table_set",at.x,at.y,0),model.last_error)
 func _save():saves+=1;return true
var game
var report={"synthetic":true,"viewport":[1360,880]}
func _initialize():run.call_deferred()
func capture(label):
 game._update_ui();game.illustration.queue_redraw()
 for frame in 5:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(OS.get_environment("OUTPUT")+"/"+OS.get_environment("PHASE")+"-"+label+".png")
func run():
 seed(8124);root.size=Vector2i(1360,880)
 game=FixtureMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false)
 await process_frame
 assert(game.model.place("plant",11,7),game.model.last_error)
 var plant_id=int(game.model.items[-1].id);game.model._arrival_elapsed=-1000000
 game._rebuild_furniture()
 var guest={}
 for tick in 18000:
  if game.model._next_customer_id<=4:game.model._spawn_customer()
  if game.model._next_customer_id==5 and game.model.customers.all(func(g):return bool(g.admitted)):game.model.set_operating_open(false)
  game._tick_live_service(1.0/30.0);game._animate_staff(1.0/30.0);game.animation_time+=1.0/30.0
  for current in game.model.customers:
   if current.phase=="leaving" and current.paid and float(current.x)<0 and float(current.x)>-.01:guest=current;break
  if not guest.is_empty():report.seconds=tick/30.0;break
  if tick%180==0:await process_frame
 assert(not guest.is_empty(),"Generated traffic must reproduce the doorway crossing")
 game._toggle_edit();game.illustration.zoom=1.0;game.illustration.pan_offset=Vector2.ZERO;game.illustration.update_projection()
 var before=guest.duplicate(true);var coins=game.model.coins
 game.selected_id=plant_id;game.selected_kind="";game.rotation_step=0
 var interaction=game.interaction
 interaction.drag_active=true;interaction.preview_active=true;interaction.drag_item_id=plant_id;interaction.drag_kind="plant";interaction.drag_rotation=0;interaction.drag_cell=Vector2i(2,0)
 interaction.last_pointer=game.illustration.iso(2.5,.5);interaction._update_validity(interaction.last_pointer)
 report.preview_valid=interaction.drag_valid;report.preview_reason=interaction.drag_reason
 report.preview_unchanged=guest==before and game.model.coins==coins
 await capture("preview")
 interaction._commit_preview();interaction._clear_gesture();game.interaction.preview_active=false
 report.moved=game.model.get_item(plant_id).x==2 and game.model.get_item(plant_id).z==0
 report.guest_unchanged=guest==before;report.wallet_unchanged=game.model.coins==coins;report.saves=game.saves
 report.guest_position=str(Vector2(guest.x,guest.z))
 await capture("committed")
 game._toggle_edit();game.model._advance_walk(guest,1.0/30.0)
 report.next_guest_position=str(Vector2(guest.x,guest.z));report.continuous_outbound=float(guest.x)<float(before.x) and Vector2(guest.x,guest.z).distance_to(Vector2(before.x,before.z))<=game.model.WALK_SPEED/30.0+.0001
 await capture("resumed")
 FileAccess.open(OS.get_environment("OUTPUT")+"/"+OS.get_environment("PHASE")+"-capture.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
 print("DEPARTING_NATIVE_CAPTURE ",JSON.stringify(report))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;await process_frame;quit()
