extends SceneTree
const M=preload("res://scripts/cafe_model.gd")
const P=preload("res://scripts/cafe_parking.gd")
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
func owned():
	var m=M.new();m.parking_owned=true;m.parking_paid_cost=P.PRICE;return m
func valid(m)->Dictionary:
	return P.validate(C.new().encode(P.snapshot(m)),m.customers,m.outside_queue,m._next_customer_id,m.operating_open)
func step(m,seconds:float):
	for i in range(ceili(seconds/.1)):P.advance(m,.1)
func _initialize():
	for count in range(1,5):
		var m=owned();check(P.reserve(m,count),"reserve bounded party "+str(count))
		var original=m.parking_visits[0].members.duplicate(true)
		check(valid(m).ok,"arrival validates")
		step(m,45)
		var car=m.parking_visits[0]
		check(car.phase=="parked" and car.members.all(func(a):return a.phase in ["dining","queued"]),"every original member disembarks/admitted or waits")
		check(valid(m).ok,"full restaurant membership validates: "+str(valid(m)))
		check(m.customers.size()+m.outside_queue.size()==count,"no duplicated or dropped guests")
		# Let the last member return first, then stagger the others.
		var last=car.members[-1]
		for visitor in m.outside_queue.duplicate():
			if visitor.id==last.id:m.outside_queue.erase(visitor)
		m.customers=m.customers.filter(func(g):return g.id!=last.id)
		check(P.start_return(m,last.id,P.HANDOFF),"return same last member")
		step(m,15)
		check(car.members[-1].phase=="boarded","last member boards their original car")
		if count>1:check(car.phase=="parked","departure waits for remaining original diners")
		var path="user://party-partly-returned-%s.json"%count
		check(m.save(path),"partly returned save: "+m.last_error)
		var restored=M.new();check(restored.load_save(path),"partly returned restore: "+restored.last_error)
		if restored.parking_visits.is_empty():continue
		check(same(restored.parking_visits,m.parking_visits),"exact car/member/appearance/motion continuity")
		for member in restored.parking_visits[0].members:
			var old=original.filter(func(a):return a.id==member.id)[0]
			check(member.car_id==old.car_id and member.appearance_sequence==old.appearance_sequence and member.species_index==old.species_index and member.appearance_recipe==old.appearance_recipe,"per-member original appearance conserved")
		for member in restored.parking_visits[0].members:
			if member.phase=="boarded":continue
			restored.customers=restored.customers.filter(func(g):return g.id!=member.id)
			restored.outside_queue=restored.outside_queue.filter(func(g):return g.id!=member.id)
			P.start_return(restored,member.id,P.HANDOFF);step(restored,15)
		check(restored.parking_visits[0].phase=="car_departing","only complete original party departs")
		check(valid(restored).ok,"departure validates")
		step(restored,45);check(restored.parking_visits.is_empty(),"car and membership retired together")
	var m=owned();check(not P.reserve(m,0-1) and not P.reserve(m,5),"invalid party counts atomic")
	P.reserve(m,4);step(m,35);m.set_operating_open(false);step(m,45)
	check(m.customers.is_empty() and m.outside_queue.is_empty(),"interrupted approach creates no orphan diner/queue")
	var legacy_model=owned();P.reserve(legacy_model,1)
	var old_car=legacy_model.parking_visits[0]
	old_car.car_route=P._legacy_car_route(0)
	var v1=C.new().encode({"format":P.LEGACY_FORMAT,"owned":true,"paid_cost":P.PRICE,"visits":[P._legacy_member(old_car,old_car.members[0])]})
	var migrated=P.validate(v1,[],[],legacy_model._next_customer_id,true)
	check(migrated.ok and migrated.state.format==P.FORMAT and migrated.state.visits[0].members[0].id==old_car.id,"v1 original member identity migrates once without replacing people")
	old_car.car_route=P.car_route(0)
	var raw=C.new().encode(P.snapshot(legacy_model))
	for field in ["id","member_id","car_id","appearance_sequence","species_index","appearance_recipe","phase","slot"]:
		var bad=raw.duplicate(true);bad.visits[0].members[0][field]=null
		check(not P.validate(bad,[],[],legacy_model._next_customer_id,true).ok,"reject malformed member "+field)
	var duplicate=raw.duplicate(true);duplicate.visits[0].members.append(duplicate.visits[0].members[0].duplicate(true))
	check(not P.validate(duplicate,[],[],legacy_model._next_customer_id,true).ok,"reject duplicate original membership")
	print("PARKING_PARTIES_RESULT ",JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
