extends RefCounted
## Transient stage-2 candidate. No save format, task allocation or runtime switch.
## Production callers keep their existing cardinal planners until codec agreement.
const DIRECTIONS = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP,
	Vector2i(1,1), Vector2i(-1,1), Vector2i(-1,-1), Vector2i(1,-1)]
const MAX_CELLS = 4096
const MAX_ROUTE = 512
const CLEARANCE = .23

static func edge_key(a:Vector2i,b:Vector2i)->String:
	if a.x>b.x or (a.x==b.x and a.y>b.y):
		var swap=a;a=b;b=swap
	return "%d,%d:%d,%d"%[a.x,a.y,b.x,b.y]

static func center(cell:Vector2i)->Vector2:
	return Vector2(cell)+Vector2(.5,.5)

static func open_cell(snapshot:Dictionary,cell:Vector2i)->bool:
	return snapshot.cells.has(cell) and not bool(snapshot.solids.get(cell,false))

static func crosses(rect:Rect2,a:Vector2,b:Vector2)->bool:
	# Inclusive slab sweep. Touching clearance is blocked, including parallel legs.
	var delta=b-a;var low=0.0;var high=1.0
	for axis in 2:
		if absf(delta[axis])<.000001:
			if a[axis]<rect.position[axis] or a[axis]>rect.end[axis]:return false
		else:
			var t0=(rect.position[axis]-a[axis])/delta[axis]
			var t1=(rect.end[axis]-a[axis])/delta[axis]
			low=maxf(low,minf(t0,t1));high=minf(high,maxf(t0,t1))
			if low>high:return false
	return high>=0.0 and low<=1.0

static func sweep_clear(snapshot:Dictionary,a:Vector2,b:Vector2)->bool:
	if not a.is_finite() or not b.is_finite():return false
	for rect in snapshot.barriers:
		if crosses(rect,a,b):return false
	return true

static func cardinal_step(snapshot:Dictionary,a:Vector2i,b:Vector2i)->bool:
	return absi(a.x-b.x)+absi(a.y-b.y)==1 and open_cell(snapshot,a) and open_cell(snapshot,b) and not snapshot.edges.has(edge_key(a,b)) and sweep_clear(snapshot,center(a),center(b))

static func can_step(snapshot:Dictionary,a:Vector2i,b:Vector2i)->bool:
	var d=b-a
	if absi(d.x)+absi(d.y)==1:return cardinal_step(snapshot,a,b)
	if absi(d.x)!=1 or absi(d.y)!=1:return false
	var x=a+Vector2i(d.x,0);var z=a+Vector2i(0,d.y)
	return cardinal_step(snapshot,a,x) and cardinal_step(snapshot,a,z) and cardinal_step(snapshot,x,b) and cardinal_step(snapshot,z,b) and sweep_clear(snapshot,center(a),center(b))

static func heuristic(a:Vector2i,b:Vector2i)->int:
	var dx=absi(a.x-b.x);var dz=absi(a.y-b.y)
	return 14*mini(dx,dz)+10*absi(dx-dz)

static func _before(a:Dictionary,b:Dictionary)->bool:
	if a.f!=b.f:return a.f<b.f
	if a.h!=b.h:return a.h<b.h
	if a.cell.x!=b.cell.x:return a.cell.x<b.cell.x
	return a.cell.y<b.cell.y

static func _push(heap:Array,entry:Dictionary):
	heap.append(entry);var at=heap.size()-1
	while at>0:
		var parent=(at-1)>>1
		if not _before(heap[at],heap[parent]):break
		var swap=heap[at];heap[at]=heap[parent];heap[parent]=swap;at=parent

static func _pop(heap:Array)->Dictionary:
	var result:Dictionary=heap[0];var tail=heap.pop_back()
	if heap.is_empty():return result
	heap[0]=tail;var at=0
	while at*2+1<heap.size():
		var child=at*2+1
		if child+1<heap.size() and _before(heap[child+1],heap[child]):child+=1
		if not _before(heap[child],heap[at]):break
		var swap=heap[at];heap[at]=heap[child];heap[child]=swap;at=child
	return result

static func _result(status:String,snapshot:Dictionary,expanded:int=0)->Dictionary:
	return {"status":status,"route":[],"cost":0,"length":0.0,"revision":snapshot.get("revision",[]).duplicate(true),"expanded":expanded}

static func plan(snapshot:Dictionary,start:Vector2i,goal:Vector2i,budget:int=MAX_CELLS)->Dictionary:
	if snapshot.cells.size()>MAX_CELLS:return _result("invalid_snapshot",snapshot)
	if not open_cell(snapshot,start):return _result("invalid_origin",snapshot)
	if not open_cell(snapshot,goal):return _result("invalid_goal",snapshot)
	var g={start:0};var previous={};var heap=[];var expanded=0
	var h=heuristic(start,goal)
	_push(heap,{"cell":start,"g":0,"h":h,"f":h})
	while not heap.is_empty():
		var entry=_pop(heap);var at:Vector2i=entry.cell
		if int(entry.g)!=int(g[at]):continue # Duplicate queue entries are stale.
		if expanded>=maxi(0,budget):return _result("pending",snapshot,expanded)
		expanded+=1
		if at==goal:
			var route:Array[Vector2i]=[at];var seen={at:true}
			while at!=start:
				if not previous.has(at) or route.size()>=MAX_ROUTE:return _result("route_limit",snapshot,expanded)
				at=previous[at]
				if seen.has(at):return _result("invalid_predecessor",snapshot,expanded)
				seen[at]=true;route.append(at)
			route.reverse()
			var result=_result("found",snapshot,expanded);result.route=route;result.cost=int(entry.g)
			for i in range(1,route.size()):result.length+=center(route[i-1]).distance_to(center(route[i]))
			return result
		for direction in DIRECTIONS:
			var next:Vector2i=at+direction
			if not can_step(snapshot,at,next):continue
			var cost=int(entry.g)+(14 if direction.x!=0 and direction.y!=0 else 10)
			if g.has(next) and cost>=int(g[next]):continue
			g[next]=cost;previous[next]=at;h=heuristic(next,goal)
			_push(heap,{"cell":next,"g":cost,"h":h,"f":cost+h})
	return _result("no_path",snapshot,expanded)

static func from_model(model,min_x:int=0,layout=null)->Dictionary:
	# Freeze facts, never retain model/item references or actor/claim occupancy.
	model.navigation_cells() # Also invalidates wall caches after direct fixture edits.
	var furniture:Array=model.items if layout==null else layout
	var cells={};var solids={};var edges={};var barriers=[]
	for z in range(model.MAX_DEPTH):
		for x in range(min_x,model.MAX_WIDTH):
			var cell=Vector2i(x,z)
			if model.is_floor_owned(cell):cells[cell]=true
	for item in furniture:
		if str(item.kind)=="rug":continue
		var at=Vector2i(int(item.x),int(item.z));solids[at]=true
		barriers.append(Rect2(Vector2(at),Vector2.ONE).grow(CLEARANCE))
	for cell in cells:
		for direction in [Vector2i.RIGHT,Vector2i.DOWN]:
			var next:Vector2i=cell+direction
			if cells.has(next) and model.edge_blocked(cell,next):edges[edge_key(cell,next)]=true
	# Reviewed segmented models own active host projection; old PR125 models
	# retain their whole-shell API. Neither path mutates model/save geometry.
	var hosts=model.collision_wall_hosts() if model.has_method("collision_wall_hosts") else model.OpeningGeometry.hosts(model.built_walls,model.shell_products)
	for host in hosts:
		for segment in model.OpeningGeometry.solid_segments(host,model.built_walls,model.wall_attachments):
			barriers.append(model.OpeningGeometry.segment_rect(segment).grow(CLEARANCE))
	var signature:Array=model.navigation_signature().duplicate(true)
	signature.append(hash(furniture));signature.append(min_x)
	return {"cells":cells,"solids":solids,"edges":edges,"barriers":barriers,"revision":signature}

static func role_plan(model,role:String,start:Vector2i,goal:Vector2i,budget:int=MAX_CELLS)->Dictionary:
	# Staff/cashier retain the existing x>=1 movement domain. Endpoint selection
	# and exclusive claims stay with each existing state machine.
	if role not in ["guest","staff","cashier"]:return {"status":"invalid_role"}
	return plan(from_model(model,0 if role=="guest" else 1),start,goal,budget)

static func follower(plan_result:Dictionary,task_token:int,owns_endpoint:Callable)->Dictionary:
	# The callback belongs to the existing claim authority, not a second ledger.
	return {"plan":plan_result.duplicate(true),"index":1,"token":task_token,"owns":owns_endpoint}

static func _remaining_valid(snapshot:Dictionary,state:Dictionary,position:Vector2)->bool:
	var route:Array=state.plan.route;var index=int(state.index)
	if route.is_empty() or index<1 or index>route.size() or not position.is_finite():return false
	if index==route.size():return position.distance_to(center(route[-1]))<.000001 and open_cell(snapshot,route[-1])
	var a=center(route[index-1]);var b=center(route[index])
	if Geometry2D.get_closest_point_to_segment(position,a,b).distance_to(position)>.000001:return false
	for i in range(index,route.size()):
		if not can_step(snapshot,route[i-1],route[i]):return false
	return sweep_clear(snapshot,position,b)

static func cancel_replan(state:Dictionary,scheduler):
	# Call on task abandonment too: retained requests must be consumed once.
	var id=int(state.get("request",0))
	if id!=0:
		scheduler.cancel(id);scheduler.take_result(id,int(state.request_epoch))
	state.request=0

static func advance(snapshot:Dictionary,state:Dictionary,position:Vector2,delta:float,speed:float,people:Array=[],scheduler=null,epoch:int=0)->Dictionary:
	var result={"status":"walking","position":position,"distance":0.0,"replanned":false}
	if not position.is_finite() or not is_finite(delta) or delta<0.0 or not is_finite(speed) or speed<=0.0:result.status="invalid_input";return result
	if state.plan.status!="found":
		if scheduler!=null:cancel_replan(state,scheduler)
		result.status=state.plan.status;return result
	if not state.owns.is_valid() or not state.owns.call(state.token):
		if scheduler!=null:cancel_replan(state,scheduler)
		result.status="stale_claim";return result
	if scheduler!=null and int(state.get("request",0))!=0:
		# Never deliver a route for a changed task, layout, endpoint or anchor.
		if state.request_epoch!=epoch or state.request_revision!=snapshot.revision or state.request_token!=state.token or state.request_goal!=state.plan.route[-1] or position.distance_to(center(state.request_origin))>.000001:
			cancel_replan(state,scheduler)
		else:
			var ready:Dictionary=scheduler.take_result(int(state.request),epoch)
			if ready.status=="pending":result.status="pending";return result
			state.request=0
			if ready.status!="found":result.status=ready.status;return result
			state.plan=ready;state.index=1;result.replanned=true
	if not _remaining_valid(snapshot,state,position):
		# Only an actual safe node is an anchor. Never round/snap mid-segment.
		var cell=Vector2i(floori(position.x),floori(position.y))
		if position.distance_to(center(cell))>.000001 or not open_cell(snapshot,cell):result.status="blocked_mid_segment";return result
		if scheduler!=null:
			var id:int=scheduler.submit(snapshot,cell,state.plan.route[-1],epoch)
			if id==0:result.status="backpressure";return result
			state.request=id;state.request_epoch=epoch;state.request_revision=snapshot.revision.duplicate()
			state.request_token=state.token;state.request_origin=cell;state.request_goal=state.plan.route[-1]
			result.status="pending";return result
		var replacement=plan(snapshot,cell,state.plan.route[-1])
		if replacement.status!="found":result.status=replacement.status;return result
		state.plan=replacement;state.index=1;result.replanned=true
	else:state.plan.revision=snapshot.revision.duplicate(true)
	# Safe speed-only avoidance: always positive, no displacement through solids,
	# no wait locks, no route churn. Docking/contact adapters must disable it.
	var scale=1.0
	for person in people:
		if person is Vector2 and person.is_finite() and person.distance_to(position)<.6:scale=.85;break
	var budget=delta*speed*scale;var route:Array=state.plan.route
	while budget>.0000001 and int(state.index)<route.size():
		var target=center(route[int(state.index)]);var distance=position.distance_to(target)
		var step=minf(distance,budget)
		if distance>.0000001:position=position.move_toward(target,step)
		budget-=step;result.distance+=step
		if distance<=step+.0000001:position=target;state.index+=1
	result.position=position
	if int(state.index)>=route.size():result.status="arrived"
	return result
