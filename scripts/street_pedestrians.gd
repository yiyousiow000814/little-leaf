extends RefCounted
## Presentation-only citizens. They never reserve a seat, create a service
## record, earn money, consume demand, or enter the save payload.
const Motion=preload("res://scripts/illustrated_motion.gd")
const Extent=preload("res://scripts/exterior_world_extent.gd")
const COUNT=32
const END_MARGIN=0.0
const Z_MIN=float(Extent.PAVEMENT_Z_MIN)+END_MARGIN
const Z_MAX=float(Extent.PAVEMENT_Z_MAX)-END_MARGIN
const LANES=[-2.10,-1.35]
const SPEEDS=[.92,1.06]
const ACTOR_RECT=Rect2(-32,-100,64,114)
var walkers:Array[Dictionary]=[]
var departures:Dictionary={}
var observed_leaving:Dictionary={}
var motion=Motion.new()
var active_motion:Dictionary={}
var visible_ambient:Dictionary={}
var previous_visible:Dictionary={}
var elapsed=0.0
var recycled=0

func _init():
	# Start an already-populated neighbourhood. Subsequent replacements happen
	# only at the far ends of the existing finite pavement, never near the cafe.
	for index in range(COUNT):
		var lane=index%2
		var rank=index/2
		var phase=(float(rank)+(.24 if lane==0 else .73))/(COUNT/2.0)
		walkers.append({"key":"street_%s"%index,"appearance":100+index,"position":Vector2(LANES[lane],lerpf(Z_MIN,Z_MAX,phase)),"heading":Vector2(0,-1 if lane==0 else 1),"speed":SPEEDS[lane]})

func advance(delta:float):
	if not is_finite(delta) or delta<=0.0:return
	elapsed+=delta
	for walker in walkers:
		var position:Vector2=walker.position
		position.y+=float(walker.heading.y)*float(walker.speed)*delta
		if position.y<Z_MIN or position.y>Z_MAX:
			# Keep the overshoot so cadence is independent of frame rate.
			position.y=Z_MIN+fposmod(position.y-Z_MIN,Z_MAX-Z_MIN)
			recycled+=1
			motion.remove(walker.key);active_motion.erase(walker.key)
		walker.position=position
	for id in departures.keys():
		var walker:Dictionary=departures[id]
		walker.position+=walker.heading*walker.speed*delta
		if walker.position.y<Z_MIN or walker.position.y>Z_MAX:
			motion.remove(walker.key);active_motion.erase(walker.key)
			departures.erase(id)

func observe_customers(customers:Array,delta:float,walk_speed:float):
	# The simulation has already completed the real exit and released its
	# service ownership. Continue exactly that animal down the same pavement
	# lane without extending a bill, table reservation, or cleaning clock.
	var live={}
	var next={}
	for guest in customers:
		live[int(guest.id)]=guest
		if str(guest.phase)!="leaving" or guest.route.is_empty():continue
		var position=Vector2(float(guest.x),float(guest.z))
		var end:Vector2=guest.route[-1]
		if int(guest.route_index)<guest.route.size()-1 or position.x>=0.0 or absf(end.x-position.x)>.001:continue
		var direction=signf(end.y-position.y)
		if direction==0.0:direction=signf(float(guest.get("heading",Vector2.DOWN).y))
		next[int(guest.id)]={"position":position,"end":end,"heading":Vector2(0,direction)}
	for id in observed_leaving:
		if next.has(id) or departures.has(id):continue
		var previous:Dictionary=observed_leaving[id]
		if live.has(id) and str(live[id].phase) not in ["dirty","cleaning"]:continue
		if previous.position.distance_to(previous.end)>walk_speed*maxf(0.0,delta)+.001:continue
		if absf(previous.heading.y)<.5:continue
		departures[id]={"key":"street_departure_%s"%id,"appearance":int(id),"position":previous.end,"heading":previous.heading,"speed":walk_speed}
	observed_leaving=next

static func screen_bounds(position:Vector2,origin:Vector2,tile:Vector2)->Rect2:
	var anchor=origin+Vector2((position.x-position.y)*tile.x,(position.x+position.y)*tile.y)
	var scale=tile.x/39.0
	return Rect2(anchor+ACTOR_RECT.position*scale,ACTOR_RECT.size*scale)

func visible_walkers(origin:Vector2,tile:Vector2,viewport:Rect2)->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	for walker in walkers+departures.values():
		if screen_bounds(walker.position,origin,tile).intersects(viewport):result.append(walker)
	return result

func _sync_visibility(origin:Vector2,tile:Vector2,viewport:Rect2):
	var current={}
	var entering=[]
	for walker in walkers:
		if not screen_bounds(walker.position,origin,tile).intersects(viewport):continue
		current[walker.key]=true
		if not previous_visible.has(walker.key):entering.append(walker)
	for key in visible_ambient.keys():
		if not current.has(key):visible_ambient.erase(key)
	# A stable shuffled order spreads initial citizens along the road rather
	# than spending the whole budget on one end. Existing visible citizens are
	# retained across camera changes, including a compact-view resize.
	entering.sort_custom(func(a,b):return posmod(int(a.appearance)*11,COUNT)<posmod(int(b.appearance)*11,COUNT))
	var budget=6 if viewport.size.x<900 or viewport.size.y<500 else 8
	for walker in entering:
		if visible_ambient.size()>=budget:break
		visible_ambient[walker.key]=true
	previous_visible=current

func _displayed(walker:Dictionary)->bool:
	# Real departing guests keep their continuity and never compete for an
	# ambient slot. Suppressed ambient walkers must leave/re-enter the view
	# before taking a free slot, so vacancies cannot create an on-screen birth.
	return str(walker.key).begins_with("street_departure_") or visible_ambient.has(walker.key)

func update_motion(delta:float,origin:Vector2,tile:Vector2,viewport:Rect2):
	# Offscreen citizens are a scalar position update, not an animated rig.
	# The padded ring warms a natural stride before any artwork enters view.
	var next={}
	_sync_visibility(origin,tile,viewport)
	for walker in visible_walkers(origin,tile,viewport.grow(96.0)):
		if not _displayed(walker):continue
		var key:String=walker.key
		next[key]=true
		if not active_motion.has(key) and delta>0.0:
			motion.update(key,walker.position-walker.heading*walker.speed*delta,0.0)
		motion.update(key,walker.position,delta)
	for key in active_motion:
		if not next.has(key):motion.remove(key)
	active_motion=next

func entries(origin:Vector2,tile:Vector2,viewport:Rect2)->Array[Dictionary]:
	_sync_visibility(origin,tile,viewport)
	var result:Array[Dictionary]=[]
	for walker in visible_walkers(origin,tile,viewport):
		if _displayed(walker):result.append(walker)
	result.sort_custom(func(a,b):return a.position.x+a.position.y<b.position.x+b.position.y)
	return result
