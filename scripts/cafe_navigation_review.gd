extends RefCounted
## Actual Main transit adapter, available only in native, save-suppressed fresh review.
const Nav=preload("res://scripts/cafe_navigation_candidate.gd")
const Scheduler=preload("res://scripts/cafe_navigation_scheduler_candidate.gd")
var game
var scheduler=Scheduler.new()
var snapshot={}
var signature=[]
var epoch=0
var serial=0
var actors={}
var legacy={}

static func allowed(owner)->bool:
	var args=OS.get_cmdline_user_args()
	return not OS.has_feature("web") and "--fresh-review" in args and "--navigation-candidate" in args and owner.fresh_start and owner.save_writes_suppressed

static func persistence_allowed(owner)->bool:
	var scope=OS.get_environment("LL_NAVIGATION_REVIEW_ROOT").replace("\\","/").simplify_path().trim_suffix("/")
	var profile=OS.get_user_data_dir().replace("\\","/").simplify_path()
	if OS.get_name()=="Windows":scope=scope.to_lower();profile=profile.to_lower()
	return allowed(owner) and "--navigation-persistence-candidate" in OS.get_cmdline_user_args() and scope.is_absolute_path() and profile.begins_with(scope+"/")

func uses_candidate(staff:Dictionary,index:int)->bool:
	return not legacy.has(index) or not is_same(legacy[index],staff)

func _init(owner):game=owner

func tick():
	var current=game.model.navigation_signature()
	if signature!=current or snapshot.is_empty():
		snapshot=Nav.from_model(game.model,1);signature=current.duplicate();epoch+=1
	# One shared search budget for all existing staff/cashier state machines.
	scheduler.tick(epoch)
	for index in actors.keys():
		if index>=game.staff_states.size() or not is_same(actors[index].staff,game.staff_states[index]):
			_cancel(actors[index]);actors.erase(index)
	for index in legacy.keys():
		if index>=game.staff_states.size() or not is_same(legacy[index],game.staff_states[index]):legacy.erase(index)

func _context(staff:Dictionary,destination:Vector2i)->Array:
	return [staff.job_kind,staff.job_token,staff.job_guest_id,staff.get("job_mess_id",-1),staff.get("job_dish_id",-1),staff.job_step,staff.station_id,destination]

func _owns(token:int,index:int,context:Array)->bool:
	if not allowed(game) or not actors.has(index) or index>=game.staff_states.size():return false
	var record:Dictionary=actors[index];var staff:Dictionary=game.staff_states[index]
	return record.serial==token and is_same(record.staff,staff) and _context(staff,staff.destination)==context and (staff.job_kind=="" or not game._staff_cell_claimed(staff.destination,index))

func _cancel(record:Dictionary):
	Nav.cancel_replan(record,scheduler)
	if not record.follower.is_empty():Nav.cancel_replan(record.follower,scheduler)

func stop():
	for record in actors.values():_cancel(record)
	actors.clear()
	legacy.clear()
	# Continue normal cooperative cleanup rather than freeing search structures here.

func export_staff(index:int,saved:Dictionary)->bool:
	var staff:Dictionary=game.staff_states[index]
	var record:Dictionary=actors.get(index,{})
	if not uses_candidate(staff,index) or record.is_empty():return not staff.has("navigation_phase")
	var follower:Dictionary=record.follower
	var following=not follower.is_empty() and not record.anchoring and int(record.request)==0 and int(follower.get("request",0))==0 and record.context==_context(staff,staff.destination) and Nav._remaining_valid(snapshot,follower,staff.pos)
	if following:
		saved.path=follower.plan.route.duplicate();saved.index=int(follower.index);saved.navigation_phase="follow"
		return true
	saved.navigation_phase="replan";saved.index=1
	var cell=Vector2i(staff.pos.floor())
	if staff.pos.distance_to(Nav.center(cell))<=.000001:saved.path=[cell];return true
	if follower.is_empty():return false
	var next=int(follower.index);var route:Array=follower.plan.route
	if next<1 or next>=route.size():return false
	if Geometry2D.get_closest_point_to_segment(staff.pos,Nav.center(route[next-1]),Nav.center(route[next])).distance_to(staff.pos)>.000001:return false
	saved.path=[route[next-1],route[next]]
	return true

func restore_staff():
	stop();snapshot={};signature=[];tick()
	for index in game.staff_states.size():
		var staff:Dictionary=game.staff_states[index]
		if not staff.has("navigation_phase"):
			legacy[index]=staff;continue
		serial+=1
		var context=_context(staff,staff.destination)
		var record={"staff":staff,"context":context,"goal":staff.destination,"serial":serial,"follower":{},"request":0,"anchoring":false}
		actors[index]=record
		if staff.navigation_phase=="replan" and staff.path.size()==1:continue
		var plan={"status":"found","route":staff.path.duplicate(),"revision":snapshot.revision.duplicate()}
		record.follower=Nav.follower(plan,serial,_owns.bind(index,context));record.follower.index=int(staff.index)
		record.anchoring=staff.navigation_phase=="replan"

func _submit(record:Dictionary,position:Vector2)->String:
	var origin=Vector2i(position.floor())
	if position.distance_to(Nav.center(origin))>.000001:return "blocked_mid_segment"
	var id=scheduler.submit(snapshot,origin,record.goal,epoch)
	if id==0:return "backpressure"
	record.request=id;record.request_scheduler=scheduler;record.request_epoch=epoch;record.origin=origin
	return "pending"

func move(staff:Dictionary,index:int,destination:Vector2i,delta:float)->Dictionary:
	var position:Vector2=staff.pos
	var result={"status":"pending","position":position,"distance":0.0,"replanned":false}
	if not allowed(game):result.status="inactive";return result
	var context=_context(staff,destination)
	var record:Dictionary=actors.get(index,{})
	if record.is_empty() or record.context!=context:
		var previous={}
		if not record.is_empty():
			_cancel(record);previous=record.follower
		serial+=1
		record={"staff":staff,"context":context,"goal":destination,"serial":serial,"follower":{},"request":0,"anchoring":false}
		actors[index]=record
		# A new job/target may be selected mid-transit. Finish only the known
		# current leg to its safe center, under the NEW task authority, before search.
		var cell=Vector2i(position.floor())
		if not previous.is_empty() and position.distance_to(Nav.center(cell))>.000001 and int(previous.index)<previous.plan.route.size():
			previous.plan.route=previous.plan.route.slice(0,int(previous.index)+1)
			previous.token=serial;previous.owns=_owns.bind(index,context)
			record.follower=previous;record.anchoring=true
	if record.follower.is_empty():
		if int(record.request)!=0 and (record.request_epoch!=epoch or position.distance_to(Nav.center(record.origin))>.000001):Nav.cancel_replan(record,scheduler)
		if int(record.request)==0:result.status=_submit(record,position);return result
		var ready=scheduler.take_result(int(record.request),epoch)
		if ready.status=="pending":return result
		record.request=0;record.erase("request_scheduler")
		if ready.status!="found":result.status=ready.status;return result
		record.follower=Nav.follower(ready,int(record.serial),_owns.bind(index,context))
	var people=[]
	# Existing docking/contact logic remains authoritative; no slowdown near it.
	if position.distance_to(Nav.center(destination))>1.0 and not record.anchoring:
		for other in game.staff_states:
			if not is_same(other,staff):people.append(other.pos)
		for guest in game.model.customers:
			if str(guest.phase) not in ["dirty","cleaning"]:people.append(Vector2(guest.x,guest.z))
	result=Nav.advance(snapshot,record.follower,position,delta,1.8,people,scheduler,epoch)
	if record.anchoring and result.status=="arrived":
		record.follower={};record.anchoring=false
		result.status=_submit(record,result.position)
	return result
