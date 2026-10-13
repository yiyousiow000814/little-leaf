extends SceneTree
## Generated policy states in the real renderer; no original player profile.
class GeneratedMain extends "res://scripts/main.gd":
 func _load_startup():
  save_writes_suppressed=true;fresh_start=true;paused=true;MinimalStart.apply(model)
 func _save():return true
var game
var facts={"synthetic":true,"player_save_used":false,"actual_seating_motion":true,"policy":"70 angry /120 unfinished departure","states":[]}
func _initialize():run.call_deferred()
func capture(label:String,record:Dictionary):
 game._update_people();game._update_ui();game.illustration.update_motion(.1);game.illustration.queue_redraw()
 for frame in 4:await process_frame
 await RenderingServer.frame_post_draw
 var path=OS.get_environment("OUTPUT")+"/"+label+".png"
 assert(root.get_texture().get_image().save_png(path)==OK)
 facts.states.append({"label":label,"path":path,"meal_wait_seconds":record.meal_wait_seconds,"symbol":game._guest_bubble_symbol(record.guest),"plate_owner":record.plate_owner,"phase":record.guest.phase,"abandoned":record.guest.get("meal_abandoned",false),"paid":record.guest.paid})
func run():
 seed(472);root.size=Vector2i(1360,880);assert(OS.get_environment("OUTPUT")!="")
 DisplayServer.window_set_title("Little Leaf 70 /120 meal waiting QA")
 game=GeneratedMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false)
 if game.cafe_intro!=null:game.cafe_intro.finish()
 game.paused=false;game.model._spawn_customer();game.model.operating_open=false;game._sync_service_guests()
 var guest=game.model.customers[0]
 for tick in 6000:
  game._tick_live_service(.05);game.illustration.update_motion(.05)
  if guest.seated:break
  if tick%300==0:await process_frame
 assert(guest.seated,"The preview must reach its chair through real arrival movement")
 for tick in 20:game.illustration.update_motion(.05)
 var record=game.service_guests[int(guest.id)]
 game.model.service_snapshot=game._service_save_snapshot();assert(game.model.save("user://policy-native-seated.json"),game.model.last_error)
 game.illustration.zoom=2.2;game.illustration.update_projection()
 game.illustration.pan_offset+=Vector2(750,550)-game.illustration.iso(guest.x,guest.z);game.illustration.update_projection()
 for seconds in [69.99,70.0,119.99]:
  record.meal_wait_seconds=seconds
  await capture("waiting-"+str(seconds),record)
 record.meal_wait_seconds=120.0;game._resolve_meal_deadlines()
 for tick in 16:game._tick_live_service(.05);game.illustration.update_motion(.05)
 assert(guest.meal_abandoned and not guest.paid)
 await capture("120-unfinished-leaves",record)
 # A second generated branch exercises the exception and real waiter handoff.
 assert(game.model.load_save("user://policy-native-seated.json"),game.model.last_error);game._restore_service_runtime()
 guest=game.model.customers[0];record=game.service_guests[int(guest.id)]
 for tick in 20:game.illustration.update_motion(.05)
 guest.phase="cooking";guest.elapsed=0.0;guest.duration=game.model.PHASE_SECONDS.cooking
 record.order_done=true;record.meal_ready=true;record.meal_wait_seconds=120.0
 var counter={}
 for entry in game.model.items:
  if entry.kind=="counter":counter=entry;break
 record.plate_owner="counter";record.plate_target_id=int(counter.id);record.meal_pass_id=int(counter.id)
 game._resolve_meal_deadlines();assert(not guest.meal_abandoned)
 await capture("120-ready-still-angry",record)
 for tick in 1200:
  game._tick_live_service(.05);game._animate_staff(.05);game.illustration.update_motion(.05)
  if record.plate_owner=="table":break
  if tick%200==0:await process_frame
 assert(record.plate_owner=="table" and game._guest_bubble_symbol(guest)=="","Real waiter contact must clear anger")
 await capture("food-handed-over",record)
 FileAccess.open(OS.get_environment("OUTPUT")+"/capture.json",FileAccess.WRITE).store_string(JSON.stringify(facts,"  "))
 print("SINGLE_GUEST_PATIENCE_NATIVE_CAPTURE ",JSON.stringify(facts))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;await process_frame;quit()
