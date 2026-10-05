extends "res://tests/fixtures/before_dishwashing_main.gd"
# Legacy role scheduling copied from public baseline 5658420.
# Freeze the pre-dishwashing controller so old pickup/wash stages remain real.
const LEGACY_ROLE_JOBS={"chef":["cook"],"waiter":["order","deliver_meal","brew","deliver_drink"],"cleaner":["cleanup"],"cashier":["take_payment"]}

func _prepare_cleanup_step(staff:Dictionary,index:int):
	if staff.job_kind!="cleanup" or not service_guests.has(int(staff.job_guest_id)):return
	var record=service_guests[int(staff.job_guest_id)]
	var current_action=str(SERVICE_STEPS.cleanup[mini(int(staff.job_step),SERVICE_STEPS.cleanup.size()-1)].action)
	var held_dishes=record.plate_owner=="staff" and int(record.plate_staff_index)==index
	var held_trash=record.trash_owner=="staff" and int(record.trash_staff_index)==index
	var forced=-1
	# Carrying is an exclusive commitment: finish the pickup gesture, then
	# reach the matching destination before accepting table/floor tools.
	if held_dishes and current_action not in ["collecting","washing"]:forced=1
	elif held_trash and current_action not in ["sweeping","disposing_trash"]:forced=5
	var desired=int(staff.job_step)
	if forced>=0:desired=forced
	elif float(staff.job_elapsed)<=0.0:
		desired=SERVICE_STEPS.cleanup.size()
		for candidate in range(SERVICE_STEPS.cleanup.size()):
			if _cleanup_step_needed(record,str(SERVICE_STEPS.cleanup[candidate].action),SERVICE_STEPS.cleanup[candidate].get("debris_kind","")):
				desired=candidate;break
	if desired!=int(staff.job_step):
		staff.job_step=desired;staff.job_elapsed=0.0;staff.path.clear();staff.index=0;staff.destination=Vector2i(-100,-100)
		staff.table_face_id=-1;staff.table_face_cell=Vector2i(-1,-1)
	if int(staff.job_step)>=SERVICE_STEPS.cleanup.size():
		record.cleanup_done=true;record.floor_cleaned=true;record.floor_dirty=false
		_clear_service_job(staff);return
	var step=SERVICE_STEPS.cleanup[int(staff.job_step)]
	if step.kind=="table":staff.station_id=-1;return
	if step.kind=="sink" and record.plate_owner=="sink":staff.station_id=int(record.plate_target_id)
	var current=model.get_item(int(staff.station_id))
	if not current.is_empty() and current.kind==step.kind:return
	var station=_service_station(str(step.kind),Vector2i(floori(staff.pos.x),floori(staff.pos.y)),index)
	if not station.is_empty():
		staff.station_id=int(station.id);staff.blocked_reason="";return
	staff.station_id=-1;staff.blocked_guest_id=int(staff.job_guest_id);staff.blocked_target_id=-1
	for item in model.items:
		if item.kind==step.kind:staff.blocked_target_id=int(item.id);break
	staff.blocked_reason="Add the included trash bin in Decorate" if step.kind=="bin" and staff.blocked_target_id<0 else ("Bin sides blocked · clear any adjacent side in Decorate" if step.kind=="bin" else "%s front blocked · make space in Decorate"%str(step.kind).capitalize())


func _assign_service_job(staff: Dictionary, index: int):
	if not bool(staff.get("on_duty",true)) or bool(staff.get("duty_pending",false)):return
	staff.blocked_reason="";staff.blocked_target_id=-1;staff.blocked_guest_id=-1
	var from=Vector2i(floori(staff.pos.x),floori(staff.pos.y))
	for kind in LEGACY_ROLE_JOBS[str(staff.role)]:
		for guest in model.customers:
			if bool(guest.get("withdrawn",false)):continue
			var record=service_guests[int(guest.id)]
			var phase=str(guest.phase)
			if kind=="take_payment" and not model.checkout_ready(guest,int(guest.get("checkout_register_id",-1))):continue
			if kind=="order" and (phase!="ordering" or record.order_done): continue
			if kind=="cook" and (phase!="cooking" or record.meal_ready): continue
			if kind=="brew" and (phase!="drinking" or record.drink_ready): continue
			if kind=="deliver_meal" and (phase!="cooking" or not record.meal_ready or record.meal_done): continue
			if kind=="deliver_drink" and (phase!="drinking" or not record.drink_ready or record.drink_done): continue
			if kind=="cleanup" and (not _cleanup_ready(guest) or record.cleanup_done): continue
			var assigned=false
			for other in staff_states:
				if int(other.job_guest_id)==int(guest.id) and int(other.job_token)==int(record.token): assigned=true;break
			if assigned: continue
			var station={}
			if kind=="take_payment":station=model.get_item(int(guest.checkout_register_id))
			elif kind=="order": station=model.get_item(int(guest.table_id))
			elif kind=="deliver_meal": station=model.get_item(int(record.meal_pass_id))
			elif kind=="deliver_drink": station=model.get_item(int(record.drink_station_id))
			else: station=_service_station({"cleanup":"sink","brew":"beverage","cook":"stove"}[kind],from,index)
			if station.is_empty() or _service_cell(station,from,[],str(staff.role))==Vector2i(-1,-1):
				_mark_blocked_job(staff,guest,kind);continue
			staff.blocked_reason="";staff.blocked_target_id=-1;staff.blocked_guest_id=-1
			staff.job_kind=kind;staff.job_guest_id=int(guest.id);staff.job_token=int(record.token)
			staff.job_step=0;staff.job_elapsed=0.0;staff.station_id=int(station.id)
			staff.table_face_id=-1;staff.table_face_cell=Vector2i(-1,-1);staff.yield_time=0.0
			if kind=="take_payment":guest.checkout_token=int(record.token)
			if kind=="cook": record.meal_station_id=int(station.id)
			if kind=="brew": record.drink_station_id=int(station.id)
			return

	floor_tasks.assign(staff,index)

