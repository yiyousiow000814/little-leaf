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
func snapshot()->Dictionary:
 var staff=staff_states[0];var record=service_guests[201]
 return {"pos":str(staff.pos),"destination":str(staff.destination),"job":staff.job_kind,"elapsed":staff.job_elapsed,"action":staff.art_action,"order_done":record.order_done,"phase":record.guest.phase,"token":record.token}
