extends RefCounted
## Inactive transient scheduler. Callers own immutable snapshots and layout epochs.
## Does not allocate tasks, claim endpoints, change codecs or move characters.
const Nav = preload("res://scripts/cafe_navigation_candidate.gd")
const MAX_REQUESTS = 256
const MAX_TICK_WORK = 4096
const MAX_REVISION_PARTS = 16
var _jobs = {}
var _cursor = 0
var _next_id = 1
var _pending = 0

func submit(snapshot:Dictionary, origin:Vector2i, goal:Vector2i, epoch:int)->int:
	if _jobs.size() >= MAX_REQUESTS:return 0 # Caller retries after consuming results.
	var id = _next_id;_next_id += 1
	var state = {"id":id,"snapshot":snapshot,"epoch":epoch,"origin":origin,"goal":goal,
		"phase":"init","status":"pending","expanded":0,"work":0,"revision":[],
		"g":{},"previous":{},"heap":[],"touched":[],"seen":{},"route":[],
		"result":{},"consumed":false,"next":id,"prev":id}
	if _cursor != 0:
		var tail = int(_jobs[_cursor].prev)
		state.next = _cursor;state.prev = tail
		_jobs[tail].next = id;_jobs[_cursor].prev = id
	else:_cursor = id
	_jobs[id] = state;_pending += 1
	return id

func cancel(id:int)->bool:
	if not _jobs.has(id) or _jobs[id].consumed:return false
	var state:Dictionary = _jobs[id]
	if state.status == "pending":_finish(state,"cancelled")
	else:_discard_delivery(state,"cancelled")
	return true

func inspect(id:int)->Dictionary:
	if not _jobs.has(id):return {"status":"unknown"}
	var state:Dictionary = _jobs[id]
	return {"status":state.status,"expanded":state.expanded,"work":state.work,
		"cleanup":state.phase == "cleanup","consumed":state.consumed}

func take_result(id:int, current_epoch:int)->Dictionary:
	if not _jobs.has(id) or _jobs[id].consumed:return {"status":"unknown"}
	var state:Dictionary = _jobs[id]
	if state.status == "pending":return {"status":"pending"}
	if state.epoch != current_epoch and state.status != "cancelled":_discard_delivery(state,"stale_revision")
	var result:Dictionary = state.result
	state.result = {};state.consumed = true
	# Search structures are reclaimed by tick, never bulk-cleared here.
	if state.phase == "retained":_jobs.erase(id)
	return result

func tick(current_epoch:int, work_budget:int=128, time_budget_usec:int=2000)->Dictionary:
	var used = 0;var started = Time.get_ticks_usec()
	var budget = clampi(work_budget,0,MAX_TICK_WORK)
	while _cursor != 0 and used < budget:
		if time_budget_usec > 0 and Time.get_ticks_usec()-started >= time_budget_usec:break
		var id = _cursor;var state:Dictionary = _jobs[id]
		_cursor = int(state.next) # One primitive per request before rotating.
		if state.status == "pending" and state.epoch != current_epoch:_finish(state,"stale_revision")
		else:_advance(state)
		used += 1;state.work += 1
		if state.phase == "retained":_unlink(id)
	return {"work":used,"pending":_pending,"retained":_jobs.size(),
		"elapsed_usec":Time.get_ticks_usec()-started}

func _unlink(id:int):
	var state:Dictionary = _jobs[id]
	if state.next == id:_cursor = 0
	else:
		_jobs[state.prev].next = state.next;_jobs[state.next].prev = state.prev
		if _cursor == id:_cursor = int(state.next)
	if state.consumed:_jobs.erase(id)

func _discard_delivery(state:Dictionary,status:String):
	# A completed route can still be cancelled/staled before delivery. Transfer
	# its storage to incremental cleanup rather than freeing 512 points here.
	if not state.result.route.is_empty():
		state.route = state.result.route
		if state.phase == "retained":
			var id = int(state.id);state.next = id;state.prev = id
			if _cursor != 0:
				var tail = int(_jobs[_cursor].prev)
				state.next = _cursor;state.prev = tail
				_jobs[tail].next = id;_jobs[_cursor].prev = id
			else:_cursor = id
		state.phase = "cleanup"
	state.result = _result(state,status);state.status = status

func _result(state:Dictionary,status:String)->Dictionary:
	return {"status":status,"route":[],"cost":0,"length":0.0,
		"revision":state.revision.duplicate(),"expanded":state.expanded}

func _finish(state:Dictionary,status:String):
	state.status = status;state.result = _result(state,status)
	state.phase = "cleanup";_pending -= 1

func _advance(state:Dictionary):
	var snapshot:Dictionary = state.snapshot
	match state.phase:
		"init":
			# Admission is O(1); validation occurs under the tick's budget.
			if not snapshot.get("cells") is Dictionary or not snapshot.get("solids") is Dictionary or not snapshot.get("edges") is Dictionary or not snapshot.get("barriers") is Array or not snapshot.get("revision") is Array:
				_finish(state,"invalid_snapshot");return
			if snapshot.cells.size() > Nav.MAX_CELLS or snapshot.revision.size() > MAX_REVISION_PARTS:
				_finish(state,"invalid_snapshot");return
			for part in snapshot.revision:
				if not part is int:_finish(state,"invalid_snapshot");return
			state.revision = snapshot.revision.duplicate()
			if not Nav.open_cell(snapshot,state.origin):_finish(state,"invalid_origin");return
			if not Nav.open_cell(snapshot,state.goal):_finish(state,"invalid_goal");return
			state.g[state.origin] = 0;state.touched.append(state.origin)
			var h = Nav.heuristic(state.origin,state.goal)
			Nav._push(state.heap,{"cell":state.origin,"g":0,"h":h,"f":h});state.phase = "pop"
		"pop":
			if state.heap.is_empty():_finish(state,"no_path");return
			var entry:Dictionary = Nav._pop(state.heap)
			if int(entry.g) != int(state.g[entry.cell]):return
			state.expanded += 1;state.entry = entry
			if entry.cell == state.goal:
				state.route.append(entry.cell);state.seen[entry.cell] = true
				state.at = entry.cell;state.phase = "trace"
			else:state.direction = 0;state.phase = "neighbor"
		"neighbor":
			if state.direction >= Nav.DIRECTIONS.size():state.phase = "pop";return
			var a:Vector2i = state.entry.cell;var d:Vector2i = Nav.DIRECTIONS[state.direction]
			var b:Vector2i = a+d;var legs = [[a,b]]
			if d.x != 0 and d.y != 0:
				var x = a+Vector2i(d.x,0);var z = a+Vector2i(0,d.y)
				legs = [[a,x],[a,z],[x,b],[z,b]]
			for leg in legs:
				var left:Vector2i = leg[0];var right:Vector2i = leg[1]
				if absi(left.x-right.x)+absi(left.y-right.y) != 1 or not Nav.open_cell(snapshot,left) or not Nav.open_cell(snapshot,right) or snapshot.edges.has(Nav.edge_key(left,right)):
					state.direction += 1;return
			if legs.size() == 4:legs.append([a,b])
			state.legs = legs;state.leg = 0;state.barrier = 0;state.next_cell = b;state.phase = "sweep"
		"sweep":
			if state.barrier >= snapshot.barriers.size():
				state.leg += 1;state.barrier = 0
				if state.leg == state.legs.size():state.phase = "relax"
				return
			var leg:Array = state.legs[state.leg]
			var blocked = Nav.crosses(snapshot.barriers[state.barrier],Nav.center(leg[0]),Nav.center(leg[1]))
			state.barrier += 1
			if blocked:state.direction += 1;state.phase = "neighbor"
		"relax":
			var next:Vector2i = state.next_cell;var d:Vector2i = Nav.DIRECTIONS[state.direction]
			var cost = int(state.entry.g)+(14 if d.x != 0 and d.y != 0 else 10)
			if not state.g.has(next) or cost < int(state.g[next]):
				if not state.g.has(next):state.touched.append(next)
				state.g[next] = cost;state.previous[next] = state.entry.cell
				var h = Nav.heuristic(next,state.goal)
				Nav._push(state.heap,{"cell":next,"g":cost,"h":h,"f":cost+h})
			state.direction += 1;state.phase = "neighbor"
		"trace":
			if state.at == state.origin:state.reverse_index = 0;state.phase = "reverse";return
			if not state.previous.has(state.at) or state.route.size() >= Nav.MAX_ROUTE:_finish(state,"route_limit");return
			state.at = state.previous[state.at]
			if state.seen.has(state.at):_finish(state,"invalid_predecessor");return
			state.seen[state.at] = true;state.route.append(state.at)
		"reverse":
			var i = int(state.reverse_index);var end = state.route.size()-1-i
			if i >= end:state.length_index = 1;state.length = 0.0;state.phase = "length";return
			var swap = state.route[i];state.route[i] = state.route[end];state.route[end] = swap
			state.reverse_index += 1
		"length":
			var i = int(state.length_index)
			if i < state.route.size():
				state.length += Nav.center(state.route[i-1]).distance_to(Nav.center(state.route[i]));state.length_index += 1
			else:
				_finish(state,"found");state.result.route = state.route;state.route = []
				state.result.cost = int(state.entry.g);state.result.length = state.length
		"cleanup":
			if not state.heap.is_empty():state.heap.pop_back();return
			if not state.touched.is_empty():
				var cell = state.touched.pop_back();state.g.erase(cell);state.previous.erase(cell);state.seen.erase(cell);return
			if not state.route.is_empty():state.route.pop_back();return
			state.phase = "retained"
