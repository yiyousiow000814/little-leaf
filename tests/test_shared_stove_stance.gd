extends SceneTree
class GeneratedMain extends "res://scripts/main.gd":
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
var checks=0;var failures=[];var frames=[]
var output=OS.get_environment("LL_SHARED_STOVE_OUTPUT")
func _initialize():root.size=Vector2i(1360,880);run.call_deferred()
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func capture(g,label):
 if output=="":return
 g._update_ui();var art=g.illustration
 art.zoom=1.0;art.pan_offset=Vector2.ZERO;art.update_projection()
 var stove=g.model.get_item(1)
 art.pan_offset+=art.camera_play_rect().get_center()-(art.iso(stove.x+.5,stove.z+.5)+Vector2(0,-18)*art.ui_scale)
 art.update_projection();art.queue_redraw();await process_frame;await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(output.path_join(label+".png"))
 frames.append({"file":label+".png","contacts":art.render_contacts.duplicate(true),"staff":g._service_save_snapshot().staff})
func run():
 if output!="" and (DisplayServer.get_name()=="headless" or not "saveguard" in OS.get_user_data_dir()):quit(2);return
 if output!="":DirAccess.make_dir_recursive_absolute(output)
 for rotation in range(4):
  seed(123456)
  var g=GeneratedMain.new();root.add_child(g);g.set_process(false);g.illustration.set_process(false)
  var stove=g.model.get_item(1);stove.x=8;stove.z=4;stove.rot=rotation;g.model._notify();g._rebuild_furniture();g._refresh_idle_homes()
  g.model._spawn_customer();var guest=g.model.customers[0];guest.phase="cooking";g._sync_service_guests()
  var record=g.service_guests[int(guest.id)];record.order_done=true;record.meal_ready=true;record.meal_station_id=stove.id;record.plate_owner="station";record.plate_target_id=stove.id
  var chef=g.staff_states.filter(func(s):return s.role=="chef")[0]
  var waiter=g.staff_states.filter(func(s):return s.role=="waiter")[0]
  var face=g.model.workface_cell(stove);var anchor=Vector2(face)+Vector2(.5,.5)
  chef.pos=anchor;chef.destination=face;chef.path=[face];chef.index=1;chef.job_kind=""
  chef.idle_home_id=stove.id;chef.idle_home_cell=face
  waiter.pos=anchor;waiter.destination=face;waiter.path=[face];waiter.index=1
  waiter.job_kind="deliver_meal";waiter.job_step=0;waiter.station_id=stove.id;waiter.job_guest_id=guest.id;waiter.job_token=record.token
  g._set_staff_art(chef,"idle",{},0)
  g._set_staff_art(waiter,"collecting_plate",stove,.55)
  var before=g._service_save_snapshot();var art=g.illustration
  for tick in range(30):art.update_motion(.025)
  check(g._service_save_snapshot()==before,"presentation preserves all service state r"+str(rotation))
  var chef_index=g.staff_states.find(chef);var waiter_index=g.staff_states.find(waiter)
  var chef_pos=art._render_position("staff_%s"%chef_index,chef.pos)
  var waiter_pos=art._render_position("staff_%s"%waiter_index,waiter.pos)
  check(absf((chef_pos.x-chef_pos.y)-(waiter_pos.x-waiter_pos.y))>.5,"distinct projected horizontal body anchors r"+str(rotation))
  check(chef.pos==waiter.pos and chef.pos==anchor,"shared authoritative workface unchanged r"+str(rotation))
  await capture(g,"before-contact-r"+str(rotation))
  waiter.job_token=-99
  check(not art.has_method("_pickup_idle_stances") or art._pickup_idle_stances().is_empty(),"stale meal cannot shift idle chef r"+str(rotation))
  waiter.job_token=record.token
  chef.job_kind="cook"
  for tick in range(30):art.update_motion(.025)
  check(art.stance_offsets["staff_%s"%chef_index]==Vector2.ZERO,"active chef retains ordinary stance r"+str(rotation))
  chef.job_kind=""
  var seen_before=false;var seen_after=false;var seen_departure=false
  waiter.job_elapsed=0
  for tick in range(100):
   g._animate_staff(.025);g.animation_time+=.025;art.update_motion(.025)
   if waiter.art_action=="collecting_plate" and waiter.art_phase>=.5 and waiter.art_phase<.65 and not seen_before:
    seen_before=true;await capture(g,"actual-before-r"+str(rotation))
   if waiter.art_action=="collecting_plate" and waiter.art_phase>=.65 and not seen_after:
    seen_after=true
    check(record.plate_owner=="staff" and int(record.plate_staff_index)==waiter_index,"actual contact transfers plate once r"+str(rotation))
    await capture(g,"actual-after-r"+str(rotation))
   if waiter.job_step==1 and not seen_departure:
    seen_departure=true;await capture(g,"departure-r"+str(rotation))
  if not (seen_before and seen_after and seen_departure):print("SHARED_STOVE_INCOMPLETE ",JSON.stringify({"rotation":rotation,"before":seen_before,"after":seen_after,"departure":seen_departure,"waiter":waiter,"chef":chef,"record":record}))
  check(seen_before and seen_after and seen_departure,"actual Main handoff reaches departure r"+str(rotation))
  for tick in range(30):art.update_motion(.025)
  check((not art.has_method("_pickup_idle_stances") or art._pickup_idle_stances().is_empty()) and art.stance_offsets["staff_%s"%chef_index]==Vector2.ZERO,"idle body offset releases after pickup r"+str(rotation))
  for player in g.audio_players.values():player.stop();player.stream=null
  g.settings_controls.sfx_player.stop();g.settings_controls.sfx_player.stream=null
  for tween in get_processed_tweens():tween.kill()
  g.queue_free();await process_frame;await process_frame
 if output!="":FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"frames":frames,"normal_scale":true,"player_save_used":false},"  "))
 print("SHARED_STOVE_STANCE_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 quit(0 if failures.is_empty() else 1)
