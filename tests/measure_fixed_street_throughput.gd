extends SceneTree
const Model=preload("res://scripts/cafe_model.gd")
func _init():
	var model=Model.new();model.coins=100000
	for cell in [Vector2i(3,6),Vector2i(6,2),Vector2i(9,5),Vector2i(9,7)]:assert(model.place("table_set",cell.x,cell.y,0),model.last_error)
	var first_admitted=-1.0;var first_seated=-1.0;var cap_seconds=0.0;var elapsed=0.0
	var initial_routes=[]
	while elapsed<1800.0:
		model.tick(.1);elapsed+=.1
		var arriving=0
		for guest in model.customers:
			if guest.phase=="arriving":arriving+=1
			if guest.id<=2 and initial_routes.size()<2 and not initial_routes.any(func(g):return g.id==guest.id):initial_routes.append({"id":guest.id,"origin":[guest.x,guest.z],"travel_seconds":guest.duration})
			if bool(guest.admitted) and first_admitted<0.0:first_admitted=elapsed
			if bool(guest.seated) and first_seated<0.0:first_seated=elapsed
		if arriving>=model.MAX_ARRIVING:cap_seconds+=.1
	print("FIXED_STREET_THROUGHPUT ",JSON.stringify({"checks":1,"failures":[],"first_admitted_seconds":first_admitted,"first_seated_seconds":first_seated,"generated_30min":model._next_customer_id-1,"served_30min":model.served,"earned_30min":model.total_earned,"at_arriving_cap_seconds":cap_seconds,"first_routes":initial_routes,"scope":"six-seat stock-model30-minute synthetic fixture; actual source demand/cap/speed/phase/payment rules; worker travel is not simulated"}))
	quit()
