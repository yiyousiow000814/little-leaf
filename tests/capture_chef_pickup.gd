extends SceneTree
## Frozen real-production frames. Generated profiles only; never player saves.
class GeneratedMain extends "res://scripts/main.gd":
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
var output=OS.get_environment("CHEF_PICKUP_CAPTURE_OUTPUT")
var validate_only="--validate-fixture" in OS.get_cmdline_user_args()
var frames=[];var checks=0;var failures=[]
const STAGES=["cooking","chef_before","ready","waiter_before","waiter_after","carrying","served"]
func _initialize():root.size=Vector2i(1360,880);run.call_deferred()
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func run():
 if not validate_only and (DisplayServer.get_name()=="headless" or output==""):printerr("Native renderer and output path required");quit(2);return
 if not validate_only:DirAccess.make_dir_recursive_absolute(output)
 for rotation in range(4):
  seed(123456)
  var game=GeneratedMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false)
  game.tutorial.skip();game.cafe_intro.active=false;game.editing=false;game.paused=false
  var stove=game.model.get_item(1);stove.x=8;stove.z=4;stove.rot=rotation
  game.model._notify();game._rebuild_furniture();game.idle_home_revision=-1
  game.model._spawn_customer();var seen={};var previous={};var actor={}
  for tick in range(16000):
   game.model._arrival_elapsed=0.0;game._tick_live_service(.025);game._animate_staff(.025);game.animation_time+=.025;game.illustration.update_motion(.025)
   if game.service_guests.is_empty():continue
   var record=game.service_guests.values()[0]
   var stage=""
   for worker in game.staff_states:
    if int(worker.job_guest_id)!=int(record.guest.id):continue
    if worker.art_action=="cooking" and worker.job_elapsed>=1.0:stage="cooking";actor=worker
    elif worker.art_action=="placing_plate" and worker.art_phase>=.55 and worker.art_phase<.65:stage="chef_before";actor=worker
    elif worker.art_action=="collecting_plate" and worker.art_phase>=.55 and worker.art_phase<.65:stage="waiter_before";actor=worker
    elif worker.art_action=="collecting_plate" and worker.art_phase>=.65 and worker.art_phase<.78:stage="waiter_after";actor=worker
    elif worker.job_kind=="deliver_meal" and worker.job_step==1 and worker.art_action=="carrying_plate" and worker.pos.distance_to(Vector2(stove.x+.5,stove.z+.5))>1.25:stage="carrying";actor=worker
   if record.meal_ready and record.plate_owner=="station":
    if not seen.has("ready"):stage="ready"
   if record.plate_owner=="table":stage="served"
   if stage=="" or seen.has(stage):continue
   seen[stage]=true
   check(record.meal_pass_id==-1 and not record.pass_reserved,"no counter claim "+stage+str(rotation))
   if stage=="ready":check(record.plate_target_id==stove.id,"ready dish remains on own stove")
   if stage=="waiter_after":check(record.plate_owner=="staff" and actor.art_payload=="plate","pickup has one waiter-owned plate")
   if stage=="carrying":check(not game._service_station("stove",Vector2i(2,2),-1).is_empty(),"stove reusable during waiter delivery")
   var receipt={"stage":stage,"rotation":rotation,"token":record.token,"owner":record.plate_owner,"plate_target":record.plate_target_id,"plate_staff":record.plate_staff_index,"meal_ready":record.meal_ready,"actor_position":actor.get("pos",Vector2.ZERO),"actor_action":actor.get("art_action",""),"actor_phase":actor.get("art_phase",0),"path":actor.get("path",[]),"path_index":actor.get("index",0),"station_id":stove.id}
   await capture(game,stage+"-r"+str(rotation),Vector2(stove.x+.5,stove.z+.5) if stage!="served" else Vector2(record.guest.x,record.guest.z),receipt)
   if stage in ["waiter_before","waiter_after"]:
    var held=[actor.pos,actor.job_elapsed,actor.job_step,record.plate_owner,record.plate_target_id,record.plate_staff_index,record.token]
    var worker_index=game.staff_states.find(actor)
    game.model.service_snapshot=game._service_save_snapshot()
    check(game.model.save("user://pickup-contact.json"),"generated handoff snapshot saves")
    check(game.model.load_save("user://pickup-contact.json"),"generated handoff snapshot reloads")
    game._restore_service_runtime();stove=game.model.get_item(1);actor=game.staff_states[worker_index];record=game.service_guests.values()[0]
    check(held[0].distance_to(actor.pos)<.00001 and is_equal_approx(float(held[1]),float(actor.job_elapsed)) and int(held[2])==int(actor.job_step) and str(held[3])==str(record.plate_owner) and int(held[4])==int(record.plate_target_id) and int(held[5])==int(record.plate_staff_index) and int(held[6])==int(record.token),"reload cannot teleport or replay handoff "+stage)
   if seen.size()==STAGES.size():break
  check(seen.size()==STAGES.size(),"complete real handoff sequence r"+str(rotation)+" "+str(seen.keys()))
  for player in game.audio_players.values():player.stop();player.stream=null
  game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
  for tween in get_processed_tweens():tween.kill()
  game.queue_free();await process_frame;await process_frame
 if not validate_only:FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE).store_string(JSON.stringify({"generated_profile":true,"renderer":RenderingServer.get_video_adapter_name(),"frames":frames,"checks":checks,"failures":failures},"  "))
 print("CHEF_PICKUP_CAPTURE_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"generated_scenes":4}))
 quit(0 if failures.is_empty() else 1)
func capture(game,label:String,center:Vector2,receipt:Dictionary):
 var art=game.illustration
 # Settle only presentation interpolation; service state stays frozen.
 for tick in range(20):art.update_motion(.025)
 game._update_ui()
 for zoom_name in ["normal","close"]:
  art.zoom=1.0 if zoom_name=="normal" else 2.5
  art.pan_offset=Vector2.ZERO;art.update_projection()
  art.pan_offset+=art.camera_play_rect().get_center()-(art.iso(center.x,center.y)+Vector2(0,-18)*art.ui_scale*art.zoom)
  art.update_projection()
  if validate_only:continue
  art.queue_redraw();await process_frame;await RenderingServer.frame_post_draw
  var name=label+"-"+zoom_name+".png"
  root.get_texture().get_image().save_png(output.path_join(name))
  var row=receipt.duplicate(true);row.merge({"file":name,"zoom":art.zoom,"camera_origin":art.origin,"contacts":art.render_contacts.duplicate(true)},true);frames.append(row)
