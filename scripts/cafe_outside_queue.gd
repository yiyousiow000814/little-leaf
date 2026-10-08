extends RefCounted
## Real prospective visitors, separate from table/service ownership until admitted.
const CAPACITY=6
const WAIT_SECONDS=90.0
const LANE_X=-1.6
const HEAD_Z=7.5
const SPACING=1.1
const STREET_X=-2.76
const END=82.0
const FORMAT="little_leaf.outside_queue.v1"

static func target(slot:int)->Vector2:return Vector2(LANE_X,HEAD_Z+slot*SPACING)

static func add(model)->bool:
	if model.outside_queue.size()>=CAPACITY:return false
	var slots={}
	for visitor in model.outside_queue:slots[int(visitor.slot)]=true
	var slot=0
	while slots.has(slot):slot+=1
	var start:Vector2=model._arrival_start_position()
	var destination=target(slot)
	model.outside_queue.append({"id":model._next_customer_id,"slot":slot,"phase":"outside_queue","x":start.x,"z":start.y,"heading":Vector2.UP if start.y>0 else Vector2.DOWN,"origin_z":start.y,"wait_seconds":0.0,"route":[Vector2(STREET_X,destination.y),destination],"route_index":0,"seated":false,"waiting":false,"table_id":-1,"chair_id":-1})
	model._next_customer_id+=1
	return true

static func cancel(visitor):
	if visitor.phase=="outside_return":return
	visitor.phase="outside_return";visitor.waiting=false
	visitor.route=[Vector2(STREET_X,float(visitor.z)),Vector2(STREET_X,float(visitor.origin_z))];visitor.route_index=0

static func settled(visitor)->bool:return int(visitor.route_index)>=visitor.route.size()

static func advance(model,delta:float):
	var retired=[]
	for visitor in model.outside_queue.duplicate():
		if not model.operating_open:cancel(visitor)
		var position=Vector2(float(visitor.x),float(visitor.z))
		var budget=model.WALK_SPEED*delta
		while budget>.000001 and not settled(visitor):
			var destination:Vector2=visitor.route[int(visitor.route_index)]
			var distance=position.distance_to(destination)
			if distance<.000001:visitor.route_index+=1;continue
			visitor.heading=(destination-position)/distance
			var step=minf(distance,budget)
			position+=visitor.heading*step;budget-=step
			if step+.000001>=distance:position=destination;visitor.route_index+=1
		visitor.x=position.x;visitor.z=position.y
		if not settled(visitor):continue
		if visitor.phase=="outside_return":retired.append(visitor);continue
		visitor.waiting=true;visitor.wait_seconds+=delta
		if not model.operating_open or visitor.wait_seconds+ .000001>=WAIT_SECONDS:cancel(visitor)
	for visitor in retired:model.outside_queue.erase(visitor)
	if not model.operating_open:return
	# Strict FIFO among live requests: a later endpoint arrival cannot overtake.
	for visitor in model.outside_queue:
		if visitor.phase!="outside_queue":continue
		if settled(visitor):model._admit_queued_visitor(visitor)
		break

static func validate(raw,customers:Array,next_id:int)->Dictionary:
	var codec=preload("res://scripts/cafe_runtime_codec.gd").new()
	var decoded=codec.decode(raw)
	if codec.error!="" or not decoded is Dictionary or decoded.get("format")!=FORMAT or not decoded.get("visitors") is Array:return {"ok":false,"error":"Invalid outside queue format"}
	var visitors:Array=decoded.visitors
	if visitors.size()>CAPACITY:return {"ok":false,"error":"Outside queue exceeds capacity"}
	var ids={};var slots={};var previous=0
	for guest in customers:ids[int(guest.id)]=true
	for visitor in visitors:
		if not visitor is Dictionary:return {"ok":false,"error":"Invalid outside visitor"}
		for key in ["id","slot","phase","x","z","heading","origin_z","wait_seconds","route","route_index","seated","waiting","table_id","chair_id"]:
			if not visitor.has(key):return {"ok":false,"error":"Incomplete outside visitor"}
		if not codec._integer(visitor.id,1,next_id-1) or ids.has(int(visitor.id)) or int(visitor.id)<=previous or not codec._integer(visitor.slot,0,CAPACITY-1) or slots.has(int(visitor.slot)):return {"ok":false,"error":"Invalid outside visitor identity/slot"}
		ids[int(visitor.id)]=true;slots[int(visitor.slot)]=true;previous=int(visitor.id)
		if visitor.phase not in ["outside_queue","outside_return"] or visitor.seated!=false or not visitor.waiting is bool or visitor.table_id!=-1 or visitor.chair_id!=-1:return {"ok":false,"error":"Outside visitor owns interior state"}
		if not codec._number(visitor.x,STREET_X,LANE_X) or not codec._number(visitor.z,-END,END) or not codec._number(visitor.wait_seconds,0,WAIT_SECONDS+.1) or not visitor.heading is Vector2 or not visitor.heading.is_finite() or visitor.heading.length()>1.001 or visitor.origin_z not in [-END,END]:return {"ok":false,"error":"Invalid outside visitor coordinates/clock"}
		if not visitor.route is Array or visitor.route.size()!=2 or not codec._integer(visitor.route_index,0,2):return {"ok":false,"error":"Invalid outside visitor route"}
		var destination=target(int(visitor.slot))
		var canonical=[Vector2(STREET_X,destination.y),destination]
		if visitor.phase=="outside_return":canonical=[Vector2(STREET_X,float(visitor.z)),Vector2(STREET_X,float(visitor.origin_z))]
		if visitor.phase=="outside_queue" and visitor.route!=canonical:return {"ok":false,"error":"Invalid outside approach"}
		if visitor.phase=="outside_return":
			if not visitor.route[0] is Vector2 or absf(visitor.route[0].x-STREET_X)>.00001 or absf(visitor.route[0].y)>END or visitor.route[1]!=canonical[1]:return {"ok":false,"error":"Invalid outside return"}
		var index=int(visitor.route_index)
		var point=Vector2(float(visitor.x),float(visitor.z))
		var first:Vector2=visitor.route[0];var last:Vector2=visitor.route[1]
		var on_route=false
		if index==2:on_route=point.distance_to(last)<.00001
		elif visitor.phase=="outside_queue":
			if index==0:on_route=absf(point.x-STREET_X)<.00001 and point.y>=minf(float(visitor.origin_z),first.y)-.00001 and point.y<=maxf(float(visitor.origin_z),first.y)+.00001
			else:on_route=absf(point.y-first.y)<.00001
		else:
			if index==0:on_route=absf(point.y-first.y)<.00001
			else:on_route=absf(point.x-STREET_X)<.00001 and point.y>=minf(first.y,last.y)-.00001 and point.y<=maxf(first.y,last.y)+.00001
		if not on_route:return {"ok":false,"error":"Outside visitor is off its route"}
	return {"ok":true,"visitors":visitors}
