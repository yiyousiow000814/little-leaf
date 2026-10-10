extends RefCounted
## Authored landmarks inside the bounded 64-by-64 neighborhood camera square.
## The camera envelope grants no land, purchases, or simulation-route changes.
const Extent=preload("res://scripts/exterior_world_extent.gd")
const ROAD_LEFT=-8.76
const ROAD_RIGHT=-3.26
const OPPOSITE_LEFT=-11.76
const LOT=Rect2(-.26,-8.7,12.26,4.9)
const MOUTH=Rect2(-3.26,-5.7,3.0,1.8)
const PEDESTRIAN_LINK=Rect2(-.26,-3.8,1.2,3.54)
const SHELTER_ROOF=Rect2(-13.55,5.45,2.0,5.0)
const SHELTER_HEIGHT=78.0
const STOP_PAD=Rect2(-13.65,4.9,3.10,6.4)
const STOP_CURB=-10.55
const STOP_APPROACH=Vector2(1.9,15.3)
const STOP_CURVE_STEPS=8
static var stop_rows=build_stop_rows()

static func inspection_bounds(tile:Vector2)->Rect2:
	# Bounded authored landmarks may be inspected with normal pan controls.
	# This affects traversal only; Fit continues to frame the owned cafe.
	var bounds=Rect2(Vector2.ZERO,Vector2.ZERO)
	var first=true
	for ground in [Extent.CAMERA_WORLD_BOUNDS,LOT,MOUTH,PEDESTRIAN_LINK,STOP_PAD,SHELTER_ROOF]:
		for point in [ground.position,Vector2(ground.end.x,ground.position.y),ground.end,Vector2(ground.position.x,ground.end.y)]:
			var projected=Vector2((point.x-point.y)*tile.x,(point.x+point.y)*tile.y)
			bounds=Rect2(projected,Vector2.ZERO) if first else bounds.expand(projected)
			first=false
	# Curved approaches extend beyond STOP_PAD. Traverse their actual cached
	# pavement vertices so both ends remain reachable through normal controls.
	for row in stop_rows:
		for point in row.points:
			var projected=Vector2((point.x-point.y)*tile.x,(point.x+point.y)*tile.y)
			bounds=bounds.expand(projected)
	# Include the shelter/people silhouette and a small inspection edge.
	return bounds.grow_individual(24*tile.x/39.0,(SHELTER_HEIGHT+24)*tile.x/39.0,24*tile.x/39.0,24*tile.x/39.0)

static func stop_blend(z:float)->float:
	var t=1.0
	if z<STOP_PAD.position.y:t=clampf((z-STOP_APPROACH.x)/(STOP_PAD.position.y-STOP_APPROACH.x),0,1)
	elif z>STOP_PAD.end.y:t=clampf((STOP_APPROACH.y-z)/(STOP_APPROACH.y-STOP_PAD.end.y),0,1)
	return t*t*(3.0-2.0*t)

static func pavement_edges(z:float)->Vector2:
	var blend=stop_blend(z)
	return Vector2(lerpf(OPPOSITE_LEFT,STOP_PAD.position.x,blend),lerpf(ROAD_LEFT,STOP_CURB,blend))

static func build_stop_rows()->Array[Dictionary]:
	# Cached world polygons retain ordinary tile rows while both edges ease
	# into the stop. No disconnected rectangular apron or sharp bay wedges.
	var rows:Array[Dictionary]=[]
	for z in range(floori(STOP_APPROACH.x),ceili(STOP_APPROACH.y)):
		var start=maxf(z,STOP_APPROACH.x);var finish=minf(z+1,STOP_APPROACH.y)
		var left=[];var right=[]
		for i in range(STOP_CURVE_STEPS+1):
			var depth=lerpf(start,finish,float(i)/STOP_CURVE_STEPS);var edges=pavement_edges(depth)
			left.append(Vector2(edges.x,depth));right.push_front(Vector2(edges.y,depth))
		rows.append({"points":left+right,"color":"dfe0c8" if posmod(z,2)==0 else "d7dcc2"})
	return rows

