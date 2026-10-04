extends "res://scripts/main.gd"
func _load_startup():
 save_writes_suppressed=true
 fresh_start=false
 model.reset_new()
 model.ensure_basic_bin()
 paused=true
func _save():return true
func setup_dirty(with_floor=true):
 model.customers.clear();service_guests.clear();floor_tasks.messes.clear();floor_tasks.walks.clear()
 for staff in staff_states:
  _clear_service_job(staff);staff.path.clear();staff.index=0;staff.destination=Vector2i(-100,-100)
  staff.on_duty=true;staff.duty_pending=false
 model.operating_open=true;model._spawn_customer();model.operating_open=false
 var guest=model.customers[0]
 model.customers.resize(1)
 guest.phase="dirty";guest.paid=true;guest.seated=false;guest.admitted=true;guest.waiting=false
 guest.settlement_mode="legacy";guest.checkout_ticket=0;guest.checkout_register_id=-1;guest.checkout_token=-1;guest.checkout_cell=Vector2i(-100,-100)
 guest.route=[];guest.route_index=0;guest.x=-1.5;guest.z=6.5;guest.exterior_exit=true
 guest.dismounting=false;guest.egress_cell=Vector2i(-100,-100);guest.dismount_progress=0.0
 model._walking_customer_id=-1
 _sync_service_guests()
 var record=service_guests[int(guest.id)]
 if with_floor:
  record.floor_debris="banana";record.trash_owner="floor";record.floor_spill=true;record.spill_cleaned=false;record.spill_remaining=1.0;record.floor_cleaned=false;record.floor_dirty=true
 _update_people()
 return record
func worker(role):
 for staff in staff_states:
  if staff.role==role:return staff
 return {}
func advance(delta=.05):
 animation_time+=delta
 _animate_staff(delta)
func legacy_job(record,step,elapsed):
 var staff=worker("cleaner")
 staff.job_kind="cleanup";staff.job_guest_id=int(record.guest.id);staff.job_token=int(record.token)
 staff.job_step=step;staff.job_elapsed=elapsed
 staff.station_id=-1
 if step==1:
  for item in model.items:
   if item.kind=="sink":staff.station_id=int(item.id)
 return staff
