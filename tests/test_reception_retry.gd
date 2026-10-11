extends SceneTree
const Model=preload("res://scripts/cafe_model.gd")
const Reception=preload("res://scripts/cafe_reception.gd")
const Occupancy=preload("res://scripts/cafe_table_occupancy.gd")
var checks=0
var failures=[]
var saves=0
func _initialize():
	create_timer(90.0).timeout.connect(func():printerr("RECEPTION_FIXTURE_TIMEOUT");quit(2))
	run.call_deferred()
func check(ok:bool,label:String):
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func same(a,b)->bool:
	if (a is int or a is float) and (b is int or b is float):return absf(float(a)-float(b))<1e-7
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
func tick(m,seconds:float):
	for frame in range(ceili(seconds/.1)):
		m._arrival_elapsed=0.0
		for guest in m.customers:
			if guest.phase not in ["arriving","leaving","dirty","cleaning"]:guest.duration=99999.0
		m.tick(.1)
func roundtrip(m,label:String):
	var path="user://reception-"+label+".json";var before=m.reception_visits.duplicate(true)
	var ok=m.save_reception(path);check(ok,label+" saves: "+m.last_error)
	if not ok:return m
	var bytes=FileAccess.get_sha256(path);var restored=fresh();ok=restored.load_reception(path)
	check(ok,label+" loads: "+restored.last_error)
	if not ok:return m
	check(FileAccess.get_sha256(path)==bytes,label+" does not rewrite original bytes")
	check(same(before,restored.reception_visits),label+" preserves exact reception state")
	check(same(m.customers,restored.customers),label+" preserves old meal/cleanup records")
	saves+=1;return restored
func full():
	var m=fresh();m._spawn_walkers(2);tick(m,72)
	check(m.customers.size()==2 and m.customers.all(func(g):return g.seated),"historical two-diner fixture naturally reaches chairs")
	return m
func make_dirty(m,index:int):
	var old=m.customers[index]
	old.phase="cleaning";old.seated=false;old.paid=true;old.x=-.85;old.z=12.5
	old.route=[];old.route_index=0;old.elapsed=0.0;old.duration=99999.0
	return int(old.id)
func nearby(m)->int:
	var ok=Reception.add(m,Vector2(-2.76,7.5));check(ok,"nearby synthetic demand accepted")
	return int(m.reception_visits[-1].id) if ok else -1
func find(m,id:int)->Dictionary:
	for v in m.reception_visits:
		if int(v.id)==id:return v
	return {}
const OldContract=preload("res://tests/fixtures/reception_original_v15_contract.gd")
func run():
	check("saveguard" in OS.get_user_data_dir(),"generated profile only")
	var m
	# A transit-cap refusal is temporary, even if occupancy IDs stay identical
	# when the first visitors promote from reception into normal service.
	m=fresh();preload("res://scripts/minimal_start.gd").apply(m);assert(m.enable_reception_review());m.first_guest_pending=false;m.coins=100000
	check(m.place("table_set",6,6,0) and m.place("table_set",9,6,0),"three-table transit fixture is reachable")
	m._spawn_walkers(2);tick(m,72);m._spawn_walkers(2);tick(m,72)
	check(m.customers.size()==3,"three synthetic historical diners occupy fixture")
	var requests=[]
	for index in range(3):requests.append(nearby(m))
	tick(m,18)
	check(m.reception_visits.size()==3 and m.reception_visits.all(func(v):return int(v.ready_order)>=0 and Reception.settled(v)),"three visitors physically wait before capacity releases")
	m.customers.clear();tick(m,.1)
	check(Reception._dining_transit_count(m)==2 and m.reception_visits.filter(func(v):return v.table_id<0).size()==1,"two concurrent moves defer the third without claiming offscreen")
	tick(m,20)
	check(m.customers.size()==3 and requests.all(func(id):return m.customers.any(func(g):return int(g.id)==id and g.seated)),"arrival-cap release retries the third waiter without unrelated edits")
	# No entrance means no actor or offscreen dining claim; restored geometry
	# accepts the same next identity rather than losing or duplicating demand.
	m=fresh();var openings=m.wall_attachments.duplicate(true);var next_id=m._next_customer_id
	m.wall_attachments.clear();m.revision+=1
	check(Reception._origins(m,Reception._empty(next_id,0,Vector2(-2.76,7.5),82)).is_empty(),"synthetic closed corridor entrance has no legal public approach")
	check(not Reception.add(m) and m.reception_visits.is_empty() and m.customers.is_empty() and m._next_customer_id==next_id,"failed entrance creates no actor, dining claim or consumed identity")
	m.wall_attachments.assign(openings);m.revision+=1
	check(Reception.add(m) and int(m.reception_visits[0].id)==next_id,"restored entrance accepts demand with original next identity")
	tick(m,72)
	check(m.customers.size()==1 and int(m.customers[0].id)==next_id and m.customers[0].seated,"restored demand actually enters and reaches its seat")
	# Population is bounded, including road requests and cars.
	m=fresh()
	for attempt in range(12):m._spawn_customer()
	check(Reception.pending_count(m)<=6 and m.customers.is_empty(),"all prospective demand stays bounded without offscreen seat holds")
	check(not Reception.add(m),"full bounded reception refuses additional demand")
	m.set_operating_open(false);tick(m,80)
	check(m.reception_visits.is_empty(),"closing returns every unseated approach by a real route")
	print("RECEPTION_RETRY_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"roundtrips":saves}))
	quit(0 if failures.is_empty() else 1)

func fresh():
	var m=Model.new();assert(m.enable_reception_review(),m.last_error);return m
