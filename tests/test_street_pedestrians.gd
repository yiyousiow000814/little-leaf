extends SceneTree
const Street=preload("res://scripts/street_pedestrians.gd")
const Model=preload("res://scripts/cafe_model.gd")
var checks=0
var failures=[]
var measurements={}
func check(ok:bool,label:String):
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)

func _init():call_deferred("run")
func run():
	var street=Street.new()
	check(street.walkers.size()==Street.COUNT,"bounded neighbourhood population")
	var seen={}
	for walker in street.walkers:
		check(not seen.has(walker.key),"unique ambient identity");seen[walker.key]=true
		check(walker.position.x> -3.26 and walker.position.x< -.26,"citizen stays on pavement")
		check(absf(walker.heading.y)==1.0 and walker.heading.x==0.0,"cardinal street route")
	var before=street.walkers.duplicate(true)
	street.advance(0.0);street.advance(-1.0);street.advance(NAN)
	check(street.walkers==before,"pause and invalid elapsed time preserve population")
	var step=.25
	var largest_jump=0.0
	for frame in range(14400):
		var previous=street.walkers.duplicate(true)
		street.advance(step)
		for i in range(Street.COUNT):
			var a=previous[i];var b=street.walkers[i]
			var travel=absf(b.position.y-a.position.y)
			if travel>1.0:
				check(absf(a.position.y)>Street.Z_MAX-1.0 and absf(b.position.y)>Street.Z_MAX-1.0,"recycle only at remote road ends")
			else:largest_jump=maxf(largest_jump,travel)
		check(street.walkers.size()==Street.COUNT,"one-hour pool remains bounded")
	measurements["one_hour_recycles"]=street.recycled
	measurements["largest_non_recycle_step"]=largest_jump
	var one=Street.new();var split=Street.new()
	one.advance(31.75)
	for i in range(127):split.advance(.25)
	for i in range(Street.COUNT):check(one.walkers[i].position.distance_to(split.walkers[i].position)<.001,"cadence independent of frame slicing")
	var departure=Street.new()
	var guest={"id":7,"phase":"leaving","x":-.85,"z":12.4,"route":[Vector2(-.85,12.5)],"route_index":0,"heading":Vector2.DOWN}
	var untouched=guest.duplicate(true)
	departure.observe_customers([guest],.1,1.5)
	check(guest==untouched and departure.departures.is_empty(),"observer cannot mutate or duplicate the live customer")
	guest.phase="dirty";guest.z=12.5
	departure.observe_customers([guest],.1,1.5)
	check(departure.departures.size()==1,"one post-service visual continuation")
	check(departure.departures[7].position==Vector2(-.85,12.5) and departure.departures[7].appearance==7,"handoff keeps exact endpoint and appearance")
	departure.observe_customers([guest],.1,1.5)
	check(departure.departures.size()==1,"repeated observation cannot clone a departure")
	departure.advance(.1)
	check(departure.departures[7].position.distance_to(Vector2(-.85,12.65))<.0001,"departure continues at original speed and lane")
	departure.advance(120.0)
	check(departure.departures.is_empty(),"departed history retires at remote road end")
	var cancelled=Street.new()
	guest.phase="leaving";guest.z=13.4;guest.route=[Vector2(-.85,13.5)]
	cancelled.observe_customers([guest],.1,1.5);cancelled.observe_customers([],.1,1.5)
	check(cancelled.departures.size()==1,"withdrawn customer removed by model continues once")
	var reset=Street.new();guest.z=5.0
	reset.observe_customers([guest],.1,1.5);reset.observe_customers([],.1,1.5)
	check(reset.departures.is_empty(),"unrelated model removal cannot fabricate an exit")
	var model=Model.new();var snapshot=[model.coins,model.customers.duplicate(true),model._arrival_elapsed,model._next_customer_id]
	var start=Time.get_ticks_usec()
	for frame in range(600):
		street.advance(1.0/60.0)
		street.update_motion(1.0/60.0,Vector2(290,160),Vector2(30,15),Rect2(0,0,390,844))
	measurements["mobile_update_usec_per_frame"]=float(Time.get_ticks_usec()-start)/600.0
	measurements["mobile_animated_rigs"]=street.active_motion.size()
	check(street.active_motion.size()<Street.COUNT,"mobile viewport animates only nearby citizens")
	check([model.coins,model.customers,model._arrival_elapsed,model._next_customer_id]==snapshot,"street has no simulation state or demand side effect")
	var bounded=Street.new()
	var phone_view=Rect2(0,0,844,390)
	var camera_origin=Vector2(450,220);var camera_tile=Vector2(4,2)
	var visible=bounded.entries(camera_origin,camera_tile,phone_view)
	check(visible.size()<=6 and visible.size()>0,"compact view renders at most six ambient citizens initially")
	var held=bounded.visible_ambient.duplicate()
	bounded.entries(camera_origin,camera_tile,phone_view)
	check(bounded.visible_ambient==held,"unchanged view keeps the same visible identities")
	var removed_key=bounded.visible_ambient.keys()[0]
	for walker in bounded.walkers:
		if walker.key==removed_key:walker.position=Vector2(-2.1,500)
	bounded.entries(camera_origin,camera_tile,phone_view)
	check(bounded.visible_ambient.size()==held.size()-1,"vacant slot cannot reveal an already-on-screen suppressed walker")
	var before_resize=bounded.visible_ambient.duplicate()
	bounded.entries(camera_origin,camera_tile,Rect2(0,0,1360,880))
	check(bounded.visible_ambient.size()<=8,"larger viewport remains globally bounded")
	for key in before_resize:check(bounded.visible_ambient.has(key),"resize retains each still-visible citizen")
	bounded.departures[99]={"key":"street_departure_99","appearance":99,"position":Vector2(-.85,0),"heading":Vector2.DOWN,"speed":1.5}
	var retained=bounded.entries(camera_origin,camera_tile,phone_view)
	check(retained.any(func(w):return w.key=="street_departure_99"),"a genuine guest departure never competes for an ambient slot")
	print("STREET_PEDESTRIANS_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"measurements":measurements}))
	quit(0 if failures.is_empty() else 1)
