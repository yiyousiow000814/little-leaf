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
	print("NAVIGATION_SCHEDULER_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"production_enabled":false}))
	quit(0 if failures.is_empty() else 1)
