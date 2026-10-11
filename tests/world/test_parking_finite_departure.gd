extends SceneTree
const Traffic=preload("res://scripts/world/cafe_road_traffic.gd")
const Parking=preload("res://scripts/cafe_parking.gd")
var failures=[]
var checks=0
var outcomes=[]

class ModelStub extends RefCounted:
	const WALK_SPEED=1.05
	var road_traffic_state:Dictionary
	var parking_visits:Array
	var road_bus=null
	var operating_open=true
	var outside_queue=[]

func check(value:bool,label:String):
	checks+=1
	if not value:failures.append(label)

func clean(value):
	if value is Vector2:return [value.x,value.y]
	if value is Array:
		var result=[]
		for item in value:result.append(clean(item))
		return result
	if value is Dictionary:
		var result={}
		for name in value:result[name]=clean(value[name])
		return result
	return value

func restore(value,key:String=""):
	if value is Array:
		if key in ["car_position","car_heading","walk_position","walk_heading","walk_origin","position"] and value.size()==2:return Vector2(float(value[0]),float(value[1]))
		var result=[]
		for item in value:
			if key in ["car_route","walk_route"]:result.append(Vector2(float(item[0]),float(item[1])))
			else:result.append(restore(item))
		return result
	if value is Dictionary:
		var result={}
		for name in value:result[name]=restore(value[name],str(name))
		return result
	return value

func car_for(model,id:int)->Dictionary:
	for car in model.parking_visits:
		if int(car.id)==id:return car
	return {}

func model_from(input:Dictionary,with_bus:bool)->ModelStub:
	var model=ModelStub.new()
	model.road_traffic_state=restore(input.road)
	model.parking_visits=restore(input.parking)
	if with_bus:
		model.road_bus=Parking.initial_bus()
		model.road_bus.elapsed=float(input.bus_elapsed)
		model.road_bus.approach_reserved=bool(input.approach_reserved)
		model.road_bus.merge_reserved=bool(input.merge_reserved)
	return model

func coupled(input:Dictionary,with_bus:bool):
	var model=model_from(input,with_bus)
	var primary=car_for(model,2);var arrival=car_for(model,12);var parked=car_for(model,8)
	var initial_body:Vector2=primary.car_position
	var initial_members=JSON.stringify(clean(primary.members))
	var initial_arrival_members=JSON.stringify(clean(arrival.members))
	var initial_parked=JSON.stringify(clean(parked))
	check(Traffic.validate(model.road_traffic_state),"Coupled initial eight-car pool invalid")
	check(Parking._on_route(initial_body,Parking.bay_point(int(primary.bay)),primary.car_route,int(primary.car_index)),"Departure body off existing route")
	check(Parking._on_route(arrival.car_position,Parking.CAR_START,arrival.car_route,int(arrival.car_index)),"Arrival body off existing route")
	var initial=JSON.stringify(clean({"road":model.road_traffic_state,"parking":model.parking_visits}))
	var bus_clock=0.0 if model.road_bus==null else model.road_bus.elapsed
	for delta in [0.0,-.01]:
		Parking.advance(model,delta)
		check(JSON.stringify(clean({"road":model.road_traffic_state,"parking":model.parking_visits}))==initial,"Nonpositive delta changed traffic/parking")
		check(model.road_bus==null or model.road_bus.elapsed==bus_clock,"Nonpositive delta changed bus clock")
	var retired_tick=-1;var maximum_move=0.0;var road4_before=model.road_traffic_state.cars[4].position
	for tick in range(96):
		var before:Vector2=primary.car_position
		Parking.advance(model,1.0/30.0)
		maximum_move=maxf(maximum_move,before.distance_to(primary.car_position))
		if retired_tick<0 and car_for(model,2).is_empty():retired_tick=tick+1
	check(Traffic.validate(model.road_traffic_state),"Coupled final eight-car pool invalid")
	check(maximum_move<=Parking.CAR_SPEED/30.0+.0001,"Departure exceeded existing speed")
	check(JSON.stringify(clean(primary.members))==initial_members,"Departure member custody changed")
	check(JSON.stringify(clean(arrival.members))==initial_arrival_members,"Pending arrival member custody changed")
	check(JSON.stringify(clean(parked))==initial_parked,"Independent queued party changed")
	check(retired_tick>0 and retired_tick<=30,"Finite final departure failed to retire")
	check(primary.car_position==Parking.CAR_END and int(primary.car_index)==primary.car_route.size(),"Departure retired before original endpoint")
	check(arrival.car_position.y>Parking.CAR_START.y and int(arrival.car_index)==0,"Serialized next arrival did not resume")
	check(model.road_traffic_state.cars[4].position.y>road4_before.y,"Road follower did not resume behind arrival")
	outcomes.append({"bus_active":with_bus,"ticks":96,"retired_tick":retired_tick,"departure_before":initial_body,"departure_after":primary.car_position,"arrival_after":arrival.car_position,"road4_before":road4_before,"road4_after":model.road_traffic_state.cars[4].position,"maximum_departure_move":maximum_move})

func compatibility(input:Dictionary):
	var road=restore(input.road).cars
	var endpoint=Vector2(-4.65,79.55285645)
	check(Traffic.allowance(endpoint,1,.0933333,road,[])==0,"Default cyclic follower still recognizes wrapped leader")
	check(is_equal_approx(Traffic.allowance(endpoint,1,.0933333,road,[],-1,false),.0933333),"Finite terminal allowance does not follow periodic image behind")
	var serialized=model_from(input,false);var arrival=car_for(serialized,12)
	var arrival_body:Vector2=arrival.car_position
	Parking.advance(serialized,1.0/30.0)
	check(arrival.car_position==arrival_body and int(arrival.car_index)==0,"Unstarted arrival still yields to serialized departure")
	var physical=model_from(input,false)
	physical.road_traffic_state.cars[4].position.y=83.9
	check(Traffic.validate(physical.road_traffic_state),"Physical-leader control pool invalid")
	var body:Vector2=car_for(physical,2).car_position
	Parking.advance(physical,1.0/30.0)
	check(car_for(physical,2).car_position==body,"Finite departure cut through physical forward blocker")
	# An earlier maneuver uses the ordinary cyclic road rule and original speed.
	var before_final=model_from(input,false);var primary=car_for(before_final,2)
	primary.car_index=33;primary.car_position=primary.car_route[32]
	var before:Vector2=primary.car_position
	Parking.advance(before_final,1.0/30.0)
	check(primary.car_position.distance_to(before)<=Parking.CAR_SPEED/30.0+.0001,"Earlier maneuver exceeded existing speed")
	check(int(primary.car_index)==33 and before_final.parking_visits.has(primary),"Earlier maneuver skipped to retirement")

func _initialize():
	var input=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/parking-finite-departure.json"))
	if not input is Dictionary or not input.candidate_only or input.historical_r2_state_recovered:
		printerr("FINITE_DEPARTURE_FIXTURE_INVALID");quit(2);return
	compatibility(input)
	coupled(input,false)
	coupled(input,true)
	print("PARKING_FINITE_DEPARTURE_RESULT ",JSON.stringify(clean({"checks":checks,"failures":failures,"coupled_outcomes":outcomes,"candidate_snapshot_only":true,"historical_r2_state_recovered":false,"natural_journey_acceptance":false})))
	quit(0 if failures.is_empty() else 1)
