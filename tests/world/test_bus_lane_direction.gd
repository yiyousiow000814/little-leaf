extends SceneTree
const Neighborhood=preload("res://scripts/world/exterior_environment.gd")
const Traffic=preload("res://scripts/world/ambient_road_traffic.gd")
const Fixture=preload("res://tests/world/test_parking_render.gd")
var checks=0
var failures=[]
func check(ok:bool,label:String):
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func _init():
	var traffic=Traffic.new()
	var adjacent=traffic.cars[1]
	check(is_equal_approx(adjacent.position.x,Traffic.LANES.min()),"nearest traffic lane is the curb-side negative-z lane")
	var position:Vector2=adjacent.position
	traffic.advance(.25,Vector2(800,345),Vector2(33.54,16.77),Rect2(0,0,1654,951))
	check(adjacent.position.y<position.y and adjacent.direction==Neighborhood.BUS_DIRECTION,"bus direction agrees with actual adjacent-lane movement")
	var art=Fixture.Recorder.new()
	Neighborhood.draw_bus(art,Neighborhood.BUS_POSITION)
	var legacy=art.commands.duplicate(true)
	art.commands=[];Neighborhood.draw_bus(art,Neighborhood.BUS_POSITION,1)
	check(art.commands==legacy,"default positive-z illustration remains backward compatible")
	check(legacy.filter(func(c):return c.color is String and c.color=="f0e7c8").size()==2,"positive-z facing retains original paired headlights")
	art.commands=[];Neighborhood.draw_bus(art,Neighborhood.BUS_POSITION,Neighborhood.BUS_DIRECTION)
	var reversed=art.commands.duplicate(true)
	check(reversed.filter(func(c):return c.color is String and c.color=="b8816f").size()==2,"negative-z bus shows paired rear lights on the visible end")
	check(not reversed.any(func(c):return c.color is String and c.color in ["f0e7c8","657b72","74866d"]),"rear does not show headlights, wipers or front destination board")
	check(reversed.filter(func(c):return c.color is String and c.color in ["e1d9bb","eee4c8","627064"])==legacy.filter(func(c):return c.color is String and c.color in ["e1d9bb","eee4c8","627064"]),"original body, roof and wheel commands stay identical")
	check(reversed.filter(func(c):return c.color is String and c.color in ["6f857b","bbc8b8"])==legacy.filter(func(c):return c.color is String and c.color in ["6f857b","bbc8b8"]),"existing curb-side boarding door stays identical")
	art.commands=[];Neighborhood.draw_props(art)
	check(art.commands.filter(func(c):return c.color is String and c.color=="b8816f").size()==2,"actual production props use the curb-side bus direction")
	art.commands=[];Neighborhood.draw_props(art,Callable(),Callable(),false)
	check(not art.commands.any(func(c):return c.color is String and c.color in ["b8816f","e1d9bb"]),"Decorate still suppresses the entire bus")
	art.commands=[];Neighborhood.draw_props(art)
	check(art.commands.filter(func(c):return c.color is String and c.color=="b8816f").size()==2,"Done restores the correctly facing bus")
	print("BUS_LANE_DIRECTION_RESULT ",JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
