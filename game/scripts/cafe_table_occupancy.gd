extends RefCounted
## One live occupancy authority, independent of the preceding cleanup job.
## Legacy dirty/cleaning customer records are service carriers, not live diners.

static func inspect(model)->Dictionary:
	var tables={};var chairs={};var error=""
	for pair in model._seating_pairs():
		tables[int(pair.table_id)]={"table_id":int(pair.table_id),"chair_id":int(pair.chair_id),"occupant_id":-1,"cleanup_owner_id":-1,"cleanliness":"clean"}
	for guest in model.customers:
		if bool(guest.get("withdrawn",false)):continue
		var table_id=int(guest.table_id);var chair_id=int(guest.chair_id)
		if not tables.has(table_id):continue
		var state:Dictionary=tables[table_id]
		if guest.phase in ["dirty","cleaning"]:
			if state.cleanup_owner_id!=-1:error="Multiple cleanup owners for one table"
			state.cleanup_owner_id=int(guest.id);state.cleanliness=str(guest.phase)
		else:
			if state.occupant_id!=-1 or chairs.has(chair_id):error="Multiple live occupants for one dining place"
			state.occupant_id=int(guest.id);chairs[chair_id]=int(guest.id)
	for visitor in model.reception_visits:
		var chair_id=int(visitor.chair_id);var table_id=int(visitor.table_id)
		if chair_id<0:continue
		if chairs.has(chair_id):error="Reception duplicates a live chair claim"
		chairs[chair_id]=int(visitor.id)
		if table_id>=0:
			if not tables.has(table_id):error="Reception references a missing dining place";continue
			if tables[table_id].occupant_id!=-1:error="Reception duplicates a live table claim"
			tables[table_id].occupant_id=int(visitor.id)
	return {"tables":tables,"chairs":chairs,"error":error}
