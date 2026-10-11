extends SceneTree
const Model=preload("res://scripts/cafe_model.gd")
const Codec=preload("res://scripts/cafe_runtime_codec.gd")
const Extent=preload("res://scripts/exterior_world_extent.gd")
class LegacyStart extends "res://scripts/cafe_model.gd":
	func _arrival_start_position()->Vector2:
		var z=maxf(ARRIVAL_START_Z,float(depth)+.8)
		for guest in customers:
			if guest.phase=="arriving" and float(guest.x)<0:z=maxf(z,float(guest.z)+.9)
		return Vector2(ARRIVAL_LANE_X,z)
var checks=0
var failures=[]
func check(ok:bool,label:String):
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func same(a,b)->bool:
	if (a is int or a is float) and (b is int or b is float):return absf(float(a)-float(b))<1e-10
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
func _init():
	check(Extent.PAVEMENT_Z_MIN==-82 and Extent.PAVEMENT_Z_MAX==82 and Extent.STREET_Z_MIN==-84 and Extent.STREET_Z_MAX==84,"original road and pavement ends retained exactly")
	var model=Model.new();model.tick(4.0)
	check(model.customers.size()==2,"unchanged first admission interval/cap")
	check(model.customers[0].z==82.0 and model.customers[1].z==-82.0,"first pair starts at opposite original road ends")
	check(model.customers[0].heading==Vector2.UP and model.customers[1].heading==Vector2.DOWN,"both arrivals face into their real route")
	var original=model.customers.duplicate(true)
	model.owned_parcels.assign(model.PARCEL_IDS);model._sync_floor_bounds()
	check(model.customers==original,"expansion never relocates existing arrivals")
	model._next_customer_id=3;check(model._arrival_start_position()==Vector2(-2.76,82),"expanded cafe uses same fixed positive end")
	model._next_customer_id=4;check(model._arrival_start_position()==Vector2(-2.76,-82),"expanded cafe uses same fixed negative end")
	model._next_customer_id=3;model.tick(1.0)
	check(absf(model.customers[0].z-80.5)<.001 and absf(model.customers[1].z+80.5)<.001,"actual approach walks at unchanged1.5 tiles per second")
	check(model.save("user://endpoints-midwalk.json"),"save far-lane arrivals: "+model.last_error)
	var path="user://endpoints-midwalk.json";var bytes=FileAccess.get_sha256(path)
	var loaded=Model.new();check(loaded.load_save(path),"load far-lane arrivals: "+loaded.last_error)
	check(same(loaded.customers,model.customers) and loaded.coins==model.coins,"mid-approach save preserves both actor identities/routes/wallet")
	check(bytes==FileAccess.get_sha256(path),"loading leaves source bytes unchanged")
	var codec=Codec.new()
	check(not codec._point(Vector2(-2.76,82)),"staff/general coordinate limit is unchanged")
	var bad=model.customers[0].duplicate(true);bad.x=-2.75
	check(not codec._street_path_valid(bad),"extended guest must be on exact street lane")
	bad=model.customers[0].duplicate(true);bad.z=82.1
	check(not codec._street_path_valid(bad),"route cannot extend beyond original endpoint")
	bad=model.customers[0].duplicate(true);bad.street_origin_z=-82.0
	check(not codec._street_path_valid(bad),"route side must match its origin")
	bad=model.customers[0].duplicate(true);bad.erase("street_route_format");bad.erase("street_origin_z")
	check(not codec._street_path_valid(bad),"long coordinates require explicit new route guard")
	bad=model.customers[0].duplicate(true);bad.phase="ordering"
	check(not codec._street_path_valid(bad),"interior service cannot borrow extended coordinates")
	bad=model.customers[0].duplicate(true);bad.route=[Vector2(3,5)]
	check(not codec._street_path_valid(bad),"outer lane cannot jump diagonally inside")
	model.set_operating_open(false)
	check(model.customers[0].route[-1]==Vector2(-2.76,82) and model.customers[1].route[-1]==Vector2(-2.76,-82),"closing sends each unadmitted guest back to its own road end")
	check(model.save("user://endpoints-withdrawn.json"),"save both returning guests: "+model.last_error)
	var withdrawn=Model.new();check(withdrawn.load_save("user://endpoints-withdrawn.json"),"load both returning guests")
	check(same(withdrawn.customers,model.customers),"withdrawal roundtrip preserves exact routes")
	model.tick(5.0)
	check(model.customers.is_empty() and model.served==0 and model.total_earned==0,"cancelled approaches finish without invented income")
	var old=LegacyStart.new();old.tick(4.0)
	for guest in old.customers:guest.erase("street_origin_z");guest.erase("street_route_format")
	check(old.save("user://old-mid-street.json"),"old in-flight route fixture saves")
	var previous=Model.new();check(previous.load_save("user://old-mid-street.json"),"old in-flight route remains readable")
	check(same(previous.customers,old.customers),"existing old route is not reset, relocated or extended")
	var rerouted=Model.new();rerouted.tick(4.0)
	for guest in rerouted.customers:check(rerouted.reroute_guest(guest),"reroute each endpoint arrival")
	check(rerouted.save("user://both-rerouted-before.json"),"save rerouted outer prefixes")
	for frame in range(1600):
		rerouted.tick(.05)
		if rerouted.customers.all(func(g):return g.phase!="arriving"):break
	check(rerouted.customers.all(func(g):return g.seated and g.phase in ["ordering","cooking"]),"both rerouted visitors reach their seats")
	check(rerouted.save("user://both-rerouted-seated.json"),"save after rerouted prefixes become consumed history: "+rerouted.last_error)
	var seated_reload=Model.new();check(seated_reload.load_save("user://both-rerouted-seated.json"),"load both seated guests with consumed street history")
	check(same(seated_reload.customers,rerouted.customers),"consumed-history reload preserves both identities/routes/clocks")
	for guest in rerouted.customers:
		var future=guest.duplicate(true);future.route=[Vector2(-2.76,float(guest.street_origin_z))];future.route_index=0
		check(not codec._street_path_valid(future),"seated guest cannot use an extended remaining route")
		var disjoint=guest.duplicate(true);disjoint.route=[Vector2(-2.76,5.5),Vector2(-2.76,float(guest.street_origin_z))];disjoint.route_index=2
		check(not codec._street_path_valid(disjoint),"consumed external history cannot appear after interior points")
		var wrong_end=guest.duplicate(true);wrong_end.route[0]=Vector2(-2.76,-float(guest.street_origin_z))
		check(not codec._street_path_valid(wrong_end),"consumed prefix cannot belong to the opposite end")
		var wrong_lane=guest.duplicate(true);wrong_lane.route[0]=Vector2(-2.70,float(guest.street_origin_z))
		check(not codec._street_path_valid(wrong_lane),"consumed prefix still requires the exact lane")
	var export_path=OS.get_environment("LL_STREET_OLD_LOADER_INPUT")
	if export_path!="":check(loaded.save(export_path),"export synthetic long-route fixture for the actual0.1.8 loader")
	print("STREET_ENDPOINTS_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"coordinate_bounds":[-82,82],"arrival_interval":Model.ARRIVAL_INTERVAL,"maximum_arriving":Model.MAX_ARRIVING}))
	quit(0 if failures.is_empty() else 1)
