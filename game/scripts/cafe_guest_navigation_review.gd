extends RefCounted
## Transient guest routes. Historical/private readers never acquire this capability.
const Nav=preload("res://scripts/cafe_navigation_candidate.gd")

static func enable(owner)->bool:
	var m=owner.model;var args=OS.get_cmdline_user_args()
	if OS.has_feature("web") or not owner.fresh_start or not owner.save_writes_suppressed:return false
	for flag in ["--fresh-review","--navigation-candidate","--guest-navigation-candidate","--reception-candidate"]:
		if flag not in args:return false
	for flag in ["--navigation-persistence-candidate","--reception-persistence-candidate","--footprint-placement"]:
		if flag in args:return false
	var raw=OS.get_environment("LL_RECEPTION_REVIEW_ROOT").replace("\\","/")
	if not raw.is_absolute_path():return false
	var scope=m.ReceptionReview.canonical(raw);var data=m.ReceptionReview.canonical(OS.get_user_data_dir())
	if not m.ReceptionReview.inside(data,scope) or not m.ReceptionReview.link_free(scope) or not m.ReceptionReview.link_free(data):return false
	for profile in m.SaveContract.PROFILES:
		for component in (scope+"/"+data).split("/"):
			if component.to_lower()==str(profile.app).to_lower():return false
	if not m._reception_fresh_eligible or m._next_customer_id!=1 or not m.customers.is_empty() or not m.outside_queue.is_empty() or not m.service_snapshot.is_empty() or m.served!=0 or m.total_earned!=0:return false
	# New transient capability; never widens private18's independent gate.
	m.reception_review_enabled=true;m.guest_navigation_enabled=true
	m.last_error="";m._guest_navigation_cache.clear()
	return true

static func snapshot(m,layout:Array=[])->Dictionary:
	var signature=m.navigation_signature()
	# Payroll/service notifications increment the general revision too. The
	# remaining signature owns geometry, so those clocks must not rebuild it.
	signature=signature.slice(1)
	if not layout.is_empty():return Nav.from_model(m,0,layout)
	if m._guest_navigation_cache.get("signature",[])!=signature:
		m._guest_navigation_cache={"signature":signature.duplicate(),"snapshot":Nav.from_model(m,0),"contacts":{}}
	return m._guest_navigation_cache.snapshot

static func path(m,start:Vector2i,goal:Vector2i,blocked:Dictionary={},layout:Array=[])->Array[Vector2i]:
	var facts=snapshot(m,layout)
	if not blocked.is_empty():
		facts=facts.duplicate(true)
		for at in blocked:facts.solids[at]=true
	var result=Nav.plan(facts,start,goal)
	var route:Array[Vector2i]=[]
	if result.status=="found":route.assign(result.route)
	return route

static func _contact_snapshot(m,chair_ids:Array)->Dictionary:
	var facts=snapshot(m)
	var key=str(chair_ids)
	if m._guest_navigation_cache.contacts.has(key):return m._guest_navigation_cache.contacts[key]
	var layout=m.items.filter(func(item):return int(item.id) not in chair_ids or str(item.kind)!="chair")
	facts=Nav.from_model(m,0,layout)
	if m._guest_navigation_cache.contacts.size()>=8:m._guest_navigation_cache.contacts.clear()
	m._guest_navigation_cache.contacts[key]=facts
	return facts

static func leg_clear(m,position:Vector2,target:Vector2,origin_chair:int=-1,target_chair:int=-1)->bool:
	if not position.is_finite() or not target.is_finite():return false
	if position.distance_to(target)<.000001:return true
	var direction=target-position
	var facts=snapshot(m)
	if absf(direction.x)>.00001 and absf(direction.y)>.00001:
		# Every diagonal is a suffix of one center-to-center unit leg; fractional
		# positions cannot authorize a long diagonal or an endpoint exception.
		var end=Vector2i(target.floor())
		if target.distance_to(Nav.center(end))>.000001:return false
		var start=end-Vector2i(1 if direction.x>0 else -1,1 if direction.y>0 else -1)
		if Geometry2D.get_closest_point_to_segment(position,Nav.center(start),target).distance_to(position)>.00001:return false
		return Nav.can_step(facts,start,end) and Nav.sweep_clear(facts,position,target)
	if m.Reception._public(m,position) or m.Reception._public(m,target):
		# Public corridor, exact entry crossing and street travel stay cardinal.
		return not m.segment_blocked(position,target)
	var contacts=[]
	for id in [origin_chair,target_chair]:
		var chair=m.get_item(id)
		if chair.is_empty() or str(chair.kind)!="chair":continue
		var cell=Vector2i(int(chair.x),int(chair.z))
		var body_contact=Rect2(Vector2(cell),Vector2.ONE).grow(Nav.CLEARANCE).has_point(position)
		if body_contact or cell==Vector2i(target.floor()):contacts.append(id)
	if not contacts.is_empty():facts=_contact_snapshot(m,contacts)
	return Nav.sweep_clear(facts,position,target) and not m.segment_blocked(position,target)

static func speed_scale(m,actor:Dictionary)->float:
	# Positive bounded slowdown, never a hard passage lock. Seat/work contact
	# retains its existing timing and route authority.
	var position=Vector2(actor.x,actor.z)
	var route:Array=actor.get("route",[])
	if not route.is_empty() and position.distance_to(route[-1])<=1.0:return 1.0
	for other in m.customers+m.reception_visits+m.departing_bodies:
		if is_same(other,actor) or str(other.phase) in ["dirty","cleaning"]:continue
		if position.distance_to(Vector2(other.x,other.z))<.6:return .85
	for staff_position in m.guest_obstacle_positions:
		if staff_position is Vector2 and position.distance_to(staff_position)<.6:return .85
	return 1.0

static func repair(m,actor:Dictionary)->bool:
	var route:Array=actor.get("route",[]);var index=int(actor.get("route_index",0))
	if index>=route.size():return true
	var position=Vector2(actor.x,actor.z);var at=Vector2i(position.floor())
	var chair=int(actor.get("chair_id",-1))
	var origin_chair=int(actor.get("previous_chair_id",chair))
	if origin_chair<0:origin_chair=chair
	var target=route[-1]
	if str(actor.phase)=="checkout_walk":
		var claimed=actor.get("checkout_cell",Vector2i(-100,-100))
		if m.Checkout.claimed_cells(m,int(actor.id)).has(claimed):return false
		target=Nav.center(claimed)
	elif chair>=0 and str(actor.phase) not in ["leaving","dirty","cleaning"]:
		var inventory=m.TableOccupancy.inspect(m)
		if not str(inventory.error).is_empty() or int(inventory.chairs.get(chair,-1))!=int(actor.id):return false
		var item=m.get_item(chair)
		if item.is_empty():return false
		target=Nav.center(Vector2i(int(item.x),int(item.z)))
	# The current safe leg may finish. Never round/snap a body off a segment.
	if position.distance_to(Nav.center(at))>.00001:return leg_clear(m,position,route[index],origin_chair,chair)
	var previous=position;var valid=route[-1].distance_to(target)<.000001
	for i in range(index,route.size()):
		if not leg_clear(m,previous,route[i],origin_chair,chair):valid=false;break
		previous=route[i]
	if valid:return true
	if route[-1].distance_to(target)>.000001:
		# Rebind moved furniture to its same immutable owner, without touching
		# phase/job/payment clocks. Never retain the old physical-cell claim.
		var replacement:Array[Vector2]=[];var distance=INF
		var goals=m.chair_egress_cells(chair,int(actor.get("table_id",-1))) if chair>=0 and str(actor.phase)!="checkout_walk" else [Vector2i(target.floor())]
		for goal in goals:
			var cells=path(m,at,goal,m.Checkout.claimed_cells(m,int(actor.id)))
			if cells.is_empty():continue
			var points:Array[Vector2]=[]
			for cell in cells:
				if Nav.center(cell)!=position:points.append(Nav.center(cell))
			if chair>=0 and str(actor.phase)!="checkout_walk":points.append(target)
			var length=m._route_length(position,points)
			if length<distance:replacement=points;distance=length
		if replacement.is_empty():return false
		actor.route=replacement;actor.route_index=0
		if actor.has("route_origin"):actor.route_origin=position
		if actor.has("goal"):actor.goal=target
		actor.waiting=false;return true
	var facts=snapshot(m);var goal_index=-1
	for i in range(route.size()-1,index-1,-1):
		var cell=Vector2i(route[i].floor())
		if route[i].distance_to(Nav.center(cell))<.000001 and Nav.open_cell(facts,cell):goal_index=i;break
	if goal_index<0:return false
	var replacement=path(m,at,Vector2i(route[goal_index].floor()))
	if replacement.is_empty():return false
	var points:Array[Vector2]=[]
	for cell in replacement:
		if Nav.center(cell)!=position:points.append(Nav.center(cell))
	points.append_array(route.slice(goal_index+1))
	previous=position
	for next in points:
		if not leg_clear(m,previous,next,origin_chair,chair):return false
		previous=next
	actor.route=points;actor.route_index=0
	if actor.has("route_origin"):actor.route_origin=position
	if actor.has("goal"):actor.goal=target
	actor.waiting=false
	return true

static func advance_mobility(m,guest:Dictionary,delta:float):
	var mobility:Dictionary=guest.mobility
	var proxy=guest.duplicate(true)
	proxy.phase="arriving" if str(mobility.kind)=="to_assigned_seat" else "checkout_walk"
	proxy.route=mobility.route;proxy.route_index=int(mobility.route_index)
	if not repair(m,proxy):guest.waiting=true;return
	if not is_same(mobility.route,proxy.route):mobility.origin=Vector2(guest.x,guest.z)
	mobility.route=proxy.route;mobility.route_index=proxy.route_index
	var at=Vector2(guest.x,guest.z);var budget=maxf(0.0,delta)*m.WALK_SPEED*speed_scale(m,guest)
	while budget>.000001 and int(mobility.route_index)<mobility.route.size():
		var target:Vector2=mobility.route[int(mobility.route_index)]
		if not leg_clear(m,at,target,-1,int(guest.chair_id) if str(mobility.kind)=="to_assigned_seat" else -1):guest.waiting=true;break
		var distance=at.distance_to(target);var step=minf(distance,budget)
		if distance>.000001:guest.heading=(target-at)/distance
		at=at.move_toward(target,step);budget-=step
		if step+.000001>=distance:at=target;mobility.route_index+=1
	guest.x=at.x;guest.z=at.y
	if int(mobility.route_index)>=mobility.route.size():
		guest.seated=str(mobility.kind)=="to_assigned_seat";guest.mobility={};guest.waiting=guest.phase=="checkout_wait"
		m._mobility_validated.erase(int(guest.id))
