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
func one_waiting_goal():
	var m=fresh();m.coins=100000
	# Preserve the central aisle and service branches while constraining the
	# reception area to one harmless alcove at (1,6).
	for x in range(1,5):
		for z in range(9):
			var at=Vector2i(x,z)
			if z==5 or at in [Vector2i(1,6),Vector2i(2,4),Vector2i(2,3)]:continue
			if m.items.any(func(i):return int(i.x)==x and int(i.z)==z):continue
			m.items.append({"id":m._next_item_id,"kind":"plant","x":x,"z":z,"rot":0});m._next_item_id+=1
	m.revision+=1
	return m
func run():
	check("saveguard" in OS.get_user_data_dir(),"generated profile only")
	var m=full()
	check(Reception.add(m,Vector2(-2.76,-4.5)),"older request starts farther from the door")
	var older=int(m.reception_visits[-1].id)
	check(Reception.add(m,Vector2(-2.76,5.5)),"newer request starts near the door")
	var first=int(m.reception_visits[-1].id)
	for frame in range(180):
		tick(m,.1)
		for v in m.reception_visits:
			check(Reception._public(m,Reception.point(v)) or m.is_floor_owned(Reception.cell(Reception.point(v))),"every walk stays on pavement or owned floor")
		check(Occupancy.inspect(m).error=="","one occupancy owner throughout simultaneous arrival")
	var a=find(m,older);var b=find(m,first)
	check(not a.is_empty() and not b.is_empty() and int(b.ready_order)<int(a.ready_order),"actual entrance arrival wins over spawn ID")
	check(m.reception_visits.all(func(v):return v.chair_id==-1 and v.table_id==-1),"occupied dining chairs are not borrowed as waiting chairs")
	check(m.reception_visits.all(func(v):return v.x>=1 and not m.Checkout.is_door_landing(m,Reception.cell(Reception.point(v)))),"standing waiters keep doorway and staff arrival strip clear")
	m=roundtrip(m,"standing-priority")
	m.customers.remove_at(0);tick(m,12)
	check(m.customers.any(func(g):return int(g.id)==first),"existing physically arrived waiter receives the first released table")
	check(not m.customers.any(func(g):return int(g.id)==older),"later physical arrival does not double-book the same table")
	m=roundtrip(m,"fairness-handoff")
	# Live departure still owns its seat; a dirty cleanup carrier does not.
	m=full();m.customers[0].paid=true;m._begin_departure(m.customers[0])
	var departure_id=int(m.customers[0].id);var table_id=int(m.customers[0].table_id)
	check(Occupancy.inspect(m).tables[table_id].occupant_id==departure_id,"leaving diner remains live occupancy until physically departed")
	# Closing/timeout during dismount must retain the body’s old chair origin,
	# even though its exclusive destination claim has already changed.
	for reason in ["close","timeout"]:
		m=full();m.items.append({"id":14,"kind":"chair","x":2,"z":7,"rot":0});m._next_item_id=15;m.rebuild_dining_sets()
		var waiting_id=nearby(m);tick(m,14);var waiting=find(m,waiting_id)
		check(not waiting.is_empty() and waiting.seated and waiting.chair_id==14,reason+" dismount fixture sits on unpaired chair")
		var cleanup_id=make_dirty(m,0);tick(m,.1);waiting=find(m,waiting_id)
		check(waiting.previous_chair_id==14 and waiting.chair_id!=14 and not waiting.seated,reason+" destination changes before body leaves old chair")
		m=roundtrip(m,reason+"-destination-claimed");waiting=find(m,waiting_id)
		if reason=="close":m.set_operating_open(false)
		else:waiting.wait_seconds=Reception.WAIT_SECONDS-.05
		tick(m,.1);waiting=find(m,waiting_id)
		check(not waiting.is_empty() and waiting.phase=="leaving" and not waiting.route.is_empty(),reason+" finds physical exit during old-chair dismount")
		m=roundtrip(m,reason+"-dismount-exit")
		tick(m,80)
		check(find(m,waiting_id).is_empty(),reason+" interrupted visitor walks out without becoming stranded")
		check(m.customers.any(func(g):return int(g.id)==cleanup_id),reason+" preserves independent preceding cleanup")
	print("RECEPTION_FAIRNESS_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"roundtrips":saves}))
	quit(0 if failures.is_empty() else 1)

func fresh():
	var m=Model.new();assert(m.enable_reception_review(),m.last_error);return m
