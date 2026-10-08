extends RefCounted
## Fixed four-bay upgrade. Real trips share the existing arrival clock and IDs.
const FORMAT="little_leaf.parking.v1"
const PRICE=2000 # Provisional in-game price; historical paid_cost is authoritative.
const CAPACITY=4
const BAY_X=[1.3,4.2,7.1,10.0]
const BAY_Z=-7.15
const AISLE_Z=-4.8
const LINK_X=.34
const HANDOFF=Vector2(-2.76,-.26)
const CAR_START=Vector2(-4.65,-82.0)
const CAR_END=Vector2(-4.65,82.0)
const CAR_SPEED=5.5
const PENDING=["car_arriving","walking_in","queued"]
const PHASES=["car_arriving","walking_in","queued","dining","walking_return","car_departing"]

static func bay_point(bay:int)->Vector2:return Vector2(BAY_X[bay],BAY_Z)
static func door_point(bay:int)->Vector2:return bay_point(bay)+Vector2(.82,0)
static func car_route(bay:int,departing=false)->Array:
	var aisle=Vector2(BAY_X[bay],AISLE_Z)
	return [aisle,Vector2(CAR_START.x,AISLE_Z),CAR_END] if departing else [Vector2(CAR_START.x,AISLE_Z),aisle,bay_point(bay)]
static func inward_route(bay:int)->Array:
	return [Vector2(door_point(bay).x,AISLE_Z),Vector2(LINK_X,AISLE_Z),Vector2(LINK_X,HANDOFF.y),HANDOFF]
static func return_route(bay:int,origin:Vector2)->Array:
	return [Vector2(HANDOFF.x,origin.y),HANDOFF,Vector2(LINK_X,HANDOFF.y),Vector2(LINK_X,AISLE_Z),Vector2(door_point(bay).x,AISLE_Z),door_point(bay)]
static func find(model,id:int)->Dictionary:
	for visit in model.parking_visits:
		if int(visit.id)==id:return visit
	return {}
static func reserved_slots(model)->Dictionary:
	var slots={}
	for visit in model.parking_visits:
		if visit.phase in ["car_arriving","walking_in"]:slots[int(visit.slot)]=true
	return slots
static func pending_count(model)->int:return reserved_slots(model).size()
static func oldest_pending(model)->int:
	var id=-1
	for visit in model.parking_visits:
		if visit.phase in PENDING and not visit.cancelled and (id<0 or int(visit.id)<id):id=int(visit.id)
	for visitor in model.outside_queue:
		if visitor.phase=="outside_queue" and (id<0 or int(visitor.id)<id):id=int(visitor.id)
	return id
static func reserve(model)->bool:
	if not model.parking_owned or model.parking_visits.size()>=CAPACITY or model.outside_queue.size()+pending_count(model)>=model.OutsideQueue.CAPACITY:return false
	# One throat/aisle maneuver at a time; never stack waiting cars at origin.
	for visit in model.parking_visits:
		if visit.car_position.distance_to(CAR_START)<2.8:return false
	var bays={};var slots=reserved_slots(model)
	for visit in model.parking_visits:bays[int(visit.bay)]=true
	for visitor in model.outside_queue:slots[int(visitor.slot)]=true
	var bay=0;var slot=0
	while bays.has(bay):bay+=1
	while slots.has(slot):slot+=1
	model.parking_visits.append({"id":model._next_customer_id,"bay":bay,"slot":slot,"phase":"car_arriving","cancelled":false,"car_position":CAR_START,"car_heading":Vector2.DOWN,"car_route":car_route(bay),"car_index":0,"walk_origin":door_point(bay),"walk_position":door_point(bay),"walk_heading":Vector2.DOWN,"walk_route":inward_route(bay),"walk_index":0})
	model._next_customer_id+=1
	return true
static func visual_walkers(model)->Array:
	var actors=[]
	for visit in model.parking_visits:
		if visit.phase not in ["walking_in","walking_return"]:continue
		actors.append({"id":visit.id,"x":visit.walk_position.x,"z":visit.walk_position.y,"heading":visit.walk_heading,"phase":"parking_walk","seated":false,"waiting":false,"table_id":-1,"chair_id":-1,"parking_visit":true})
	return actors
static func _move(visit:Dictionary,prefix:String,budget:float):
	var position:Vector2=visit[prefix+"position"];var route:Array=visit[prefix+"route"];var index=int(visit[prefix+"index"])
	while budget>.000001 and index<route.size():
		var difference:Vector2=route[index]-position;var distance=difference.length()
		if distance<.000001:index+=1;continue
		visit[prefix+"heading"]=difference/distance
		var step=minf(distance,budget);position+=visit[prefix+"heading"]*step;budget-=step
		if step+.000001>=distance:position=route[index];index+=1
	visit[prefix+"position"]=position;visit[prefix+"index"]=index
static func _settled(visit:Dictionary,prefix:String)->bool:return int(visit[prefix+"index"])==visit[prefix+"route"].size()
static func _drive_out(visit:Dictionary):
	visit.phase="car_departing";visit.slot=-1
	visit.car_route=car_route(int(visit.bay),true);visit.car_index=0
static func start_return(model,id:int,position:Vector2)->bool:
	var visit=find(model,id)
	if visit.is_empty() or visit.phase in ["walking_return","car_departing"]:return false
	visit.phase="walking_return";visit.slot=-1
	visit.walk_origin=position;visit.walk_position=position;visit.walk_route=return_route(int(visit.bay),position);visit.walk_index=0
	return true
static func return_queued(model,visitor:Dictionary)->bool:
	if find(model,int(visitor.id)).is_empty():return false
	start_return(model,int(visitor.id),Vector2(float(visitor.x),float(visitor.z)))
	model.outside_queue.erase(visitor)
	return true
static func admitted(model,guest:Dictionary):
	var visit=find(model,int(guest.id))
	if visit.is_empty():return
	visit.phase="dining";visit.slot=-1;guest["parking_visit"]=true
static func close(model):
	for visit in model.parking_visits:
		if visit.phase in ["car_arriving","walking_in"]:visit.cancelled=true
	for visitor in model.outside_queue.duplicate():return_queued(model,visitor)
static func _handoff(model,visit:Dictionary):
	if visit.cancelled or not model.operating_open:
		start_return(model,int(visit.id),HANDOFF);return
	var visitor={"id":visit.id,"slot":visit.slot,"phase":"outside_queue","x":HANDOFF.x,"z":HANDOFF.y,"heading":Vector2.DOWN,"origin_z":-82.0,"wait_seconds":0.0,"route":[Vector2(HANDOFF.x,model.OutsideQueue.target(int(visit.slot)).y),model.OutsideQueue.target(int(visit.slot))],"route_index":0,"seated":false,"waiting":false,"table_id":-1,"chair_id":-1}
	if oldest_pending(model)==int(visit.id) and model._try_admit_queued_visitor(visitor):return
	visit.phase="queued";model.outside_queue.append(visitor)
	model.outside_queue.sort_custom(func(a,b):return int(a.id)<int(b.id))
static func _driving(visit:Dictionary)->bool:
	if visit.phase not in ["car_arriving","car_departing"]:return false
	var origin=CAR_START if visit.phase=="car_arriving" else bay_point(int(visit.bay))
	return int(visit.car_index)>0 or visit.car_position!=origin
static func advance(model,delta:float):
	var moving_id=-1
	# A maneuver already in progress keeps the throat, even if an older diner
	# finishes walking back while that car is moving. No mid-route preemption.
	for visit in model.parking_visits:
		if _driving(visit):moving_id=int(visit.id);break
	for visit in model.parking_visits:
		if moving_id<0 and visit.phase in ["car_arriving","car_departing"]:moving_id=int(visit.id)
	var retired=[]
	for visit in model.parking_visits:
		if not model.operating_open and visit.phase in ["car_arriving","walking_in"]:visit.cancelled=true
		match visit.phase:
			"car_arriving","car_departing":
				if int(visit.id)!=moving_id:continue
				_move(visit,"car_",CAR_SPEED*delta)
				if not _settled(visit,"car_"):continue
				if visit.phase=="car_departing":retired.append(visit)
				elif visit.cancelled:_drive_out(visit)
				else:visit.phase="walking_in"
			"walking_in":
				_move(visit,"walk_",model.WALK_SPEED*delta)
				if _settled(visit,"walk_"):_handoff(model,visit)
			"walking_return":
				_move(visit,"walk_",model.WALK_SPEED*delta)
				if _settled(visit,"walk_"):_drive_out(visit)
	for visit in retired:model.parking_visits.erase(visit)

static func _on_route(point:Vector2,origin:Vector2,route:Array,index:int)->bool:
	if index==route.size():return point.distance_to(route[-1])<.0001
	var start=origin if index==0 else route[index-1]
	var end:Vector2=route[index]
	return absf(point.distance_to(start)+point.distance_to(end)-start.distance_to(end))<.0001
static func validate(raw,customers:Array,queue:Array,next_id:int,open:bool)->Dictionary:
	var codec=preload("res://scripts/cafe_runtime_codec.gd").new()
	var data=codec.decode(raw)
	if codec.error!="" or not data is Dictionary or not data.get("format") is String or data.get("format")!=FORMAT or not data.get("owned") is bool or not codec._integer(data.get("paid_cost"),0,1000000000) or not data.get("visits") is Array:return {"ok":false,"error":"Invalid parking format"}
	if (data.owned and data.paid_cost<=0) or (not data.owned and (data.paid_cost!=0 or not data.visits.is_empty())) or data.visits.size()>CAPACITY:return {"ok":false,"error":"Invalid parking ownership or capacity"}
	var ids={};var bays={};var slots={};var guests={};var visitors={}
	for guest in customers:
		if guest.has("parking_visit") and (not guest.parking_visit is bool or not guest.parking_visit):return {"ok":false,"error":"Invalid parking guest marker"}
		guests[int(guest.id)]=guest
	for visitor in queue:visitors[int(visitor.id)]=visitor;slots[int(visitor.slot)]=int(visitor.id)
	var pending=0;var driving=0
	for visit in data.visits:
		if not visit is Dictionary:return {"ok":false,"error":"Invalid parking visit"}
		for key in ["id","bay","slot","phase","cancelled","car_position","car_heading","car_route","car_index","walk_origin","walk_position","walk_heading","walk_route","walk_index"]:
			if not visit.has(key):return {"ok":false,"error":"Incomplete parking visit"}
		if not codec._integer(visit.id,1,next_id-1) or ids.has(int(visit.id)) or not codec._integer(visit.bay,0,CAPACITY-1) or bays.has(int(visit.bay)) or visit.phase not in PHASES or not visit.cancelled is bool:return {"ok":false,"error":"Invalid parking identity/bay/phase"}
		if not codec._integer(visit.slot,-1,model_queue_capacity()-1) or not visit.car_route is Array or not visit.walk_route is Array:return {"ok":false,"error":"Invalid parking slot or route type"}
		for point in visit.car_route+visit.walk_route:
			if not point is Vector2 or not point.is_finite():return {"ok":false,"error":"Invalid parking route point"}
		var id=int(visit.id);var bay=int(visit.bay)
		ids[id]=visit;bays[bay]=true
		for key in ["car_position","car_heading","walk_origin","walk_position","walk_heading"]:
			if not visit[key] is Vector2 or not visit[key].is_finite():return {"ok":false,"error":"Invalid parking coordinate"}
		for key in ["car_heading","walk_heading"]:
			if visit[key] not in [Vector2.UP,Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT]:return {"ok":false,"error":"Invalid parking heading"}
		if not codec._integer(visit.car_index,0,3) or not codec._integer(visit.walk_index,0,6):return {"ok":false,"error":"Invalid parking route index"}
		var cancelled_before_exit=visit.phase=="car_departing" and visit.cancelled and visit.walk_route==inward_route(bay) and int(visit.walk_index)==0 and visit.walk_position==door_point(bay)
		var returning=visit.phase=="walking_return" or (visit.phase=="car_departing" and not cancelled_before_exit)
		if returning:
			if not codec._number(visit.walk_origin.x,HANDOFF.x,-.85) or not codec._number(visit.walk_origin.y,-2.5,28):return {"ok":false,"error":"Invalid parking return origin"}
		elif visit.walk_origin!=door_point(bay):return {"ok":false,"error":"Invalid parking walk origin"}
		var expected_walk=return_route(bay,visit.walk_origin) if returning else inward_route(bay)
		var departing=visit.phase=="car_departing"
		if visit.car_route!=car_route(bay,departing) or visit.walk_route!=expected_walk or not codec._integer(visit.car_index,0,3) or not codec._integer(visit.walk_index,0,expected_walk.size()):return {"ok":false,"error":"Invalid parking route"}
		if not _on_route(visit.car_position,bay_point(bay) if departing else CAR_START,visit.car_route,int(visit.car_index)) or not _on_route(visit.walk_position,visit.walk_origin,visit.walk_route,int(visit.walk_index)):return {"ok":false,"error":"Parking actor is off route"}
		if visit.phase not in ["car_arriving","car_departing"] and (visit.car_position!=bay_point(bay) or int(visit.car_index)!=3):return {"ok":false,"error":"Driver left an unparked car"}
		if visit.phase=="car_arriving" and (visit.walk_position!=door_point(bay) or int(visit.walk_index)!=0):return {"ok":false,"error":"Driver exists before parking"}
		if visit.phase=="car_departing" and not cancelled_before_exit and not _settled(visit,"walk_"):return {"ok":false,"error":"Car departed before driver boarded"}
		if visit.phase=="dining" and visit.cancelled:return {"ok":false,"error":"Cancelled parking request owns dining"}
		if _driving(visit):driving+=1
		if driving>1:return {"ok":false,"error":"Multiple cars own parking maneuver"}
		if visit.phase in ["queued","dining"] and not _settled(visit,"walk_"):return {"ok":false,"error":"Driver has not reached pavement"}
		if visit.phase in PENDING:
			if not codec._integer(visit.slot,0,model_queue_capacity()-1):return {"ok":false,"error":"Invalid reserved queue slot"}
			if slots.has(int(visit.slot)) and int(slots[int(visit.slot)])!=id:return {"ok":false,"error":"Duplicate reserved queue slot"}
			slots[int(visit.slot)]=id
			if visit.phase!="queued":pending+=1
		elif visit.slot!=-1:return {"ok":false,"error":"Finished request retains queue slot"}
		if not open and visit.phase in ["car_arriving","walking_in"] and not visit.cancelled:return {"ok":false,"error":"Closed cafe has uncancelled parking arrival"}
		if visit.phase=="queued":
			if not visitors.has(id) or visitors[id].phase!="outside_queue" or int(visitors[id].slot)!=int(visit.slot) or guests.has(id) or visit.cancelled:return {"ok":false,"error":"Parking queue ownership mismatch"}
			if visitors[id].origin_z!=-82.0 or float(visitors[id].z)<HANDOFF.y-.00001:return {"ok":false,"error":"Parking queue guest predates pavement handoff"}
		elif visitors.has(id):return {"ok":false,"error":"Duplicate parking pedestrian"}
		if visit.phase=="dining":
			if not guests.has(id) or guests[id].phase in ["dirty","cleaning"] or guests[id].get("parking_visit",false)!=true:return {"ok":false,"error":"Parking dining ownership mismatch"}
		elif guests.has(id) and (visit.phase not in ["walking_return","car_departing"] or guests[id].phase not in ["dirty","cleaning"] or guests[id].get("parking_visit",false)!=true):return {"ok":false,"error":"Duplicate parking guest"}
	if queue.size()+pending>model_queue_capacity():return {"ok":false,"error":"Parking requests exceed outside capacity"}
	for guest in customers:
		if guest.has("parking_visit"):
			if guest.parking_visit!=true or (guest.phase not in ["dirty","cleaning"] and (not ids.has(int(guest.id)) or ids[int(guest.id)].phase!="dining")):return {"ok":false,"error":"Orphan parking guest"}
	return {"ok":true,"state":data}
static func model_queue_capacity()->int:return 6
static func empty_state()->Dictionary:return {"format":FORMAT,"owned":false,"paid_cost":0,"visits":[]}
