extends RefCounted
## Fixed four-bay upgrade. Real trips share the existing arrival clock and IDs.
const LEGACY_FORMAT="little_leaf.parking.v1"
const FORMAT="little_leaf.parking.v2"
const APPEARANCE_RECIPE="original_guest_v1"
const Traffic=preload("res://scripts/cafe_road_traffic.gd")
const PRICE=2000 # Provisional in-game price; historical paid_cost is authoritative.
const CAPACITY=4
const BAY_X=[1.3,4.2,7.1,10.0]
const BAY_Z=-7.15
const AISLE_Z=-4.8
const LINK_X=.34
const HANDOFF=Vector2(-2.76,-.26)
const CAR_START=Vector2(-4.65,-82.0)
const CAR_END=Vector2(-4.65,82.0)
const CAR_SPEED=2.8
const PENDING=["car_arriving","walking_in","queued"]
const PHASES=["car_arriving","walking_in","queued","dining","walking_return","car_departing","parked"]

static func initial_traffic()->Dictionary:return Traffic.initial()
static func snapshot(model)->Dictionary:
	return {"format":FORMAT,"owned":model.parking_owned,"paid_cost":model.parking_paid_cost,"visits":model.parking_visits,"traffic":model.road_traffic_state}
static func restore_traffic(model,state:Dictionary):model.road_traffic_state=state.traffic.duplicate(true)
static func bay_point(bay:int)->Vector2:return Vector2(BAY_X[bay],BAY_Z)
static func door_point(bay:int)->Vector2:return bay_point(bay)+Vector2(.82,0)
static func _legacy_car_route(bay:int,departing=false)->Array:
	var aisle=Vector2(BAY_X[bay],AISLE_Z)
	return [aisle,Vector2(CAR_START.x,AISLE_Z),CAR_END] if departing else [Vector2(CAR_START.x,AISLE_Z),aisle,bay_point(bay)]
static func _arc(points:Array,center:Vector2,radius:float,start:float,finish:float):
	# Static route geometry allocated once per maneuver, never per frame.
	for i in range(1,17):points.append(center+Vector2(cos(lerpf(start,finish,i/16.0)),sin(lerpf(start,finish,i/16.0)))*radius)
static func car_route(bay:int,departing=false)->Array:
	var points=[];var x:float=BAY_X[bay]
	if departing:
		points.append(Vector2(x,AISLE_Z-.8))
		_arc(points,Vector2(x+.8,AISLE_Z-.8),.8,PI,PI/2)
		points.append(Vector2(CAR_START.x+1.5,AISLE_Z))
		_arc(points,Vector2(CAR_START.x+1.5,AISLE_Z+1.5),1.5,-PI/2,-PI)
		points.append(CAR_END)
	else:
		points.append(Vector2(CAR_START.x,AISLE_Z-1.5))
		_arc(points,Vector2(CAR_START.x+1.5,AISLE_Z-1.5),1.5,PI,PI/2)
		points.append(Vector2(x-.8,AISLE_Z))
		_arc(points,Vector2(x-.8,AISLE_Z-.8),.8,PI/2,0)
		points.append(bay_point(bay))
	return points
static func inward_route(bay:int)->Array:
	return [Vector2(door_point(bay).x,AISLE_Z),Vector2(LINK_X,AISLE_Z),Vector2(LINK_X,HANDOFF.y),HANDOFF]
static func return_route(bay:int,origin:Vector2)->Array:
	return [Vector2(HANDOFF.x,origin.y),HANDOFF,Vector2(LINK_X,HANDOFF.y),Vector2(LINK_X,AISLE_Z),Vector2(door_point(bay).x,AISLE_Z),door_point(bay)]
static func find(model,id:int)->Dictionary:
	for car in model.parking_visits:
		for member in car.members:
			if int(member.id)==id:return member
	return {}
static func car_for(model,id:int)->Dictionary:
	for car in model.parking_visits:
		if car.members.any(func(m):return int(m.id)==id):return car
	return {}
static func reserved_slots(model)->Dictionary:
	var slots={}
	for car in model.parking_visits:
		for member in car.members:
			if member.phase in ["in_car","walking_in"]:slots[int(member.slot)]=true
	return slots
static func pending_count(model)->int:return reserved_slots(model).size()
static func oldest_pending(model)->int:
	var id=-1
	for car in model.parking_visits:
		for member in car.members:
			if member.phase in ["in_car","walking_in","queued"] and not member.cancelled and (id<0 or int(member.id)<id):id=int(member.id)
	for visitor in model.outside_queue:
		if visitor.phase=="outside_queue" and (id<0 or int(visitor.id)<id):id=int(visitor.id)
	return id
static func reserve(model,party_size:int=0)->bool:
	if not model.parking_owned or model.parking_visits.size()>=CAPACITY:return false
	# Existing arrival cadence chooses one bounded party; no additional timer.
	var count=1+posmod(model._next_customer_id,4) if party_size==0 else party_size
	if count<1 or count>4 or model.outside_queue.size()+pending_count(model)+count>model.OutsideQueue.CAPACITY:return false
	for car in model.parking_visits:
		if car.car_position.distance_to(CAR_START)<Traffic.GAP:return false
	for car in model.road_traffic_state.cars:
		if car.direction==1 and absf(car.position.y-CAR_START.y)<Traffic.GAP:return false
	var bays={};var slots=reserved_slots(model)
	for car in model.parking_visits:bays[int(car.bay)]=true
	for visitor in model.outside_queue:slots[int(visitor.slot)]=true
	var bay=0
	while bays.has(bay):bay+=1
	var car_id=int(model._next_customer_id);var members=[]
	for i in range(count):
		var slot=0
		while slots.has(slot):slot+=1
		slots[slot]=true
		var id=int(model._next_customer_id);model._next_customer_id+=1
		members.append({"id":id,"member_id":id,"car_id":car_id,"appearance_sequence":id,"species_index":posmod(id,3),"appearance_recipe":APPEARANCE_RECIPE,"bay":bay,"slot":slot,"phase":"in_car","cancelled":false,"walk_origin":door_point(bay),"walk_position":door_point(bay),"walk_heading":Vector2.DOWN,"walk_route":inward_route(bay),"walk_index":0})
	model.parking_visits.append({"id":car_id,"bay":bay,"phase":"car_arriving","cancelled":false,"car_position":CAR_START,"car_heading":Vector2.DOWN,"car_route":car_route(bay),"car_index":0,"members":members})
	return true
static func _bind(actor:Dictionary,member:Dictionary):
	actor.parking_car_id=member.car_id;actor.parking_member_id=member.id
	actor.appearance_sequence=member.appearance_sequence;actor.species_index=member.species_index;actor.appearance_recipe=member.appearance_recipe
static func visual_walkers(model)->Array:
	var actors=[]
	for car in model.parking_visits:
		for member in car.members:
			if member.phase not in ["walking_in","walking_return"]:continue
			var actor={"id":member.id,"x":member.walk_position.x,"z":member.walk_position.y,"heading":member.walk_heading,"phase":"parking_walk","seated":false,"waiting":false,"table_id":-1,"chair_id":-1,"parking_visit":true}
			_bind(actor,member);actors.append(actor)
	return actors
static func _move(visit:Dictionary,prefix:String,budget:float,stop_index:int=-1):
	var position:Vector2=visit[prefix+"position"];var route:Array=visit[prefix+"route"];var index=int(visit[prefix+"index"])
	while budget>.000001 and index<route.size() and (stop_index<0 or index<stop_index):
		var difference:Vector2=route[index]-position;var distance=difference.length()
		if distance<.000001:index+=1;continue
		var origin=visit.walk_origin if prefix=="walk_" else (CAR_START if visit.phase=="car_arriving" else bay_point(int(visit.bay)))
		var start=origin if index==0 else route[index-1]
		visit[prefix+"heading"]=(route[index]-start).normalized()
		var step=minf(distance,budget);position+=visit[prefix+"heading"]*step;budget-=step
		# Back out to the right, retain the parked front, then drive left along
		# the aisle. Body/axles stay collinear with travel through the reverse arc.
		if prefix=="car_" and visit.phase=="car_departing" and route.size()==35 and index<=16:visit.car_heading=-visit.car_heading
		if step+.000001>=distance:position=route[index];index+=1
	visit[prefix+"position"]=position;visit[prefix+"index"]=index
static func _settled(visit:Dictionary,prefix:String)->bool:return int(visit[prefix+"index"])==visit[prefix+"route"].size()
static func _drive_out(car:Dictionary):
	if not car.members.all(func(m):return m.phase=="boarded"):return
	car.phase="car_departing";car.car_route=car_route(int(car.bay),true);car.car_index=0
static func start_return(model,id:int,position:Vector2)->bool:
	var member=find(model,id)
	if member.is_empty() or member.phase in ["walking_return","boarded","in_car"]:return false
	member.phase="walking_return";member.slot=-1
	member.walk_origin=position;member.walk_position=position;member.walk_route=return_route(int(member.bay),position);member.walk_index=0
	return true
static func return_queued(model,visitor:Dictionary)->bool:
	if find(model,int(visitor.id)).is_empty():return false
	start_return(model,int(visitor.id),Vector2(float(visitor.x),float(visitor.z)));model.outside_queue.erase(visitor)
	return true
static func admitted(model,guest:Dictionary):
	var member=find(model,int(guest.id))
	if member.is_empty():return
	member.phase="dining";member.slot=-1;guest["parking_visit"]=true;_bind(guest,member)
static func close(model):
	for car in model.parking_visits:
		for member in car.members:
			if member.phase in ["in_car","walking_in"]:member.cancelled=true
		car.cancelled=car.members.all(func(m):return m.cancelled)
	for visitor in model.outside_queue.duplicate():return_queued(model,visitor)
static func _handoff(model,member:Dictionary):
	if member.cancelled or not model.operating_open:start_return(model,int(member.id),HANDOFF);return
	var visitor={"id":member.id,"slot":member.slot,"phase":"outside_queue","x":HANDOFF.x,"z":HANDOFF.y,"heading":Vector2.DOWN,"origin_z":-82.0,"wait_seconds":0.0,"route":[Vector2(HANDOFF.x,model.OutsideQueue.target(int(member.slot)).y),model.OutsideQueue.target(int(member.slot))],"route_index":0,"seated":false,"waiting":false,"table_id":-1,"chair_id":-1}
	_bind(visitor,member)
	if oldest_pending(model)==int(member.id) and model._try_admit_queued_visitor(visitor):return
	member.phase="queued";model.outside_queue.append(visitor);model.outside_queue.sort_custom(func(a,b):return int(a.id)<int(b.id))
static func _driving(car:Dictionary)->bool:
	if car.phase not in ["car_arriving","car_departing"]:return false
	var origin=CAR_START if car.phase=="car_arriving" else bay_point(int(car.bay))
	return int(car.car_index)>0 or car.car_position!=origin
static func advance(model,delta:float):
	if not is_finite(delta) or delta<=0:return
	Traffic.advance(model.road_traffic_state,model.parking_visits,delta)
	var moving_id=-1
	for car in model.parking_visits:
		if _driving(car):moving_id=int(car.id);break
	for car in model.parking_visits:
		if moving_id<0 and car.phase in ["car_arriving","car_departing"]:moving_id=int(car.id)
	var retired=[]
	for car in model.parking_visits:
		if not model.operating_open:
			for m in car.members:
				if m.phase in ["in_car","walking_in"]:m.cancelled=true
		if car.phase in ["car_arriving","car_departing"]:
			if int(car.id)!=moving_id:continue
			var budget=CAR_SPEED*delta;var stop_index=-1
			if absf(car.car_position.x-CAR_START.x)<.01:
				budget=Traffic.allowance(car.car_position,1,budget,model.road_traffic_state.cars,[])
			if car.phase=="car_departing" and car.car_route.size()==35 and (int(car.car_index)<18 or (int(car.car_index)==18 and car.car_position.distance_to(car.car_route[17])<.0001)):
				# Wait at the aisle before committing the merge arc; once committed,
				# road followers yield to the physical car instead of restarting it.
				if not Traffic.merge_clear(model.road_traffic_state,AISLE_Z+1.5):stop_index=18
			_move(car,"car_",budget,stop_index)
			if not _settled(car,"car_"):continue
			if car.phase=="car_departing":retired.append(car);continue
			car.phase="parked"
		# Doorway spacing follows the preceding member's actual movement.
		var can_exit=true
		for member in car.members:
			if member.phase=="in_car":
				if member.cancelled:member.phase="boarded";member.slot=-1
				elif can_exit:member.phase="walking_in"
				else:continue
			if member.phase=="walking_in":
				_move(member,"walk_",model.WALK_SPEED*delta)
				can_exit=member.walk_position.distance_to(door_point(int(car.bay)))>=.95
				if _settled(member,"walk_"):_handoff(model,member)
			elif member.phase=="walking_return":
				_move(member,"walk_",model.WALK_SPEED*delta)
				if _settled(member,"walk_"):member.phase="boarded"
		_drive_out(car)
	for car in retired:model.parking_visits.erase(car)

static func _on_route(point:Vector2,origin:Vector2,route:Array,index:int)->bool:
	if index==route.size():return point.distance_to(route[-1])<.0001
	var start=origin if index==0 else route[index-1]
	var end:Vector2=route[index]
	return absf(point.distance_to(start)+point.distance_to(end)-start.distance_to(end))<.0001
static func _validate_single(raw,customers:Array,queue:Array,next_id:int,open:bool)->Dictionary:
	var codec=preload("res://scripts/cafe_runtime_codec.gd").new()
	var data=codec.decode(raw)
	if codec.error!="" or not data is Dictionary or not data.get("format") is String or data.get("format")!=LEGACY_FORMAT or not data.get("owned") is bool or not codec._integer(data.get("paid_cost"),0,1000000000) or not data.get("visits") is Array:return {"ok":false,"error":"Invalid parking format"}
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
		if not codec._integer(visit.id,1,next_id-1) or ids.has(int(visit.id)) or not codec._integer(visit.bay,0,CAPACITY-1) or bays.has(int(visit.bay)) or visit.phase not in PHASES or visit.phase=="parked" or not visit.cancelled is bool:return {"ok":false,"error":"Invalid parking identity/bay/phase"}
		if not codec._integer(visit.slot,-1,model_queue_capacity()-1) or not visit.car_route is Array or not visit.walk_route is Array:return {"ok":false,"error":"Invalid parking slot or route type"}
		for point in visit.car_route+visit.walk_route:
			if not point is Vector2 or not point.is_finite():return {"ok":false,"error":"Invalid parking route point"}
		var id=int(visit.id);var bay=int(visit.bay)
		ids[id]=visit;bays[bay]=true
		for key in ["car_position","car_heading","walk_origin","walk_position","walk_heading"]:
			if not visit[key] is Vector2 or not visit[key].is_finite():return {"ok":false,"error":"Invalid parking coordinate"}
		for key in ["car_heading","walk_heading"]:
			if (key=="walk_heading" and visit[key] not in [Vector2.UP,Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT]) or (key=="car_heading" and absf(visit[key].length()-1.0)>.0001):return {"ok":false,"error":"Invalid parking heading"}
		if not codec._integer(visit.car_index,0,visit.car_route.size()) or not codec._integer(visit.walk_index,0,6):return {"ok":false,"error":"Invalid parking route index"}
		var cancelled_before_exit=visit.phase=="car_departing" and visit.cancelled and visit.walk_route==inward_route(bay) and int(visit.walk_index)==0 and visit.walk_position==door_point(bay)
		var returning=visit.phase=="walking_return" or (visit.phase=="car_departing" and not cancelled_before_exit)
		if returning:
			if not codec._number(visit.walk_origin.x,HANDOFF.x,-.85) or not codec._number(visit.walk_origin.y,-2.5,28):return {"ok":false,"error":"Invalid parking return origin"}
		elif visit.walk_origin!=door_point(bay):return {"ok":false,"error":"Invalid parking walk origin"}
		var expected_walk=return_route(bay,visit.walk_origin) if returning else inward_route(bay)
		var departing=visit.phase=="car_departing"
		if (visit.car_route!=car_route(bay,departing) and visit.car_route!=_legacy_car_route(bay,departing)) or visit.walk_route!=expected_walk or not codec._integer(visit.car_index,0,visit.car_route.size()) or not codec._integer(visit.walk_index,0,expected_walk.size()):return {"ok":false,"error":"Invalid parking route"}
		if not _on_route(visit.car_position,bay_point(bay) if departing else CAR_START,visit.car_route,int(visit.car_index)) or not _on_route(visit.walk_position,visit.walk_origin,visit.walk_route,int(visit.walk_index)):return {"ok":false,"error":"Parking actor is off route"}
		if visit.phase not in ["car_arriving","car_departing"] and (visit.car_position!=bay_point(bay) or int(visit.car_index)!=visit.car_route.size()):return {"ok":false,"error":"Driver left an unparked car"}
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
static func empty_state()->Dictionary:return {"format":LEGACY_FORMAT,"owned":false,"paid_cost":0,"visits":[]}

static func _legacy_member(car:Dictionary,member:Dictionary)->Dictionary:
	var visit=member.duplicate(true)
	for key in ["car_position","car_heading","car_route","car_index"]:visit[key]=car[key]
	if car.phase=="car_arriving":visit.phase="car_arriving"
	elif car.phase=="car_departing":visit.phase="car_departing"
	elif member.phase=="boarded":visit.phase="walking_return"
	return visit
static func _migrate_single(visit:Dictionary)->Dictionary:
	var car=visit.duplicate(true);var member=visit.duplicate(true)
	member.member_id=member.id;member.car_id=member.id;member.appearance_sequence=member.id
	member.species_index=posmod(int(member.id),3);member.appearance_recipe=APPEARANCE_RECIPE
	if visit.phase=="car_arriving":member.phase="in_car"
	elif visit.phase=="car_departing":member.phase="boarded"
	else:car.phase="parked"
	for key in ["car_position","car_heading","car_route","car_index"]:member.erase(key)
	car.members=[member];return car
static func validate(raw,customers:Array,queue:Array,next_id:int,open:bool)->Dictionary:
	var codec=preload("res://scripts/cafe_runtime_codec.gd").new();var data=codec.decode(raw)
	if codec.error!="" or not data is Dictionary:return {"ok":false,"error":"Invalid parking format"}
	var legacy_format=data.get("format")==LEGACY_FORMAT
	if legacy_format:
		var legacy=_validate_single(raw,customers,queue,next_id,open)
		if not legacy.ok:return legacy
		data=legacy.state;var cars=[]
		for visit in data.visits:cars.append(_migrate_single(visit))
		data.format=FORMAT;data.visits=cars
	if data.get("format")!=FORMAT or not data.get("owned") is bool or not codec._integer(data.get("paid_cost"),0,1000000000) or not data.get("visits") is Array:return {"ok":false,"error":"Invalid parking party format"}
	if (data.owned and data.paid_cost<=0) or (not data.owned and (data.paid_cost!=0 or not data.visits.is_empty())) or data.visits.size()>CAPACITY:return {"ok":false,"error":"Invalid parking ownership/capacity"}
	if legacy_format:data.traffic=Traffic.initial()
	if not Traffic.validate(data.get("traffic")):return {"ok":false,"error":"Invalid road traffic snapshot"}
	var ids={};var bays={};var slots={};var moving=0;var pending=0
	for visitor in queue:slots[int(visitor.slot)]=int(visitor.id)
	for car in data.visits:
		if not car is Dictionary or not car.get("members") is Array or car.members.size()<1 or car.members.size()>4:return {"ok":false,"error":"Invalid parking membership"}
		if not codec._integer(car.get("id"),1,next_id-1) or not codec._integer(car.get("bay"),0,CAPACITY-1) or bays.has(int(car.bay)) or car.get("phase") not in ["car_arriving","parked","car_departing"] or not car.get("cancelled") is bool:return {"ok":false,"error":"Invalid parking car identity"}
		bays[int(car.bay)]=true
		for key in ["car_position","car_heading","car_route","car_index"]:
			if not car.has(key):return {"ok":false,"error":"Incomplete parking car"}
		if not car.members[0] is Dictionary or not codec._integer(car.members[0].get("id"),1,next_id-1) or int(car.members[0].id)!=int(car.id):return {"ok":false,"error":"Car owner changed"}
		if not codec._integer(car.car_index,0,35) or not car.car_position is Vector2 or not car.car_position.is_finite() or not car.car_heading is Vector2 or not car.car_heading.is_finite() or not car.car_route is Array:return {"ok":false,"error":"Invalid car motion"}
		for point in car.car_route:
			if not point is Vector2 or not point.is_finite():return {"ok":false,"error":"Invalid car route point"}
		var departing=car.phase=="car_departing"
		if car.car_route!=car_route(int(car.bay),departing) and car.car_route!=_legacy_car_route(int(car.bay),departing):return {"ok":false,"error":"Invalid car route"}
		if not codec._integer(car.car_index,0,car.car_route.size()) or not _on_route(car.car_position,bay_point(int(car.bay)) if departing else CAR_START,car.car_route,int(car.car_index)):return {"ok":false,"error":"Car moved off its owned route"}
		if car.phase=="parked" and (car.car_position!=bay_point(int(car.bay)) or int(car.car_index)!=car.car_route.size()):return {"ok":false,"error":"Members left an unparked car"}
		if _driving(car):moving+=1
		if moving>1:return {"ok":false,"error":"Multiple parking maneuvers"}
		for member in car.members:
			if not member is Dictionary or not codec._integer(member.get("id"),1,next_id-1) or ids.has(int(member.id)):return {"ok":false,"error":"Duplicate/invalid parking member"}
			var id=int(member.id);ids[id]=true
			if member.get("member_id")!=id or member.get("car_id")!=car.id or member.get("appearance_sequence")!=id or member.get("appearance_recipe")!=APPEARANCE_RECIPE or member.get("species_index")!=posmod(id,3) or member.get("bay")!=car.bay:return {"ok":false,"error":"Parking identity/appearance/owner changed"}
			if member.get("phase") not in ["in_car","walking_in","queued","dining","walking_return","boarded"]:return {"ok":false,"error":"Invalid member phase"}
			if (car.phase=="car_arriving" and member.phase!="in_car") or (car.phase=="car_departing" and member.phase!="boarded") or (member.phase=="in_car" and car.phase=="car_departing"):return {"ok":false,"error":"Car moved without its original members"}
			var guest_list=customers.filter(func(g):return int(g.id)==id)
			var visitor_list=queue.filter(func(v):return int(v.id)==id)
			var visit=_legacy_member(car,member)
			if member.phase=="in_car" and car.phase=="parked":
				visit.phase="car_arriving";visit.car_position=CAR_START;visit.car_route=car_route(int(car.bay));visit.car_index=0
			if member.phase=="boarded" and member.cancelled and member.walk_index==0:
				visit.phase="car_departing";visit.car_position=bay_point(int(car.bay));visit.car_route=car_route(int(car.bay),true);visit.car_index=0
			var check=_validate_single(codec.encode({"format":LEGACY_FORMAT,"owned":true,"paid_cost":data.paid_cost,"visits":[visit]}),guest_list,visitor_list,next_id,open)
			if not check.ok:return check
			if member.phase in ["in_car","walking_in","queued"]:
				if slots.has(int(member.slot)) and slots[int(member.slot)]!=id:return {"ok":false,"error":"Duplicate party queue reservation"}
				slots[int(member.slot)]=id
				if member.phase!="queued":pending+=1
			for actor in guest_list+visitor_list:
				if legacy_format:_bind(actor,member)
				elif actor.get("parking_car_id")!=car.id or actor.get("parking_member_id")!=id or actor.get("appearance_sequence")!=id or actor.get("species_index")!=member.species_index or actor.get("appearance_recipe")!=APPEARANCE_RECIPE:return {"ok":false,"error":"Guest/party binding mismatch"}
	if queue.size()+pending>model_queue_capacity():return {"ok":false,"error":"Party reservations exceed queue capacity"}
	for guest in customers:
		if guest.get("parking_visit",false) and guest.phase not in ["dirty","cleaning"] and not ids.has(int(guest.id)):return {"ok":false,"error":"Orphan parking guest"}
	return {"ok":true,"state":data}
