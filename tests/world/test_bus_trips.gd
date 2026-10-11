extends SceneTree
const Stop=preload("res://scripts/bus_stop_pedestrians.gd")
const N=preload("res://scripts/exterior_environment.gd")
const Art=preload("res://tests/test_parking_render.gd")
var checks=0
var failures=[]
func check(ok:bool,label:String):
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func run():
	var stop=Stop.new();var period:float=stop.actors[0].period
	check(stop.actors.size()==6 and stop.actors.all(func(a):return a.period==period) and is_equal_approx(period,189.342857142857),"fixed two groups retain old three-visits-per-period frequency")
	check(is_equal_approx(3*60/period,.950656428),"boarding and alighting rates remain approximately 0.951/minute")
	check(stop.bus_snapshot().state=="stopped" and stop.bus_snapshot().position==N.BUS_POSITION,"arrival aligns bus and occluded far-side door")
	check(stop.actors.slice(0,3).all(func(a):return a.state=="waiting") and stop.actors[3].state=="alighting","different fixed groups wait and alight at arrival")
	var stop_time:float=stop.bus_snapshot().dwell
	check(stop.actors.slice(0,3).all(func(a):return a.board_start+a.boarding<=stop_time+.00001),"dwell covers every independently planned boarding journey")
	var geometry_ok=true;var monotonic=true;var door_ok=true;var pool_ok=true
	var previous={};var states={};var boards={};var exits={}
	# One finite presentation cycle, not a simulation soak or diagnostic matrix.
	for step in range(758):
		stop.elapsed=step*period/757.0
		for actor in stop.actors:stop._set_actor(actor)
		var bus=stop.bus_snapshot();states[bus.state]=true
		if bus.visible:
			var rear:Vector2=-bus.heading;var side=Vector2(rear.y,-rear.x)
			for x in [-.85,.85]:
				for i in range(41):
					var point:Vector2=bus.position+side*x+rear*lerpf(-2.7,2.7,i/40.0)
					geometry_ok=geometry_ok and point.x>=N.pavement_edges(point.y).y-.00001 and point.x<=-6.01
			if not previous.is_empty() and previous.state==bus.state and bus.state in ["approaching","departing"]:monotonic=monotonic and bus.position.y<previous.position.y
		for actor in stop.actors:
			pool_ok=pool_ok and (not actor.visible or Stop.walkable(actor.position))
			if actor.state=="boarding":boards[actor.key]=true;door_ok=door_ok and bus.state=="stopped"
			if actor.role=="alighting" and actor.visible:
				exits[actor.key]=true
				if actor.position.x>Stop.WALK_X and absf(actor.position.y-N.BUS_DOOR.y)<.01:door_ok=door_ok and bus.state=="stopped"
		previous=bus
	check(geometry_ok,"complete bus footprint clears curved curb and stays in the negative-z half-road")
	check(monotonic and states.size()==4,"continuous negative-z approach/departure separated by offscreen trip interval")
	check(door_ok and boards.size()==3 and exits.size()==3,"all three board and three different people alight only beside stopped bus")
	check(pool_ok and stop.actors.size()==6,"fixed groups stay on existing walkable routes")
	var aligned=true;var dense_clear=true;var min_clearance=INF
	var recorder=Art.Recorder.new()
	for state in ["approaching","departing"]:
		var span=Stop.APPROACH_LENGTH if state=="approaching" else Stop.DEPART_LENGTH
		for sample in range(1001):
			var z=N.BUS_POSITION.y+span*sample/1000.0*(1 if state=="approaching" else -1)
			var path=Stop.bus_path(z,state);var next=Stop.bus_path(z-.0028,state)
			var velocity:Vector2=(next.position-path.position).normalized()
			var projection=N.BusProjection.new(recorder,path.position,path.heading)
			var forward:Vector2=projection.iso(0,-2.6)-projection.iso(0,0)
			var tangent=Vector2(velocity.x-velocity.y,(velocity.x+velocity.y)*.5)
			var axles:Vector2=projection.iso(.77,-1.72)-projection.iso(.77,1.66)
			aligned=aligned and absf(forward.angle_to(tangent))<.001 and absf(axles.angle_to(tangent))<.001
			var rear:Vector2=-path.heading;var side=Vector2(rear.y,-rear.x)
			for x in [-.85,.85]:
				for depth in range(41):
					var point:Vector2=path.position+side*x+rear*lerpf(-2.7,2.7,depth/40.0)
					var clearance=minf(point.x-N.pavement_edges(point.y).y,-6.01-point.x)
					min_clearance=minf(min_clearance,clearance);dense_clear=dense_clear and clearance>=-.00001
	check(aligned,"dense approach/departure body and wheel-axis projection agrees with actual path tangent")
	check(dense_clear,"rotated full shadow/body footprint clears curved curb and center line at 2002 samples")
	check(N.BUS_DOOR.is_equal_approx(N.BUS_POSITION+Vector2(-.795,2.0)),"far-side doorway anchor follows original door geometry and shifted bus center")
	stop.elapsed=0
	var saved=stop.actors.duplicate(true)
	for delta in [0.0,-1.0,NAN,INF]:stop.advance(delta,Vector2(800,345),Vector2(33.54,16.77),Rect2(0,0,1654,951))
	check(stop.elapsed==0 and stop.actors==saved,"inactive/invalid deltas retain clock and actors")
	stop.advance(3,Vector2(100000,100000),Vector2(33.54,16.77),Rect2(0,0,1654,951))
	check(stop.elapsed==0,"existing offscreen gate also freezes derived bus")
	var whole=Stop.new();var sliced=Stop.new()
	whole.advance(31.75,Vector2(800,345),Vector2(33.54,16.77),Rect2(0,0,1654,951))
	for i in range(127):sliced.advance(.25,Vector2(800,345),Vector2(33.54,16.77),Rect2(0,0,1654,951))
	check(whole.bus_snapshot()==sliced.bus_snapshot() and whole.actors==sliced.actors,"frame slicing preserves trip and both groups")
	var art=Art.Recorder.new()
	N.draw_props(art,Callable(),Callable(),false,whole.draw_bus.bind(art))
	check(not art.commands.any(func(c):return c.color is String and c.color=="e1d9bb"),"Decorate prevents moving-bus callback")
	art.commands=[];N.draw_props(art,Callable(),Callable(),true,stop.draw_bus.bind(art))
	check(art.commands.filter(func(c):return c.color is String and c.color=="b8816f").size()==2,"Done draws original negative-z rear marking")
	# Same production retained slot: translation must not invalidate body ink.
	var artist=load("res://scripts/illustrated_cafe.gd").new();root.add_child(artist);artist.set_process(false)
	artist.origin=Vector2(1180,570);artist.tile=Vector2(33.54,16.77);artist.ui_scale=.86
	var people_calls=[0]
	artist.canvas_stream.begin(artist,true)
	N.draw_oriented_bus(artist,N.BUS_POSITION,Vector2.UP,func():people_calls[0]+=1)
	var node=artist.native_object_nodes[0];var retained_ref=weakref(node)
	var key=node.appearance.duplicate(true);var first_transform=node.transform
	for i in range(32):
		artist.canvas_stream.begin(artist,true)
		N.draw_oriented_bus(artist,N.BUS_POSITION+Vector2(0,-i*.1),Vector2.UP,func():people_calls[0]+=1)
	check(artist.native_object_nodes.size()==1 and artist.native_object_nodes[0]==node,"moving bus reuses one retained painter slot")
	check(node.appearance==key and node.transform!=first_transform,"translation changes placement without body invalidation")
	check(people_calls[0]==33,"far-side people callback remains outside retained body and runs every frame")
	artist.canvas_stream.begin(artist,true)
	N.draw_oriented_bus(artist,N.BUS_POSITION,Vector2(-.25,-1).normalized())
	check(node.appearance!=key and artist.native_object_nodes.size()==1,"turn invalidates heading geometry without allocating a new retained slot")
	artist.canvas_stream.begin(artist,true)
	# Translated shelter art uses the same two bounded owner-managed slots.
	for frame in range(32):
		artist.canvas_stream.begin(artist,true)
		N.draw_shelter(N.ShelterProjection.new(artist))
	check(artist.native_object_nodes.size()==2,"translated shelter keeps two retained painter slots across repeated draws")
	var shelter_ref=weakref(artist.native_object_nodes[1])
	artist.canvas_stream.begin(artist,true)
	# Standalone artists intentionally bypass culling; use a live owner here.
	artist.game=Art.TestGame.new()
	artist.art_transform(Vector2.ZERO)
	N.draw_oriented_bus(artist,Vector2(100000,100000),Vector2.UP)
	check(artist.canvas_stream.cursor==0,"bus world culling precedes retained callback")
	artist.game.free();artist.game=null
	artist.queue_free();await process_frame;await process_frame
	check(retained_ref.get_ref()==null,"artist teardown releases retained bus painter")
	check(shelter_ref.get_ref()==null,"artist teardown releases translated shelter painter")
	print("BUS_TRIPS_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"period":period,"dwell":stop_time,"minimum_rotated_clearance":min_clearance}));quit(0 if failures.is_empty() else 1)
