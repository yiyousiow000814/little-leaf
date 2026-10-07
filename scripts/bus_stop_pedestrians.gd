extends RefCounted
## Three bounded presentation visitors. No model, seat, fare, service or save.
const Neighborhood=preload("res://scripts/exterior_environment.gd")
const Street=preload("res://scripts/street_pedestrians.gd")
const Motion=preload("res://scripts/illustrated_motion.gd")
const COUNT=3
const SPEED=1.05
const WAIT_SECONDS=14.0
const ABOARD_SECONDS=16.0
const WALK_X=-11.35
var actors:Array[Dictionary]=[]
var motion=Motion.new()
var elapsed=0.0
func _init():
	for i in range(COUNT):
		var wait:Vector2=Neighborhood.WAITING_POINTS[i]
		var approach=[Vector2(WALK_X,Street.Z_MIN),Vector2(WALK_X,wait.y),wait]
		var board=[wait,Vector2(WALK_X,wait.y),Vector2(WALK_X,Neighborhood.BUS_DOOR.y),Neighborhood.BUS_DOOR]
		var exit=[Neighborhood.BUS_DOOR,Vector2(WALK_X,Neighborhood.BUS_DOOR.y),Vector2(WALK_X,Street.Z_MAX)]
		var arriving=route_duration(approach);var boarding=route_duration(board);var leaving=route_duration(exit)
		var offset=arriving+WAIT_SECONDS-3 if i==0 else (arriving-3 if i==1 else arriving+WAIT_SECONDS+boarding+ABOARD_SECONDS-1)
		actors.append({"key":"bus_stop_%s"%i,"appearance":400+i,"approach":approach,"board":board,"exit":exit,"arriving":arriving,"boarding":boarding,"leaving":leaving,"period":arriving+WAIT_SECONDS+boarding+ABOARD_SECONDS+leaving,"offset":offset})
		_set_actor(actors[-1])
static func route_duration(points:Array)->float:
	var distance=0.0
	for i in range(1,points.size()):distance+=(points[i] as Vector2).distance_to(points[i-1])
	return distance/SPEED
static func route_sample(points:Array,seconds:float)->Dictionary:
	var distance=seconds*SPEED
	for i in range(1,points.size()):
		var a:Vector2=points[i-1];var b:Vector2=points[i];var length=a.distance_to(b)
		if distance<=length:return {"position":a.lerp(b,clampf(distance/length,0,1)),"heading":(b-a).normalized()}
		distance-=length
	return {"position":points[-1],"heading":(points[-1]-points[-2]).normalized()}
func _set_actor(actor:Dictionary):
	var time=fposmod(elapsed+actor.offset,actor.period)
	actor.visible=true
	var sample:Dictionary
	if time<actor.arriving:
		actor.state="approaching";sample=route_sample(actor.approach,time)
	elif time<actor.arriving+WAIT_SECONDS:
		actor.state="waiting";sample={"position":actor.approach[-1],"heading":Vector2.RIGHT}
	elif time<actor.arriving+WAIT_SECONDS+actor.boarding:
		actor.state="boarding";sample=route_sample(actor.board,time-actor.arriving-WAIT_SECONDS)
	elif time<actor.arriving+WAIT_SECONDS+actor.boarding+ABOARD_SECONDS:
		actor.state="aboard";actor.visible=false;sample={"position":Neighborhood.BUS_DOOR,"heading":Vector2.RIGHT}
	else:
		actor.state="alighting";sample=route_sample(actor.exit,time-actor.arriving-WAIT_SECONDS-actor.boarding-ABOARD_SECONDS)
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
		if not actor.visible or (actor.position.x<Neighborhood.SHELTER_ROOF.end.x)!=under_roof:continue
		if Street.screen_bounds(actor.position,origin,tile).intersects(view):result.append(actor)
	result.sort_custom(func(a,b):return a.position.x+a.position.y<b.position.x+b.position.y)
	return result
static func walkable(p:Vector2)->bool:
	if Neighborhood.STOP_PAD.has_point(p):return true
	if p.y<4.9 or p.y>11.3:return p.x>=Neighborhood.OPPOSITE_LEFT and p.x<=Neighborhood.ROAD_LEFT and p.y>=Street.Z_MIN and p.y<=Street.Z_MAX
	return p.x>=Neighborhood.STOP_CURB and p.x<=Neighborhood.BUS_DOOR.x+.01 and p.y>=Neighborhood.BOARDING_GAP.x and p.y<=Neighborhood.BOARDING_GAP.y
static func obstacles()->Array[Rect2]:
	var shapes:Array[Rect2]=[Neighborhood.STOP_BENCH,Rect2(-13.34,5.75,.08,4.4),Rect2(-13.3,5.71,1.5,.08),Rect2(-10.77,10.98,.14,.14)]
	for post in Neighborhood.STOP_POSTS:shapes.append(Rect2(post-Vector2(.06,.06),Vector2(.12,.12)))
	return shapes
