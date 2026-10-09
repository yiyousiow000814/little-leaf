extends SceneTree
const Neighborhood=preload("res://scripts/exterior_environment.gd")
const Street=preload("res://scripts/street_pedestrians.gd")
const Visibility=preload("res://scripts/cafe_render_visibility.gd")
class Recorder extends RefCounted:
	var origin=Vector2(800,345)
	var ui_scale=1.0
	var zoom=1.0
	var detail=1.0
	var viewport=Rect2(0,0,1654,951)
	var culling=false
	var commands=[]
	func iso(x,z,h=0.0):return origin+Vector2((x-z)*39,(x+z)*19.5)*ui_scale*zoom-Vector2(0,h*ui_scale*zoom*detail)
	func get_viewport_rect():return viewport
	func render_bounds_visible(bounds):return not culling or Visibility.visible(bounds,viewport,6)
	func record(kind,bounds,data,color):commands.append({"bounds":bounds,"key":str([kind,data,color]),"color":color})
	func poly(points,color):record("poly",Visibility.points_bounds(points),points,color)
	func rounded_poly(points,r,color):record("rounded",Visibility.points_bounds(points),[points,r],color)
	func ellipse(p,size,color):record("ellipse",Rect2(p-size,size*2),[p,size],color)
	func line(a,b,color,width=1.0):record("line",Rect2(a,Vector2.ZERO).expand(b).grow(width*.5),[a,b,width],color)
	func draw_rect(rect,color):record("rect",rect,rect,color)
class ParkingModel extends RefCounted:
	var parking_owned=false
	var parking_visits:Array=[]
	var people:Array=[]
	func visual_customers()->Array:return people
class HistoricalModel extends RefCounted:
	func visual_customers()->Array:return []
class TestGame extends Node:
	var model
	var wall_detail=false
class StreetArt extends "res://scripts/illustrated_cafe.gd":
	var recorded=[]
	var characters=[]
	func _ready():set_process(false)
	func _draw():pass
	func art_transform(_offset:Vector2,_rotation:float=0.0,_scale:Vector2=Vector2.ONE):pass
	func poly(_points:Array,color):
		if color is String and color in ["a2b3b3","ddcdb0"]:recorded.append("car")
	func rounded_poly(_points:Array,_radius:float,color):
		if color is String and color in ["a2b3b3","ddcdb0"]:recorded.append("car")
	func ellipse(_point:Vector2,_size:Vector2,_color):pass
	func character(_p:Vector2,id:int,_staff=false,_moving=false,_seated=false,_action="idle",_progress=0.0,_reach=Vector2(18,-28),_look=Vector2(1,0),_payload="none",_tool="none",_pose={},_role="chef"):
		characters.append(id);recorded.append("guest_%s"%id)
var checks=0
var failures=[]
func check(ok:bool,label:String):
	checks+=1
	if not ok and failures.size()<30:failures.append(label);printerr("FAIL ",label)
func visible_keys(commands,viewport)->Array:
	var result=[]
	for command in commands:
		if Visibility.visible(command.bounds,viewport,2):result.append(command.key)
	return result
func _initialize():run.call_deferred()
func run():
	var visits:Array=[]
	var phases=["car_arriving","walking_in","queued","dining","walking_return","car_departing"]
	for index in phases.size():visits.append({"id":index+1,"bay":index%4,"phase":phases[index],"car_position":Vector2(1.3,-7.15),"car_heading":Vector2.DOWN})
	var snapshot=visits.duplicate(true)
	var entries=Neighborhood.parking_cars(visits)
	check(entries.size()==phases.size(),"one authoritative car for every live lifecycle phase")
	for index in entries.size():
		check(entries[index].id==visits[index].id and entries[index].position==visits[index].car_position and entries[index].heading==visits[index].car_heading,"car retains authoritative identity position and heading")
	check(visits==snapshot,"render entry preparation never changes parking authority")
	check(Neighborhood.parking_cars([]).is_empty(),"empty parking ledger has no decorative vehicles")
	check(Neighborhood.parking_cars([{"id":20,"phase":"retired","car_position":Vector2.ZERO}]).is_empty(),"retired visit is never drawn")
	check(Neighborhood.parking_cars([{"id":20,"phase":"dining","car_position":Vector2.INF}]).is_empty(),"nonfinite positions are not submitted to the renderer")
	var recorder=Recorder.new()
	# The complete lot is an owned upgrade, not ambient landscape.
	var model_for_ground=preload("res://scripts/cafe_model.gd").new()
	check(not model_for_ground.parking_owned,"fresh profile does not own parking")
	Neighborhood.draw_ground(recorder,model_for_ground.parking_owned);Neighborhood.draw_crossing(recorder,model_for_ground.parking_owned)
	var unbought=recorder.commands.duplicate(true)
	check(not unbought.any(func(command):return command.color in ["919f92","dce0ca","d3d9c1"]),"unbought lawn has no asphalt, bay markings or driveway crossing")
	model_for_ground.coins=10000;model_for_ground.begin_decoration_session()
	check(model_for_ground.buy_parking(),"buy parking in Decorate")
	recorder.commands=[];Neighborhood.draw_ground(recorder,model_for_ground.parking_owned);Neighborhood.draw_crossing(recorder,model_for_ground.parking_owned)
	var bought=recorder.commands.duplicate(true)
	for color in ["919f92","dce0ca","d3d9c1"]:
		check(bought.any(func(command):return command.color==color),"purchased parking reveals "+color)
	var path="user://parking-render-owned.json"
	check(model_for_ground.save(path),"save purchased parking in disposable profile")
	var reloaded=preload("res://scripts/cafe_model.gd").new()
	check(reloaded.load_save(path) and reloaded.parking_owned,"reload retains purchased parking")
	recorder.commands=[];Neighborhood.draw_ground(recorder,reloaded.parking_owned);Neighborhood.draw_crossing(recorder,reloaded.parking_owned)
	check(recorder.commands==bought,"reload renders identical purchased lot")
	check(model_for_ground.sell_parking() and model_for_ground.coins==10000,"same-session sale restores full refund")
	recorder.commands=[];Neighborhood.draw_ground(recorder,model_for_ground.parking_owned);Neighborhood.draw_crossing(recorder,model_for_ground.parking_owned)
	check(recorder.commands==unbought,"sale restores original unbought lawn commands")
	check(model_for_ground.save(path),"save sold parking")
	check(reloaded.load_save(path) and not reloaded.parking_owned,"reload retains sold parking")
	recorder.commands=[]
	Neighborhood.draw_props(recorder)
	check(not recorder.commands.any(func(command):return command.color is String and command.color in ["a2b3b3","ddcdb0"]),"static neighbourhood has no parked-car stand-ins")
	check(recorder.commands.any(func(command):return command.color is String and command.color=="e1d9bb"),"ambient bus illustration remains present")
	var at=Vector2(4.2,-7.15)
	for heading in [Vector2.DOWN,Vector2.UP,Vector2.RIGHT,Vector2.LEFT]:
		var projection=Neighborhood.CarProjection.new(recorder,at,heading)
		var front=at+heading*1.1
		check(projection.iso(0,1.1*projection.direction,14).distance_to(recorder.iso(front.x,front.y,14))<.001,"headlights face actual car travel direction")
		check(projection.iso(0,0,34).distance_to(recorder.iso(at.x,at.y,34))<.001,"world-axis turn keeps car roof vertically above ground")
		check(is_equal_approx(absf(projection.transverse.dot(projection.longitudinal)),0.0),"car body maintains orthogonal fixed-size footprint")
	var removed=0
	for viewport in [Rect2(0,0,390,844),Rect2(0,0,1360,880),Rect2(0,0,844,390)]:
		recorder.viewport=viewport
		for scale in [.25,1.0,4.0]:
			recorder.zoom=scale
			for detail in [1.0,1.55]:
				recorder.detail=detail
				for origin in [Vector2.ZERO,Vector2(390,250),Vector2(-1100,-700),Vector2(1800,1200),Vector2(0,880),Vector2(1360,0)]:
					recorder.origin=origin
					for heading in [Vector2.DOWN,Vector2.UP,Vector2.RIGHT,Vector2.LEFT]:
						recorder.culling=false;recorder.commands=[]
						Neighborhood.draw_oriented_car(recorder,at,heading,"a2b3b3")
						var baseline=recorder.commands.duplicate()
						recorder.culling=true;recorder.commands=[]
						Neighborhood.draw_oriented_car(recorder,at,heading,"a2b3b3")
						check(visible_keys(baseline,viewport)==visible_keys(recorder.commands,viewport),"oriented vehicle culling preserves visible drawing commands")
						removed+=baseline.size()-recorder.commands.size()
	check(removed>0,"oriented offscreen cars are culled")
	var guest={"id":7,"phase":"leaving","x":-.85,"z":12.4,"route":[Vector2(-.85,12.5)],"route_index":0,"heading":Vector2.DOWN,"parking_visit":true}
	var street=Street.new();snapshot=guest.duplicate(true)
	street.observe_customers([guest],.1,1.5)
	guest.phase="dirty";guest.z=12.5
	street.observe_customers([guest],.1,1.5)
	check(street.observed_leaving.is_empty() and street.departures.is_empty(),"parking guest marker suppresses street continuation after dirty phase")
	guest=snapshot.duplicate(true);guest.erase("parking_visit")
	street.observe_customers([guest],.1,1.5,[{"id":7}]);street.observe_customers([],.1,1.5,[{"id":7}])
	check(street.observed_leaving.is_empty() and street.departures.is_empty(),"parking ledger suppresses continuation when service guest disappears")
	street.observe_customers([guest],.1,1.5);street.observe_customers([],.1,1.5)
	check(street.departures.has(7),"ordinary walking guest still continues down pavement")
	street.motion.update("street_departure_7",Vector2(-.85,12.5),.1);street.active_motion["street_departure_7"]=true
	street.observe_customers([],.1,1.5,[{"id":7}])
	check(street.departures.is_empty() and not street.active_motion.has("street_departure_7") and not street.motion._actors.has("street_departure_7"),"restored parking ownership retires stale departure and motion rig")
	root.size=Vector2i(1654,951)
	var art=StreetArt.new();var game=TestGame.new();var model=ParkingModel.new()
	game.model=model;art.game=game;art.origin=Vector2(800,345);art.street_pedestrians.walkers.clear();root.add_child(art)
	model.parking_visits=[visits[0].duplicate(true)]
	art._draw_street_people(true)
	check(art.recorded.is_empty(),"unowned parking does not draw even a stale ledger")
	model.parking_owned=true;model.people=[{"id":1,"x":1.0,"z":-7.15,"phase":"parking_walk","heading":Vector2.DOWN},{"id":99,"x":1.9,"z":-7.15,"phase":"parking_walk","heading":Vector2.DOWN}]
	art._draw_street_people(true)
	check(art.characters==[1,99],"parking pedestrians use each same-ID original character exactly once")
	check(art.recorded.front()=="guest_1" and art.recorded.back()=="guest_99" and "car" in art.recorded,"cars and exterior people share ground-depth ordering")
	art.characters.clear();art.recorded.clear();art._draw_street_people(false)
	check(art.characters.is_empty() and "car" not in art.recorded,"editing hides service people and occupied vehicle")
	# Decorate hides every exterior person, not just authoritative customers.
	art.street_pedestrians=Street.new()
	for index in art.street_pedestrians.walkers.size():art.street_pedestrians.walkers[index].position=Vector2(-1,3) if index==0 else Vector2(-1,500)
	var people_before=model.people.duplicate(true);var visits_before=model.parking_visits.duplicate(true)
	var walkers_before=art.street_pedestrians.walkers.duplicate(true);var bus_before=art.bus_stop_pedestrians.actors.duplicate(true)
	art.characters.clear();art.recorded.clear()
	art._draw_street_people(false);art._draw_bus_stop_people(true,false);art._draw_bus_stop_people(false,false)
	check(art.characters.is_empty(),"Decorate hides ambient street, queue/parking guests and both bus-stop layers")
	check("car" not in art.recorded,"Decorate hides occupied car presentation")
	art._draw_street_people(true);art._draw_bus_stop_people(true,true);art._draw_bus_stop_people(false,true)
	check(art.characters.size()>model.people.size(),"Done restores ambient people as well as exterior customers")
	check("car" in art.recorded,"Done restores occupied car presentation")
	check(art.characters.any(func(id):return id>=400),"Done restores bus-stop visitors")
	check(model.people==people_before and model.parking_visits==visits_before and art.street_pedestrians.walkers==walkers_before and art.bus_stop_pedestrians.actors==bus_before,"hiding and restoring never deletes or resets people, queue or parking state")
	game.model=HistoricalModel.new()
	check(art._parking_visits().is_empty(),"historical controller without parking fails open to empty ledger")
	art.queue_free();game.free();await process_frame
	print("PARKING_RENDER_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"culled_commands":removed}));quit(0 if failures.is_empty() else 1)
