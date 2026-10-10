extends SceneTree
const Nav=preload("res://scripts/cafe_navigation_candidate.gd")
const Model=preload("res://scripts/cafe_model.gd")
var checks=0
var failures=[]
var owner_token=17

func check(ok:bool,label:String):
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)

func grid(width:int=8,height:int=8)->Dictionary:
	var cells={}
	for z in height:
		for x in width:cells[Vector2i(x,z)]=true
	return {"cells":cells,"solids":{},"edges":{},"barriers":[],"revision":[1]}

func owns(token:int)->bool:return token==owner_token

func oracle(s:Dictionary,start:Vector2i,goal:Vector2i)->int:
	# Independent Dijkstra frontier: no heuristic, heap or predecessor code.
	if not Nav.open_cell(s,start) or not Nav.open_cell(s,goal):return -1
	var distances={start:0};var visited={}
	while true:
		var best=1000000;var found=false;var at=Vector2i.ZERO
		for cell in distances:
			if not visited.has(cell) and int(distances[cell])<best:best=distances[cell];at=cell;found=true
		if not found:return -1
		if at==goal:return best
		visited[at]=true
		for d in Nav.DIRECTIONS:
			var next:Vector2i=at+d
			if visited.has(next) or not Nav.can_step(s,at,next):continue
			var cost=best+(14 if d.x!=0 and d.y!=0 else 10)
			if not distances.has(next) or cost<int(distances[next]):distances[next]=cost
	return -1

func _initialize():run.call_deferred()
func run():
	var s=grid();var a=Vector2i(0,0);var d=Vector2i(1,1)
	var p=Nav.plan(s,a,Vector2i(3,2))
	check(p.status=="found" and p.cost==38,"N01 mixed route octile cost 38")
	check(absf(p.length-(2*sqrt(2)+1))<.000001,"metric length distinct from 10/14 cost")
	check(Nav.plan(s,a,a).status=="found" and Nav.plan(s,a,a).cost==0,"same cell explicitly found")
	check(Nav.plan(s,a,Vector2i(3,3),0).status=="pending","N13 budget is pending")
	check(Nav.plan(s,Vector2i(-1,0),d).status=="invalid_origin","N03 unowned origin")
	s.solids[d]=true
	check(Nav.plan(s,a,d).status=="invalid_goal","N03 solid endpoint rejected without exception")
	s.solids.clear()
	for side in [Vector2i(1,0),Vector2i(0,1)]:
		s.solids[side]=true;check(not Nav.can_step(s,a,d),"N04 blocked side "+str(side));s.solids.clear()
	s.cells.erase(Vector2i(1,0));check(not Nav.can_step(s,a,d),"N09 unowned diagonal side");s=grid()
	for edge in [[a,Vector2i(1,0)],[a,Vector2i(0,1)],[Vector2i(1,0),d],[Vector2i(0,1),d]]:
		s.edges[Nav.edge_key(edge[0],edge[1])]=true
		check(not Nav.can_step(s,a,d),"N05 each of four cardinal wall edges "+str(edge));s.edges.clear()
	check(Nav.can_step(s,a,d),"N04 clear four edges permits diagonal")
	check(not Nav.can_step(s,a,Vector2i(2,2)),"no multigrid shortcut")
	s.barriers=[Rect2(.95,.95,.1,.1)]
	check(not Nav.can_step(s,a,d),"N06 center sweep blocks corner thickness even if edge flags clear")
	check(Nav.crosses(Rect2(1.0,.95,.1,.2),Vector2(.5,.5),Vector2(1.5,1.5)),"N08 door jamb diagonal sweep")
	check(Nav.crosses(Rect2(0,0,1,1),Vector2(-1,.5),Vector2(2,.5)),"parallel slab sweep")
	check(not Nav.crosses(Rect2(0,0,1,1),Vector2(-1,2),Vector2(2,2)),"parallel slab separation")
	s=grid(2,2);s.solids[Vector2i(1,0)]=true;s.solids[Vector2i(0,1)]=true
	check(Nav.plan(s,a,d).status=="no_path","N03 unreachable distinct from invalid/pending")
	# Deterministic seeded maps, all pairs per map. Verify returned legs separately.
	var rng=RandomNumberGenerator.new();rng.seed=11011
	for trial in 12:
		s=grid(5,5)
		for cell in s.cells:
			if rng.randf()<.18:s.solids[cell]=true
			for direction in [Vector2i.RIGHT,Vector2i.DOWN]:
				if rng.randf()<.08:s.edges[Nav.edge_key(cell,cell+direction)]=true
		for sample in 20:
			var start=Vector2i(rng.randi_range(0,4),rng.randi_range(0,4))
			var goal=Vector2i(rng.randi_range(0,4),rng.randi_range(0,4))
			p=Nav.plan(s,start,goal);var expected=oracle(s,start,goal)
			check((p.status=="found" and p.cost==expected) or (p.status!="found" and expected==-1),"N02 Dijkstra cost seed11011 trial%d pair%d"%[trial,sample])
			check(p==Nav.plan(s,start,goal),"N02 deterministic replay")
			for i in range(1,p.route.size()):check(Nav.can_step(s,p.route[i-1],p.route[i]),"N02 every route leg legal")
	# One follower is used for all roles. No economy/service/claim writes.
	s=grid();p=Nav.plan(s,a,Vector2i(3,2))
	for hz in [30,60,120]:
		var f=Nav.follower(p,17,owns);var position=Nav.center(a);var elapsed=0.0;var outcome={}
		while elapsed<10.0:
			outcome=Nav.advance(s,f,position,1.0/hz,1.8);position=outcome.position;elapsed+=1.0/hz
			if outcome.status=="arrived":break
		check(outcome.status=="arrived" and absf(elapsed-p.length/1.8)<=1.0/hz+.000001,"M01 M02 speed and frame budget "+str(hz))
	var f=Nav.follower(p,17,owns)
	check(Nav.advance(s,f,Nav.center(a),0,1.8).position==Nav.center(a),"M03 pause consumes no distance")
	check(Nav.advance(s,f,Nav.center(a),100,1.8).status=="arrived","M02 large delta consumes all legs once")
	f=Nav.follower(p,17,owns);owner_token=18
	check(Nav.advance(s,f,Nav.center(a),1,1.8).status=="stale_claim" and f.index==1,"T11 old token cannot move after generation replacement")
	owner_token=17
	# Soft avoidance remains positive under permanent congestion, with no side drift.
	for role in ["guest","staff","cashier"]:
		f=Nav.follower(p,17,owns);var position=Nav.center(a);var arrived=false
		for tick in 100:
			var moved=Nav.advance(s,f,position,.1,1.8,[position]);position=moved.position
			if moved.status=="arrived":arrived=true;break
		check(arrived,"M04 M10 persistent people cannot deadlock "+role)
	# Replan at a safe center; unrelated edits retain the current plan.
	f=Nav.follower(p,17,owns);var old_route=f.plan.route.duplicate();s.revision=[2];s.solids[Vector2i(7,7)]=true
	var moved=Nav.advance(s,f,Nav.center(a),0,1.8)
	check(not moved.replanned and f.plan.route==old_route and f.plan.revision==[2],"M08 unrelated geometry only revalidates")
	s.solids[Vector2i(1,1)]=true;s.revision=[3];moved=Nav.advance(s,f,Nav.center(a),0,1.8)
	check(moved.replanned and f.plan.route!=old_route,"M08 future obstacle replans at safe node")
	s=grid();f=Nav.follower(p,17,owns);moved=Nav.advance(s,f,Nav.center(a),.1,1.8)
	var exact=moved.position;s.solids[Vector2i(1,1)]=true;s.revision=[2]
	moved=Nav.advance(s,f,exact,1,1.8)
	check(moved.status=="blocked_mid_segment" and moved.position==exact,"M07 invalid partial segment stops without snapping")
	check(Nav.advance(s,f,Vector2(NAN,0),.1,1.8).status=="invalid_input","nonfinite position refused")
	# Real public model adapter: all role planners share a frozen geometry authority.
	var model=Model.new();model.reset_new();model.items.clear()
	var before=[model.coins,model.served,model.total_earned,model.customers.duplicate(true),model.service_snapshot.duplicate(true)]
	var start=Vector2i(2,2);var goal=Vector2i(7,6)
	var guest=Nav.role_plan(model,"guest",start,goal)
	check(guest.status=="found" and guest.cost==66,"actual owned-floor guest adapter")
	for role in ["staff","cashier"]:
		check(Nav.role_plan(model,role,start,goal).route==guest.route,"same planner route for "+role)
	check(before==[model.coins,model.served,model.total_earned,model.customers,model.service_snapshot],"S01 economy service actors remain unchanged")
	var frozen=Nav.from_model(model)
	model.items.append({"id":100,"kind":"plant","x":3,"z":3,"rot":0})
	var changed=Nav.from_model(model)
	check(frozen.solids.is_empty() and changed.solids.has(Vector2i(3,3)),"N11 immutable snapshot versus direct geometry mutation")
	check(not Nav.can_step(changed,Vector2i(2,2),Vector2i(3,3)),"actual furniture blocks diagonal")
	model.items.append({"id":101,"kind":"rug","x":4,"z":4,"rot":0})
	check(not Nav.from_model(model).solids.has(Vector2i(4,4)),"N10 rug remains traversable")
	check(Nav.role_plan(model,"cashier",Vector2i(0,2),goal).status=="invalid_origin","cashier keeps restricted staff domain")
	var empty_layout=Nav.from_model(model,0,[])
	check(empty_layout.solids.is_empty() and empty_layout.revision!=changed.revision,"proposed empty layout is explicit and has distinct revision")
	model.items.clear()
	model.built_walls.append({"id":1,"axis":"x","x":3,"z":3,"height":"full","material":"original"})
	var wall_snapshot=Nav.from_model(model)
	check(not Nav.can_step(wall_snapshot,Vector2i(3,2),Vector2i(3,3)),"actual wall blocks cardinal edge")
	check(not Nav.can_step(wall_snapshot,Vector2i(2,2),Vector2i(3,3)),"actual wall forbids diagonal with only one blocked edge")
	model.built_walls.clear()
	check(Nav.can_step(Nav.from_model(model),Vector2i(2,2),Vector2i(3,3)),"direct wall removal invalidates cached geometry")
	# Two opposing followers on a one-cell corridor always pass through safely.
	s=grid(1,6);var left=Nav.follower(Nav.plan(s,Vector2i(0,0),Vector2i(0,5)),17,owns)
	var right=Nav.follower(Nav.plan(s,Vector2i(0,5),Vector2i(0,0)),17,owns)
	var lp=Nav.center(Vector2i(0,0));var rp=Nav.center(Vector2i(0,5))
	var ls="walking";var rs="walking"
	for tick in 100:
		var prior_lp=lp;var prior_rp=rp
		var l=Nav.advance(s,left,prior_lp,.1,1.8,[prior_rp]);var r=Nav.advance(s,right,prior_rp,.1,1.8,[prior_lp])
		lp=l.position;rp=r.position;ls=l.status;rs=r.status
		if ls=="arrived" and rs=="arrived":break
	check(ls=="arrived" and rs=="arrived" and lp.x==.5 and rp.x==.5,"M04 opposing narrow-corridor actors pass without mutual lock or side drift")
	print("NAVIGATION_CANDIDATE_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"seed":11011,"production_enabled":false,"save_writes":0}))
	quit(0 if failures.is_empty() else 1)
