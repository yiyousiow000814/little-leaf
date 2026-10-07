extends SceneTree
const Neighborhood=preload("res://scripts/exterior_environment.gd")
const Traffic=preload("res://scripts/ambient_road_traffic.gd")
var checks=0
var failures=[]
func check(ok:bool,label:String):
	checks+=1
	if not ok and label not in failures:failures.append(label);printerr("FAIL ",label)
func _init():
	var hooks=Neighborhood.parking_hooks()
	check(not hooks.purchase_enabled and not hooks.customer_parking_enabled and hooks.price==null,"unapproved product never invents purchase or customer allocation")
	check(Neighborhood.LOT.end.y<0,"rear parking never consumes existing buildable cafe tiles")
	check(-Neighborhood.LOT.end.y*39.0-128.0>20.0,"entire lot ground clears projected full-height rear wall")
	check(Neighborhood.PEDESTRIAN_LINK.size.x>=.88 and is_equal_approx(Neighborhood.PEDESTRIAN_LINK.position.y,Neighborhood.LOT.end.y),"clear pedestrian link reaches lot with guest-width clearance")
	for pocket in Neighborhood.BUFFER_PLANTING:check(not Neighborhood.PEDESTRIAN_LINK.has_point(pocket),"low planting leaves pedestrian link clear")
	for bay in hooks.bay_centers:check(Neighborhood.LOT.has_point(bay),"future bay anchor stays inside separate lot")
	check(is_equal_approx(Neighborhood.MOUTH.position.x,Neighborhood.ROAD_RIGHT) and is_equal_approx(Neighborhood.MOUTH.end.x,Neighborhood.LOT.position.x),"single short mouth directly joins existing road to lot")
	check(Neighborhood.TREES.size()==6,"sparse authored trees")
	check(Neighborhood.TREE_VARIANTS.size()==Neighborhood.TREES.size(),"each sparse tree has a deterministic silhouette identity")
	check(Neighborhood.greenery.trees.size()==3 and Neighborhood.greenery.pockets.size()==3,"distinct airy/columnar/sapling trees and fan/shrub/fern ground planting")
	check(Neighborhood.SHELTER_BOARDING.size.x>=.88 and Neighborhood.SHELTER_BOARDING.position.x>=Neighborhood.SHELTER_ROOF.end.x,"open guest-width boarding corridor beyond roof supports")
	for pocket in Neighborhood.POCKETS:check(not Neighborhood.SHELTER_BOARDING.has_point(pocket),"ground planting never occupies shelter boarding corridor")
	var traffic=Traffic.new();var origin=Vector2(800,345);var tile=Vector2(33.54,16.77);var view=Rect2(0,0,1654,951)
	check(traffic.cars.size()==8,"bounded traffic pool")
	var before=traffic.cars.duplicate(true)
	for invalid in [0.0,-1.0,NAN,INF]:traffic.advance(invalid,origin,tile,view)
	check(traffic.cars==before,"paused and invalid time preserve all cars")
	traffic.advance(2,Vector2(100000,100000),tile,view)
	check(traffic.cars==before and traffic.elapsed==0,"offscreen road suspends traffic")
	for frame in range(14400):
		traffic.advance(.25,origin,tile,view)
		for car in traffic.cars:check(car.position.y>=-84 and car.position.y<84 and (is_equal_approx(car.position.x,Traffic.LANES[0]) or is_equal_approx(car.position.x,Traffic.LANES[1])),"hour of traffic stays within road lanes and finite endpoints")
	check(traffic.cars.size()==8,"hour of traffic cannot grow pool")
	var one=Traffic.new();var split=Traffic.new();one.advance(31.75,origin,tile,view)
	for i in range(127):split.advance(.25,origin,tile,view)
	for i in range(8):check(one.cars[i].position.distance_to(split.cars[i].position)<.001,"frame slicing preserves cadence")
	print("ENVIRONMENT_RESULT ",JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
