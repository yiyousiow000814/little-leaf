extends RefCounted
## Session-only explanation of actual admission gates. Never changes gameplay,
## emits model.changed, or reads/writes a save. The shared Log bounds retention.
const Log=preload("res://scripts/cafe_save_log.gd")

static func record(model,code:String):
	model._admission_reason=code
	write(model,code)

static func write(model,code:String):
	var used_tables={};var used_chairs={};var arrivals=0
	for guest in model.customers:
		if guest.phase=="arriving":arrivals+=1
		if bool(guest.get("withdrawn",false)):continue
		used_tables[int(guest.table_id)]=true;used_chairs[int(guest.chair_id)]=true
	var pairs=model._seating_pairs();var free=0
	for pair in pairs:
		if not used_tables.has(int(pair.table_id)) and not used_chairs.has(int(pair.chair_id)):free+=1
	if not model.reception_visits.is_empty():
		free=0
		for state in model.TableOccupancy.inspect(model).tables.values():
			if int(state.occupant_id)<0:free+=1
	var fields={"layer":"guest","code":code,"queued":model.outside_queue.size()+model.reception_visits.size(),"arrivals":arrivals,"pairs":pairs.size(),"available":free}
	# No positions, clocks or per-frame values: unchanged waits produce no spam.
	if fields==model._admission_log_snapshot:return
	model._admission_log_snapshot=fields.duplicate()
	Log.record("guest_admission",fields)

static func observe(game):
	var model=game.model;var active=[]
	for visitor in model.outside_queue:
		if visitor.phase=="outside_queue":active.append(visitor)
	for visitor in model.reception_visits:
		if visitor.phase!="leaving":active.append(visitor)
	var code=str(model._admission_reason)
	if active.is_empty():code="QUEUE_NONE" if model.outside_queue.is_empty() and model.reception_visits.is_empty() else "QUEUE_RETURNING"
	elif game.save_recovery_blocked:code="QUEUE_RECOVERY_BLOCKED"
	elif game.paused:code="QUEUE_PAUSED"
	elif game.editing:code="QUEUE_EDITING"
	elif game.browser_suspended:code="QUEUE_BROWSER_SUSPENDED"
	elif game.compact_ui.viewport_too_small:code="QUEUE_VIEWPORT_BLOCKED"
	elif not model.operating_open:code="QUEUE_CAFE_CLOSED"
	elif not model.reception_visits.is_empty():
		if active.any(func(v):return v.phase=="waiting_cleaning"):code="RECEPTION_WAITING_CLEANING"
		elif active.any(func(v):return v.phase=="waiting_table"):code="RECEPTION_WAITING_TABLE"
		elif active.any(func(v):return v.phase=="waiting_seat"):code="RECEPTION_WAITING_SEAT"
		elif active.any(func(v):return bool(v.get("waiting",false))):code="QUEUE_ROUTE_BLOCKED"
		else:code="RECEPTION_APPROACHING"
	else:
		var ready={}
		for visitor in active:
			if visitor.has("ready_order") and (ready.is_empty() or int(visitor.ready_order)<int(ready.ready_order)):ready=visitor
		if ready.is_empty():code="QUEUE_NOT_CHECKED" if active.any(func(v):return model.OutsideQueue.settled(v)) else "QUEUE_HEAD_APPROACHING"
		elif not model.OutsideQueue.settled(ready):code="QUEUE_MOVING_UP"
	write(model,code)
