extends SceneTree
const AudioDrain=preload("res://tests/fixtures/audio_mixer_drain.gd")
class SfxEvents extends RefCounted:
 var events:Array=[]
 func play(kind:String,volume_db=0.0):events.append([kind,volume_db]);return true
 func tick(_epoch:Array):pass
var game
var checks=0
var failures=[]
var cleaner
var initial_positions=[]
var occlusion_observations=[]
func _initialize():run.call_deferred()
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func event(point:Vector2,pressed:bool,device=0,canceled=false):
 var e=InputEventMouseButton.new();e.position=point;e.global_position=point;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=pressed;e.device=device;e.canceled=canceled
 if pressed:game.interaction.handle_unhandled_input(e)
 else:game.interaction.handle_input(e)
func settle():
 await process_frame
 await RenderingServer.frame_post_draw
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
 game.illustration.queue_redraw()
 await process_frame
 await RenderingServer.frame_post_draw
 var entry=game.floor_tasks.messes[id];var center=game.illustration.iso(entry.floor_target.x,entry.floor_target.y)
 for y in range(-30,31,2):
  for x in range(-30,31,2):
   var point=center+Vector2(x,y)
   if not game.interaction.manual_cleanup.hit(point,false).is_empty():return point
 return Vector2(-999,-999)
func alive(id:int)->bool:return game.floor_tasks.messes.has(id)
func run():
 # Load the game fixture after the SceneTree exists for editor-attached runs.
 var Fixture=load("res://tests/fixtures/role_fixture.gd")
 if not "saveguard" in OS.get_user_data_dir():printerr("Use isolated profile");quit(2);return
 root.size=Vector2i(1360,880);game=Fixture.new();root.add_child(game);await process_frame
 game.set_process(false);game.illustration.set_process(false)
 if game.cafe_intro!=null:game.cafe_intro.finish()
 cleaner=game.interaction.manual_cleanup
 for staff in game.staff_states:initial_positions.append(staff.pos)
 var identity:Dictionary={}
 var stale:Dictionary={}
 # Real pointer acceptance requires a painted native frame. Headless CI tests
 # only the shared custody/idempotence/save API; it never fabricates a receipt.
 if DisplayServer.get_name()!="headless":
  var wallet=game.model.coins
  for kind in ["banana","crumbs"]:
   var before_coin=game.model.coins
   var id=fresh(kind);check(id>0,"valid "+kind+" fixture")
   var point=await point_for(id);check(point.x>0,"paint silhouette hit "+kind)
   event(point,true);event(point,false);await settle()
   check(not alive(id) and game.floor_tasks.completed==1,"one tap completes "+kind)
   check(cleaner.puffs.size()==1,"one successful puff "+kind)
   check(game.model.coins==before_coin+1,"one successful click earns exactly one coin "+kind)
   event(point,false);await settle();event(point,true);event(point,false);await settle()
   check(game.floor_tasks.completed==1 and cleaner.puffs.size()==1,"repeat tap/release inert "+kind)
   check(game.model.coins==before_coin+1,"repeated tap/release cannot award twice "+kind)
   check(cleaner.tick(cleaner.EFFECT_SECONDS+.1) and cleaner.puffs.is_empty(),"effect expires without completion callback")
  var deferred_id=fresh();var deferred_point=await point_for(deferred_id)
  event(deferred_point,true);event(deferred_point,false)
  check(alive(deferred_id) and cleaner.released,"release defers completion until a certified native frame")
  game.paused=true;await settle()
  check(alive(deferred_id) and cleaner.puffs.is_empty() and not cleaner.released,"Pause before certified settlement cancels queued release")
  deferred_id=fresh();deferred_point=await point_for(deferred_id)
  event(deferred_point,true);event(deferred_point,false);game.interaction.on_focus_lost();await settle()
  check(alive(deferred_id) and not game.illustration.character_pick_geometry.query_active(),"focus cancellation closes released query before settlement")
  deferred_id=fresh();deferred_point=await point_for(deferred_id)
  event(deferred_point,true);event(deferred_point,false)
  game.illustration.character_pick_geometry.query_deadline=Time.get_ticks_msec()-1
  await settle()
  check(alive(deferred_id) and not cleaner.released,"expired query never completes and drops its intent")
  # The paired native capture uses these exact generated targets and cameras.
  for zoom_name in ["normal","max"]:
   game.illustration.zoom=1.15 if zoom_name=="normal" else game.illustration.camera_zoom_limits().y
   game.illustration.pan_offset=Vector2.ZERO;game.floor_tasks.next_id=1
   var capture_id=fresh("crumbs");var entry=game.floor_tasks.messes[capture_id]
   var world:Vector2=entry.mess_shape.pieces[0].center
   var capture_point:Vector2=game.illustration.iso(world.x,world.y)
   game.interaction._pan_by(game.illustration.camera_safe_rect().get_center()-capture_point)
   capture_point=game.illustration.iso(world.x,world.y)
   game.illustration.queue_redraw()
   await process_frame
   await RenderingServer.frame_post_draw
   check(not cleaner.hit(capture_point,false).is_empty(),"capture center is visible at "+zoom_name)
   event(capture_point,true);event(capture_point,false);await settle()
   check(not alive(capture_id),"capture pointer succeeds at "+zoom_name)
  game.illustration.zoom=1.15;game.illustration.pan_offset=Vector2.ZERO
  var id=fresh();var point=await point_for(id)
  event(point,true);motion(point+Vector2(8,0));motion(point);event(point,false);await settle()
  check(alive(id) and cleaner.puffs.is_empty(),"pan crossing threshold cannot turn back into tap")
  id=fresh();point=await point_for(id);event(point,true);game.interaction.on_focus_lost();event(point,false);await settle()
  check(alive(id),"focus loss cancels cleanup")
  id=fresh();point=await point_for(id);event(point,true);event(point,false,0,true)
  check(alive(id),"canceled release never cleans")
  id=fresh();point=await point_for(id);event(point,true);motion(point,0);event(point,false);await settle()
  check(alive(id),"lost outside-window release cancels cleanup")
  id=fresh();point=await point_for(id);event(point,true);event(point,false,InputEvent.DEVICE_ID_EMULATION)
  check(alive(id),"emulated release cannot finish physical press");game.interaction.on_focus_lost()
  id=fresh();point=await point_for(id);event(point,true);game.editing=true;event(point,false);await settle()
  check(alive(id),"mode change cancels pending cleanup")
  id=fresh();point=await point_for(id);game.editing=true;event(point,true);event(point,false);await settle()
  check(alive(id),"Decorate never cleans")
  id=fresh();point=await point_for(id);game.paused=true;event(point,true);event(point,false);await settle()
  check(alive(id),"Pause retains world state")
  id=fresh();point=await point_for(id);game.save_recovery_blocked=true;event(point,true);event(point,false);await settle()
  check(alive(id),"recovery blocks cleanup")
  id=fresh();point=await point_for(id);event(point,true);game.settings.show();event(point,false);await settle()
  check(alive(id),"new modal after press owns release")
  id=fresh();point=await point_for(id);event(point,true);game.interaction._zoom_step_at(point,1);event(point,false);await settle()
  check(alive(id),"zoom invalidates prior pointer receipt")
  id=fresh();point=await point_for(id);event(point,true);event(Vector2(-10,-10),false)
  check(alive(id),"outside viewport release cancels cleanup")
  id=fresh();point=await point_for(id);event(point,true);game.floor_tasks.restore(game.floor_tasks.snapshot());event(point,false);await settle()
  check(alive(id),"floor restore invalidates equal numeric identity")
  id=fresh();point=await point_for(id);event(point,true);game.ground_mess_generation+=1;event(point,false);await settle()
  check(alive(id),"runtime restore generation invalidates pending receipt")
  id=fresh();point=await point_for(id);event(point,true)
  identity=game.ground_mess_identity("floor",id);game.complete_ground_mess(identity,"manual");event(point,false);await settle()
  check(game.floor_tasks.completed==1 and cleaner.puffs.is_empty(),"NPC or other completion wins before release")
  id=fresh();point=await point_for(id);var npc=game.worker("cleaner");game.floor_tasks.assign(npc,game.staff_states.find(npc));stale=npc.duplicate(true)
  event(point,true);event(point,false);await settle();game.floor_tasks.contact(stale,game.staff_states.find(npc),"sweeping",{},1)
  check(not alive(id) and npc.job_kind=="" and game.floor_tasks.completed==1,"manual completion releases approach and stale NPC replay is inert")
  # A second finger cancels the existing mouse-emulated world transaction.
  id=fresh();point=await point_for(id);event(point,true,InputEvent.DEVICE_ID_EMULATION)
  for finger in 2:
   var touch=InputEventScreenTouch.new();touch.index=finger;touch.position=point+Vector2(finger*20,0);touch.pressed=true;game.camera_gestures.handle_input(touch)
  event(point,false,InputEvent.DEVICE_ID_EMULATION)
  check(alive(id),"second touch cancels manual pending tap");game.camera_gestures.on_focus_lost()
  # Draw feedback is transient across restore and never serializes into saves.
  id=fresh();point=await point_for(id);event(point,true);event(point,false);await settle()
  game.model.service_snapshot=game._service_save_snapshot()
  check(game.model.save("user://manual-cleanup.json"),"completed cleanup saves during puff: "+game.model.last_error)
  check(game.model.load_save("user://manual-cleanup.json"),"saved cleanup validates and loads: "+game.model.last_error)
  game._restore_service_runtime();cleaner.tick(.01)
  check(cleaner.puffs.is_empty() and game.floor_tasks.messes.is_empty(),"save restore drops cosmetic puff without resurrecting dirt")
  check(game.model.coins>wallet,"successful player cleanup rewards persist in the generated save")
 reward_visual_checks()
 await coin_audio_checks()
 if DisplayServer.get_name()!="headless":await mesh_runtime_checks()
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
 # A synthetic legacy cleaner already holds trash while a spill remains visible.
 record=game.setup_dirty();janitor=game.legacy_job(record,5,.35)
 var holder=game.staff_states.find(janitor)
 record.trash_owner="staff";record.trash_staff_index=holder;record.trash_target_id=-1
 identity=game.ground_mess_identity("guest",int(record.guest.id))
 check(game.complete_ground_mess(identity,"manual"),"manual click cleans remaining spill beside carried trash")
 check(record.spill_cleaned and record.spill_remaining==0.0 and not record.floor_cleaned,"only visible spill completes while carried obligation remains")
 check(record.trash_owner=="staff" and record.trash_staff_index==holder and record.trash_target_id==-1,"manual spill cleanup preserves garbage custody")
 check(janitor.job_kind=="cleanup" and janitor.job_step==5 and is_equal_approx(janitor.job_elapsed,.35),"manual spill cleanup preserves legacy disposal job and elapsed")
 check(not game.complete_ground_mess(identity,"manual"),"repeat spill click cannot settle carried garbage")
 game.model.service_snapshot=game._service_save_snapshot()
 check(game.model.save("user://manual-carried-spill.json") and game.model.load_save("user://manual-carried-spill.json"),"synthetic carried obligation still validates and reloads")
 game._restore_service_runtime();janitor=game.worker("cleaner");record=game.service_guests[int(record.guest.id)]
 check(record.trash_owner=="staff" and janitor.job_kind=="cleanup" and janitor.job_step==5,"restored cleaner retains carried disposal obligation")
 game._service_contact(janitor,game.staff_states.find(janitor),"disposing_trash",{},1.0)
 game.complete_ground_mess_if_ready(game.ground_mess_identity("guest",int(record.guest.id)))
 check(record.trash_owner=="disposed" and record.floor_cleaned,"existing NPC disposal settles remaining obligation")
 if DisplayServer.get_name()!="headless":
  game.illustration.set_process(true)
  for trial in 3:
   var id=fresh("crumbs");var point=await point_for(id)
   event(point,true);event(point,false);await settle()
   check(not alive(id) and game.floor_tasks.completed==1,"completed-frame cleanup remains usable with active artist repaint "+str(trial))
  game.illustration.set_process(false)
 await fixed_furniture_occlusion_checks()
 var coin_viewport=cleaner.coin_renderer.viewport
 var coin_world=cleaner.coin_renderer.world_root
 var coin_audio_player=cleaner.coin_audio.player
 game.queue_free()
 await process_frame
 await process_frame
 if DisplayServer.get_name()!="headless":check(not is_instance_valid(coin_viewport) and not is_instance_valid(coin_world),"scene exit releases the retained coin viewport and mesh world")
 check(not is_instance_valid(coin_audio_player) and cleaner.coin_audio.playback==null and cleaner.coin_audio.active.is_empty(),"scene exit releases the cleanup audio player and playback voices")
 var drain=await AudioDrain.wait_for_mixer_cycles(self)
 check(drain.ok,"cleanup fixture teardown observes mixer retirement")
 print("AUDIO_TEARDOWN_RESULT ",JSON.stringify(drain))
 print("MANUAL_GROUND_CLEANUP_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"player_save_used":false,"native_render_verified":DisplayServer.get_name()!="headless","pointer_checks_skipped":DisplayServer.get_name()=="headless","fixed_occlusion_observations":occlusion_observations}))
 quit(0 if failures.is_empty() else 1)

func reward_visual_checks():
 var legacy_owner=Node.new()
 var unsupported=cleaner.get_script().new(legacy_owner)
 unsupported.hover(Vector2.ZERO)
 check(not unsupported.tick(.1) and unsupported.hovered.is_empty() and unsupported.puffs.is_empty(),"historical owner without cleanup authority never enters hover projection")
 legacy_owner.free()
 var wallet=game.model.coins
 var served=game.model.served
 var id=fresh("crumbs")
 var entry=game.floor_tasks.messes[id]
 var shape_before=entry.mess_shape.duplicate(true)
 var world:Vector2=entry.mess_shape.pieces[0].center
 var point:Vector2=game.illustration.iso(world.x,world.y)
 var identity=game.ground_mess_identity("floor",id)
 var hit_before=cleaner.hit(point,false)
 cleaner.hover(point)
 check(cleaner.hovered==hit_before and not hit_before.is_empty(),"hover uses original litter silhouette")
 check(cleaner.hit(point,false)==hit_before and entry.mess_shape==shape_before,"hover never changes hit geometry or saved shape")
 check(game.model.coins==wallet,"hover never rewards")
 cleaner.hover(Vector2(-20,-20))
 check(cleaner.hovered.is_empty(),"hover exits outside viewport")
 cleaner.hover(point);game.paused=true;cleaner.tick(0)
 check(cleaner.hovered.is_empty(),"Pause clears hover")
 game.paused=false
 check(cleaner._complete(identity),"player transaction completes standalone litter")
 check(game.model.coins==wallet+1 and game.model.served==served,"standalone cleanup earns exactly one and no served reward")
 check(not cleaner._complete(identity) and game.model.coins==wallet+1,"removed identity never rewards twice")
 check(cleaner.puffs.size()==1 and cleaner.puffs[0].record.mess_shape==shape_before,"effect preserves original pre-completion geometry snapshot")
 check(is_equal_approx(cleaner.pop_scale(0),1.0) and is_equal_approx(cleaner.pop_scale(cleaner.POP_PEAK_SECONDS),cleaner.POP_PEAK_SCALE) and is_zero_approx(cleaner.pop_scale(cleaner.POP_SECONDS)),"litter slightly enlarges then shrinks to zero")
 check(cleaner.coin_phase(cleaner.COIN_DELAY-.01).is_empty(),"coin waits for click pop")
 check(is_equal_approx(cleaner.coin_phase(cleaner.COIN_DELAY+.35).height,26.0),"coin initial emergence apex")
 check(is_zero_approx(cleaner.coin_phase(cleaner.COIN_DELAY+.70).height),"coin first lands on ground")
 check(is_equal_approx(cleaner.coin_phase(cleaner.COIN_DELAY+.92).height,12.0),"first rebound apex")
 check(is_zero_approx(cleaner.coin_phase(cleaner.COIN_DELAY+1.14).height),"first rebound returns to ground")
 check(is_equal_approx(cleaner.coin_phase(cleaner.COIN_DELAY+1.30).height,4.8),"second smaller rebound apex")
 check(is_zero_approx(cleaner.coin_phase(cleaner.COIN_DELAY+1.46).height),"second rebound settles on ground")
 check(cleaner.coin_phase(cleaner.COIN_DELAY+1.95).alpha>0 and cleaner.coin_phase(cleaner.COIN_DELAY+1.95).alpha<.4,"coin gradually fades during pickup ascent")
 check(cleaner.coin_phase(cleaner.COIN_DELAY+2.10).is_empty(),"coin fully expires")
 var prior_height=0.0
 for ascent in [1.60,1.70,1.85,2.0,2.09]:
  var phase=cleaner.coin_phase(cleaner.COIN_DELAY+ascent)
  check(phase.height>=prior_height and phase.travel==1.0,"pickup translates vertically from settled ground at "+str(ascent))
  prior_height=phase.height
 check(prior_height>50.0,"pickup travels visibly upward before disappearing")
 check(is_equal_approx(cleaner.coin_phase(cleaner.COIN_DELAY+cleaner.COIN_PICKUP_START).alpha,1.0),"pickup starts from a full-proportion visible coin")
 check(cleaner.POP_PEAK_SCALE>=1.45 and cleaner.POP_SECONDS>=.50,"larger and longer pop is visible without changing picking")
 check(cleaner.coin_renderer.load_model(),"actual editable GLB imports as a PackedScene")
 var renderer=cleaner.coin_renderer
 check(renderer.mesh_surface_count==3 and renderer.mesh_triangle_count==1536,"real indexed mesh has front back and beveled edge surfaces")
 check(renderer.model_bounds.size.is_equal_approx(Vector3(2,2,.32)),"real model has diameter2 and physical thickness.32")
 var vertex=Vector3(.8,.3,.14);var other=Vector3(-.2,-.6,-.14)
 for turn in [0.0,.4,PI*.5,2.2,PI,4.0,PI*1.5,5.8]:
  var pose=renderer.pose_basis(turn,.08)
  check(is_equal_approx((pose*vertex).distance_to(pose*other),vertex.distance_to(other)) and is_equal_approx(pose.determinant(),1.0),"actual Node3D basis is rigid at angle "+str(turn))
 check(renderer.support_clearance(renderer.pose_basis(PI*.5,.08),9.0)>8.0,"ground support derives from actual mesh vertices")
 cleaner.coin_rng.seed=20261013
 var first=cleaner.new_coin_motion(entry.floor_target)
 var next=cleaner.new_coin_motion(entry.floor_target)
 cleaner.coin_rng.seed=20261013
 check(first==cleaner.new_coin_motion(entry.floor_target),"cosmetic test seed reproduces one immutable emission")
 check(first.direction!=next.direction,"successive emissions vary lateral direction")
 check(first.distance>0 and first.distance<=cleaner.COIN_TRAVEL_MAX and is_equal_approx(first.direction.length(),1.0),"cosmetic travel is short and bounded")
 check(cleaner.coin_path_clear(entry.floor_target,first.direction,first.distance),"cosmetic trajectory stays on usable floor")
 var synthetic={"at":entry.floor_target,"coin_motion":first}
 var previous=0.0
 for time in [.0,.35,.70,.92,1.14,1.30,1.46,1.95]:
  var phase=cleaner.coin_phase(cleaner.COIN_DELAY+time,first)
  check(phase.travel>=previous and phase.travel<=1.0,"lateral progress continues without resetting "+str(time));previous=phase.travel
 for time in [.70,1.14,1.46]:
  var before=cleaner.coin_ground(synthetic,cleaner.coin_phase(cleaner.COIN_DELAY+time-.0001,first))
  var after=cleaner.coin_ground(synthetic,cleaner.coin_phase(cleaner.COIN_DELAY+time+.0001,first))
  check(before.distance_to(after)<.001,"ground anchor is continuous across contact "+str(time))
 check(cleaner.coin_ground(synthetic,cleaner.coin_phase(cleaner.COIN_DELAY+1.46,first)).distance_to(entry.floor_target)>0.1,"coin settles away from emission point")
 cleaner.tick(cleaner.EFFECT_SECONDS+.1)
 check(cleaner.puffs.is_empty() and game.model.coins==wallet+1,"effect retirement cannot issue more coins")
 id=fresh("crumbs");identity=game.ground_mess_identity("floor",id)
 check(game.complete_ground_mess(identity,"manual"),"shared cleanup can win before player")
 check(not cleaner._complete(identity) and game.model.coins==wallet+1,"domain/NPC completion does not grant player coin")
 var record=game.setup_dirty();identity=game.ground_mess_identity("guest",int(record.guest.id))
 check(cleaner._complete(identity) and game.model.coins==wallet+2,"retained guest cleanup earns one coin")
 check(not cleaner._complete(identity) and game.model.coins==wallet+2,"retained guest identity cannot reward again")
 cleaner.tick(.1);game.ground_mess_generation+=1;cleaner.tick(.1)
 check(cleaner.puffs.is_empty(),"restore generation removes cosmetic coin and litter snapshots")
 id=fresh("crumbs");identity=game.ground_mess_identity("floor",id);game.model.coins=999999999
 check(cleaner._complete(identity) and game.model.coins==1000000000,"last legal wallet coin is awarded exactly")
 id=fresh("crumbs");identity=game.ground_mess_identity("floor",id)
 check(not cleaner._complete(identity) and alive(id) and game.model.coins==1000000000,"full wallet preserves litter and loadable balance")
 game.model.coins=wallet+2

func coin_audio_checks():
 var id=fresh("crumbs")
 var identity=game.ground_mess_identity("floor",id)
 var settings=game.settings_controls
 settings.sfx_player.stop()
 check(cleaner._complete(identity),"sound fixture completes one real cleanup transaction")
 check(not settings.sfx_player.playing,"cleanup click does not emit the cash-settlement sound")
 var wallet=game.model.coins
 var initial_puff:Dictionary=cleaner.puffs[0].duplicate(true)
 var audio=cleaner.coin_audio
 audio.stop()
 var recorder=SfxEvents.new();cleaner.coin_audio=recorder
 var expected=[]
 for contact in cleaner.COIN_CONTACTS:
  var when=cleaner.COIN_DELAY+float(contact[0])
  cleaner.tick(when-.0001-float(cleaner.puffs[0].age))
  check(recorder.events==expected,"contact cue never precedes its actual landing at "+str(contact[0]))
  check(is_zero_approx(cleaner.coin_phase(when).height),"audio contact corresponds to a true geometric landing at "+str(contact[0]))
  cleaner.tick(.0002);expected.append(["coin_drop",float(contact[1])])
  check(recorder.events==expected,"each distinct landing emits one correctly attenuated cue at "+str(contact[0]))
  cleaner.tick(0);cleaner.tick(-.2)
  check(recorder.events==expected,"resting or repeated ticks never replay a landing at "+str(contact[0]))
 check(expected[0][1]>expected[1][1] and expected[1][1]>expected[2][1],"successively smaller bounces have progressively lower gain")
 cleaner.tick(cleaner.COIN_DELAY+cleaner.COIN_PICKUP_START-.0001-float(cleaner.puffs[0].age))
 check(recorder.events==expected,"pickup waits until upward ascent")
 cleaner.tick(.0002);expected.append(["coin_pickup",0.0])
 check(recorder.events==expected,"pickup starts once at unchanged upward ascent")
 cleaner.tick(.03);cleaner.tick(cleaner.EFFECT_SECONDS)
 check(recorder.events==expected and cleaner.puffs.is_empty(),"ascent and retirement never duplicate contact or pickup events")
 check(game.model.coins==wallet,"contacts and pickup never award a second reward")
 cleaner.puffs=[initial_puff.duplicate(true)];recorder.events.clear()
 cleaner.tick(cleaner.EFFECT_SECONDS+.1)
 check(recorder.events==expected,"one slow frame retains all three genuine contacts then pickup, exactly once")
 cleaner.tick(0);cleaner.tick(.2)
 check(recorder.events==expected,"slow-frame retirement does not replay missed frames")
 cleaner.puffs=[initial_puff.duplicate(true)];recorder.events.clear()
 game.ground_mess_generation+=1;cleaner.tick(cleaner.EFFECT_SECONDS+.1)
 check(recorder.events.is_empty() and cleaner.puffs.is_empty(),"restore retires the old effect before any delayed sound")
 cleaner.coin_audio=audio;audio.tick(cleaner._epoch())
 var sources={"coin_drop":"38a3c91cb0180a892a8e37f15b6b4cf95232558c70dc49a4396c0e0288f0172a","coin_pickup":"d269638b92f9852eb32239667262ea31143142e90a3bfe72ff793860bc232991"}
 for kind in sources:
  var stream=settings.effects.get(kind)
  check(stream is AudioStreamMP3 and not stream.loop,"cleanup feedback imports as a finite original MP3: "+kind)
  if not stream is AudioStreamMP3:continue
  var digest=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(stream.data)
  check(digest.finish().hex_encode()==sources[kind],"cleanup feedback retains exact supplied compressed bytes: "+kind)
  check(audio.play(kind),"actual cleanup voice starts the original sound: "+kind)
  check(audio.playback.is_stream_playing(audio.active.back()),"actual polyphonic playback owns the sound: "+kind)
  audio.stop()
 var was_enabled=settings.sfx_enabled;var volume=settings.sfx_volume
 settings.set_audio_enabled("SFX",false)
 check(not audio.play("coin_drop") and audio.active.is_empty(),"disabled SFX suppresses cleanup drop")
 settings.set_audio_enabled("SFX",true);settings.set_audio_volume("SFX",0.0)
 check(not audio.play("coin_pickup") and audio.active.is_empty(),"zero SFX volume suppresses cleanup pickup")
 settings.set_audio_volume("SFX",volume);settings.set_audio_enabled("SFX",was_enabled)
 check(audio.player.bus=="SFX" and audio.player.stream.polyphony==audio.MAX_VOICES,"cleanup keeps one bounded scene-owned player on the existing preference bus")
 var observed=[]
 var capture_cue=func(kind,volume_db,voice_id):observed.append([kind,volume_db,voice_id])
 audio.cue_started.connect(capture_cue)
 var prior_cash=settings.sfx_player.stream
 for cue in expected:check(audio.play(cue[0],cue[1]),"slow-frame cue receives an independent playback voice: "+str(cue))
 check(audio.active.size()==4,"a slow frame retains four overlapping voices rather than replacing earlier contacts")
 var ids={}
 for voice_id in audio.active:ids[voice_id]=true
 check(ids.size()==4 and observed.size()==4,"distinct contacts have distinct active playback identities")
 check(settings.sfx_player.stream==prior_cash and not settings.sfx_player.playing,"per-contact gain never changes or starts the cash/place voice")
 for i in expected.size():check(observed[i][0]==expected[i][0] and observed[i][1]==expected[i][1],"actual cue uses its isolated per-impact gain "+str(i))
 audio.cue_started.disconnect(capture_cue)
 # Observe real mixer retirement; a simulated timer does not certify audio completion.
 var retirement_deadline=Time.get_ticks_usec()+2000000
 while not audio.active.is_empty() and Time.get_ticks_usec()<retirement_deadline:
  await process_frame
  audio.tick(cleaner._epoch())
 check(audio.active.is_empty() and audio.playback==null and not audio.player.playing,"finished cleanup voices retire and the idle mixer player stops")
 var player_id=audio.player.get_instance_id()
 check(audio.play("coin_drop",-4.0) and audio.player.get_instance_id()==player_id,"later cleanup reuses its one scene-owned player")
 game.ground_mess_generation+=1;audio.tick(cleaner._epoch())
 check(audio.active.is_empty() and audio.playback==null and not audio.player.playing,"restore immediately retires old cleanup audio voices")

func mesh_runtime_checks():
 var id=fresh("crumbs");var identity=game.ground_mess_identity("floor",id)
 check(cleaner._complete(identity),"mesh fixture uses original successful cleanup authority")
 cleaner.puffs[0].age=cleaner.COIN_DELAY+.35
 for frame in range(3):game.illustration.queue_redraw();await settle()
 var renderer=cleaner.coin_renderer
 check(is_instance_valid(renderer.viewport) and renderer.viewport is SubViewport and renderer.viewport.own_world_3d,"real meshes render in an isolated SubViewport World3D")
 check(renderer.camera is Camera3D and renderer.camera.current,"real Camera3D renders the coin mesh")
 check(renderer.active_count==1 and renderer.pool.size()==1,"one successful effect activates one bounded model slot")
 check(renderer.pool[0].meshes[0].node is MeshInstance3D,"rendered coin is an actual MeshInstance3D")
 check(renderer.viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_OBJECTS_IN_FRAME)>0,"native viewport reports actual3D rendered objects")
 check(renderer.viewport.get_texture().get_image().get_used_rect().has_area(),"actual3D viewport contains visible coin pixels")
 print("COIN_MESH_ACTIVE_RECEIPT ",JSON.stringify(renderer.receipt()))
 renderer.world_root.visible=false
 for frame in range(3):game.illustration.queue_redraw();await settle()
 check(not renderer.viewport.get_texture().get_image().get_used_rect().has_area(),"hiding actual3D nodes removes the coin from the viewport")
 renderer.world_root.visible=true
 for frame in range(3):game.illustration.queue_redraw();await settle()
 var normal_scale=renderer.pool[0].root.basis.get_scale()
 for ascent in [1.60,1.75,1.90,2.05]:
  cleaner.puffs[0].age=cleaner.COIN_DELAY+ascent
  for frame in range(3):game.illustration.queue_redraw();await settle()
  check(renderer.pool[0].root.basis.get_scale().is_equal_approx(normal_scale),"actual pickup mesh retains all three axis lengths at "+str(ascent))
 cleaner.puffs[0].age=cleaner.COIN_DELAY+.35
 for frame in range(3):game.illustration.queue_redraw();await settle()
 var original_basis=renderer.pool[0].root.basis
 cleaner.puffs[0].age+=.2
 for frame in range(3):game.illustration.queue_redraw();await settle()
 check(not renderer.pool[0].root.basis.is_equal_approx(original_basis),"runtime rotation changes the actual Node3D basis")
 var duplicate:Dictionary=cleaner.puffs[0].duplicate(true);duplicate.age=cleaner.COIN_DELAY+1.85;duplicate.at+=Vector2(.08,.05);cleaner.puffs.append(duplicate)
 for frame in range(3):game.illustration.queue_redraw();await settle()
 check(renderer.active_count==2 and renderer.pool.size()==2,"overlapping effects own two real models")
 check(not is_same(renderer.pool[0].materials[0].material,renderer.pool[1].materials[0].material),"each model has independent material fade state")
 check(renderer.pool[0].materials[0].material.albedo_color.a>renderer.pool[1].materials[0].material.albedo_color.a,"one fading coin cannot change the newer coin's opacity")
 # Pixel proof: two coincident half-faded solids must accumulate alpha rather
 # than let the nearer transparent model erase the one behind it.
 var original_puffs=cleaner.puffs.duplicate(true)
 cleaner.puffs=[cleaner.puffs[0].duplicate(true)]
 cleaner.puffs[0].age=cleaner.COIN_DELAY+(cleaner.COIN_PICKUP_START+.08+cleaner.COIN_SECONDS)*.5
 for frame in range(3):game.illustration.queue_redraw();await settle()
 var logical_size:Vector2=game.illustration.get_viewport_rect().size
 var model_center:Vector3=renderer.pool[0].root.position
 var sample_point=Vector2i((Vector2(model_center.x+logical_size.x*.5,logical_size.y*.5-model_center.y)*Vector2(renderer.viewport.size)/logical_size).round())
 var single_alpha=renderer.viewport.get_texture().get_image().get_pixelv(sample_point).a
 cleaner.puffs.append(cleaner.puffs[0].duplicate(true))
 for frame in range(3):game.illustration.queue_redraw();await settle()
 var double_alpha=renderer.viewport.get_texture().get_image().get_pixelv(sample_point).a
 check(single_alpha>.4 and single_alpha<.6 and double_alpha>single_alpha+.15,"native half-fade overlap retains both transparent meshes")
 print("COIN_MESH_OVERLAP_PIXELS ",JSON.stringify({"point":str(sample_point),"single_alpha":single_alpha,"double_alpha":double_alpha}))
 cleaner.puffs=original_puffs
 for frame in range(3):game.illustration.queue_redraw();await settle()
 var before_pan=renderer.pool[0].root.position
 game.interaction._pan_by(Vector2(28,14))
 for frame in range(3):game.illustration.queue_redraw();await settle()
 var after_pan=renderer.pool[0].root.position
 check(Vector2(after_pan.x-before_pan.x,-after_pan.y+before_pan.y).distance_to(Vector2(28,14))<.1,"camera pan reaches the 3D mesh exactly once")
 game.interaction._pan_by(Vector2(-28,-14))
 var mesh_id=renderer.pool[0].root.get_instance_id()
 var material_id=renderer.pool[0].materials[0].material.get_instance_id()
 var viewport_id=renderer.viewport.get_instance_id()
 game.editing=true
 for frame in range(3):game.illustration.queue_redraw();await settle()
 check(renderer.active_count==0 and renderer.viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"Decorate hides3Dcoins and disables updates")
 game.editing=false
 for frame in range(3):game.illustration.queue_redraw();await settle()
 check(renderer.pool[0].root.get_instance_id()==mesh_id and renderer.pool[0].materials[0].material.get_instance_id()==material_id and renderer.viewport.get_instance_id()==viewport_id,"existing viewport mesh and materials are reused after mode switch")
 var original_zoom=game.illustration.zoom
 game.illustration.zoom=1.8;game.illustration.update_projection()
 for frame in range(3):game.illustration.queue_redraw();await settle()
 var expected_radius=9.0*game.illustration.ui_scale*game.illustration.zoom*(1.55 if game.wall_detail else 1.0)
 check(absf(renderer.pool[0].root.basis.get_scale().x-expected_radius)<.01,"camera zoom scales the actual mesh without changing its geometry")
 game.illustration.zoom=original_zoom;game.illustration.update_projection()
 var old_size=root.size;root.size=Vector2i(1100,760)
 for frame in range(3):game.illustration.queue_redraw();await settle()
 check(is_equal_approx(renderer.camera.size,game.illustration.get_viewport_rect().size.y),"3D camera follows resized logical viewport height")
 root.size=old_size
 for frame in range(3):game.illustration.queue_redraw();await settle()
 var template:Dictionary=cleaner.puffs[0].duplicate(true)
 for i in range(35):cleaner.puffs.append(template.duplicate(true))
 for frame in range(3):game.illustration.queue_redraw();await settle()
 check(renderer.pool.size()==renderer.MAX_MODELS and renderer.active_count==renderer.MAX_MODELS,"3Dmodel pool and active rendering remain capped at32")
 game.ground_mess_generation+=1;cleaner.tick(0)
 for frame in range(3):game.illustration.queue_redraw();await settle()
 check(cleaner.puffs.is_empty() and renderer.active_count==0,"epoch restoration removes3D geometry and cosmetic state")
 cleaner.puffs.clear()
 for frame in range(3):game.illustration.queue_redraw();await settle()
 check(renderer.active_count==0 and renderer.viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"expired effects stop 3D viewport updates and texture submission")
 check(not renderer.pool[0].root.visible and not renderer.pool[1].root.visible,"expired models are hidden without ghost geometry")
 print("COIN_MESH_RUNTIME_RECEIPT ",JSON.stringify(renderer.receipt()))

func fixed_furniture_occlusion_checks():
 # Generated fixture, not a reconstruction of the user's cropped screenshot.
 # Coordinates derive from the authored round table, not hit() or a pixel scan.
 # x=28 is beyond its painted top/legs but inside the legacy +/-30 box;
 # (20,-24) lies on its opaque top. Both point at a saved paper silhouette.
 game.model.items.clear();game.model.dining_sets.clear();game.model.coins=100000
 game.model._notify()
 check(game.model.place("table_set",4,4),"fixed occlusion table fixture")
 game._rebuild_furniture();game._update_ui()
 var art=game.illustration
 for camera in ["normal","detail","zoom-pan"]:
  for exposed in [true,false]:
   var id=fresh("crumbs")
   check(id>=0,"fixed litter fixture can spawn")
   if id<0:continue
   for staff in game.staff_states:staff.pos=Vector2(-10,-10)
   game.wall_detail=camera=="detail";art.zoom=1.15
   art.pan_offset=Vector2.ZERO;art.update_projection()
   if camera=="zoom-pan":art.zoom=art.camera_zoom_limits().y;art.update_projection()
   var local=Vector2(28,-15) if exposed else Vector2(20,-24)
   var point=art.iso(4.5,4.5)+local*art.ui_scale*art.zoom*(1.55 if game.wall_detail else 1.0)
   game.interaction._pan_by(art.camera_safe_rect().get_center()-point)
   point=art.iso(4.5,4.5)+local*art.ui_scale*art.zoom*(1.55 if game.wall_detail else 1.0)
   var world=art.screen_to_world(point)
   var record=game.floor_tasks.messes[id]
   var piece={"kind":"paper","center":world,"angle":0.0,"size":.5}
   record.floor_cell=Vector2i(world.floor());record.floor_target=world
   record.debris_target=world;record.spill_target=world
   record.mess_shape={"version":1,"seed":1,"center":world,"outline":game.floor_tasks.geometry.piece_bounds(piece),"spill_outline":[],"pieces":[piece]}
   check(art.hit_item(point)>=0,"fixed "+camera+" point reproduces old rectangle rejection")
   check(cleaner.hit(point,false)==game.ground_mess_identity("floor",id),"fixed "+camera+" point hits original paper without searching picker")
   if DisplayServer.get_name()=="headless":
    # Dummy runs the real retained draw callbacks, but has no presented-image
    # signal. Inspect their completed commands only; never fabricate a frame
    # receipt or claim a pointer transaction/pixel result in this branch.
    art.queue_redraw()
    for frame in 4:await process_frame
    var covered=fixed_command_coverage(point)
    check(covered==(0 if exposed else 1),"actual retained table commands match fixed "+camera+(" exposed" if exposed else " covered")+" point")
    occlusion_observations.append({"scene":camera+("-exposed" if exposed else "-covered"),"pointer":[point.x,point.y],"table_local_point":[local.x,local.y],"command_coverage":covered,"native_pointer_skipped":true})
    continue
   # Normal/detail await actual paint for optional baseline evidence. Zoom-pan
   # deliberately taps immediately after projection changes, requiring a fresh
   # completed receipt rather than reusing the previous camera's commands.
   if camera!="zoom-pan":art.queue_redraw();await settle();await settle()
   var label=camera+("-exposed" if exposed else "-covered")
   var capture=OS.get_environment("LL_CAPTURE_OUTPUT")
   if capture!="" and camera!="zoom-pan" and DisplayServer.get_name()!="headless":
    check(root.get_texture().get_image().save_png(capture.path_join("ground-"+label+".png"))==OK,"capture actual fixed "+label)
   var wallet=game.model.coins
   event(point,true);event(point,false);await settle();await settle()
   check(alive(id)!=exposed,"fixed "+label+" respects actual painted coverage")
   check(game.model.coins==wallet+(1 if exposed else 0),"fixed "+label+" rewards only visible completed litter")
   occlusion_observations.append({"scene":label,"pointer":[point.x,point.y],"table_local_point":[local.x,local.y],"expected_cleaned":exposed,"cleaned":not alive(id),"legacy_box_hits":true})

 # Native-slot counters stay at zero in immediate fallback, but that empty
 # range must never certify furniture/walls as absent from the painted scene.
 for flag in ["use_command_retention","use_retained_geometry","use_native_object_nodes"]:
  art.set(flag,false);art.queue_redraw()
  for frame in 4:await process_frame
  check(art.ground_occlusion_start==-1 and art.ground_occlusion_end==-1,"immediate painter invalidates ground span when "+flag+" is disabled")
  art.set(flag,true)
 art.queue_redraw()
 for frame in 4:await process_frame
 check(art.ground_occlusion_start>=0 and art.ground_occlusion_end>art.ground_occlusion_start,"retained painter restores a nonempty world span after fallback")

func fixed_command_coverage(point:Vector2)->int:
 var art=game.illustration
 var pick=art.character_pick_geometry
 var images={}
 for nodes in [art.native_object_nodes,art.native_world_shapes]:
  for order in nodes:
   if order<art.ground_occlusion_start or order>=art.ground_occlusion_end:continue
   var result=pick._node_hit(nodes[order],point,art.modulate.a,images)
   if result!=0:return result
 return 0
