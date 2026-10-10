extends SceneTree
const Nav = preload("res://scripts/cafe_navigation_candidate.gd")
const Scheduler = preload("res://scripts/cafe_navigation_scheduler_candidate.gd")
var checks = 0
var failures = []
var measurements = []

func check(ok:bool,label:String):
	checks += 1
	if not ok:failures.append(label);printerr("FAIL ",label)

func grid(width:int,height:int)->Dictionary:
	var cells = {}
	for z in height:
		for x in width:cells[Vector2i(x,z)] = true
	return {"cells":cells,"solids":{},"edges":{},"barriers":[],"revision":[1]}

func complete(scheduler,id:int,epoch:int,budget:int=128,label:String="fixture")->Dictionary:
	var total = 0;var ticks = 0;var maximum = 0;var started = Time.get_ticks_usec()
	while scheduler.inspect(id).status == "pending" and total < 3000000:
		var step = scheduler.tick(epoch,budget,0)
		check(step.work <= mini(budget,Scheduler.MAX_TICK_WORK),"tick work bound")
		total += step.work;ticks += 1;maximum = maxi(maximum,step.elapsed_usec)
	check(scheduler.inspect(id).status != "pending","bounded fixture eventually completes")
	measurements.append({"label":label,"budget":budget,"ticks":ticks,"work":total,
		"expanded":scheduler.inspect(id).expanded,"max_tick_usec":maximum,"total_usec":Time.get_ticks_usec()-started})
	return scheduler.take_result(id,epoch)

func equivalent(actual:Dictionary,expected:Dictionary,label:String):
	check(actual == expected,label+" exact route/status/cost/length/revision/expanded equivalence")

func drain(scheduler,epoch:int,label:String=""):
	var ticks = 0;var maximum = 0;var total = 0
	while scheduler._cursor != 0 and ticks < 100000:
		var step = scheduler.tick(epoch,128,0)
		check(step.work <= 128,"cleanup shares bounded work")
		maximum = maxi(maximum,step.elapsed_usec);total += step.work
		ticks += 1
	check(scheduler._cursor == 0,"cleanup eventually finishes")
	if not label.is_empty():measurements.append({"label":label,"budget":128,"ticks":ticks,"work":total,"max_tick_usec":maximum})

func _initialize():run.call_deferred()
func run():
	# Interleaving and different slice sizes must preserve published A* ordering.
	var rng = RandomNumberGenerator.new();rng.seed = 11128
	for fixture in 12:
		var snapshot = grid(7,7)
		for i in 12:
			var cell = Vector2i(rng.randi_range(0,6),rng.randi_range(0,6))
			if cell != Vector2i.ZERO and cell != Vector2i(6,6):snapshot.solids[cell] = true
		for i in 4:
			var cell = Vector2i(rng.randi_range(0,5),rng.randi_range(0,5))
			snapshot.edges[Nav.edge_key(cell,cell+Vector2i.RIGHT)] = true
		if fixture%2 == 0:snapshot.barriers.append(Rect2(Vector2(2.15,3.1),Vector2(.3,1.8)))
		var expected = Nav.plan(snapshot,Vector2i.ZERO,Vector2i(6,6))
		for budget in [1,7,128]:
			var scheduler = Scheduler.new();var id = scheduler.submit(snapshot,Vector2i.ZERO,Vector2i(6,6),1)
			equivalent(complete(scheduler,id,1,budget),expected,"seeded fixture "+str(fixture)+" budget "+str(budget))
			drain(scheduler,1)
	# Four-edge diagonal checks and inclusive frame clearance remain identical.
	for edge in [[Vector2i(0,0),Vector2i(1,0)],[Vector2i(0,0),Vector2i(0,1)],[Vector2i(1,0),Vector2i(1,1)],[Vector2i(0,1),Vector2i(1,1)]]:
		var snapshot = grid(2,2);snapshot.edges[Nav.edge_key(edge[0],edge[1])] = true
		var scheduler = Scheduler.new();var id = scheduler.submit(snapshot,Vector2i.ZERO,Vector2i.ONE,1)
		equivalent(complete(scheduler,id,1,3),Nav.plan(snapshot,Vector2i.ZERO,Vector2i.ONE),"corner edge");drain(scheduler,1)
	var framed = grid(3,3);framed.barriers.append(Rect2(Vector2(.95,.95),Vector2(.1,.1)))
	var framed_scheduler = Scheduler.new();var framed_id = framed_scheduler.submit(framed,Vector2i.ZERO,Vector2i(2,2),1)
	equivalent(complete(framed_scheduler,framed_id,1,7),Nav.plan(framed,Vector2i.ZERO,Vector2i(2,2)),"frame sweep");drain(framed_scheduler,1)
	# Each active request receives one unit per rotation, even inside barrier scans.
	var busy = grid(64,64)
	for i in 2048:busy.barriers.append(Rect2(Vector2(-10,-10),Vector2.ONE))
	var fair = Scheduler.new();var fair_ids = []
	for i in 8:fair_ids.append(fair.submit(busy,Vector2i.ZERO,Vector2i(63,63),1))
	for cycle in 12:
		check(fair.tick(1,8,0).work == 8,"full fair rotation")
		for id in fair_ids:check(fair.inspect(id).work == cycle+1,"equal fair service")
	for id in fair_ids:
		check(fair._jobs[id].phase == "sweep" and fair._jobs[id].barrier < 12,"large barrier list scanned incrementally")
	var before = fair.inspect(fair_ids[0]).expanded
	check(fair.cancel(fair_ids[0]),"cancel during a barrier sweep")
	check(fair.take_result(fair_ids[0],1).status == "cancelled","cancel cannot deliver route")
	fair.tick(2,8,0)
	for i in range(1,8):
		check(fair.inspect(fair_ids[i]).status == "stale_revision","changed layout invalidates queued search")
		check(fair.take_result(fair_ids[i],2).route.is_empty(),"stale layout has no delivered route")
	check(fair.inspect(fair_ids[0]).expanded == before,"cancelled search cannot expand")
	drain(fair,2)
	# Completed but undelivered routes also refuse a changed epoch.
	var delivery = Scheduler.new();var delivery_id = delivery.submit(grid(1,1),Vector2i.ZERO,Vector2i.ZERO,1)
	while delivery.inspect(delivery_id).status == "pending":delivery.tick(1,1,0)
	check(delivery.take_result(delivery_id,2).status == "stale_revision","stale completed route refused");drain(delivery,2)
	var undelivered = Scheduler.new();var undelivered_id = undelivered.submit(grid(512,1),Vector2i.ZERO,Vector2i(511,0),1)
	while undelivered._cursor != 0:undelivered.tick(1,128,0)
	check(undelivered.cancel(undelivered_id),"cancel completed retained route")
	check(undelivered.inspect(undelivered_id).cleanup,"cancelled completed route rejoins incremental cleanup")
	check(undelivered.take_result(undelivered_id,1).route.is_empty(),"cancel completed does not deliver points")
	drain(undelivered,1)
	check(undelivered.inspect(undelivered_id).status == "unknown","consumed cancelled request released")
	# Deliberately difficult full graphs: equivalence and bounded slices, including cleanup.
	var detour = grid(64,64)
	for z in 63:detour.solids[Vector2i(32,z)] = true
	var isolated = grid(64,64)
	isolated.edges[Nav.edge_key(Vector2i(63,63),Vector2i(62,63))] = true
	isolated.edges[Nav.edge_key(Vector2i(63,63),Vector2i(63,62))] = true
	var worst = Scheduler.new();var worst_ids = []
	for snapshot in [detour,isolated]:worst_ids.append(worst.submit(snapshot,Vector2i.ZERO,Vector2i(63,63),3))
	for i in 2:equivalent(complete(worst,worst_ids[i],3,128,["4096-detour","4096-no-path"][i]),Nav.plan([detour,isolated][i],Vector2i.ZERO,Vector2i(63,63)),"4096-cell worst case")
	drain(worst,3,"4096-completion-cleanup")
	var late = Scheduler.new();var late_id = late.submit(isolated,Vector2i.ZERO,Vector2i(63,63),3)
	while late.inspect(late_id).expanded < 2000:check(late.tick(3,128,0).work <= 128,"late-cancel preparation work bound")
	check(late.cancel(late_id),"cancel after 2000 expansions")
	check(late.take_result(late_id,3).status == "cancelled","late cancel cannot deliver route")
	drain(late,3,"2000-expansion-cancel-cleanup")
	for size in [512,513]:
		var snapshot = grid(size,1);var scheduler = Scheduler.new()
		var id = scheduler.submit(snapshot,Vector2i.ZERO,Vector2i(size-1,0),1)
		equivalent(complete(scheduler,id,1,17),Nav.plan(snapshot,Vector2i.ZERO,Vector2i(size-1,0)),"route boundary "+str(size));drain(scheduler,1)
	# Admission/backpressure, validation, budget zero and cancellation before init.
	var capped = Scheduler.new();var capped_ids = []
	for i in Scheduler.MAX_REQUESTS:capped_ids.append(capped.submit(grid(1,1),Vector2i.ZERO,Vector2i.ZERO,1))
	check(capped.submit(grid(1,1),Vector2i.ZERO,Vector2i.ZERO,1) == 0,"bounded admission")
	check(capped.tick(1,0,0).work == 0,"zero budget does no work")
	check(capped.tick(1,-1,0).work == 0,"negative work budget clamped")
	for id in capped_ids:
		capped.cancel(id);check(capped.take_result(id,1).status == "cancelled","cancel before init")
	drain(capped,1)
	check(capped.submit(grid(1,1),Vector2i.ZERO,Vector2i.ZERO,1) != 0,"incremental cleanup releases admission")
	for snapshot in [grid(4097,1),{"cells":{},"solids":{},"edges":{},"barriers":[],"revision":["bad"]}]:
		var scheduler = Scheduler.new();var id = scheduler.submit(snapshot,Vector2i.ZERO,Vector2i.ZERO,1)
		check(complete(scheduler,id,1).status == "invalid_snapshot","invalid graph contract");drain(scheduler,1)
	var timed = Scheduler.new();timed.submit(busy,Vector2i.ZERO,Vector2i(63,63),1)
	check(timed.tick(1,100000,0).work == Scheduler.MAX_TICK_WORK,"oversized work budget clamped")
	var timed_step = timed.tick(1,4096,1)
	check(timed_step.work < 4096,"cooperative elapsed deadline yields early")
	check(timed_step.work >= 0,"deadline never creates negative work")
	print("NAVIGATION_SCHEDULER_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"measurements":measurements,"fps_measured":false}))
	quit(0 if failures.is_empty() else 1)
