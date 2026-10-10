extends RefCounted
## Model-owned fixed pool; shares the existing service tick and parking snapshot.
const Extent=preload("res://scripts/exterior_world_extent.gd")
const COUNT=8
const SPEED=2.8
const GAP=4.5
const LANES=[-4.65,-7.35]
static func initial()->Dictionary:
	var cars=[]
	for i in range(COUNT):cars.append({"id":i,"position":Vector2(LANES[i%2],-65.0+i*19.0),"direction":1 if i%2==0 else -1,"color":"a2b3b3" if i%3==0 else "ddcdb0"})
	return {"elapsed":0.0,"cars":cars}
static func validate(state)->bool:
	if not state is Dictionary or not state.get("cars") is Array or state.cars.size()!=COUNT:return false
	if not (state.get("elapsed") is int or state.get("elapsed") is float) or not is_finite(float(state.elapsed)) or float(state.elapsed)<0:return false
	var ids={}
	for car in state.cars:
		if not car is Dictionary or not (car.get("id") is int or car.get("id") is float) or not is_finite(float(car.id)) or float(car.id)!=floorf(float(car.id)) or car.id<0 or car.id>=COUNT or ids.has(car.id):return false
		ids[car.id]=true
		if car.get("direction")!=(1 if int(car.id)%2==0 else -1) or car.get("color")!=("a2b3b3" if int(car.id)%3==0 else "ddcdb0"):return false
		if not car.get("position") is Vector2 or not car.position.is_finite() or not is_equal_approx(car.position.x,LANES[int(car.id)%2]) or car.position.y<Extent.STREET_Z_MIN or car.position.y>=Extent.STREET_Z_MAX:return false
	for car in state.cars:
		for other in state.cars:
			if car.id!=other.id and car.direction==other.direction and fposmod((other.position.y-car.position.y)*car.direction,float(Extent.STREET_Z_MAX-Extent.STREET_Z_MIN))<GAP-.001:return false
	return true
static func allowance(position:Vector2,direction:int,budget:float,road:Array,parking:Array,except_id:int=-1)->float:
	var allowed=budget;var span=float(Extent.STREET_Z_MAX-Extent.STREET_Z_MIN)
	for car in road:
		if car.id==except_id or car.direction!=direction:continue
		var ahead=fposmod((car.position.y-position.y)*direction,span)
		allowed=minf(allowed,maxf(0,ahead-GAP))
	for car in parking:
		if car.phase not in ["car_arriving","car_departing"] or absf(car.car_position.x-position.x)>1.7:continue
		if car.phase=="car_departing" and car.car_route.size()==35 and (int(car.car_index)<18 or (int(car.car_index)==18 and car.car_position.distance_to(car.car_route[17])<.0001)):continue
		var ahead=(car.car_position.y-position.y)*direction
		if ahead>=0:allowed=minf(allowed,maxf(0,ahead-GAP))
	return allowed
static func merge_clear(state:Dictionary,z:float)->bool:
	for car in state.cars:
		if car.direction==1 and absf(car.position.y-z)<GAP+2.0:return false
	return true
static func _advance_cars(state:Dictionary,parking:Array,delta:float):
	# Compute from one old-position snapshot so following is independent of array order.
	var movements=[]
	for car in state.cars:movements.append(allowance(car.position,int(car.direction),SPEED*delta,state.cars,parking,int(car.id)))
	for i in range(COUNT):
		var car=state.cars[i]
		car.position.y=Extent.STREET_Z_MIN+fposmod(car.position.y-Extent.STREET_Z_MIN+car.direction*movements[i],Extent.STREET_Z_MAX-Extent.STREET_Z_MIN)
	state.elapsed+=delta

# Optional transient controller. The serialized road dictionary remains unchanged.
static func advance(state:Dictionary,parking:Array,delta:float,bus=null):
	if bus==null:
		_advance_cars(state,parking,delta);return
	if not is_finite(delta) or delta<=0:return
	var remaining=delta
	while remaining>.000001:
		var step=minf(remaining,1.0/30.0)
		_advance_shared(state,parking,step,bus)
		remaining-=step
static func bus_bounds(snapshot:Dictionary)->Rect2:
	var rear:Vector2=-snapshot.heading;var side=Vector2(rear.y,-rear.x)
	var bounds=Rect2(snapshot.position,Vector2.ZERO)
	for x in [-.77,.77]:
		for z in [-2.60,2.60]:bounds=bounds.expand(snapshot.position+side*x+rear*z)
	# Actual body plus longitudinal breathing room for the original tall iso art.
	return Rect2(bounds.position-Vector2(.30,1.60),bounds.size+Vector2(.60,3.20))
static func _car_intersects(car_position:Vector2,bounds:Rect2)->bool:
	var span=float(Extent.STREET_Z_MAX-Extent.STREET_Z_MIN)
	for image in [-span,0.0,span]:
		if bounds.intersects(Rect2(car_position+Vector2(-.60,-1.10+image),Vector2(1.20,2.20))):return true
	return false
static func _occupied(bounds:Rect2,road:Array,parking:Array)->bool:
	for car in road:
		if _car_intersects(car.position,bounds):return true
	for car in parking:
		if car.phase in ["car_arriving","car_departing"] and _car_intersects(car.car_position,bounds):return true
	return false
static func _approach_bounds(bus)->Rect2:
	if bus.traffic_approach_region.has_area():return bus.traffic_approach_region
	var bounds=bus_bounds(bus.bus_path(bus.Neighborhood.BUS_POSITION.y,"approaching"))
	for i in range(1,22):bounds=bounds.merge(bus_bounds(bus.bus_path(bus.Neighborhood.BUS_POSITION.y+bus.APPROACH_LENGTH*i/21.0,"approaching")))
	bus.traffic_approach_region=bounds
	return bounds
static func _merge_bounds(bus)->Rect2:
	if bus.traffic_merge_region.has_area():return bus.traffic_merge_region
	var path=bus.bus_path(bus.Neighborhood.BUS_POSITION.y,"departing")
	var bounds=bus_bounds(path)
	# Reserve the actual oriented departure arc once, before leaving the bay.
	for i in range(1,19):
		path=bus.bus_path(bus.Neighborhood.BUS_POSITION.y-bus.DEPART_LENGTH*i/18.0,"departing")
		bounds=bounds.merge(bus_bounds(path))
	bus.traffic_merge_region=bounds
	return bounds
static func _bus_allowance(position:Vector2,direction:int,budget:float,bounds:Rect2)->float:
	if position.x+.60<=bounds.position.x or position.x-.60>=bounds.end.x:return budget
	var span=float(Extent.STREET_Z_MAX-Extent.STREET_Z_MIN);var allowed=budget
	for image in [-span,0.0,span]:
		var near_edge=bounds.position.y+image-1.10 if direction>0 else bounds.end.y+image+1.10
		var ahead=(near_edge-position.y)*direction
		if ahead>=-.00001:allowed=minf(allowed,maxf(0,ahead))
	return allowed
static func _advance_shared(state:Dictionary,parking:Array,step:float,bus):
	# Neither authority reads positions already moved by the other this step.
	var old_bus=bus.bus_snapshot();var next_bus=bus.snapshot_at(bus.elapsed+step)
	var has_bus=bool(old_bus.visible) or bool(next_bus.visible)
	var sweep=Rect2();var accepted=true
	if has_bus:
		sweep=bus_bounds(next_bus if next_bus.visible else old_bus)
		if old_bus.visible and next_bus.visible:sweep=sweep.merge(bus_bounds(old_bus))
		if next_bus.state=="approaching" and next_bus.position.y<bus.Neighborhood.BUS_POSITION.y+bus.APPROACH_LENGTH and not bus.approach_reserved:
			var approach=_approach_bounds(bus)
			if _occupied(approach,state.cars,parking):accepted=false
			else:bus.approach_reserved=true
		if old_bus.state=="stopped" and next_bus.state=="departing" and not bus.merge_reserved:
			var merge=_merge_bounds(bus)
			if _occupied(merge,state.cars,parking):accepted=false
			else:bus.merge_reserved=true
		if accepted and next_bus.state in ["approaching","departing"] and _occupied(sweep,state.cars,parking):accepted=false
		if not accepted:
			has_bus=bool(old_bus.visible)
			if has_bus:sweep=bus_bounds(old_bus)
		if bus.approach_reserved:
			if old_bus.state=="stopped":bus.approach_reserved=false
			else:sweep=sweep.merge(_approach_bounds(bus))
		if bus.merge_reserved:
			if old_bus.state=="departing" and old_bus.position.y<=bus.Neighborhood.BUS_POSITION.y-bus.DEPART_LENGTH:bus.merge_reserved=false
			else:sweep=sweep.merge(_merge_bounds(bus))
	var movements=[]
	for car in state.cars:
		var movement=allowance(car.position,int(car.direction),SPEED*step,state.cars,parking,int(car.id))
		if has_bus:movement=_bus_allowance(car.position,int(car.direction),movement,sweep)
		movements.append(movement)
	for i in range(COUNT):
		var car=state.cars[i]
		car.position.y=Extent.STREET_Z_MIN+fposmod(car.position.y-Extent.STREET_Z_MIN+car.direction*movements[i],Extent.STREET_Z_MAX-Extent.STREET_Z_MIN)
	state.elapsed+=step
	if accepted:bus.accept_traffic_progress(step)
