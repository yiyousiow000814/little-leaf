extends RefCounted
## Two fixed three-person presentation groups. No customer, economy or save state.
const Neighborhood=preload("res://scripts/exterior_environment.gd")
const Street=preload("res://scripts/street_pedestrians.gd")
const Motion=preload("res://scripts/illustrated_motion.gd")
const GROUP_SIZE=3
const COUNT=GROUP_SIZE*2
const Traffic=preload("res://scripts/ambient_road_traffic.gd")
const Extent=preload("res://scripts/exterior_world_extent.gd")
const BUS_SPEED=2.8 # Match existing ambient road motion; not a gameplay setting.
const SPEED=1.05
const WAIT_SECONDS=14.0
const LEGACY_ABOARD_SECONDS=16.0 # Frequency reference only; different groups exchange.
const WALK_X=-11.8
const LEGACY_DOOR=Vector2(-10.345,10.1)
const DOOR_INSIDE=Neighborhood.BUS_POSITION+Vector2(-.2,2.0)
const APPROACH_LENGTH=10.5
const DEPART_LENGTH=9.0
var actors:Array[Dictionary]=[]
var motion=Motion.new()
var elapsed=0.0
# Transient traffic commitment, excluded from all save envelopes.
var merge_reserved=false
var approach_reserved=false
var traffic_approach_region=Rect2()
var traffic_merge_region=Rect2()
func _init():
	for i in range(GROUP_SIZE):
		var wait:Vector2=Neighborhood.WAITING_POINTS[i]
		var pace:float=[1.05,1.12,.92][i]
		var arrival_lead:float=[8.0,3.5,.8][i]
		var approach=sidewalk_route(Street.Z_MIN,wait.y)
		approach.append(wait)
		var old_board=[wait,Vector2(-11.35,wait.y),Vector2(-11.35,LEGACY_DOOR.y),LEGACY_DOOR]
		var old_exit=[LEGACY_DOOR,Vector2(-11.35,LEGACY_DOOR.y),Vector2(-11.35,Street.Z_MAX)]
		var board=[wait,Vector2(WALK_X,wait.y),Vector2(WALK_X,Neighborhood.BUS_DOOR.y),Vector2(Neighborhood.STOP_CURB,Neighborhood.BUS_DOOR.y),Neighborhood.BUS_DOOR,DOOR_INSIDE]
		var exit=[DOOR_INSIDE,Neighborhood.BUS_DOOR,Vector2(Neighborhood.STOP_CURB,Neighborhood.BUS_DOOR.y),Vector2(WALK_X,Neighborhood.BUS_DOOR.y)]
		exit.append_array(sidewalk_route(Neighborhood.BUS_DOOR.y,Street.Z_MAX).slice(1))
		var arriving=route_duration(approach,pace);var boarding=route_duration(board,pace);var leaving=route_duration(exit,pace)
		# Retain the old complete-route period as the frequency authority.
		var old_approach=[Vector2(-11.35,Street.Z_MIN),Vector2(-11.35,wait.y),wait]
		actors.append({"key":"bus_stop_%s"%i,"appearance":400+i,"role":"boarding","walk_speed":pace,"arrival_lead":arrival_lead,"approach":approach,"board":board,"exit":exit,"arriving":arriving,"boarding":boarding,"leaving":leaving,"period":route_duration(old_approach)+WAIT_SECONDS+route_duration(old_board)+LEGACY_ABOARD_SECONDS+route_duration(old_exit)})
	for i in range(GROUP_SIZE):
		var actor=actors[i].duplicate(true)
		actor.key="bus_stop_exit_%s"%i;actor.appearance=403+i;actor.role="alighting"
		# Distinct onward journeys: one continues, one returns along the other
		# direction behind the shelter, one takes the outer pavement onward.
		actor.walk_speed=[1.18,.98,1.02][i]
		actor.intent=["onward","returning","outer_onward"][i]
		actor.exit=actor.exit.slice(0,4)
		if i!=0:actor.exit.append(Vector2(WALK_X,10.65)) # Clear the end post before turning behind the glass.
		if i==1:
			actor.exit.append(Vector2(-14.3,10.65))
			actor.exit.append_array(sidewalk_route(10.65,Street.Z_MIN,-14.3,-11.50).slice(1))
		elif i==2:
			actor.exit.append(Vector2(-13.0,10.65))
			actor.exit.append_array(sidewalk_route(10.65,Street.Z_MAX,-13.0,-11.50).slice(1))
		else:actor.exit.append_array(sidewalk_route(Neighborhood.BUS_DOOR.y,Street.Z_MAX).slice(1))
		actor.leaving=route_duration(actor.exit,actor.walk_speed)
		actor.exit_offset=0.0 if i==0 else actors[-1].exit_offset+route_duration(actors[-1].exit.slice(0,3),actors[-1].walk_speed)
		actors.append(actor)
	for actor in actors:actor.period=actors[0].period
	# One doorway is shared; each person approaches from their own waiting
	# point in time to use it, instead of starting together on a group clock.
	var available=alighting_clearance()
	for i in range(GROUP_SIZE):
		var actor=actors[i]
		var approach_time=route_duration(actor.board.slice(0,4),actor.walk_speed)
		actor.board_start=maxf(0,available-approach_time)
		available=actor.board_start+actor.boarding
	for actor in actors:_set_actor(actor)
static func sidewalk_route(start:float,finish:float,bay_x:float=WALK_X,street_x:float=-11.35)->Array:
	var points=[]
	var segments=ceili(absf(finish-start))
	for i in range(segments+1):
		var z=lerpf(start,finish,float(i)/segments)
		points.append(Vector2(lerpf(street_x,bay_x,Neighborhood.stop_blend(z)),z))
	return points
func alighting_clearance()->float:
	# Doorway clearance is a shared resource, not a shared departure signal.
	var clearance=0.0
	for actor in actors:
		if actor.role=="alighting":
			var corridor=actor.exit.slice(0,4)
			clearance=maxf(clearance,actor.exit_offset+route_duration(corridor,actor.walk_speed))
	return clearance
func boarding_start()->float:return actors[0].board_start
func bus_snapshot()->Dictionary:return snapshot_at(elapsed)
func snapshot_at(clock:float)->Dictionary:
	var period:float=actors[0].period
	var phase=fposmod(clock,period)
	var dwell=alighting_clearance()
	for i in range(GROUP_SIZE):dwell=maxf(dwell,actors[i].board_start+actors[i].boarding)
	var state="away";var z=Neighborhood.BUS_POSITION.y;var visible=false
	if phase<=dwell:state="stopped";visible=true
	elif phase<dwell+(z-Extent.STREET_Z_MIN+2.85)/BUS_SPEED:
		state="departing";visible=true;z-=BUS_SPEED*(phase-dwell)
	elif phase>period-(Extent.STREET_Z_MAX+2.85-z)/BUS_SPEED:
		state="approaching";visible=true;z+=BUS_SPEED*(period-phase)
	var path=bus_path(z,state)
	return {"state":state,"visible":visible,"position":path.position,"heading":path.heading,"direction":Neighborhood.BUS_DIRECTION,"trip":int(floor(clock/period))+(1 if state=="approaching" else 0),"phase":phase,"period":period,"dwell":dwell}
static func bus_path(z:float,state:String)->Dictionary:
	# Ease the center along the bay, and project every body/wheel point using
	# the exact path tangent. No screen-space sprite skew or sideways merge.
	var incoming=state=="approaching"
	var span=APPROACH_LENGTH if incoming else DEPART_LENGTH
	var distance=z-Neighborhood.BUS_POSITION.y if incoming else Neighborhood.BUS_POSITION.y-z
	var t=clampf(distance/span,0,1) if state in ["approaching","departing"] else 0.0
	var offset=float(Traffic.LANES[1])-Neighborhood.BUS_POSITION.x
	var x=Neighborhood.BUS_POSITION.x+offset*t*t*(3-2*t)
	var derivative=offset*6*t*(1-t)/span*(1 if incoming else -1)
	return {"position":Vector2(x,z),"heading":Vector2(-derivative,-1).normalized()}
func draw_bus(art,people_draw:Callable=Callable()):
	var bus=bus_snapshot()
	if bus.visible:Neighborhood.draw_oriented_bus(art,bus.position,bus.heading,people_draw)
	elif people_draw.is_valid():people_draw.call()
static func route_duration(points:Array,speed:float=SPEED)->float:
	var distance=0.0
	for i in range(1,points.size()):distance+=(points[i] as Vector2).distance_to(points[i-1])
	return distance/speed
static func route_sample(points:Array,seconds:float,speed:float=SPEED)->Dictionary:
	var distance=seconds*speed
	for i in range(1,points.size()):
		var a:Vector2=points[i-1];var b:Vector2=points[i];var length=a.distance_to(b)
		if distance<=length:return {"position":a.lerp(b,clampf(distance/length,0,1)),"heading":(b-a).normalized()}
		distance-=length
	return {"position":points[-1],"heading":(points[-1]-points[-2]).normalized()}
func _set_actor(actor:Dictionary):
	var phase=fposmod(elapsed,actor.period)
	actor.visible=true
	var sample:Dictionary
	if actor.role=="alighting":
		var seconds=phase-actor.exit_offset
		actor.state="alighting" if seconds>=0 and seconds<actor.leaving else "away"
		actor.visible=actor.state=="alighting"
		sample=route_sample(actor.exit,maxf(seconds,0),actor.walk_speed)
	elif phase>=actor.period-actor.arriving-actor.arrival_lead:
		var seconds=phase-(actor.period-actor.arriving-actor.arrival_lead)
		actor.state="approaching" if seconds<actor.arriving else "waiting"
		sample=route_sample(actor.approach,seconds,actor.walk_speed)
	elif phase<actor.board_start:
		actor.state="waiting";sample={"position":actor.approach[-1],"heading":Vector2.RIGHT}
	elif phase<actor.board_start+actor.boarding:
		actor.state="boarding";sample=route_sample(actor.board,phase-actor.board_start,actor.walk_speed)
	else:
		# A departing group's presentation slots remain hidden, then recycle
		# only at the remote sidewalk entry for the next trip's different people.
		actor.state="aboard";actor.visible=false;sample={"position":Neighborhood.BUS_DOOR,"heading":Vector2.RIGHT}
	actor.position=sample.position;actor.heading=sample.heading

func area_visible(origin:Vector2,tile:Vector2,view:Rect2)->bool:
	var bounds=Rect2(origin+Vector2((-13.65-4.9)*tile.x,(-13.65+4.9)*tile.y),Vector2.ZERO)
	for x in [-13.65,-8.76]:
		for z in [4.4,11.8]:bounds=bounds.expand(origin+Vector2((x-z)*tile.x,(x+z)*tile.y))
	if bounds.grow(110*tile.x/39).intersects(view):return true
	for actor in actors:
		if actor.visible and Street.screen_bounds(actor.position,origin,tile).intersects(view):return true
	return false
func advance(delta:float,origin:Vector2,tile:Vector2,view:Rect2):
	if not is_finite(delta) or delta<=0 or not area_visible(origin,tile,view):return
	elapsed+=delta
	for actor in actors:
		var previous:Vector2=actor.position
		_set_actor(actor)
		if not actor.visible or not Street.screen_bounds(actor.position,origin,tile).intersects(view.grow(96)):
			motion.remove(actor.key);continue
		motion.update(actor.key,previous,0)
		motion.update(actor.key,actor.position,delta)
func entries(origin:Vector2,tile:Vector2,view:Rect2,under_roof:bool)->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	for actor in actors:
		if not actor.visible or (actor.position.x<(Neighborhood.SHELTER_ROOF.end.x+Neighborhood.SHELTER_OFFSET.x))!=under_roof:continue
		if Street.screen_bounds(actor.position,origin,tile).intersects(view):result.append(actor)
	result.sort_custom(func(a,b):return a.position.x+a.position.y<b.position.x+b.position.y)
	return result
static func walkable(p:Vector2)->bool:
	var edges=Neighborhood.pavement_edges(p.y)
	if p.x>=edges.x and p.x<=edges.y and p.y>=Street.Z_MIN and p.y<=Street.Z_MAX:return true
	return p.x>=Neighborhood.STOP_CURB and p.x<=DOOR_INSIDE.x+.01 and p.y>=Neighborhood.BOARDING_GAP.x and p.y<=Neighborhood.BOARDING_GAP.y
static func obstacles()->Array[Rect2]:
	var shapes:Array[Rect2]=[Neighborhood.STOP_BENCH,Rect2(Vector2(-13.34,5.75)+Neighborhood.SHELTER_OFFSET,Vector2(.08,4.4)),Rect2(Vector2(-13.3,5.71)+Neighborhood.SHELTER_OFFSET,Vector2(1.5,.08)),Rect2(-10.77,10.98,.14,.14)]
	for post in Neighborhood.STOP_POSTS:shapes.append(Rect2(post-Vector2(.06,.06),Vector2(.12,.12)))
	return shapes

func reset_traffic_entry():
	# A restored pool keeps its positions; a transient bus enters from outside it.
	elapsed=actors[0].period-(Extent.STREET_Z_MAX+2.85-Neighborhood.BUS_POSITION.y)/BUS_SPEED-.05
	merge_reserved=false;approach_reserved=false
	for actor in actors:_set_actor(actor)
func accept_traffic_progress(delta:float):
	elapsed+=delta
	for actor in actors:_set_actor(actor)

func observe_traffic_motion(delta:float,origin:Vector2,tile:Vector2,view:Rect2):
	# Read accepted model poses only; observation never advances the bus clock.
	if not is_finite(delta) or delta<=0:return
	for actor in actors:
		if not actor.visible or not Street.screen_bounds(actor.position,origin,tile).intersects(view.grow(96)):
			motion.remove(actor.key);continue
		motion.update(actor.key,actor.position,delta)
