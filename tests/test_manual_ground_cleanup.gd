extends SceneTree
const Fixture=preload("res://tests/role_fixture.gd")
var game
var checks=0
var failures=[]
var cleaner
var initial_positions=[]
func _initialize():run.call_deferred()
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func event(point:Vector2,pressed:bool,device=0,canceled=false):
 var e=InputEventMouseButton.new();e.position=point;e.global_position=point;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=pressed;e.device=device;e.canceled=canceled
 if pressed:game.interaction.handle_unhandled_input(e)
 else:game.interaction.handle_input(e)
func motion(point:Vector2,buttons=MOUSE_BUTTON_MASK_LEFT):
 var e=InputEventMouseMotion.new();e.position=point;e.global_position=point;e.button_mask=buttons
 game.interaction.handle_input(e)
func fresh(kind="banana")->int:
 game.interaction.on_focus_lost();game.interaction.manual_cleanup.puffs.clear()
 game.floor_tasks.messes.clear();game.floor_tasks.completed=0;game.service_guests.clear();game.model.customers.clear()
 for index in game.staff_states.size():
  var staff=game.staff_states[index];game._clear_service_job(staff);staff.pos=initial_positions[index]
 game.paused=false;game.editing=false;game.save_recovery_blocked=false;game.settings.hide()
 game.illustration.update_projection()
 return game.floor_tasks.spawn(Vector2i(4,6),kind)
func point_for(id:int)->Vector2:
 var entry=game.floor_tasks.messes[id];var center=game.illustration.iso(entry.floor_target.x,entry.floor_target.y)
 for y in range(-30,31,2):
  for x in range(-30,31,2):
   var point=center+Vector2(x,y)
   if not game.interaction.manual_cleanup.hit(point).is_empty():return point
 return Vector2(-999,-999)
func alive(id:int)->bool:return game.floor_tasks.messes.has(id)
func run():
 if not "saveguard" in OS.get_user_data_dir():printerr("Use isolated profile");quit(2);return
 root.size=Vector2i(1360,880);game=Fixture.new();root.add_child(game);await process_frame
 game.set_process(false);game.illustration.set_process(false)
 if game.cafe_intro!=null:game.cafe_intro.finish()
 cleaner=game.interaction.manual_cleanup
 for staff in game.staff_states:initial_positions.append(staff.pos)
 var wallet=game.model.coins
 for kind in ["banana","crumbs"]:
  var id=fresh(kind);check(id>0,"valid "+kind+" fixture")
  var point=point_for(id);check(point.x>0,"paint silhouette hit "+kind)
  event(point,true);event(point,false)
  check(not alive(id) and game.floor_tasks.completed==1,"one tap completes "+kind)
  check(cleaner.puffs.size()==1,"one successful puff "+kind)
  event(point,false);event(point,true);event(point,false)
  check(game.floor_tasks.completed==1 and cleaner.puffs.size()==1,"repeat tap/release inert "+kind)
  check(cleaner.tick(.5) and cleaner.puffs.is_empty(),"puff expires without completion callback")
 # The paired native capture uses these exact generated targets and cameras.
 for zoom_name in ["normal","max"]:
  game.illustration.zoom=1.15 if zoom_name=="normal" else game.illustration.camera_zoom_limits().y
  game.illustration.pan_offset=Vector2.ZERO;game.floor_tasks.next_id=1
  var capture_id=fresh("crumbs");var entry=game.floor_tasks.messes[capture_id]
  var world:Vector2=entry.mess_shape.pieces[0].center
  var capture_point:Vector2=game.illustration.iso(world.x,world.y)
  game.interaction._pan_by(game.illustration.camera_safe_rect().get_center()-capture_point)
  capture_point=game.illustration.iso(world.x,world.y)
  check(not cleaner.hit(capture_point).is_empty(),"capture center is visible at "+zoom_name)
  event(capture_point,true);event(capture_point,false)
  check(not alive(capture_id),"capture pointer succeeds at "+zoom_name)
 game.illustration.zoom=1.15;game.illustration.pan_offset=Vector2.ZERO
 var id=fresh();var point=point_for(id)
 event(point,true);motion(point+Vector2(8,0));motion(point);event(point,false)
 check(alive(id) and cleaner.puffs.is_empty(),"pan crossing threshold cannot turn back into tap")
 id=fresh();point=point_for(id);event(point,true);game.interaction.on_focus_lost();event(point,false)
 check(alive(id),"focus loss cancels cleanup")
 id=fresh();point=point_for(id);event(point,true);event(point,false,0,true)
 check(alive(id),"canceled release never cleans")
 id=fresh();point=point_for(id);event(point,true);motion(point,0);event(point,false)
 check(alive(id),"lost outside-window release cancels cleanup")
 id=fresh();point=point_for(id);event(point,true);event(point,false,InputEvent.DEVICE_ID_EMULATION)
 check(alive(id),"emulated release cannot finish physical press");game.interaction.on_focus_lost()
 id=fresh();point=point_for(id);event(point,true);game.editing=true;event(point,false)
 check(alive(id),"mode change cancels pending cleanup")
 id=fresh();point=point_for(id);game.editing=true;event(point,true);event(point,false)
 check(alive(id),"Decorate never cleans")
 id=fresh();point=point_for(id);game.paused=true;event(point,true);event(point,false)
 check(alive(id),"Pause retains world state")
 id=fresh();point=point_for(id);game.save_recovery_blocked=true;event(point,true);event(point,false)
 check(alive(id),"recovery blocks cleanup")
 id=fresh();point=point_for(id);event(point,true);game.settings.show();event(point,false)
 check(alive(id),"new modal after press owns release")
 id=fresh();point=point_for(id);event(point,true);game.interaction._zoom_step_at(point,1);event(point,false)
 check(alive(id),"zoom invalidates prior pointer receipt")
 id=fresh();point=point_for(id);event(point,true);event(Vector2(-10,-10),false)
 check(alive(id),"outside viewport release cancels cleanup")
 id=fresh();point=point_for(id);event(point,true);game.floor_tasks.restore(game.floor_tasks.snapshot());event(point,false)
 check(alive(id),"floor restore invalidates equal numeric identity")
 id=fresh();point=point_for(id);event(point,true);game.ground_mess_generation+=1;event(point,false)
 check(alive(id),"runtime restore generation invalidates pending receipt")
 id=fresh();point=point_for(id);event(point,true)
 var identity=game.ground_mess_identity("floor",id);game.complete_ground_mess(identity,"manual");event(point,false)
 check(game.floor_tasks.completed==1 and cleaner.puffs.is_empty(),"NPC or other completion wins before release")
 id=fresh();point=point_for(id);var npc=game.worker("cleaner");game.floor_tasks.assign(npc,game.staff_states.find(npc));var stale=npc.duplicate(true)
 event(point,true);event(point,false);game.floor_tasks.contact(stale,game.staff_states.find(npc),"sweeping",{},1)
 check(not alive(id) and npc.job_kind=="" and game.floor_tasks.completed==1,"manual completion releases approach and stale NPC replay is inert")
 # A second finger cancels the existing mouse-emulated world transaction.
 id=fresh();point=point_for(id);event(point,true,InputEvent.DEVICE_ID_EMULATION)
 for finger in 2:
  var touch=InputEventScreenTouch.new();touch.index=finger;touch.position=point+Vector2(finger*20,0);touch.pressed=true;game.camera_gestures.handle_input(touch)
 event(point,false,InputEvent.DEVICE_ID_EMULATION)
 check(alive(id),"second touch cancels manual pending tap");game.camera_gestures.on_focus_lost()
 # Draw feedback is transient across restore and never serializes into saves.
 id=fresh();point=point_for(id);event(point,true);event(point,false)
 game.model.service_snapshot=game._service_save_snapshot()
 check(game.model.save("user://manual-cleanup.json"),"completed cleanup saves during puff: "+game.model.last_error)
 check(game.model.load_save("user://manual-cleanup.json"),"saved cleanup validates and loads: "+game.model.last_error)
 game._restore_service_runtime();cleaner.tick(.01)
 check(cleaner.puffs.is_empty() and game.floor_tasks.messes.is_empty(),"save restore drops cosmetic puff without resurrecting dirt")
 check(game.model.coins==wallet,"manual cleanup changes no coins or XP economy")
 # Shared API preserves concurrent table obligations and waiter sink claim.
 game.interaction.on_focus_lost();game.paused=false
 var record=game.setup_dirty();var waiter=game.worker("waiter");var janitor=game.legacy_job(record,3,.1)
 waiter.job_kind="cleanup";waiter.job_guest_id=int(record.guest.id);waiter.job_token=int(record.token);waiter.job_step=0;waiter.job_elapsed=0
 game._prepare_cleanup_step(waiter,game.staff_states.find(waiter))
 var sink=record.get("dish_sink_id",-1);var before_dishes=record.dishes_collected;var before_table=record.table_wiped;stale=janitor.duplicate(true)
 check(sink>0,"concurrent waiter holds an actual sink reservation")
 identity=game.ground_mess_identity("guest",int(record.guest.id))
 check(game.complete_ground_mess(identity,"manual"),"guest floor shared completion succeeds")
 game._service_contact(stale,game.staff_states.find(janitor),"sweeping",{},1)
 check(record.floor_cleaned and record.trash_owner=="disposed","stale guest NPC contact cannot reopen cleaned ground")
 check(record.dishes_collected==before_dishes and record.table_wiped==before_table and record.get("dish_sink_id",-1)==sink and waiter.job_kind=="cleanup","manual ground completion preserves waiter work and sink claim")
 check(not game.complete_ground_mess(identity,"manual"),"guest completion is idempotent")
 print("MANUAL_GROUND_CLEANUP_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"player_save_used":false,"native_render_verified":false}))
 quit(0 if failures.is_empty() else 1)
