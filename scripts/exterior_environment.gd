extends RefCounted
## Render-only neighbourhood. No land, inventory, wallet or save mutations.
const Extent=preload("res://scripts/exterior_world_extent.gd")
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
const POCKETS=[Vector2(-13,4),Vector2(-12,-5),Vector2(.7,17),Vector2(8.9,14.2),Vector2(16,-5.2),Vector2(21.4,15.3),Vector2(15.8,19.7)]

static func parking_hooks()->Dictionary:
	# A future Decorate product must supply an approved parcel/price policy.
	# These anchors are geometry, never admission routes or owned cafe tiles.
	var bays:Array[Vector2]=[]
	for x in BAY_CENTERS:bays.append(Vector2(x,-7.15))
	return {"id":"rear_roadside_parking","bounds":LOT,"mouth_bounds":MOUTH,"entrance":MOUTH.get_center(),"road_join":Vector2(ROAD_RIGHT,MOUTH.get_center().y),"aisle_join":Vector2(LOT.position.x,MOUTH.get_center().y),"pedestrian_link_bounds":PEDESTRIAN_LINK,"pedestrian_exit":Vector2(-.26,-.26),"bay_centers":bays,"purchase_enabled":false,"customer_parking_enabled":false,"price":null,"parcel_policy":"pending"}

static func quad(a,x0:float,z0:float,x1:float,z1:float,color):
	a.poly([a.iso(x0,z0),a.iso(x1,z0),a.iso(x1,z1),a.iso(x0,z1)],color)

static func draw_ground(a):
	quad(a,ROAD_LEFT,Extent.STREET_Z_MIN,ROAD_RIGHT,Extent.STREET_Z_MAX,"8b9b90")
	quad(a,OPPOSITE_LEFT,Extent.PAVEMENT_Z_MIN,ROAD_LEFT,Extent.PAVEMENT_Z_MAX,"d7dcc2")
	# Short opposite-side bus lay-by, leaving the through lane unobstructed.
	quad(a,-10.15,4.9,ROAD_LEFT,11.3,"8b9b90")
	for z in range(Extent.MARK_Z_MIN,Extent.MARK_Z_MAX,3):
		var start=a.iso(-6.01,z);var finish=a.iso(-6.01,z+.85)
		if Rect2(start,Vector2.ZERO).expand(finish).grow(3).intersects(a.get_viewport_rect()):a.line(start,finish,"c6ceb7",2*a.ui_scale)
	# Flush vehicle crossing across the existing public sidewalk; no access road.
	quad(a,LOT.position.x,LOT.position.y,LOT.end.x,LOT.end.y,"919f92")
	for x in [0.0,2.9,5.8,8.7,11.6]:a.line(a.iso(x,-8.45),a.iso(x,-5.75),"dce0ca",1.3*a.ui_scale)
	a.line(a.iso(0,-8.45),a.iso(11.6,-8.45),"dce0ca",1.3*a.ui_scale)
	# Open lawn separates the lot from the wall; only one short pedestrian link.
	quad(a,PEDESTRIAN_LINK.position.x,PEDESTRIAN_LINK.position.y,PEDESTRIAN_LINK.end.x,PEDESTRIAN_LINK.end.y,"d7dcc2")
	for z in range(Extent.PAVEMENT_Z_MIN,Extent.PAVEMENT_Z_MAX):
		var p=a.iso(OPPOSITE_LEFT,z);var q=a.iso(ROAD_LEFT,z)
		if Rect2(p,Vector2.ZERO).expand(q).grow(2).intersects(a.get_viewport_rect()):a.line(p,q,"c5cbb3",.7)

static func draw_crossing(a):
	quad(a,MOUTH.position.x,MOUTH.position.y,MOUTH.end.x,MOUTH.end.y,"919f92")
	# A clear continuous pedestrian strip passes over the flush driveway.
	for z in [-5.49,-5.13,-4.77,-4.41,-4.05]:quad(a,-2.55,z,-1.0,z+.12,"d3d9c1")

static func draw_props(a):
	for i in range(1,4):draw_car(a,Vector2(BAY_CENTERS[i],-7.15),1,"a2b3b3" if i==2 else "ddcdb0")
	# Opposite-side stop: cream canopy, sage frame, bench, bus on road.
	quad(a,-13.0,5.3,-11.1,10.7,"c9d2b6")
	for z in [5.7,10.1]:a.line(a.iso(-12.5,z),a.iso(-12.5,z,62),"789270",3*a.ui_scale)
	a.poly([a.iso(-12.5,5.7,12),a.iso(-12.5,10.1,12),a.iso(-12.5,10.1,54),a.iso(-12.5,5.7,54)],Color(.55,.68,.62,.26))
	a.rounded_poly([a.iso(-13.0,5.3,62),a.iso(-11.1,5.3,62),a.iso(-11.1,10.7,62),a.iso(-13.0,10.7,62)],5*a.ui_scale*a.zoom,"ede2c6")
	a.line(a.iso(-12.2,6.2,18),a.iso(-12.2,9.6,18),"a6936b",5*a.ui_scale)
	var sign=a.iso(-11.0,10.9)
	a.line(sign,sign-Vector2(0,52)*a.ui_scale*a.zoom,"7a8c72",2*a.ui_scale)
	a.draw_rect(Rect2(sign-Vector2(9,65)*a.ui_scale*a.zoom,Vector2(18,15)*a.ui_scale*a.zoom),Color("879fa4"))
	draw_bus(a,Vector2(-9.4,8.1))
	for p in POCKETS:draw_pocket(a,p)
	for p in BUFFER_PLANTING:draw_pocket(a,p)

static func quad_height(a,x0:float,z0:float,x1:float,z1:float,h:float,color):
	a.poly([a.iso(x0,z0,h),a.iso(x1,z0,h),a.iso(x1,z1,h),a.iso(x0,z1,h)],color)

static func draw_car(a,p:Vector2,direction:int,color):
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
	# A dedicated original 2D illustration, not an elongated passenger car.
	var scale=a.ui_scale*a.zoom;var half=.77;var length=2.60
	quad(a,p.x-.85,p.y-2.7,p.x+.85,p.y+2.7,Color(.35,.42,.33,.16))
	for z in [-1.72,1.66]:
		a.ellipse(bus_point(a,p,-half,z,8),Vector2(6.8,9.0)*scale,"627064")
	# Cream body, sage lower skirt, rounded front and shallow cream roof.
	bus_face(a,p,half,-length,length,7,53,"e1d9bb",4)
	bus_face(a,p,half,-length,length,8,26,"8ca17d",3)
	var front=[bus_point(a,p,-half,length,8),bus_point(a,p,half,length,8),bus_point(a,p,half,length,51),bus_point(a,p,-half,length,51)]
	a.rounded_poly(front,5*scale,"e9dfbd")
	a.rounded_poly([bus_point(a,p,-half,length,8),bus_point(a,p,half,length,8),bus_point(a,p,half,length,26),bus_point(a,p,-half,length,26)],3*scale,"90a47d")
	a.rounded_poly([bus_point(a,p,-half,-length,53),bus_point(a,p,half,-length,53),bus_point(a,p,half,length,53),bus_point(a,p,-half,length,53)],6*scale,"eee4c8")
	# Four distinct passenger windows, with quiet reflection and cream mullions.
	for z in [-2.27,-1.31,-.35,.61]:
		bus_face(a,p,half+.012,z,z+.77,30,47,"748d88",2)
		bus_face(a,p,half+.018,z+.07,z+.70,33,45,"b1c0b5",1.5)
		a.line(bus_point(a,p,half+.025,z+.13,43),bus_point(a,p,half+.025,z+.55,43),"cdd6c1",.8*scale)
	# Tall glazed folding door beside the front axle; sill stays above the skirt.
	bus_face(a,p,half+.025,1.65,2.37,14,47,"6f857b",2)
	for z in [1.72,2.05]:bus_face(a,p,half+.03,z,z+.25,18,45,"bbc8b8",1)
	a.line(bus_point(a,p,half+.04,2.02,16),bus_point(a,p,half+.04,2.02,46),"83977f",1*scale)
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

static func draw_pocket(a,p:Vector2):
	# Low, irregular illustration using the game's existing muted ink/palette.
	for offset in [Vector2(-.35,0),Vector2(.1,.13),Vector2(.35,-.1)]:
		var q=a.iso(p.x+offset.x,p.y+offset.y)
		a.ellipse(q-Vector2(0,5)*a.ui_scale*a.zoom,Vector2(10,7)*a.ui_scale*a.zoom,"92a779")
	for offset in [Vector2(-.2,.25),Vector2(.3,.2)]:
		var q=a.iso(p.x+offset.x,p.y+offset.y)
		a.ellipse(q-Vector2(0,8)*a.ui_scale*a.zoom,Vector2(2.5,2.5)*a.ui_scale*a.zoom,"e7dfc2")
