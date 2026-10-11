extends RefCounted
## Real restaurant reception. Prospective visitors never own meal/service jobs.
const FORMAT="little_leaf.reception.v2"
const LEGACY_FORMAT="little_leaf.reception.v1"
const CAPACITY=6
const WAIT_SECONDS=90.0
const NONE=Vector2i(-100,-100)
const PHASES=["approaching","waiting_seat","waiting_table","waiting_cleaning","leaving"]
const TableOccupancy=preload("res://scripts/cafe_table_occupancy.gd")

static func point(v:Dictionary)->Vector2:return Vector2(float(v.x),float(v.z))
static func cell(p:Vector2)->Vector2i:return Vector2i(floori(p.x),floori(p.y))
static func settled(v:Dictionary)->bool:return int(v.route_index)>=v.route.size()
static func pending_count(m)->int:return m.reception_visits.size()+m.outside_queue.size()+m.Parking.pending_count(m)
static func _slots(m)->Dictionary:
	var result=m.Parking.reserved_slots(m)
	for v in m.reception_visits+m.outside_queue:result[int(v.slot)]=true
	return result
static func _public(m,p:Vector2)->bool:
	return p.x>=-3.0 and p.x<0.0 and p.y>=m.StreetExtent.PAVEMENT_Z_MIN and p.y<=m.StreetExtent.PAVEMENT_Z_MAX
static func _empty(id:int,slot:int,start:Vector2,origin_z:float)->Dictionary:
	return {"id":id,"slot":slot,"phase":"approaching","x":start.x,"z":start.y,"heading":Vector2.DOWN if origin_z<0 else Vector2.UP,"origin_z":origin_z,"wait_seconds":0.0,"ready_order":-1,"route_origin":start,"goal":start,"route":[],"route_index":0,"seated":false,"waiting":false,"table_id":-1,"chair_id":-1,"previous_chair_id":-1,"cleanup_owner_id":-1,"entry_cell":NONE,"entry_outside":NONE,"entry_direction":Vector2i.LEFT}

static func add(m,start_override:Vector2=Vector2.INF)->bool:
	if not m.reception_review_enabled:return false
	if pending_count(m)>=CAPACITY:
		m.AdmissionLog.record(m,"RECEPTION_CAPACITY");return false
	var slot=0;var slots=_slots(m)
	while slots.has(slot):slot+=1
	var endpoint:Vector2=m._arrival_start_position()
	var start:Vector2=endpoint if not start_override.is_finite() else start_override
	var v=_empty(m._next_customer_id,slot,start,endpoint.y)
	if not _plan_reception(m,v):
		m.AdmissionLog.record(m,"QUEUE_NO_CORRIDOR_ENTRANCE" if m.boundary_entries().is_empty() else "RECEPTION_NO_WAITING_SPACE");return false
	m.reception_visits.append(v);m._next_customer_id+=1
	return true

static func from_parking(m,visit:Dictionary):
	if not m.reception_review_enabled:return
	var v=_empty(int(visit.id),int(visit.slot),m.Parking.HANDOFF,-82.0)
	visit.phase="queued";m.reception_visits.append(v)
	if not _plan_reception(m,v):v.waiting=true

static func migrate_outside(m):
	# Called during normal simulation, never as a write or mutation of load bytes.
	for old in m.outside_queue.duplicate():
		var v=_empty(int(old.id),int(old.slot),point(old),float(old.origin_z))
		v.wait_seconds=float(old.wait_seconds)
		m.reception_visits.append(v);m.outside_queue.erase(old)
		if old.phase=="outside_return":
			v.phase="leaving";_set_route(v,old.route.slice(int(old.route_index)));continue
		# Preserve actual standing age from a legacy line without transporting it.
		if old.has("ready_order"):v.ready_order=int(old.ready_order);v.phase="waiting_seat"
		if not _plan_reception(m,v):v.waiting=true
	_normalize_ranks(m)

static func _normalize_ranks(m):
	var ready=m.reception_visits.filter(func(v):return int(v.ready_order)>=0 and v.phase!="leaving")
	ready.sort_custom(func(a,b):return int(a.ready_order)<int(b.ready_order) if int(a.ready_order)!=int(b.ready_order) else int(a.id)<int(b.id))
	for rank in range(ready.size()):ready[rank].ready_order=rank

static func _blocked(m,except_id:int)->Dictionary:
	var result=m.Checkout.claimed_cells(m,except_id)
	for other in m.reception_visits:
		if int(other.id)==except_id:continue
		if int(other.chair_id)<0 and other.phase!="leaving":result[cell(other.goal)]=true
	return result

static func _seat_clear(m,chair:Dictionary,id:int)->bool:
	var target=m.cell_center(Vector2i(int(chair.x),int(chair.z)))
	for guest in m.customers+m.reception_visits+m.departing_bodies:
		if int(guest.id)==id or guest.phase in ["dirty","cleaning"]:continue
		if point(guest).distance_to(target)<.85:return false
	return true

static func _origin_chair(m,v:Dictionary)->int:
	# The destination claim can change before the body has left its old chair.
	# Interruptions must route from the furniture actually beneath the body.
	for id in [int(v.previous_chair_id),int(v.chair_id)]:
		var chair=m.get_item(id)
		if not chair.is_empty() and cell(point(v))==Vector2i(int(chair.x),int(chair.z)):return id
	return -1

static func _origins(m,v:Dictionary)->Array:
	var at=point(v);var result=[]
	if _public(m,at):
		for entry in m.boundary_entries():
			var outside=m.cell_center(entry.outside);var inside=m.cell_center(entry.cell)
			var prefix:Array[Vector2]=[Vector2(m.ARRIVAL_LANE_X,at.y),Vector2(m.ARRIVAL_LANE_X,outside.y),outside,inside]
			if _route_error(m,at,prefix,-1,-1)=="":result.append({"cell":entry.cell,"prefix":prefix,"entry":entry})
		return result
	if not m.is_floor_owned(cell(at)):return result
	var chair=m.get_item(_origin_chair(m,v))
	if not chair.is_empty():
		for direction in m.DIRECTIONS:
			var landing=cell(at)+direction
			if not m._walkable(landing) or m.edge_blocked(cell(at),landing):continue
			var target=m.cell_center(landing)
			if not m.segment_blocked(at,target):result.append({"cell":landing,"prefix":[target],"entry":{}})
	elif m._walkable(cell(at)):
		var center=m.cell_center(cell(at))
		if absf(at.x-center.x)<.0001 or absf(at.y-center.y)<.0001:
			result.append({"cell":cell(at),"prefix":[center] if at.distance_to(center)>.0001 else [],"entry":{}})
	return result

static func _route_to(m,v:Dictionary,target:Vector2i,chair_id:int=-1)->Dictionary:
	var best={};var distance=INF;var blocked=_blocked(m,int(v.id));blocked.erase(target)
	for origin in _origins(m,v):
		var path=m.Checkout.path(m,origin.cell,target,blocked)
		if path.is_empty():continue
		var route:Array[Vector2]=[];route.assign(origin.prefix)
		for step in path:
			var next=m.cell_center(step)
			if route.is_empty() or route[-1].distance_to(next)>.00001:route.append(next)
		if chair_id>=0:
			var chair=m.get_item(chair_id)
			route.append(m.cell_center(Vector2i(int(chair.x),int(chair.z))))
		if _route_error(m,point(v),route,_origin_chair(m,v),chair_id)!="":continue
		var length=m._route_length(point(v),route)
		if length<distance:
			distance=length;best={"route":route,"entry":origin.entry,"length":length,"approach":target}
	return best

static func _seat_route(m,v:Dictionary,chair_id:int,table_id:int=-1)->Dictionary:
	var chair=m.get_item(chair_id)
	if chair.is_empty():return {}
	var center=Vector2i(int(chair.x),int(chair.z));var best={};var distance=INF
	for direction in m.DIRECTIONS:
		var landing=center+direction
		if not m._walkable(landing) or m.edge_blocked(center,landing):continue
		if table_id>=0:
			var table=m.get_item(table_id)
			if landing==Vector2i(int(table.x),int(table.z)):continue
		var candidate=_route_to(m,v,landing,chair_id)
		if not candidate.is_empty() and float(candidate.length)<distance:best=candidate;distance=float(candidate.length)
	return best

static func _excluded_wait_cells(m)->Dictionary:
	var excluded=m.Checkout.claimed_cells(m)
	for entry in m.boundary_entries():excluded[entry.cell]=true
	for item in m.items:
		if item.kind in ["stove","beverage","sink","counter","register"]:
			excluded[m.workface_cell(item)]=true
			if item.kind in ["counter","register"]:excluded[Vector2i(int(item.x),int(item.z))*2-m.workface_cell(item)]=true
		elif item.kind=="bin":
			for candidate in m.bin_service_cells(item):excluded[candidate]=true
		elif item.kind=="table":
			for candidate in m.table_service_cells(item):excluded[candidate]=true
	for pair in m._seating_pairs():
		for candidate in m.chair_egress_cells(int(pair.chair_id),int(pair.table_id)):excluded[candidate]=true
	return excluded

static func _standing_route(m,v:Dictionary)->Dictionary:
	var excluded=_excluded_wait_cells(m);var claimed=_blocked(m,int(v.id));var best={};var length=INF
	var entries=m.boundary_entries()
	for entry in entries:
		for x in range(maxi(1,int(entry.cell.x)-3),mini(m.width,int(entry.cell.x)+5)):
			for z in range(maxi(0,int(entry.cell.y)-3),mini(m.depth,int(entry.cell.y)+4)):
				var target=Vector2i(x,z)
				if not m._walkable(target) or excluded.has(target) or claimed.has(target):continue
				if m.Checkout.is_door_landing(m,target):continue
				# A waiting body must not sever a narrow aisle to a workface/exit.
				var blocked=claimed.duplicate();blocked[target]=true;var cuts=false
				for essential in excluded:
					if not m._walkable(essential):continue
					if not m.Checkout.path(m,entry.cell,essential,claimed).is_empty() and m.Checkout.path(m,entry.cell,essential,blocked).is_empty():cuts=true;break
				if cuts:continue
				var candidate=_route_to(m,v,target)
				if not candidate.is_empty() and float(candidate.length)<length:best=candidate;length=float(candidate.length)
	return best

static func _set_route(v:Dictionary,route:Array):
	v.route_origin=point(v);v.route=[]
	for next in route:
		if (v.route.is_empty() and point(v).distance_to(next)<.00001) or (not v.route.is_empty() and v.route[-1].distance_to(next)<.00001):continue
		v.route.append(next)
	v.route_index=0;v.goal=point(v) if v.route.is_empty() else v.route[-1];v.seated=false;v.waiting=v.route.is_empty()

static func _take_route(v:Dictionary,planned:Dictionary):
	if bool(v.seated):v.previous_chair_id=int(v.chair_id)
	_set_route(v,planned.route)
	if not planned.get("entry",{}).is_empty():
		v.entry_cell=planned.entry.cell;v.entry_outside=planned.entry.outside;v.entry_direction=planned.entry.direction

static func _plan_reception(m,v:Dictionary)->bool:
	var planned=_standing_route(m,v)
	if planned.is_empty():return false
	_take_route(v,planned)
	return true

static func _dining_transit_count(m)->int:
	var moving=m.customers.filter(func(g):return g.phase=="arriving").size()
	for other in m.reception_visits:
		if int(other.table_id)>=0 and not settled(other):moving+=1
	return moving

static func _admission_signature(m,v:Dictionary)->Array:
	var clear={}
	for chair in m.items:
		if chair.kind in ["chair","bench"]:clear[int(chair.id)]=_seat_clear(m,chair,int(v.id))
	# Retry only when a real eligibility input changes. Arrival-cap release,
	# checkout clearance and departing bodies matter even when seat IDs do not.
	return [m.navigation_signature(),TableOccupancy.inspect(m),_dining_transit_count(m),_blocked(m,int(v.id)),clear]

static func _claim_dining(m,v:Dictionary)->bool:
	var inventory=TableOccupancy.inspect(m)
	if inventory.error!="":return false
	if _dining_transit_count(m)>=m.MAX_ARRIVING:return false
	for dirty in [false,true]:
		var best={};var chosen={};var shortest=INF
		for state in inventory.tables.values():
			if int(state.occupant_id)>=0 or (int(state.cleanup_owner_id)>=0)!=dirty:continue
			var chair=m.get_item(int(state.chair_id))
			if not _seat_clear(m,chair,int(v.id)):continue
			var planned=_seat_route(m,v,int(state.chair_id),int(state.table_id))
			if not planned.is_empty() and float(planned.length)<shortest:best=planned;chosen=state;shortest=float(planned.length)
		if best.is_empty():continue
		_take_route(v,best)
		v.table_id=int(chosen.table_id);v.chair_id=int(chosen.chair_id);v.cleanup_owner_id=int(chosen.cleanup_owner_id)
		v.phase="waiting_cleaning" if dirty else "waiting_seat"
		return true
	return false

static func _claim_waiting_chair(m,v:Dictionary)->bool:
	var inventory=TableOccupancy.inspect(m);var linked={}
	for group in m.dining_sets:linked[int(group.seat_id)]=true
	var best={};var chosen=-1;var length=INF
	for chair in m.items:
		if chair.kind not in ["chair","bench"] or linked.has(int(chair.id)) or inventory.chairs.has(int(chair.id)):continue
		if not _seat_clear(m,chair,int(v.id)):continue
		var planned=_seat_route(m,v,int(chair.id))
		if not planned.is_empty() and float(planned.length)<length:best=planned;chosen=int(chair.id);length=float(planned.length)
	if chosen<0:return false
	_take_route(v,best);v.chair_id=chosen;v.table_id=-1;v.cleanup_owner_id=-1;v.phase="waiting_table"
	return true

static func _promote(m,v:Dictionary):
	var target=m.get_item(int(v.chair_id));var table=m.get_item(int(v.table_id))
	if target.is_empty() or table.is_empty():return
	var exits=m.chair_egress_cells(int(v.chair_id),int(v.table_id))
	if exits.is_empty():return
	var guest={"id":v.id,"table_id":v.table_id,"chair_id":v.chair_id,"mobility":{},"phase":"ordering","elapsed":0.0,"duration":m.PHASE_SECONDS.ordering,"x":v.x,"z":v.z,"paid":false,"seated":true,"admitted":true,"withdrawn":false,"exit_completed":false,"meal_abandoned":false,"route":[],"route_index":0,"heading":(Vector2(table.x,table.z)-Vector2(target.x,target.z)).normalized(),"service_cell":exits[0],"waiting":false,"exterior_exit":false,"entry_cell":v.entry_cell,"entry_direction":v.entry_direction,"entry_outside":v.entry_outside,"departure_blocked":false,"dismounting":false,"egress_cell":NONE,"dismount_progress":0.0}
	m.Checkout.init_guest(m,guest)
	guest.table_service_direction=m._table_service_direction_in(table,m.items)
	m.reception_visits.erase(v);m.customers.append(guest);m.Parking.admitted(m,guest)
	m._reception_plan_signatures.erase(int(v.id));m.AdmissionLog.record(m,"QUEUE_ADMITTED")

static func _exit_route(m,v:Dictionary)->Array[Vector2]:
	var at=point(v);var best:Array[Vector2]=[];var length=INF
	if _public(m,at):
		if not m.Parking.find(m,int(v.id)).is_empty():return [Vector2(m.ARRIVAL_LANE_X,at.y)]
		return [Vector2(m.ARRIVAL_LANE_X,at.y),Vector2(m.ARRIVAL_LANE_X,float(v.origin_z))]
	for entry in m.boundary_entries():
		var planned=_route_to(m,v,entry.cell)
		if planned.is_empty():continue
		var route:Array[Vector2]=[];route.assign(planned.route)
		route.append(m.cell_center(entry.outside));route.append(Vector2(m.ARRIVAL_LANE_X,m.cell_center(entry.outside).y))
		if m.Parking.find(m,int(v.id)).is_empty():route.append(Vector2(m.ARRIVAL_LANE_X,float(v.origin_z)))
		if _route_error(m,at,route,_origin_chair(m,v),-1)!="":continue
		var candidate=m._route_length(at,route)
		if candidate<length:best=route;length=candidate
	return best

static func leave(m,v:Dictionary):
	if v.phase!="leaving":
		v.phase="leaving";v.ready_order=-1;v.cleanup_owner_id=-1
		if bool(v.seated):v.previous_chair_id=int(v.chair_id)
	_set_route(v,_exit_route(m,v));v.waiting=v.route.is_empty()
	if v.route.is_empty() and _public(m,point(v)):v.waiting=false
	m._reception_plan_signatures.erase(int(v.id))

static func close(m):
	for v in m.reception_visits:leave(m,v)

static func _move(m,v:Dictionary,delta:float)->float:
	var at=point(v);var budget=m.WALK_SPEED*delta;var elapsed=0.0;var entered=INF
	while budget>.000001 and not settled(v):
		var target:Vector2=v.route[int(v.route_index)];var distance=at.distance_to(target)
		if distance<.000001:v.route_index+=1;continue
		if m.segment_blocked(at,target):v.waiting=true;break
		v.heading=(target-at)/distance
		var step=minf(distance,budget);var next=at+v.heading*step
		if int(v.ready_order)<0 and entered==INF and m.is_floor_owned(cell(next)):
			# The public corridor meets owned floor at x=0. Preserve the exact
			# crossing time within a simulation slice, not the slice-end order.
			entered=elapsed+maxf(0.0,-at.x)/m.WALK_SPEED if at.x<0 and v.heading.x>0 else elapsed
		at=next;budget-=step;elapsed+=step/m.WALK_SPEED;v.waiting=false
		if step+.000001>=distance:at=target;v.route_index+=1
	v.x=at.x;v.z=at.y
	# Retain only the current/future route. An edit behind a walking visitor
	# must not invalidate a consumed historical leg or inflate the save.
	v.route=v.route.slice(int(v.route_index));v.route_index=0;v.route_origin=at
	if int(v.previous_chair_id)>=0:
		var previous=m.get_item(int(v.previous_chair_id))
		if previous.is_empty() or cell(at)!=Vector2i(int(previous.x),int(previous.z)):v.previous_chair_id=-1
	return entered

static func advance(m,delta:float):
	if not m.reception_review_enabled:return
	migrate_outside(m)
	var arrivals=[];var retired=[]
	for v in m.reception_visits.duplicate():
		if not m.operating_open and v.phase!="leaving":leave(m,v)
		var was_ready=int(v.ready_order)>=0
		if v.phase=="leaving" and settled(v) and bool(v.waiting):leave(m,v)
		var arrival_time=_move(m,v,delta)
		if v.phase=="leaving":
			if int(v.chair_id)>=0:
				var chair=m.get_item(int(v.chair_id))
				if not chair.is_empty() and point(v).distance_to(m.cell_center(Vector2i(int(chair.x),int(chair.z))))>.9:v.chair_id=-1;v.table_id=-1
			if settled(v) and not bool(v.waiting):
				m.Parking.start_return(m,int(v.id),point(v));retired.append(v)
			continue
		if arrival_time<INF:arrivals.append({"visitor":v,"time":arrival_time})
		if int(v.cleanup_owner_id)>=0 and not m.customers.any(func(g):return int(g.id)==int(v.cleanup_owner_id)):
			v.cleanup_owner_id=-1;v.phase="waiting_seat"
		var waiting_delta=delta if was_ready or bool(v.waiting) else (maxf(0.0,delta-arrival_time) if arrival_time<INF else 0.0)
		v.wait_seconds=minf(WAIT_SECONDS,float(v.wait_seconds)+waiting_delta)
		if float(v.wait_seconds)+.000001>=WAIT_SECONDS:leave(m,v);continue
	for v in retired:m.reception_visits.erase(v);m._reception_plan_signatures.erase(int(v.id))
	arrivals.sort_custom(func(a,b):return float(a.time)<float(b.time) if not is_equal_approx(float(a.time),float(b.time)) else int(a.visitor.id)<int(b.visitor.id))
	var next=0
	for v in m.reception_visits:next=maxi(next,int(v.ready_order)+1)
	for arrival in arrivals:
		var v=arrival.visitor
		if v.phase=="leaving" or int(v.ready_order)>=0:continue
		v.ready_order=next;next+=1;v.phase="waiting_seat"
	_normalize_ranks(m)
	var ready=m.reception_visits.filter(func(v):return v.phase!="leaving" and int(v.ready_order)>=0 and settled(v))
	ready.sort_custom(func(a,b):return int(a.ready_order)<int(b.ready_order))
	for v in ready:
		v.waiting=true
		if not m.is_floor_owned(cell(point(v))):continue
		if int(v.chair_id)>=0:
			v.seated=true;v.previous_chair_id=-1;v.route_origin=point(v);v.route=[];v.route_index=0
			v.heading=Vector2(m._chair_table_direction(int(v.chair_id),int(v.table_id)))
		if int(v.table_id)>=0:
			var inventory=TableOccupancy.inspect(m);var state=inventory.tables.get(int(v.table_id),{})
			if state.is_empty():leave(m,v);continue
			v.cleanup_owner_id=int(state.cleanup_owner_id)
			if int(v.cleanup_owner_id)<0:_promote(m,v)
			else:v.phase="waiting_cleaning"
			continue
		var signature=_admission_signature(m,v)
		if m._reception_plan_signatures.get(int(v.id),[])==signature:continue
		m._reception_plan_signatures[int(v.id)]=signature.duplicate(true)
		if _claim_dining(m,v):continue
		if int(v.chair_id)<0:_claim_waiting_chair(m,v)
	for v in m.reception_visits:
		# Parking handoffs and legacy ready visitors may initially have no safe
		# reception goal. Freed dynamic standing/checkout claims must retry them.
		if v.phase!="leaving" and int(v.chair_id)<0 and settled(v) and _public(m,point(v)):
			v.waiting=true
			var signature=[m.navigation_signature(),_blocked(m,int(v.id))]
			if m._reception_plan_signatures.get(int(v.id),[])!=signature:
				m._reception_plan_signatures[int(v.id)]=signature.duplicate(true);_plan_reception(m,v)
	_normalize_ranks(m)

static func _route_error(m,origin:Vector2,route:Array,origin_chair:int=-1,target_chair:int=-1)->String:
	var previous=origin;var start=m.get_item(origin_chair);var target=m.get_item(target_chair)
	var start_cell=Vector2i(int(start.x),int(start.z)) if not start.is_empty() else NONE
	if start_cell!=cell(origin):start_cell=NONE
	var target_cell=Vector2i(int(target.x),int(target.z)) if not target.is_empty() else NONE
	for index in range(route.size()):
		var next=route[index]
		if not next is Vector2 or not next.is_finite():return "Invalid reception route point"
		if absf(previous.x-next.x)>.0001 and absf(previous.y-next.y)>.0001:return "Reception route must be cardinal"
		if m.segment_blocked(previous,next):return "Reception route crosses a wall"
		var samples=maxi(1,ceili(previous.distance_to(next)*8.0))
		for sample in range(samples+1):
			var at=previous.lerp(next,float(sample)/samples);var here=cell(at)
			if _public(m,at):continue
			if not m.is_floor_owned(here):return "Reception route leaves owned floor/public corridor"
			if not m._walkable(here) and not (index==0 and here==start_cell) and not (index==route.size()-1 and here==target_cell):return "Reception route crosses furniture"
		previous=next
	return ""

static func uses_item(m,id:int)->bool:
	for v in m.reception_visits:
		if id in [int(v.table_id),int(v.chair_id),int(v.previous_chair_id)]:return true
	return false
static func uses_cell(m,at:Vector2i)->bool:
	if m.DepartingBodies.uses_cell(m,at):return true
	for v in m.reception_visits:
		if cell(point(v))==at:return true
		for index in range(int(v.route_index),v.route.size()):
			if cell(v.route[index])==at:return true
	return false

static func layout_error(m,layout:Array,walls:Array,ownership:Array,openings:Array)->String:
	if m.reception_visits.is_empty() and m.departing_bodies.is_empty():return ""
	var shadow=m.FurnitureMotion.copy_model(m)
	shadow.items.assign(layout);shadow.built_walls.assign(walls);shadow.owned_parcels.assign(ownership);shadow.wall_attachments.assign(openings)
	shadow._sync_floor_bounds();shadow.revision+=1
	var departure_error=m.DepartingBodies.layout_error(shadow)
	if departure_error!="":return departure_error
	for v in shadow.reception_visits:
		var at=point(v);var origin_chair=int(v.previous_chair_id) if int(v.previous_chair_id)>=0 else int(v.chair_id)
		var target_chair=int(v.chair_id) if v.phase!="leaving" else -1
		if _route_error(shadow,at,v.route.slice(int(v.route_index)),origin_chair,target_chair)!="":return "Keep the waiting visitor's walking route clear"
		if not _public(shadow,at) and not shadow.is_floor_owned(cell(at)):return "Keep waiting visitors on owned floor"
		if int(v.chair_id)>=0:
			var chair=shadow.get_item(int(v.chair_id))
			if chair.is_empty():return "Wait until this reception chair is clear"
			if v.seated and at.distance_to(shadow.cell_center(Vector2i(int(chair.x),int(chair.z))))>.0001:return "Wait until this reception chair is clear"
		if _exit_route(shadow,v).is_empty():return "Keep a legal exit for waiting visitors"
	return ""

static func validate(m,raw,next_id:int)->Dictionary:
	var codec=m.RuntimeCodec.new();var data=codec.decode(raw)
	if codec.error!="" or not data is Dictionary or data.get("format") not in [FORMAT,LEGACY_FORMAT] or not data.get("visitors") is Array:return {"ok":false,"error":"Invalid reception format"}
	if data.format==LEGACY_FORMAT and data.has("departures"):return {"ok":false,"error":"Legacy reception contains departing bodies"}
	if data.format==FORMAT and not data.get("departures") is Array:return {"ok":false,"error":"Missing departing-body ledger"}
	if data.visitors.size()+m.outside_queue.size()+m.Parking.pending_count(m)>CAPACITY:return {"ok":false,"error":"Reception population exceeds capacity"}
	var ids={};var slots={};var ranks={}
	for guest in m.customers+m.outside_queue:ids[int(guest.id)]=true
	for visitor in m.outside_queue:slots[int(visitor.slot)]=true
	for v in data.visitors:
		if not v is Dictionary:return {"ok":false,"error":"Invalid reception visitor"}
		for key in ["id","slot","phase","x","z","heading","origin_z","wait_seconds","ready_order","route_origin","goal","route","route_index","seated","waiting","table_id","chair_id","previous_chair_id","cleanup_owner_id","entry_cell","entry_outside","entry_direction"]:
			if not v.has(key):return {"ok":false,"error":"Incomplete reception visitor"}
		if not codec._integer(v.id,1,next_id-1) or ids.has(int(v.id)) or not codec._integer(v.slot,0,CAPACITY-1) or slots.has(int(v.slot)):return {"ok":false,"error":"Duplicate reception identity or request slot"}
		ids[int(v.id)]=true;slots[int(v.slot)]=true
		if v.phase not in PHASES or not v.seated is bool or not v.waiting is bool or not codec._number(v.wait_seconds,0,WAIT_SECONDS+.0001):return {"ok":false,"error":"Invalid reception state or patience"}
		if not codec._number(v.x,-3,m.MAX_WIDTH) or not codec._number(v.z,m.StreetExtent.PAVEMENT_Z_MIN,m.StreetExtent.PAVEMENT_Z_MAX) or not v.heading is Vector2 or not v.heading.is_finite() or v.heading.length()>1.001 or v.origin_z not in [-82.0,82.0]:return {"ok":false,"error":"Invalid reception position or origin"}
		if not codec._integer(v.ready_order,-1,CAPACITY-1) or (int(v.ready_order)>=0 and ranks.has(int(v.ready_order))):return {"ok":false,"error":"Invalid reception arrival order"}
		if int(v.ready_order)>=0:ranks[int(v.ready_order)]=true
		for key in ["table_id","chair_id","previous_chair_id","cleanup_owner_id"]:
			if not codec._integer(v[key],-1,1000000000):return {"ok":false,"error":"Invalid reception reference"}
		if v.phase=="approaching" and (int(v.ready_order)>=0 or int(v.chair_id)!=-1 or int(v.table_id)!=-1):return {"ok":false,"error":"Offscreen reception request owns a place"}
		if v.phase in ["waiting_seat","waiting_table","waiting_cleaning"] and int(v.ready_order)<0:return {"ok":false,"error":"Waiting visitor has no physical arrival order"}
		if v.phase in ["waiting_seat","waiting_table","waiting_cleaning"] and (int(v.chair_id)>=0 or int(v.table_id)>=0) and not m.is_floor_owned(cell(point(v))):return {"ok":false,"error":"Public approach cannot own a dining or waiting place"}
		if v.phase=="leaving" and (int(v.ready_order)!=-1 or int(v.cleanup_owner_id)!=-1):return {"ok":false,"error":"Departing reception visitor retains priority/cleanup reference"}
		if not m.operating_open and v.phase!="leaving":return {"ok":false,"error":"Closed cafe retains active reception demand"}
		var chair=m.get_item(int(v.chair_id));var previous_chair=m.get_item(int(v.previous_chair_id))
		if int(v.chair_id)>=0 and (chair.is_empty() or chair.kind not in ["chair","bench"]):return {"ok":false,"error":"Reception references a missing chair"}
		if int(v.previous_chair_id)>=0 and (previous_chair.is_empty() or previous_chair.kind not in ["chair","bench"]):return {"ok":false,"error":"Reception lost its dismount chair"}
		if v.phase=="waiting_table" and (int(v.table_id)!=-1 or int(v.chair_id)<0 or m.dining_sets.any(func(g):return int(g.seat_id)==int(v.chair_id))):return {"ok":false,"error":"Waiting chair belongs to a dining set"}
		if int(v.table_id)>=0 and not m._seating_pairs().any(func(p):return int(p.table_id)==int(v.table_id) and int(p.chair_id)==int(v.chair_id)):return {"ok":false,"error":"Reception dining claim is not a pair"}
		if v.phase=="waiting_cleaning" and (int(v.table_id)<0 or int(v.cleanup_owner_id)<0):return {"ok":false,"error":"Waiting-cleaning lacks a real cleanup owner"}
		if int(v.cleanup_owner_id)>=0:
			var old=m.customers.filter(func(g):return int(g.id)==int(v.cleanup_owner_id) and int(g.table_id)==int(v.table_id) and g.phase in ["dirty","cleaning"])
			if old.size()!=1:return {"ok":false,"error":"Reception cleanup owner is missing or still physically present"}
		if not v.goal is Vector2 or not v.goal.is_finite() or not v.route_origin is Vector2 or not v.route_origin.is_finite() or not v.route is Array or v.route.size()>512 or not codec._integer(v.route_index,0,v.route.size()):return {"ok":false,"error":"Invalid reception route"}
		var origin_chair=int(v.previous_chair_id) if int(v.previous_chair_id)>=0 else (int(v.chair_id) if v.phase=="leaving" else -1)
		var route_error=_route_error(m,v.route_origin,v.route,origin_chair,int(v.chair_id) if v.phase!="leaving" else -1)
		if route_error!="":return {"ok":false,"error":route_error}
		if v.goal.distance_to(point(v) if v.route.is_empty() else v.route[-1])>.0001:return {"ok":false,"error":"Reception goal disagrees with route"}
		if int(v.chair_id)>=0 and v.phase!="leaving":
			var destination=point(v) if v.route.is_empty() else v.route[-1]
			if destination.distance_to(m.cell_center(Vector2i(int(chair.x),int(chair.z))))>.0001:return {"ok":false,"error":"Reception route misses its claimed chair"}
		var start:Vector2=v.route_origin if int(v.route_index)==0 else v.route[int(v.route_index)-1]
		var finish:Vector2=start if settled(v) else v.route[int(v.route_index)]
		if absf(point(v).distance_to(start)+point(v).distance_to(finish)-start.distance_to(finish))>.001:return {"ok":false,"error":"Reception position is off its route"}
		if not _public(m,point(v)) and not m.is_floor_owned(cell(point(v))):return {"ok":false,"error":"Reception body is on unpurchased land"}
		if v.seated and (not settled(v) or chair.is_empty() or point(v).distance_to(m.cell_center(Vector2i(int(chair.x),int(chair.z))))>.0001):return {"ok":false,"error":"Reception seating disagrees with chair"}
		for key in ["entry_cell","entry_outside","entry_direction"]:
			if not v[key] is Vector2i:return {"ok":false,"error":"Invalid reception entrance metadata"}
		if v.phase!="leaving" and m.is_floor_owned(cell(point(v))) and v.entry_cell==NONE:return {"ok":false,"error":"Claimed reception visitor has no entrance provenance"}
		if v.entry_cell!=NONE and (v.entry_direction not in m.DIRECTIONS or not m.is_floor_owned(v.entry_cell) or not m._public_exterior_cell(v.entry_outside) or v.entry_cell+v.entry_direction!=v.entry_outside):return {"ok":false,"error":"Reception entrance is not owned/public"}
	var departure_check=m.DepartingBodies.validate(m,data.get("departures",[]),next_id,data.visitors)
	if not departure_check.ok:return departure_check
	var previous_bodies=m.departing_bodies;var candidate_bodies:Array[Dictionary]=[];candidate_bodies.assign(departure_check.bodies);m.departing_bodies=candidate_bodies
	var previous=m.reception_visits;var candidate:Array[Dictionary]=[];candidate.assign(data.visitors);m.reception_visits=candidate
	var inventory=TableOccupancy.inspect(m)
	var geometry_error=layout_error(m,m.items,m.built_walls,m.owned_parcels,m.wall_attachments)
	m.reception_visits=previous;m.departing_bodies=previous_bodies
	if inventory.error!="":return {"ok":false,"error":inventory.error}
	if geometry_error!="":return {"ok":false,"error":geometry_error}
	return {"ok":true,"visitors":data.visitors,"departures":departure_check.bodies}
