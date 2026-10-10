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
static func advance(state:Dictionary,parking:Array,delta:float):
	# Compute from one old-position snapshot so following is independent of array order.
	var movements=[]
	for car in state.cars:movements.append(allowance(car.position,int(car.direction),SPEED*delta,state.cars,parking,int(car.id)))
	for i in range(COUNT):
		var car=state.cars[i]
		car.position.y=Extent.STREET_Z_MIN+fposmod(car.position.y-Extent.STREET_Z_MIN+car.direction*movements[i],Extent.STREET_Z_MAX-Extent.STREET_Z_MIN)
	state.elapsed+=delta
