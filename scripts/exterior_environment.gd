extends RefCounted
## Render-only neighbourhood. No land, inventory, wallet or save mutations.
const Visibility=preload("res://scripts/cafe_render_visibility.gd")
const Extent=preload("res://scripts/exterior_world_extent.gd")
const CameraLandmarks=preload("res://scripts/cafe_camera_landmarks.gd")
const Greenery=preload("res://scripts/environment_greenery.gd")
static var greenery=Greenery.new()
const ROAD_LEFT=-8.76
const ROAD_RIGHT=-3.26
const OPPOSITE_LEFT=-11.76
const LOT=Rect2(-.26,-8.7,12.26,4.9)
const MOUTH=Rect2(-3.26,-5.7,3.0,1.8)
const PEDESTRIAN_LINK=Rect2(-.26,-3.8,1.2,3.54)
const BUFFER_PLANTING=[Vector2(2.5,-3.35),Vector2(7.8,-3.35),Vector2(11.9,-2.4)]
# Normal projection: a rear-wall point rises128px while each negative-z tile
# separates ground from its silhouette by39px. z=-3.8 leaves20.2px clearance
# before camera scaling. This exposes the entire lot, not just vehicle roofs.
const BAY_CENTERS=[1.3,4.2,7.1,10.0]
const TREES=[Vector3(-13.1,1.5,.86),Vector3(-.0,18.8,.95),Vector3(7.7,14.0,1.0),Vector3(16.0,-6.4,.90),Vector3(20.3,13.8,.85),Vector3(22.1,14.0,.62)]
const TREE_VARIANTS=["oak","airy","oak","columnar","airy","sapling"]
const SHELTER_ROOF=Rect2(-13.55,5.45,2.0,5.0)
const SHELTER_HEIGHT=78.0
const STOP_PAD=Rect2(-13.65,4.9,3.10,6.4)
const STOP_CURB=-10.55
const STOP_APPROACH=Vector2(1.9,15.3)
const STOP_CURVE_STEPS=8
const KERB_WIDTH=.10
const KERB_DROP=3.5
const KERB_RAMP=.30
const BOARDING_GAP=Vector2(9.65,10.7)
static var stop_rows=build_stop_rows()
static var stop_paving=build_stop_paving()
static var stop_grid=build_stop_grid()
static var stop_edges=build_stop_edges()
static var stop_kerb=build_stop_kerb()
const SHELTER_BOARDING=Rect2(-11.55,4.9,1.0,6.4)
const BUS_POSITION=Vector2(-9.55,8.1)
const BUS_DOOR=Vector2(-10.345,10.1)
const WAITING_POINTS=[Vector2(-12,6.95),Vector2(-12,8.3),Vector2(-12,9.5)]
const STOP_BENCH=Rect2(-13.05,6.3,.55,3.2)
const STOP_POSTS=[Vector2(-13.3,5.75),Vector2(-13.3,10.15),Vector2(-11.8,5.75),Vector2(-11.8,10.15)]
const POCKETS=[Vector2(-13.75,4),Vector2(-12,-5),Vector2(.7,17),Vector2(8.9,14.2),Vector2(16,-5.2),Vector2(21.4,15.3),Vector2(15.8,19.7)]

static func inspection_bounds(tile:Vector2)->Rect2:
	return CameraLandmarks.inspection_bounds(tile)

static func quad(a,x0:float,z0:float,x1:float,z1:float,color):
	var points=[a.iso(x0,z0),a.iso(x1,z0),a.iso(x1,z1),a.iso(x0,z1)]
	if not screen_visible(a,Visibility.points_bounds(points)):return
	a.poly(points,color)
static func screen_visible(a,bounds:Rect2)->bool:
	return a.render_bounds_visible(bounds) if a.has_method("render_bounds_visible") else Visibility.visible(bounds,a.get_viewport_rect(),6.0)
static func world_bounds(a,footprint:Rect2,height:float)->Rect2:
	var points=[]
	for x in [footprint.position.x,footprint.end.x]:
		for z in [footprint.position.y,footprint.end.y]:
			points.append(a.iso(x,z));points.append(a.iso(x,z,height))
	return Visibility.points_bounds(points).grow(12*a.ui_scale*a.zoom)


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

static func build_stop_paving()->Array[Dictionary]:
	# Square world cells keep the original grid phase/orientation. The same
	# curved outline clips edge cells; it never drags a whole tile sideways.
	var tiles:Array[Dictionary]=[]
	for row in stop_rows:
		var z=floori(row.points[0].y)
		for column in range(floori(STOP_PAD.position.x-OPPOSITE_LEFT),ceili(ROAD_LEFT-OPPOSITE_LEFT)):
			var bounds=Rect2(Vector2(OPPOSITE_LEFT+column,z),Vector2.ONE)
			var square=PackedVector2Array([bounds.position,Vector2(bounds.end.x,bounds.position.y),bounds.end,Vector2(bounds.position.x,bounds.end.y)])
			for polygon in Geometry2D.intersect_polygons(square,PackedVector2Array(row.points)):
				var full=polygon.size()==4
				for corner in square:
					var found=false
					for point in polygon:found=found or point.is_equal_approx(corner)
					full=full and found
				tiles.append({"points":Array(polygon),"color":row.color,"bounds":bounds,"full":full})
	return tiles

static func build_stop_grid()->Array:
	# Only straight fixed-x seams. Integer-z cross seams are drawn by the
	# existing sidewalk row loop. Shared tile edges are cached just once.
	var seams=[];var seen={}
	for tile in stop_paving:
		for i in range(tile.points.size()):
			var p:Vector2=tile.points[i];var q:Vector2=tile.points[(i+1)%tile.points.size()]
			if absf(p.x-q.x)>.00001 or p.distance_to(q)<.00001:continue
			if absf((p.x-OPPOSITE_LEFT)-roundf(p.x-OPPOSITE_LEFT))>.00001:continue
			var low=minf(p.y,q.y);var high=maxf(p.y,q.y)
			var key="%d/%d/%d"%[roundi(p.x*100000),roundi(low*100000),roundi(high*100000)]
			if seen.has(key):continue
			seen[key]=true;seams.append([Vector2(p.x,low),Vector2(p.x,high)])
	return seams

static func build_stop_edges()->Array[Vector2]:
	var points:Array[Vector2]=[]
	var cuts=[STOP_APPROACH.x,STOP_PAD.position.y,STOP_PAD.end.y,STOP_APPROACH.y]
	for segment in range(3):
		var count=ceili((cuts[segment+1]-cuts[segment])*STOP_CURVE_STEPS)
		for i in range(count):
			var z=lerpf(cuts[segment],cuts[segment+1],float(i)/count)
			points.append(Vector2(pavement_edges(z).y,z))
	points.append(Vector2(ROAD_LEFT,STOP_APPROACH.y))
	return points

static func kerb_drop(z:float)->float:
	# Short dropped-kerb shoulders terminate at a genuinely flush bus door.
	if z>=BOARDING_GAP.x and z<=BOARDING_GAP.y:return 0.0
	var distance=BOARDING_GAP.x-z if z<BOARDING_GAP.x else z-BOARDING_GAP.y
	return KERB_DROP*clampf(distance/KERB_RAMP,0.0,1.0)

static func build_stop_kerb()->Array[Dictionary]:
	var strips:Array[Dictionary]=[]
	# Retain the same boundary right along the straight approaches. Exact
	# ramp and opening endpoints prevent a small sliver across the doorway.
	var cuts=[float(Extent.PAVEMENT_Z_MIN),STOP_APPROACH.x,STOP_PAD.position.y,BOARDING_GAP.x-KERB_RAMP,BOARDING_GAP.x,BOARDING_GAP.y,BOARDING_GAP.y+KERB_RAMP,STOP_PAD.end.y,STOP_APPROACH.y,float(Extent.PAVEMENT_Z_MAX)]
	for segment in range(cuts.size()-1):
		var start:float=cuts[segment];var finish:float=cuts[segment+1]
		if start>=BOARDING_GAP.x and finish<=BOARDING_GAP.y:continue
		var curved=(start>=STOP_APPROACH.x and finish<=STOP_PAD.position.y) or (start>=STOP_PAD.end.y and finish<=STOP_APPROACH.y)
		var count=maxi(1,ceili((finish-start)*STOP_CURVE_STEPS)) if curved else 1
		for i in range(count):
			var z0=lerpf(start,finish,float(i)/count);var z1=lerpf(start,finish,float(i+1)/count)
			var p=Vector2(pavement_edges(z0).y,z0);var q=Vector2(pavement_edges(z1).y,z1)
			strips.append({"outer":[p,q],"inner":[p-Vector2(KERB_WIDTH,0),q-Vector2(KERB_WIDTH,0)],"drop":Vector2(kerb_drop(z0),kerb_drop(z1))})
	return strips

static func kerb_planes(a)->Array[Dictionary]:
	var planes:Array[Dictionary]=[]
	for span in [Vector2(Extent.PAVEMENT_Z_MIN,BOARDING_GAP.x),Vector2(BOARDING_GAP.y,Extent.PAVEMENT_Z_MAX)]:
		var outer=[];var inner=[];var lower=[]
		for strip in stop_kerb:
			if strip.outer[0].y<span.x or strip.outer[1].y>span.y:continue
			for i in range(2):
				var p:Vector2=strip.outer[i];var q:Vector2=strip.inner[i]
				var top=a.iso(p.x,p.y)
				if not outer.is_empty() and outer.back()==top:continue
				outer.append(top);inner.push_front(a.iso(q.x,q.y))
				# Do not duplicate flush endpoints in the tapered face polygon.
				if strip.drop[i]>0:lower.push_front(a.iso(p.x,p.y,-strip.drop[i]))
		planes.append({"top":outer+inner,"face":outer+lower})
	return planes

static func draw_kerb(a):
	# Four continuous filled polygons avoid the AA cross-lines that separate
	# tiny outlined quads would leave along a curved kerb.
	for plane in kerb_planes(a):
		if screen_visible(a,Visibility.points_bounds(plane.face)):a.poly(plane.face,"a4b09b")
		if screen_visible(a,Visibility.points_bounds(plane.top)):a.poly(plane.top,"d0d4be")

static func projected(a,points:Array)->Array:
	var result=[]
	for point in points:result.append(a.iso(point.x,point.y))
	return result

static func draw_ground(a):
	quad(a,ROAD_LEFT,Extent.STREET_Z_MIN,ROAD_RIGHT,Extent.STREET_Z_MAX,"8b9b90")
	for z in range(Extent.PAVEMENT_Z_MIN,Extent.PAVEMENT_Z_MAX):
		quad(a,OPPOSITE_LEFT,z,ROAD_LEFT,z+1,"dfe0c8" if posmod(z,2)==0 else "d7dcc2")
	# The reference's four marked edges ease into the same public sidewalk.
	# The bay first clears original paving; curved tile strips then cover its
	# lawn side. The through road and shelter/waiting positions stay fixed.
	var stop_polygon=projected(a,stop_edges)
	# At distant zoomed-in map edges this long curve is fully offscreen.
	# Skip its needless large-coordinate triangulation, as for nearby quads.
	if screen_visible(a,Visibility.points_bounds(stop_polygon)):a.poly(stop_polygon,"8b9b90")
	for row in stop_paving:
		var points=projected(a,row.points)
		if screen_visible(a,Visibility.points_bounds(points)):a.poly(points,row.color)
	for z in range(Extent.MARK_Z_MIN,Extent.MARK_Z_MAX,3):
		var start=a.iso(-6.01,z);var finish=a.iso(-6.01,z+.85)
		if Rect2(start,Vector2.ZERO).expand(finish).grow(3).intersects(a.get_viewport_rect()):a.line(start,finish,"c6ceb7",2*a.ui_scale)
	for z in range(Extent.PAVEMENT_Z_MIN,Extent.PAVEMENT_Z_MAX):
		var edges=pavement_edges(z)
		var p=a.iso(edges.x,z);var q=a.iso(edges.y,z)
		if Rect2(p,Vector2.ZERO).expand(q).grow(2).intersects(a.get_viewport_rect()):a.line(p,q,"c5cbb3",.7)
	for seam in stop_grid:a.line(a.iso(seam[0].x,seam[0].y),a.iso(seam[1].x,seam[1].y),"c5cbb3",.7)
	# The ordinary field keeps the same fixed square grid on both approaches.
	for x in [OPPOSITE_LEFT+1,OPPOSITE_LEFT+2]:
		for span in [Vector2(Extent.PAVEMENT_Z_MIN,STOP_APPROACH.x),Vector2(STOP_APPROACH.y,Extent.PAVEMENT_Z_MAX)]:
			a.line(a.iso(x,span.x),a.iso(x,span.y),"c5cbb3",.7)
	# Paving remains at its existing level. A narrow cap occupies only the
	# pavement edge; its road-facing riser drops below that plane, so there is
	# no floating raised strip or change to the authored sidewalk silhouette.
	draw_kerb(a)

static func draw_props(a,under_roof:Callable=Callable(),front_people:Callable=Callable()):
	# All low ground plants precede elevated structures. Never paint a ground
	# pocket over the roof just because its projected anchor overlaps the canopy.
	for i in range(POCKETS.size()):draw_pocket(a,POCKETS[i],i%3)
	for i in range(BUFFER_PLANTING.size()):draw_pocket(a,BUFFER_PLANTING[i],i)
	draw_shelter(a,under_roof)
	if front_people.is_valid():front_people.call()
	draw_bus(a,BUS_POSITION)

static func draw_shelter(a,under_roof:Callable=Callable()):
	if not screen_visible(a,world_bounds(a,Rect2(-14,5,4,7),88)):
		# People keep their own visibility and the same depth-order callback.
		if under_roof.is_valid():under_roof.call()
		return
	var scale=a.ui_scale*a.zoom
	# Ground was drawn with the continuous public sidewalk. Back structure,
	# waiting people, front posts and roof have separate occlusion passes.
	for z in [5.75,10.15]:
		a.ellipse(a.iso(-13.3,z),Vector2(4,2)*scale,"a8b59b")
		a.line(a.iso(-13.3,z),a.iso(-13.3,z,SHELTER_HEIGHT),"789270",3*scale)
	# Quiet back and end glazing remain connected to the posts and roof beam.
	a.poly([a.iso(-13.3,5.75,5),a.iso(-13.3,10.15,5),a.iso(-13.3,10.15,73),a.iso(-13.3,5.75,73)],Color(.62,.72,.68,.26))
	a.poly([a.iso(-13.3,5.75,5),a.iso(-11.8,5.75,5),a.iso(-11.8,5.75,73),a.iso(-13.3,5.75,73)],Color(.69,.77,.71,.22))
	a.line(a.iso(-13.3,6.05,62),a.iso(-13.3,7.05,69),Color(.90,.93,.81,.65),1.5*scale)
	# A wood seat has an actual seat plane, backrest and two grounded leg pairs.
	for z in [6.55,9.2]:
		for x in [-13.0,-12.6]:a.line(a.iso(x,z),a.iso(x,z,18),"8f8c6c",2.3*scale)
	quad_height(a,-13.05,6.3,-12.5,9.5,18,"b3a079")
	a.poly([a.iso(-13.05,6.3,20),a.iso(-13.05,9.5,20),a.iso(-13.05,9.5,34),a.iso(-13.05,6.3,34)],"b8a581")
	a.line(a.iso(-12.5,6.3,18),a.iso(-12.5,9.5,18),"948968",2*scale)
	if under_roof.is_valid():under_roof.call()
	for z in [5.75,10.15]:
		a.ellipse(a.iso(-11.8,z),Vector2(4,2)*scale,"a8b59b")
		a.line(a.iso(-11.8,z),a.iso(-11.8,z,SHELTER_HEIGHT),"789270",3*scale)
	# Thin fascia connects the full roof edge to all four support tops.
	var r=SHELTER_ROOF
	a.poly([a.iso(r.position.x,r.position.y,74),a.iso(r.end.x,r.position.y,74),a.iso(r.end.x,r.position.y,78),a.iso(r.position.x,r.position.y,78)],"d2c6a7")
	a.poly([a.iso(r.end.x,r.position.y,74),a.iso(r.end.x,r.end.y,74),a.iso(r.end.x,r.end.y,78),a.iso(r.end.x,r.position.y,78)],"c7bb9e")
	a.rounded_poly([a.iso(r.position.x,r.position.y,78),a.iso(r.end.x,r.position.y,78),a.iso(r.end.x,r.end.y,78),a.iso(r.position.x,r.end.y,78)],3*scale,"ede2c6")
	# Separate readable stop sign sits beyond the open boarding corridor.
	var sign=a.iso(-10.7,11.05)
	a.line(sign,a.iso(-10.7,11.05,58),"7a8c72",2.2*scale)
	var top=a.iso(-10.7,11.05,66)
	a.draw_rect(Rect2(top-Vector2(9,0)*scale,Vector2(18,16)*scale),Color("879fa4"))
	a.draw_rect(Rect2(top+Vector2(-5,4)*scale,Vector2(10,6)*scale),Color("e5e3cb"))
	for x in [-3,3]:a.ellipse(top+Vector2(x,11)*scale,Vector2(1.1,1.1)*scale,"e5e3cb")

static func quad_height(a,x0:float,z0:float,x1:float,z1:float,h:float,color):
	a.poly([a.iso(x0,z0,h),a.iso(x1,z0,h),a.iso(x1,z1,h),a.iso(x0,z1,h)],color)

static func draw_car(a,p:Vector2,direction:int,color):
	if not screen_visible(a,world_bounds(a,Rect2(p-Vector2(.75,1.25),Vector2(1.5,2.5)),42)):return
	var half=.60;var length=1.1
	quad(a,p.x-half,p.y-length,p.x+half,p.y+length,Color(.35,.42,.33,.14))
	for z in [-length*.67,length*.67]:
		a.ellipse(a.iso(p.x-half,p.y+z,5),Vector2(4.6,5.8)*a.ui_scale*a.zoom,"657569")
	var corners=[Vector2(p.x-half,p.y-length),Vector2(p.x+half,p.y-length),Vector2(p.x+half,p.y+length),Vector2(p.x-half,p.y+length)]
	for side in [[0,1],[1,2],[2,3],[3,0]]:
		var u=corners[side[0]];var v=corners[side[1]]
		a.poly([a.iso(u.x,u.y,5),a.iso(v.x,v.y,5),a.iso(v.x,v.y,22),a.iso(u.x,u.y,22)],color)
	a.rounded_poly([a.iso(p.x-half,p.y-length,22),a.iso(p.x+half,p.y-length,22),a.iso(p.x+half,p.y+length,22),a.iso(p.x-half,p.y+length,22)],5*a.ui_scale*a.zoom,color)
	# Small inset cabin, sloping windscreens and soft roof use 2D ink shapes.
	var cabin=length*.58
	a.poly([a.iso(p.x-half*.85,p.y-cabin,22),a.iso(p.x+half*.85,p.y-cabin,22),a.iso(p.x+half*.72,p.y-cabin*.65,34),a.iso(p.x-half*.72,p.y-cabin*.65,34)],"9aafb0")
	a.poly([a.iso(p.x+half*.85,p.y-cabin,22),a.iso(p.x+half*.85,p.y+cabin,22),a.iso(p.x+half*.72,p.y+cabin*.65,34),a.iso(p.x+half*.72,p.y-cabin*.65,34)],"9aafb0")
	a.poly([a.iso(p.x-half*.85,p.y+cabin,22),a.iso(p.x+half*.85,p.y+cabin,22),a.iso(p.x+half*.72,p.y+cabin*.65,34),a.iso(p.x-half*.72,p.y+cabin*.65,34)],"a6b8b6")
	a.rounded_poly([a.iso(p.x-half*.72,p.y-cabin*.65,34),a.iso(p.x+half*.72,p.y-cabin*.65,34),a.iso(p.x+half*.72,p.y+cabin*.65,34),a.iso(p.x-half*.72,p.y+cabin*.65,34)],3*a.ui_scale*a.zoom,color)
	for z in [-length*.67,length*.67]:
		a.ellipse(a.iso(p.x+half,p.y+z,5),Vector2(4.6,5.8)*a.ui_scale*a.zoom,"657569")
	var front=p.y+length*direction
	for x in [-half*.6,half*.6]:a.ellipse(a.iso(p.x+x,front,14),Vector2(2.5,2)*a.ui_scale*a.zoom,"eee4c8")
static func bus_point(a,p:Vector2,x:float,z:float,h:float)->Vector2:
	return a.iso(p.x+x,p.y+z,h)

static func bus_face(a,p:Vector2,x:float,z0:float,z1:float,h0:float,h1:float,color,radius:float=2.0):
	a.rounded_poly([bus_point(a,p,x,z0,h0),bus_point(a,p,x,z1,h0),bus_point(a,p,x,z1,h1),bus_point(a,p,x,z0,h1)],radius*a.ui_scale*a.zoom,color)

static func draw_bus(a,p:Vector2):
	if not screen_visible(a,world_bounds(a,Rect2(p-Vector2(1,2.85),Vector2(2,5.7)),60)):return
	# A dedicated original 2D illustration, not an elongated passenger car.
	var scale=a.ui_scale*a.zoom;var half=.77;var length=2.60
	quad(a,p.x-.85,p.y-2.7,p.x+.85,p.y+2.7,Color(.35,.42,.33,.16))
	for z in [-1.72,1.66]:
		a.ellipse(bus_point(a,p,-half,z,8),Vector2(6.8,9.0)*scale,"627064")
	# The curb-side door is drawn behind the visible body, never on the
	# through-road side. Boarding people pass behind the bus at this same edge.
	bus_face(a,p,-half,-length,length,7,53,"d7d2b4",4)
	bus_face(a,p,-half-.025,1.65,2.37,14,47,"6f857b",2)
	for z in [1.72,2.05]:bus_face(a,p,-half-.03,z,z+.25,18,45,"bbc8b8",1)
	# Cream body, sage lower skirt, rounded front and shallow cream roof.
	bus_face(a,p,half,-length,length,7,53,"e1d9bb",4)
	bus_face(a,p,half,-length,length,8,26,"8ca17d",3)
	var front=[bus_point(a,p,-half,length,8),bus_point(a,p,half,length,8),bus_point(a,p,half,length,51),bus_point(a,p,-half,length,51)]
	a.rounded_poly(front,5*scale,"e9dfbd")
	a.rounded_poly([bus_point(a,p,-half,length,8),bus_point(a,p,half,length,8),bus_point(a,p,half,length,26),bus_point(a,p,-half,length,26)],3*scale,"90a47d")
	a.rounded_poly([bus_point(a,p,-half,-length,53),bus_point(a,p,half,-length,53),bus_point(a,p,half,length,53),bus_point(a,p,-half,length,53)],6*scale,"eee4c8")
	# Four distinct passenger windows, with quiet reflection and cream mullions.
	for z in [-2.27,-1.31,-.35,.61,1.57]:
		bus_face(a,p,half+.012,z,z+.77,30,47,"748d88",2)
		bus_face(a,p,half+.018,z+.07,z+.70,33,45,"b1c0b5",1.5)
		a.line(bus_point(a,p,half+.025,z+.13,43),bus_point(a,p,half+.025,z+.55,43),"cdd6c1",.8*scale)
	# Wide upright windscreen, destination board and small paired front lights.
	a.rounded_poly([bus_point(a,p,-.61,length+.01,29),bus_point(a,p,.61,length+.01,29),bus_point(a,p,.61,length+.01,45),bus_point(a,p,-.61,length+.01,45)],3*scale,"748d88")
	a.rounded_poly([bus_point(a,p,-.55,length+.02,31),bus_point(a,p,.55,length+.02,31),bus_point(a,p,.55,length+.02,43),bus_point(a,p,-.55,length+.02,43)],2*scale,"afc0b4")
	a.line(bus_point(a,p,0,length+.03,30),bus_point(a,p,0,length+.03,44),"879a8b",1*scale)
	a.line(bus_point(a,p,-.37,length+.04,30),bus_point(a,p,-.1,length+.04,33),"657b72",.8*scale)
	a.line(bus_point(a,p,.18,length+.04,30),bus_point(a,p,.44,length+.04,33),"657b72",.8*scale)
	a.line(bus_point(a,p,-.48,length+.03,48),bus_point(a,p,.48,length+.03,48),"74866d",3*scale)
	for x in [-.54,.54]:
		a.ellipse(bus_point(a,p,x,length+.035,21),Vector2(3,2.7)*scale,"f0e7c8")
		a.ellipse(bus_point(a,p,x,length+.04,17),Vector2(1.5,1.4)*scale,"c3a26f")
	a.line(bus_point(a,p,-.61,length+.04,11),bus_point(a,p,.61,length+.04,11),"aeb99a",2*scale)
	# Grounded wheels and muted hubs overlap the body, never the roof.
	for z in [-1.72,1.66]:
		a.ellipse(bus_point(a,p,half+.045,z,8),Vector2(6.8,9.0)*scale,"627064")
		a.ellipse(bus_point(a,p,half+.06,z,8),Vector2(3.1,4.4)*scale,"adb79c")
		a.ellipse(bus_point(a,p,half+.075,z,8),Vector2(1.3,1.7)*scale,"819179")

static func draw_pocket(a,p:Vector2,variant:int=0):greenery.draw_pocket(a,p,variant)
