extends SceneTree
class GeneratedMain extends "res://scripts/main.gd":
 func _load_startup():
  save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
  model.first_guest_pending=false
  model.items.append({"id":model._next_item_id,"kind":"stove","x":8,"z":1,"rot":0});model._next_item_id+=1
  model.cooks=2;model.duty_counts.chef=2;model.duty_targets.chef=2;model._notify()
func _initialize():run.call_deferred()
func run():
 var g=GeneratedMain.new();root.add_child(g);g.set_process(false);g.illustration.set_process(false)
 g.model._spawn_customer();var guest=g.model.customers[0];guest.phase="cooking";g._sync_service_guests()
 var r=g.service_guests[int(guest.id)];r.order_done=true
 var chefs=g.staff_states.filter(func(s):return s.role=="chef")
 var stove=g.model.items.filter(func(i):return i.kind=="stove")[0]
 var face=g.model.workface_cell(stove)
 var carrier=chefs[1];carrier.job_kind="cook";carrier.job_step=3;carrier.job_guest_id=guest.id;carrier.job_token=r.token;carrier.station_id=stove.id
 carrier.pos=Vector2(face)+Vector2(.5,.5);carrier.destination=face
 r.meal_station_id=stove.id;r.plate_owner="staff";r.plate_staff_index=g.staff_states.find(carrier);r.plate_target_id=-1
 g._refresh_idle_homes()
 var before=carrier.job_elapsed
 for tick in 120:g._animate_staff(.05)
 var stalled=carrier.job_kind=="cook" and carrier.job_step==3 and carrier.job_elapsed==before and r.plate_owner=="staff"
 var observation={"idle_claim_stalls_carrier":stalled,"chef_home":str(chefs[0].idle_home_cell),"stove_face":str(face),"carrier_elapsed":carrier.job_elapsed,"carrier_destination":str(carrier.destination),"plate_owner":r.plate_owner}
 # Independent requested shared-standing-cell boundary, using a ready dish.
 r.plate_owner="station";r.plate_target_id=stove.id;r.meal_ready=true
 carrier.job_kind="";carrier.job_guest_id=-1;carrier.job_token=-1
 var waiter=g.staff_states.filter(func(s):return s.role=="waiter")[0]
 waiter.job_kind="deliver_meal";waiter.job_step=0;waiter.station_id=stove.id;waiter.job_guest_id=guest.id;waiter.job_token=r.token
 chefs[0].destination=face;chefs[0].pos=Vector2(face)+Vector2(.5,.5)
 observation.pickup_with_chef_claim=str(g._service_destination(waiter,stove,face,[face]))
 observation.pickup_without_claim=str(g._service_destination(waiter,stove,face,[]))
 var failures=[];var checks=0
 checks+=1
 if stalled:failures.append("idle home starves later chef deposit")
 checks+=1
 if observation.pickup_with_chef_claim!=str(face):failures.append("ready pickup cannot share idle chef home")
 checks+=1
 if observation.pickup_without_claim!=str(face):failures.append("ordinary pickup destination changed")
 var saved_token=waiter.job_token;waiter.job_token=-999
 checks+=1
 if g._service_destination(waiter,stove,face,[face])!=Vector2i(-1,-1):failures.append("stale token shares destination")
 waiter.job_token=saved_token
 chefs[0].role="cleaner"
 checks+=1
 if g._service_destination(waiter,stove,face,[face])!=Vector2i(-1,-1):failures.append("unrelated cleaner claim ignored")
 chefs[0].role="chef"
 var old_owner=r.plate_owner;r.plate_owner="staff"
 checks+=1
 if g._service_destination(waiter,stove,face,[face])!=Vector2i(-1,-1):failures.append("unprepared dish shares destination")
 r.plate_owner=old_owner
 var blocker={"id":g.model._next_item_id,"kind":"plant","x":face.x,"z":face.y,"rot":0}
 g.model.items.append(blocker);g.model._notify()
 checks+=1
 if g._service_destination(waiter,stove,face,[face])!=Vector2i(-1,-1):failures.append("pickup bypasses furniture obstacle")
 g.model.items.erase(blocker);g.model._notify()
 print("CHEF_CLAIM_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"player_save_used":false}))
 print("CHEF_CLAIM_OBSERVATION ",JSON.stringify(observation))
 for p in g.audio_players.values():p.stop();p.stream=null
 g.settings_controls.sfx_player.stop();g.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 g.queue_free();await process_frame;await process_frame;quit(0 if failures.is_empty() else 1)
