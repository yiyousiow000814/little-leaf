extends RefCounted
## Fixed presentation-only pool. Offscreen road and inactive gameplay freeze it.
const Neighborhood=preload("res://scripts/exterior_environment.gd")
const Extent=preload("res://scripts/exterior_world_extent.gd")
const COUNT=8
const LANES=[-4.65,-7.35]
var cars:Array[Dictionary]=[]
var elapsed=0.0
func _init():
	for i in range(COUNT):cars.append({"position":Vector2(LANES[i%2],-65.0+i*19.0),"direction":1 if i%2==0 else -1,"color":"a2b3b3" if i%3==0 else "ddcdb0"})
static func road_visible(origin:Vector2,tile:Vector2,viewport:Rect2)->bool:
	var corners=PackedVector2Array()
	for x in [Neighborhood.ROAD_LEFT,Neighborhood.ROAD_RIGHT]:
		for z in [Extent.STREET_Z_MIN,Extent.STREET_Z_MAX]:corners.append(origin+Vector2((x-z)*tile.x,(x+z)*tile.y))
	# Polygon intersection avoids a huge road bounding box falsely staying active.
	var polygon=PackedVector2Array([corners[0],corners[2],corners[3],corners[1]])
	var view=PackedVector2Array([viewport.position,Vector2(viewport.end.x,viewport.position.y),viewport.end,Vector2(viewport.position.x,viewport.end.y)])
	return not Geometry2D.intersect_polygons(polygon,view).is_empty()
func advance(delta:float,origin:Vector2,tile:Vector2,viewport:Rect2):
	if not is_finite(delta) or delta<=0.0 or not road_visible(origin,tile,viewport):return
	elapsed+=delta
	for car in cars:
		car.position.y=Extent.STREET_Z_MIN+fposmod(car.position.y-Extent.STREET_Z_MIN+car.direction*2.8*delta,Extent.STREET_Z_MAX-Extent.STREET_Z_MIN)
func draw(a):
	for car in cars:
		# The car renderer owns conservative projected-footprint culling. A fixed
		# anchor box clips edge-visible bodywork, especially at detail zoom.
		Neighborhood.draw_car(a,car.position,car.direction,car.color)
