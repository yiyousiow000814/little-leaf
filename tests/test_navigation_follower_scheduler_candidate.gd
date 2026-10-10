extends SceneTree
const Nav = preload("res://scripts/cafe_navigation_candidate.gd")
const Scheduler = preload("res://scripts/cafe_navigation_scheduler_candidate.gd")
var checks = 0
var failures = []
var claim = true

func check(ok:bool,label:String):
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)

func owns(_token:int)->bool:return claim

func grid()->Dictionary:
	var cells={}
	for y in 4:
		for x in 4:cells[Vector2i(x,y)]=true
	return {"cells":cells,"solids":{},"edges":{},"barriers":[],"revision":[1]}

func blocked()->Dictionary:
	var snapshot=grid();snapshot.solids[Vector2i(1,1)]=true;snapshot.revision=[2]
	return snapshot

func actor()->Dictionary:return Nav.follower(Nav.plan(grid(),Vector2i.ZERO,Vector2i(3,3)),7,owns)

func step(snapshot:Dictionary,state:Dictionary,scheduler,epoch:int=2,position:Vector2=Vector2(.5,.5))->Dictionary:
	return Nav.advance(snapshot,state,position,.2,1.0,[],scheduler,epoch)

func finish(scheduler,id:int,epoch:int):
	var ticks=0
	while scheduler.inspect(id).status=="pending" and ticks<10000:
		scheduler.tick(epoch,7,0);ticks+=1
	check(ticks<10000,"search completes through cooperative ticks")

func drain(scheduler,epoch:int):
	for i in 10000:
		var progress=scheduler.tick(epoch,32,0)
		if progress.retained==0:return
	check(false,"consumer leaves no retained request")

func changed_tail_scenario():
	var scheduler=Scheduler.new();var state=actor()
	var initial=Nav.advance(grid(),state,Vector2(.5,.5),.4,1.0,[],scheduler,1)
	var position:Vector2=initial.position
	var changed=grid();changed.revision=[2];changed.solids[Vector2i(2,2)]=true
	var continuing=Nav.advance(changed,state,position,.3,1.0,[],scheduler,2)
	check(continuing.status=="walking" and is_equal_approx(continuing.distance,.3),"future obstruction permits budgeted legal current-leg movement")
	check(scheduler._jobs.is_empty(),"no search before actor reaches actual safe center")
	position=continuing.position
	var remaining=position.distance_to(Nav.center(Vector2i.ONE))
	var anchored=Nav.advance(changed,state,position,100.0,1.0,[],scheduler,2)
	check(anchored.status=="pending" and anchored.position==Nav.center(Vector2i.ONE) and is_equal_approx(anchored.distance,remaining),"large frame stops at next anchor without traversing invalid tail")
	check(state.request_origin==Vector2i.ONE,"replan starts at actual reached center")
	var old_id=int(state.request);finish(scheduler,old_id,2)
	var newest=changed.duplicate(true);newest.revision=[3];newest.solids[Vector2i(2,1)]=true
	var stale=Nav.advance(newest,state,anchored.position,.1,1.0,[],scheduler,3)
	check(stale.status=="pending" and stale.distance==0 and state.request!=old_id,"stale completed layout route cannot leave safe anchor")
	var next_id=int(state.request);finish(scheduler,next_id,3)
	var delivered=Nav.advance(newest,state,anchored.position,0.0,1.0,[],scheduler,3)
	check(delivered.replanned and state.plan.route[0]==Vector2i.ONE,"newest result delivered from safe anchor")
	for i in range(1,state.plan.route.size()):
		check(Nav.can_step(newest,state.plan.route[i-1],state.plan.route[i]),"replanned leg preserves edge/corner/segment legality")
	var arrived=Nav.advance(newest,state,anchored.position,100.0,1.0,[],scheduler,3)
	check(arrived.status=="arrived" and arrived.position==Nav.center(Vector2i(3,3)),"representative detour arrives at original caller endpoint")
	drain(scheduler,3)
	# Blocking any current diagonal corner/edge or sweep forbids even anchor travel.
	for obstacle in ["corner","edge","frame"]:
		state=actor();scheduler=Scheduler.new();var geometry=grid();geometry.revision=[2]
		if obstacle=="corner":geometry.solids[Vector2i(1,0)]=true
		elif obstacle=="edge":geometry.edges[Nav.edge_key(Vector2i(1,0),Vector2i.ONE)]=true
		else:geometry.barriers.append(Rect2(Vector2(.99,.99),Vector2(.02,.02)))
		var stopped=Nav.advance(geometry,state,initial.position,100.0,1.0,[],scheduler,2)
		check(stopped.status=="blocked_mid_segment" and stopped.position==initial.position and stopped.distance==0,"current diagonal "+obstacle+" obstruction stops without snap")
		check(scheduler._jobs.is_empty(),"no search from unsafe current "+obstacle)
	state=actor();var legacy=Nav.advance(changed,state,initial.position,100.0,1.0)
	check(legacy.status=="blocked_mid_segment" and legacy.distance==0,"legacy caller preserves old mid-segment behavior")

func scheduler_lifecycle():
	var snapshot=blocked();var original=Scheduler.new();var replacement=Scheduler.new();var state=actor()
	step(snapshot,state,original);var old_id=int(state.request);finish(original,old_id,2)
	var switched=step(snapshot,state,replacement)
	check(switched.status=="pending" and state.request_scheduler==replacement,"new scheduler owns replacement request even if numeric IDs match")
	check(original.take_result(old_id,2).status=="unknown","replacement consumes old scheduler result")
	Nav.cancel_replan(state)
	check(state.request==0 and not state.has("request_scheduler"),"abandonment uses recorded owner and releases its reference")
	drain(original,2);drain(replacement,2)
	original=Scheduler.new();state=actor();step(snapshot,state,original);old_id=int(state.request)
	var legacy=Nav.advance(snapshot,state,Vector2(.5,.5),.2,1.0)
	check(legacy.replanned and state.request==0 and original.take_result(old_id,2).status=="unknown","legacy fallback cancels outstanding scheduled request")
	drain(original,2)

func _initialize():run.call_deferred()
func run():
	var snapshot=blocked();var scheduler=Scheduler.new();var state=actor()
	var first=step(snapshot,state,scheduler);var id=int(state.request)
	check(first.status=="pending" and first.distance==0 and first.position==Vector2(.5,.5),"invalid route holds its exact safe anchor")
	check(scheduler.inspect(id).work==0,"advance submits without searching")
	for i in 3:
		var waiting=step(snapshot,state,scheduler)
		check(waiting.status=="pending" and state.request==id,"pending follower does not duplicate request")
	finish(scheduler,id,2)
	var resumed=step(snapshot,state,scheduler)
	check(resumed.status=="walking" and resumed.replanned and resumed.distance>0,"completed replan resumes follower")
	check(state.plan==Nav.plan(snapshot,Vector2i.ZERO,Vector2i(3,3)),"consumed route matches deterministic planner")
	check(scheduler.take_result(id,2).status=="unknown","follower consumes delivery exactly once")
	var position:Vector2=resumed.position
	for i in 60:
		var next=Nav.advance(snapshot,state,position,.2,1.0,[],scheduler,2);position=next.position
		if next.status=="arrived":break
	check(position==Nav.center(Vector2i(3,3)),"replanned follower reaches caller endpoint")
	drain(scheduler,2)
	# A completed old result cannot move a changed-layout follower.
	scheduler=Scheduler.new();state=actor();step(snapshot,state,scheduler);id=int(state.request);finish(scheduler,id,2)
	var changed=snapshot.duplicate(true);changed.revision=[3];changed.solids[Vector2i(1,0)]=true
	var replaced=step(changed,state,scheduler,3)
	check(replaced.status=="pending" and replaced.distance==0 and state.request!=id,"layout change discards completed delivery and resubmits")
	check(scheduler.take_result(id,3).status=="unknown","obsolete delivery consumed during cancellation")
	Nav.cancel_replan(state,scheduler);drain(scheduler,3)
	# Ownership loss cancels pending work; valid new task cannot use old result.
	scheduler=Scheduler.new();state=actor();step(snapshot,state,scheduler);id=int(state.request);claim=false
	check(step(snapshot,state,scheduler).status=="stale_claim" and state.request==0,"claim loss cancels pending replan")
	claim=true;drain(scheduler,2)
	scheduler=Scheduler.new();state=actor();step(snapshot,state,scheduler);id=int(state.request);finish(scheduler,id,2);state.token=8
	check(step(snapshot,state,scheduler).status=="pending" and state.request!=id,"new task token rejects completed old delivery")
	Nav.cancel_replan(state,scheduler);drain(scheduler,2)
	scheduler=Scheduler.new();state=actor();step(snapshot,state,scheduler);id=int(state.request);finish(scheduler,id,2)
	state.plan=Nav.plan(grid(),Vector2i.ZERO,Vector2i(3,2))
	var retargeted=step(snapshot,state,scheduler)
	check(retargeted.status=="pending" and state.request!=id and state.request_goal==Vector2i(3,2),"changed endpoint rejects old completed route")
	Nav.cancel_replan(state,scheduler);drain(scheduler,2)
	scheduler=Scheduler.new();state=actor();step(snapshot,state,scheduler);finish(scheduler,int(state.request),2);claim=false
	check(step(snapshot,state,scheduler).status=="stale_claim" and state.request==0,"claim loss rejects completed delivery")
	claim=true;drain(scheduler,2)
	scheduler=Scheduler.new();state=actor();step(snapshot,state,scheduler);state.plan={"status":"cancelled"}
	check(step(snapshot,state,scheduler).status=="cancelled" and state.request==0,"replaced terminal task cleans pending request")
	drain(scheduler,2)
	# Outside movement cannot be snapped to the queued origin.
	scheduler=Scheduler.new();state=actor();step(snapshot,state,scheduler);id=int(state.request)
	var displaced=step(snapshot,state,scheduler,2,Vector2(.6,.6))
	check(displaced.status=="blocked_mid_segment" and displaced.position==Vector2(.6,.6) and state.request==0,"displaced pending origin stops without snap")
	drain(scheduler,2)
	# Unreachable endpoints and slot pressure never fall back to synchronous A*.
	scheduler=Scheduler.new();state=actor();var sealed=snapshot.duplicate(true);sealed.solids[Vector2i(3,3)]=true
	step(sealed,state,scheduler);id=int(state.request);finish(scheduler,id,2)
	check(step(sealed,state,scheduler).status=="invalid_goal" and state.request==0,"terminal search failure is reported without movement")
	drain(scheduler,2)
	scheduler=Scheduler.new();state=actor();var ids=[]
	for i in Scheduler.MAX_REQUESTS:ids.append(scheduler.submit(snapshot,Vector2i.ZERO,Vector2i(3,3),2))
	var full=step(snapshot,state,scheduler)
	check(full.status=="backpressure" and full.distance==0,"full scheduler holds caller for retry")
	for pending_id in ids:scheduler.cancel(pending_id);scheduler.take_result(pending_id,2)
	drain(scheduler,2)
	check(step(snapshot,state,scheduler).status=="pending","released slots allow follower retry")
	Nav.cancel_replan(state,scheduler);drain(scheduler,2)
	# Existing callers and valid-route movement keep their original behavior.
	state=actor();var old=Nav.advance(snapshot,state,Vector2(.5,.5),.2,1.0)
	check(old.replanned and old.distance>0,"old advance signature retains synchronous replan")
	scheduler=Scheduler.new();state=actor();var normal=step(grid(),state,scheduler,1)
	check(normal.status=="walking" and scheduler._jobs.is_empty(),"valid route does not allocate search")
	changed_tail_scenario();scheduler_lifecycle()
	print("NAVIGATION_SCHEDULER_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"production_enabled":false}))
	quit(0 if failures.is_empty() else 1)
