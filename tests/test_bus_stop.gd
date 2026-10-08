extends SceneTree
const Stop=preload("res://scripts/bus_stop_pedestrians.gd")
const Neighborhood=preload("res://scripts/exterior_environment.gd")
const Model=preload("res://scripts/cafe_model.gd")
class KerbProjection:
	var scale:float
	func _init(value:float):scale=value
	func iso(x:float,z:float,h:float=0.0)->Vector2:return Vector2((x-z)*39.0,(x+z)*19.5)*scale-Vector2(0,h*scale)
var checks=0
var failures=[]
func check(ok:bool,label:String):
	checks+=1
	if not ok and label not in failures:failures.append(label);printerr("FAIL ",label)
func _init():
	var model=Model.new()
	var before=JSON.stringify({"customers":model.customers,"coins":model.coins,"items":model.items,"owned":model.owned_parcels,"floors":model.floor_finishes})
	var stop=Stop.new();var origin=Vector2(800,345);var tile=Vector2(33.54,16.77);var view=Rect2(0,0,1654,951)
	check(stop.actors.size()==3,"fixed three-visitor presentation pool")
	check(Neighborhood.STOP_PAD.position.x<Neighborhood.OPPOSITE_LEFT and Neighborhood.STOP_PAD.end.x>Neighborhood.OPPOSITE_LEFT,"same-level shelter paving overlaps original sidewalk rather than isolated slab")
	check(Neighborhood.BUS_DOOR.x<Neighborhood.BUS_POSITION.x and Neighborhood.BUS_DOOR.y>Neighborhood.BOARDING_GAP.x and Neighborhood.BUS_DOOR.y<Neighborhood.BOARDING_GAP.y,"curb-facing bus door meets flush boarding opening")
	check(Neighborhood.SHELTER_BOARDING.size.x>=.88,"continuous full pedestrian-width bypass outside canopy posts")
	for z in [Neighborhood.STOP_APPROACH.x,Neighborhood.STOP_APPROACH.y]:
		var edges=Neighborhood.pavement_edges(z)
		check(is_equal_approx(edges.x,Neighborhood.OPPOSITE_LEFT) and is_equal_approx(edges.y,Neighborhood.ROAD_LEFT),"both flare ends rejoin original sidewalk without gaps")
		var slope=(Neighborhood.pavement_edges(z+.001)-Neighborhood.pavement_edges(z-.001))/.002
		check(slope.length()<.003,"both curved connections have tangent continuity at original sidewalk")
	for z in [Neighborhood.STOP_PAD.position.y,Neighborhood.STOP_PAD.end.y]:
		var slope=(Neighborhood.pavement_edges(z+.001)-Neighborhood.pavement_edges(z-.001))/.002
		check(slope.length()<.003,"curves ease into shelter rectangle without sharp shoulders")
	for n in range(1341):
		var edges=Neighborhood.pavement_edges(1.9+n*.01)
		check(edges.y-edges.x>=2.999 and edges.y<=Neighborhood.ROAD_LEFT,"flare preserves full sidewalk width and through-road lane")
	for row in Neighborhood.stop_paving:check(Geometry2D.triangulate_polygon(PackedVector2Array(row.points)).size()>0,"cached curved tile polygons triangulate without crossing")
	check(Geometry2D.triangulate_polygon(PackedVector2Array(Neighborhood.stop_edges)).size()>0,"curved bus bay triangulates without crossing")
	check(Neighborhood.POCKETS[0].x<Neighborhood.pavement_edges(Neighborhood.POCKETS[0].y).x-.35,"existing low planting stays on lawn beyond new curved paving")
	var full_tiles=0
	for tile_data in Neighborhood.stop_paving:
		var bounds:Rect2=tile_data.bounds
		check(bounds.size==Vector2.ONE and is_equal_approx(bounds.position.x-Neighborhood.OPPOSITE_LEFT,roundf(bounds.position.x-Neighborhood.OPPOSITE_LEFT)) and is_equal_approx(bounds.position.y,roundf(bounds.position.y)),"every tile uses fixed original one-by-one world grid")
		for point in tile_data.points:check(bounds.grow(.00002).has_point(point),"curve clips tile inside square cell instead of stretching it")
		if tile_data.full:
			full_tiles+=1
			for projection in [Vector2(33.54,16.77),Vector2(78,39)]:
				var projected_bounds=Rect2(Vector2((tile_data.points[0].x-tile_data.points[0].y)*projection.x,(tile_data.points[0].x+tile_data.points[0].y)*projection.y),Vector2.ZERO)
				for point in tile_data.points:projected_bounds=projected_bounds.expand(Vector2((point.x-point.y)*projection.x,(point.x+point.y)*projection.y))
				check(projected_bounds.size.distance_to(projection*2)<.003,"uncut tiles retain original isometric dimensions at normal and close-up scales")
	check(full_tiles>0,"actual interior includes complete original square tiles")
	for seam in Neighborhood.stop_grid:
		check(is_equal_approx(seam[0].x,seam[1].x) and seam[1].y-seam[0].y<=1.00002,"straight clipped seams never bend or stretch with transition")
	check(Neighborhood.SHELTER_BOARDING.size.x-Neighborhood.KERB_WIDTH>=.88,"kerb leaves a full pedestrian-width clear boarding bypass")
	check(Neighborhood.stop_kerb.size()<70,"cached kerb samples only curves rather than subdividing entire street")
	for strip in Neighborhood.stop_kerb:
		check(strip.outer[1].y<=Neighborhood.BOARDING_GAP.x or strip.outer[0].y>=Neighborhood.BOARDING_GAP.y,"no kerb top or face crosses flush bus doorway")
		for i in range(2):
			var point:Vector2=strip.outer[i]
			check(is_equal_approx(point.x,Neighborhood.pavement_edges(point.y).y),"kerb preserves existing pavement and road boundary")
			check(is_equal_approx(strip.inner[i].x,point.x-Neighborhood.KERB_WIDTH) and is_equal_approx(strip.inner[i].y,point.y),"kerb cap stays inside paving without drifting grid or widening bay")
			check(strip.drop[i]>=0 and strip.drop[i]<=Neighborhood.KERB_DROP,"road face is bounded beneath original pavement plane")
	for z in [Neighborhood.BOARDING_GAP.x,Neighborhood.BUS_DOOR.y,Neighborhood.BOARDING_GAP.y]:check(is_zero_approx(Neighborhood.kerb_drop(z)),"boarding opening remains genuinely flush")
	for scale in [.86,2.0]:
		var planes=Neighborhood.kerb_planes(KerbProjection.new(scale))
		check(planes.size()==2,"kerb has just two continuous runs split by doorway")
		for plane in planes:
			for surface in [plane.top,plane.face]:
				check(Geometry2D.triangulate_polygon(PackedVector2Array(surface)).size()>0,"filled cap and road face triangulate at both review scales")
			check(plane.top!=plane.face,"kerb top and side are distinct coherent filled planes")
	var still=stop.actors.duplicate(true)
	for invalid in [0.0,-1.0,NAN,INF]:stop.advance(invalid,origin,tile,view)
	check(stop.actors==still and stop.elapsed==0,"pause/invalid delta keeps all people unchanged")
	stop.advance(2,Vector2(100000,100000),tile,view)
	check(stop.actors==still and stop.elapsed==0,"offscreen stop and people freeze")
	var seen={};var obstacles=Stop.obstacles()
	for n in range(14400):
		stop.advance(.25,origin,tile,view)
		for actor in stop.actors:
			seen[actor.state]=true
			check(actor.position.is_finite() and Stop.walkable(actor.position),"hour of routes stays on connected sidewalk/pad or door opening")
			check(actor.position.x<0 and actor.position.y>=-82 and actor.position.y<=82,"presentation never enters cafe or escapes finite pavement")
			if actor.visible:
				for obstacle in obstacles:check(not obstacle.grow(.35).has_point(actor.position),"pedestrian foot clearance from bench/glass/posts/sign")
		check(stop.actors.size()==3 and stop.motion._actors.size()<=3,"clock never grows actors or animated rigs")
	for state in ["approaching","waiting","boarding","aboard","alighting"]:check(seen.has(state),"cycle demonstrates "+state)
	var whole=Stop.new();var sliced=Stop.new();whole.advance(31.75,origin,tile,view)
	for n in range(127):sliced.advance(.25,origin,tile,view)
	for i in range(3):check(whole.actors[i].position.distance_to(sliced.actors[i].position)<.001 and whole.actors[i].state==sliced.actors[i].state,"frame slicing preserves presentation routes/waits")
	check(before==JSON.stringify({"customers":model.customers,"coins":model.coins,"items":model.items,"owned":model.owned_parcels,"floors":model.floor_finishes}),"stop presentation cannot change customer/land/economy state")
	print("BUS_STOP_RESULT ",JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
