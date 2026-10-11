extends RefCounted
## Movement-only continuation after the diner physically clears its dining place.
## Meal/cleanup remains with its original service record; this body owns no seat.
const CAPACITY=60
const NONE=Vector2i(-100,-100)

static func point(body:Dictionary)->Vector2:return Vector2(float(body.x),float(body.z))
static func _handoff_valid(m,endpoint,entry_cell,entry_outside,entry_direction)->bool:
	if not endpoint is Vector2 or not endpoint.is_finite() or absf(endpoint.x+.85)>.0001 or endpoint.y< -2.5 or endpoint.y>28:return false
	if not entry_cell is Vector2i or not entry_outside is Vector2i or not entry_direction is Vector2i:return false
	return entry_direction==Vector2i.LEFT and m.is_floor_owned(entry_cell) and m._public_exterior_cell(entry_outside) and entry_cell+entry_direction==entry_outside

static func can_split(m,guest:Dictionary)->bool:
	if not m.reception_review_enabled:return false
	if m.departing_bodies.size()>=CAPACITY or guest.phase!="leaving" or bool(guest.get("withdrawn",false)) or bool(guest.get("seated",false)) or bool(guest.get("dismounting",false)) or not guest.get("mobility",{}).is_empty():return false
	if not bool(guest.paid) and not bool(guest.get("meal_abandoned",false)):return false
	# The existing cashier queue keeps its front until this same body clears it.
	if guest.get("checkout_cell",NONE)!=NONE:return false
	var chair=m.get_item(int(guest.chair_id));var table=m.get_item(int(guest.table_id))
	if chair.is_empty() or table.is_empty():return false
	var at=point(guest)
	if at.distance_to(Vector2(chair.x+.5,chair.z+.5))<=.9 or at.distance_to(Vector2(table.x+.5,table.z+.5))<=1.3:return false
	var route:Array=guest.route.slice(int(guest.route_index))
	if route.is_empty() or route.size()>512 or not _handoff_valid(m,route[-1],guest.get("entry_cell"),guest.get("entry_outside"),guest.get("entry_direction")):return false
	var codec=m.RuntimeCodec.new()
	if not codec._number(guest.x,-3,m.MAX_WIDTH) or not codec._number(guest.z,-2.5,28) or not guest.heading is Vector2 or not guest.heading.is_finite() or guest.heading.length()>1.001:return false
	# Genuine historical in-flight routes retain their old authority unchanged.
	return m.Reception._route_error(m,at,route)==""

static func split(m,guest:Dictionary)->bool:
	if not can_split(m,guest):return false
	var at=point(guest);var route:Array=guest.route.slice(int(guest.route_index))
	var body={"id":int(guest.id),"phase":"leaving","x":at.x,"z":at.y,"heading":guest.heading,"route_origin":at,"route":route.duplicate(),"route_index":0,"endpoint":route[-1],"waiting":false,"seated":false,"table_id":-1,"chair_id":-1,"cleanup_owner_id":int(guest.id),"entry_cell":guest.entry_cell,"entry_outside":guest.entry_outside,"entry_direction":guest.entry_direction,"parking_visit":bool(guest.get("parking_visit",false))}
	m.departing_bodies.append(body)
	# The old record is now only the cleanup owner. Retain its ID, paid status,
	# table/chair provenance and service token, with no second moving body.
	guest.phase="dirty";guest.elapsed=0.0;guest.duration=m.PHASE_SECONDS.dirty
	guest.route=[];guest.route_index=0;guest.waiting=false
	guest.checkout_cell=NONE
	guest.dismounting=false;guest.seated=false;guest.dismount_progress=1.0
	if m._walking_customer_id==int(guest.id):m._walking_customer_id=-1
	return true

static func advance(m,delta:float,active=null):
	for body in m.departing_bodies.duplicate() if active==null else active:
		var at=point(body);var budget=m.WALK_SPEED*delta
		while budget>.000001 and int(body.route_index)<body.route.size():
			var target:Vector2=body.route[int(body.route_index)];var distance=at.distance_to(target)
			if distance<.000001:body.route_index+=1;continue
			if m.segment_blocked(at,target):body.waiting=true;break
			body.heading=(target-at)/distance
			var step=minf(distance,budget);at+=body.heading*step;budget-=step;body.waiting=false
			if step+.000001>=distance:at=target;body.route_index+=1
		body.x=at.x;body.z=at.y
		body.route=body.route.slice(int(body.route_index));body.route_index=0;body.route_origin=at
		if body.route.is_empty():
			m.Parking.start_return(m,int(body.id),at)
			m.departing_bodies.erase(body)
	refresh_cleanup_references(m)

static func refresh_cleanup_references(m):
	for body in m.departing_bodies:
		if not m.customers.any(func(g):return int(g.id)==int(body.id)):body.cleanup_owner_id=-1

static func uses_cell(m,cell:Vector2i)->bool:
	for body in m.departing_bodies:
		var previous=point(body)
		if m.Reception.cell(previous)==cell:return true
		for target in body.route:
			var count=maxi(1,ceili(previous.distance_to(target)*8))
			for i in range(count+1):
				if m.Reception.cell(previous.lerp(target,float(i)/count))==cell:return true
			previous=target
	return false

static func layout_error(m)->String:
	for body in m.departing_bodies:
		if m.Reception._route_error(m,point(body),body.route)!="":return "Keep the departing visitor's walking route clear"
	return ""

static func validate(m,raw,next_id:int,waiting:Array)->Dictionary:
	if not raw is Array or raw.size()>CAPACITY:return {"ok":false,"error":"Invalid departing-body capacity"}
	var codec=m.RuntimeCodec.new();var ids={};var guests={}
	for guest in m.customers:guests[int(guest.id)]=guest
	for visitor in m.outside_queue+waiting:ids[int(visitor.id)]=true
	for body in raw:
		if not body is Dictionary:return {"ok":false,"error":"Invalid departing body"}
		for key in ["id","phase","x","z","heading","route_origin","route","route_index","endpoint","waiting","seated","table_id","chair_id","cleanup_owner_id","entry_cell","entry_outside","entry_direction","parking_visit"]:
			if not body.has(key):return {"ok":false,"error":"Incomplete departing body"}
		if not codec._integer(body.id,1,next_id-1) or ids.has(int(body.id)):return {"ok":false,"error":"Duplicate departing actor identity"}
		ids[int(body.id)]=true
		if body.phase!="leaving" or not body.seated is bool or body.seated or not codec._integer(body.table_id,-1,-1) or not codec._integer(body.chair_id,-1,-1) or not body.waiting is bool or not body.parking_visit is bool:return {"ok":false,"error":"Departing body retains dining authority"}
		if not codec._number(body.x,-3,m.MAX_WIDTH) or not codec._number(body.z,-2.5,28) or not body.heading is Vector2 or not body.heading.is_finite() or body.heading.length()>1.001:return {"ok":false,"error":"Invalid departing position or heading"}
		if not codec._integer(body.cleanup_owner_id,-1,next_id-1) or int(body.cleanup_owner_id) not in [-1,int(body.id)]:return {"ok":false,"error":"Invalid departing cleanup reference"}
		if guests.has(int(body.id)):
			if guests[int(body.id)].phase not in ["dirty","cleaning"] or int(body.cleanup_owner_id)!=int(body.id):return {"ok":false,"error":"Departure duplicates a live diner"}
			if bool(guests[int(body.id)].get("parking_visit",false))!=body.parking_visit:return {"ok":false,"error":"Departure changed its parking identity"}
		elif int(body.cleanup_owner_id)!=-1:return {"ok":false,"error":"Departing cleanup owner is missing"}
		if not body.route_origin is Vector2 or not body.route_origin.is_finite() or not body.endpoint is Vector2 or not body.endpoint.is_finite() or not body.route is Array or body.route.is_empty() or body.route.size()>512 or not codec._integer(body.route_index,0,0):return {"ok":false,"error":"Invalid departing route"}
		if point(body).distance_to(body.route_origin)>.0001 or not body.route[-1] is Vector2 or body.endpoint.distance_to(body.route[-1])>.0001 or absf(body.endpoint.x+.85)>.0001 or not codec._number(body.endpoint.y,-2.5,28):return {"ok":false,"error":"Departing route lost its exit handoff"}
		for key in ["entry_cell","entry_outside","entry_direction"]:
			if not body[key] is Vector2i:return {"ok":false,"error":"Invalid departing entrance metadata"}
		if not _handoff_valid(m,body.endpoint,body.entry_cell,body.entry_outside,body.entry_direction):return {"ok":false,"error":"Departing exit is not owned/public"}
		var error=m.Reception._route_error(m,point(body),body.route)
		if error!="":return {"ok":false,"error":error}
	return {"ok":true,"bodies":raw}
