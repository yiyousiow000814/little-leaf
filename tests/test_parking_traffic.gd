extends SceneTree
const M=preload("res://scripts/cafe_model.gd")
const P=preload("res://scripts/cafe_parking.gd")
const T=preload("res://scripts/cafe_road_traffic.gd")
const E=preload("res://scripts/exterior_environment.gd")
const C=preload("res://scripts/cafe_runtime_codec.gd")
var checks=0
var failures=[]
func check(ok:bool,label:String):
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func same(a,b)->bool:
	if (a is int or a is float) and (b is int or b is float):return absf(float(a)-float(b))<1e-8
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		for key in a:
			if not b.has(key) or not same(a[key],b[key]):return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size():return false
		for i in range(a.size()):
			if not same(a[i],b[i]):return false
		return true
	return a==b
func _initialize():
	var m=M.new();m.parking_owned=true;m.parking_paid_cost=P.PRICE
	var before=m.road_traffic_state.duplicate(true);P.advance(m,0);P.advance(m,NAN)
	check(m.road_traffic_state==before,"zero/nonfinite delta freezes authoritative traffic")
	P.advance(m,1)
	check(is_equal_approx(m.road_traffic_state.cars[0].position.y-before.cars[0].position.y,T.SPEED),"road and parking use same speed")
	# Rear car follows an actual stopped parking car, with no screen visibility input.
	var road=T.initial();road.cars[0].position=Vector2(-4.65,-12)
	var obstacle={"phase":"car_arriving","car_position":Vector2(-4.65,-5)}
	for i in range(60):T.advance(road,[obstacle],.1)
	check(is_equal_approx(road.cars[0].position.y,-5-T.GAP),"physical road follower waits with body clearance")
	road.cars[0].position=Vector2(-4.65,-3.3-T.GAP)
	check(not T.merge_clear(road,-3.3),"parking merge waits for actual nearby road car")
	road.cars[0].position=Vector2(-4.65,20)
	check(T.merge_clear(road,-3.3),"clear road gap releases merge")
	check(P.reserve(m,4),"reserve original party")
	for i in range(450):P.advance(m,.1)
	var path="user://parking-traffic.json"
	check(m.save(path),"save validates bounded road snapshot: "+m.last_error)
	var restored=M.new();check(restored.load_save(path),"traffic restore validates before apply")
	check(same(restored.road_traffic_state,m.road_traffic_state),"traffic clock/pool/positions survive reload")
	var bad=P.snapshot(m).duplicate(true);bad.traffic.cars[1].id=bad.traffic.cars[0].id
	check(not P.validate(C.new().encode(bad),m.customers,m.outside_queue,m._next_customer_id,true).ok,"duplicate traffic identity rejected")
	bad=P.snapshot(m).duplicate(true);bad.traffic.elapsed=NAN
	check(not P.validate(C.new().encode(bad),m.customers,m.outside_queue,m._next_customer_id,true).ok,"nonfinite traffic clock rejected")
	bad=P.snapshot(m).duplicate(true);bad.traffic.cars.append(bad.traffic.cars[0])
	check(not P.validate(C.new().encode(bad),m.customers,m.outside_queue,m._next_customer_id,true).ok,"traffic retention cannot grow beyond eight")
	bad=P.snapshot(m).duplicate(true);bad.erase("traffic")
	check(not P.validate(C.new().encode(bad),m.customers,m.outside_queue,m._next_customer_id,true).ok,"present v2 cannot silently regenerate traffic")
	bad=P.snapshot(m).duplicate(true);bad.traffic.cars[2].position=bad.traffic.cars[0].position
	check(not P.validate(C.new().encode(bad),m.customers,m.outside_queue,m._next_customer_id,true).ok,"overlapping road ledger rejected")
	print("PARKING_TRAFFIC_RESULT ",JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
