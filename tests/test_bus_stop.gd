extends SceneTree
const Stop=preload("res://scripts/bus_stop_pedestrians.gd")
const Neighborhood=preload("res://scripts/exterior_environment.gd")
const Model=preload("res://scripts/cafe_model.gd")
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
