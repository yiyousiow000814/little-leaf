extends "res://scripts/main.gd"
## One seated synthetic diner; never read or write a player profile.
func _load_startup():
 save_writes_suppressed=true;fresh_start=false;paused=true;model.reset_new()
func _save():return true
func setup():
 save_writes_suppressed=true;model.reset_new();model.operating_open=false
 model.items.assign([
  {"id":101,"kind":"table","x":5,"z":4,"rot":0},
  {"id":102,"kind":"chair","x":5,"z":5,"rot":0},
  {"id":103,"kind":"plant","x":4,"z":4,"rot":0},
  {"id":104,"kind":"plant","x":5,"z":3,"rot":0},
  {"id":105,"kind":"plant","x":6,"z":4,"rot":0}])
 model.dining_sets.clear();model.built_walls.clear();model.wall_attachments.clear()
 model.customers.assign([{"id":201,"table_id":101,"chair_id":102,"phase":"ordering","x":5.5,"z":5.5,"seated":true,"paid":false,"elapsed":0.0,"duration":Model.PHASE_SECONDS.ordering,"mobility":{},"withdrawn":false,"meal_abandoned":false,"admitted":true,"route":[],"route_index":0,"heading":Vector2.UP}])
 model.revision+=1;staff_states.clear();service_guests.clear()
 _add_staff("waiter",Vector2(3.5,6.5));_sync_service_guests()
func setup_idle_chef():
 setup();staff_states.clear()
 model.cooks=1;model.waiters=1;model.cleaners=0;model.cashiers=0
 _add_staff("chef",Vector2(5.5,6.5));_add_staff("waiter",Vector2(3.5,6.5))
 _assign_service_job(staff_states[1],1);_refresh_idle_homes()
func setup_targetless_cook():
 setup_idle_chef()
 model.items.append({"id":110,"kind":"stove","x":8,"z":1,"rot":0})
 model.items.append({"id":111,"kind":"plant","x":8,"z":2,"rot":0})
 model.items.append({"id":112,"kind":"counter","x":8,"z":7,"rot":0})
 model.items.append({"id":113,"kind":"plant","x":8,"z":8,"rot":0})
 model.items.append({"id":121,"kind":"table","x":8,"z":4,"rot":0})
 model.items.append({"id":122,"kind":"chair","x":8,"z":5,"rot":0})
 var guest=model.customers[0].duplicate(true)
 guest.id=202;guest.table_id=121;guest.chair_id=122;guest.x=8.5;guest.phase="cooking";guest.duration=Model.PHASE_SECONDS.cooking
 model.customers.append(guest);model.revision+=1;_sync_service_guests()
 var chef=staff_states[0];var record=service_guests[202]
 chef.job_kind="cook";chef.job_guest_id=202;chef.job_token=record.token;chef.job_step=3;chef.job_elapsed=0.0;chef.station_id=110
 record.plate_owner="staff";record.plate_staff_index=0;record.plate_target_id=-1;record.meal_station_id=110
 _reserve_pass(chef);_refresh_idle_homes()
 # The reviewed old-source state: a valid held-meal job has no pass target,
 # so its prior idle fallback is R even though the waiter already pinned R.
 chef.destination=Vector2i(5,6)
func setup_combined_work():
 setup_targetless_cook()
 # Two held-meal fallbacks compete with an order and a different chef's pass.
 # The original blocked pass/stove remain blocked; only guest204 owns pass130.
 model.items.append({"id":130,"kind":"counter","x":2,"z":4,"rot":0})
 for id in [203,204]:
  var guest=model.customers[1].duplicate(true);guest.id=id;model.customers.append(guest)
 model.revision+=1;_sync_service_guests()
 _add_staff("chef",Vector2(2.5,3.5));_add_staff("chef",Vector2(3.5,2.5))
 for index in [2,3]:
  var chef=staff_states[index];var record=service_guests[201+index]
  chef.job_kind="cook";chef.job_guest_id=201+index;chef.job_token=record.token;chef.job_step=3;chef.station_id=110
  record.plate_owner="staff";record.plate_staff_index=index;record.meal_station_id=110
 _reserve_pass(staff_states[3]);_reserve_pass(staff_states[2]);_reserve_pass(staff_states[0])
 staff_states[2].destination=Vector2i(2,3)
 _refresh_idle_homes()
func snapshot()->Dictionary:
 var staff=staff_states.filter(func(worker):return worker.role=="waiter")[0];var record=service_guests[201]
 var result={"pos":str(staff.pos),"destination":str(staff.destination),"job":staff.job_kind,"elapsed":staff.job_elapsed,"action":staff.art_action,"order_done":record.order_done,"phase":record.guest.phase,"token":record.token}
 if staff_states[0].role=="chef":result.idle_chef={"pos":str(staff_states[0].pos),"destination":str(staff_states[0].destination),"home":str(staff_states[0].idle_home_cell),"job":staff_states[0].job_kind}
 if service_guests.has(202):
  var held=service_guests[202]
  result.held_meal={"token":held.token,"plate_owner":held.plate_owner,"plate_staff_index":held.plate_staff_index,"pass":held.meal_pass_id,"reserved":held.pass_reserved}
 return result
