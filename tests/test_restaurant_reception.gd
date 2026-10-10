extends SceneTree
const Model=preload("res://scripts/cafe_model.gd")
const Reception=preload("res://scripts/cafe_reception.gd")
const Occupancy=preload("res://scripts/cafe_table_occupancy.gd")
var checks=0
var failures=[]
var saves=0
func _initialize():
	create_timer(45.0).timeout.connect(func():printerr("RECEPTION_FIXTURE_TIMEOUT");quit(2))
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
func run():
	check("saveguard" in OS.get_user_data_dir(),"generated profile only")
	var m=fresh();m.tick(4.0)
	check(m.customers.is_empty() and m.reception_visits.size()==2 and m.outside_queue.is_empty(),"ordinary demand approaches reception, not a mandatory outside FIFO")
	check(m.reception_visits.all(func(v):return v.table_id==-1 and v.chair_id==-1),"offscreen walkers own no dining or waiting seat")
	m=roundtrip(m,"road")
	tick(m,72)
	check(m.customers.size()==2 and m.customers.all(func(g):return g.seated),"ordinary walkers enter and find two clean dining seats")
	check(m.reception_visits.is_empty(),"clean seating leaves no duplicate waiting visitor")
	m=roundtrip(m,"ordinary-seated")
	# Fully occupied dining room: a separate unpaired chair is a real waiting seat.
	m=full();m.items.append({"id":14,"kind":"chair","x":2,"z":7,"rot":0});m._next_item_id=15;m.rebuild_dining_sets()
	var id=nearby(m);tick(m,14)
	var visitor=find(m,id)
	check(not visitor.is_empty() and visitor.phase=="waiting_table" and visitor.seated and visitor.chair_id==14 and visitor.table_id==-1,"unpaired chair offers seated waiting without stealing a dining chair")
	check(m.customers.size()==2,"waiting chair creates no food service customer")
	m=roundtrip(m,"waiting-chair")
	visitor=find(m,id);var waited=float(visitor.get("wait_seconds",0))
	if not visitor.is_empty():
		var old_id=make_dirty(m,0);tick(m,12);visitor=find(m,id)
		check(not visitor.is_empty() and visitor.phase=="waiting_cleaning" and visitor.seated,"waiting-chair guest walks to physically vacant dirty dining chair")
		check(not visitor.is_empty() and float(visitor.wait_seconds)>waited,"patience does not reset across waiting states")
		if not visitor.is_empty():
			var inventory=Occupancy.inspect(m);var state=inventory.tables[int(visitor.table_id)]
			check(inventory.error=="" and state.occupant_id==id and state.cleanup_owner_id==old_id,"one live occupant and independent previous cleanup owner")
			check(not m.customers.any(func(g):return int(g.id)==id),"dirty-table waiter has no new order/job before cleanup")
			m=roundtrip(m,"old-cleanup-new-seated")
			var old=m.customers.filter(func(g):return int(g.id)==old_id)[0]
			old.elapsed=old.duration-.05;tick(m,.1)
			check(m.customers.any(func(g):return int(g.id)==id and g.phase=="ordering" and g.seated),"actual cleanup completion promotes same seated identity to ordering")
			check(not m.customers.any(func(g):return int(g.id)==old_id) and find(m,id).is_empty(),"cleanup carrier retires without duplicate live customer")
			m=roundtrip(m,"cleanup-handoff")
	# Dirty table never preempts a usable clean one.
	m=full();make_dirty(m,0);m.customers.remove_at(1);id=nearby(m);tick(m,14)
	check(m.customers.any(func(g):return int(g.id)==id and g.table_id==8),"clean dining pair wins before dirty one")
	# Timeout leaves an independently owned dirty-table job untouched.
	m=full();var cleanup_id=make_dirty(m,0);id=nearby(m);tick(m,15)
	visitor=find(m,id)
	check(not visitor.is_empty() and visitor.phase=="waiting_cleaning","timeout fixture sits at dirty table")
	if not visitor.is_empty():
		visitor.wait_seconds=89.95;tick(m,.1);visitor=find(m,id)
		check(not visitor.is_empty() and visitor.phase=="leaving","90-second accumulated waiting starts a real departure")
		check(m.customers.any(func(g):return int(g.id)==cleanup_id and g.phase=="cleaning"),"timeout never deletes previous cleanup job")
		m=roundtrip(m,"timeout-departure")
		tick(m,65);check(find(m,id).is_empty(),"timed-out diner walks out and retires")
	# Every malformed private save is atomic; historical default reads are tested separately.
	m=fresh();nearby(m);tick(m,2);m=roundtrip(m,"mid-entrance")
	var source="user://reception-format-source.json";var source_saved=m.save_reception(source);check(source_saved,"version fixture writes")
	if not source_saved:
		print("RESTAURANT_RECEPTION_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"roundtrips":saves}));quit(1);return
	var data=JSON.parse_string(FileAccess.get_file_as_string(source));check(int(data.version)==18 and data.reception_format==Reception.FORMAT,"new native format explicitly versioned")
	var victim=fresh();victim.coins=777;var raw=data.duplicate(true);raw.erase("reception")
	var corrupt="user://reception-missing.json";var file=FileAccess.open(corrupt,FileAccess.WRITE);file.store_string(JSON.stringify(raw));file.close()
	var hash=FileAccess.get_sha256(corrupt)
	check(not victim.load_reception(corrupt) and victim.coins==777 and FileAccess.get_sha256(corrupt)==hash,"missing required v18 ledger rejects atomically without rewrite")
	print("RESTAURANT_RECEPTION_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"roundtrips":saves}))
	quit(0 if failures.is_empty() else 1)

func fresh():
	var m=Model.new();assert(m.enable_reception_review(),m.last_error);return m
