extends SceneTree
const Model=preload("res://scripts/cafe_model.gd")
const GuestNav=preload("res://scripts/cafe_guest_navigation_review.gd")
const Nav=preload("res://scripts/cafe_navigation_candidate.gd")
var checks=0
var failures=[]
func _initialize():run.call_deferred()
func check(ok:bool,label:String):
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func run():
	var m=Model.new();m.items.clear();m.built_walls.clear();m.guest_navigation_enabled=true
	var route=m.Checkout.path(m,Vector2i(2,2),Vector2i(5,5))
	check(route.size()==4,"actual Checkout planner selects three indoor diagonal legs")
	for i in range(1,route.size()):check(Nav.can_step(GuestNav.snapshot(m),route[i-1],route[i]),"each selected leg has orthogonal clearance")
	m.items.append({"id":50,"kind":"plant","x":3,"z":2,"rot":0});m.revision+=1
	check(not GuestNav.leg_clear(m,Vector2(2.5,2.5),Vector2(3.5,3.5)),"blocked orthogonal furniture forbids diagonal corner")
	var bypass=m.path_between(Vector2i(2,2),Vector2i(5,5))
	check(not bypass.is_empty() and bypass[1]!=Vector2i(3,3),"Model planner routes around blocked furniture corner")
	m.items.clear();m.revision+=1
	m.built_walls.append({"id":1,"axis":"x","x":3,"z":3,"height":"full","material":"original"})
	check(not GuestNav.leg_clear(m,Vector2(2.5,2.5),Vector2(3.5,3.5)),"real wall edge forbids adjacent diagonal")
	m.built_walls.clear()
	check(GuestNav.leg_clear(m,Vector2(2.5,2.5),Vector2(3.5,3.5)),"direct wall removal invalidates geometry cache")
	check(not GuestNav.leg_clear(m,Vector2(-.5,4.5),Vector2(.5,5.5)),"exterior door crossing cannot borrow indoor diagonal authority")
	check(not GuestNav.leg_clear(m,Vector2(2.5,2.5),Vector2(5.5,5.5)),"long diagonal cannot skip cells")
	check(GuestNav.leg_clear(m,Vector2(2.8,2.8),Vector2(3.5,3.5)),"continuous fractional suffix of legal diagonal remains valid")
	check(not GuestNav.leg_clear(m,Vector2(2.8,2.7),Vector2(3.5,3.5)),"off-line body cannot invent diagonal origin")
	m.items.append({"id":10,"kind":"chair","x":5,"z":5,"rot":0})
	m.items.append({"id":11,"kind":"table","x":6,"z":5,"rot":0});m.revision+=1
	m.rebuild_dining_sets()
	check(not GuestNav.leg_clear(m,Vector2(4.5,4.5),Vector2(5.5,5.5),10,10),"diagonal chair contact never gains furniture exception")
	check(GuestNav.leg_clear(m,Vector2(4.5,5.5),Vector2(5.5,5.5),-1,10),"exact cardinal seat contact is legal")
	check(GuestNav.leg_clear(m,Vector2(4.9,5.5),Vector2(4.5,5.5),10,-1),"own-chair shoulder overlap remains legal during cardinal dismount")
	var unclaimed={"id":8,"chair_id":-1,"previous_chair_id":10,"phase":"leaving","x":4.9,"z":5.5,"route":[Vector2(4.5,5.5)],"route_index":0,"route_origin":Vector2(4.9,5.5),"heading":Vector2.LEFT,"ready_order":0,"waiting":false}
	m.Reception._move(m,unclaimed,.02)
	check(unclaimed.x<4.9 and unclaimed.previous_chair_id==10,"released reception chair retains only current shoulder-clearance authority")
	m.Reception._move(m,unclaimed,.3)
	check(unclaimed.route.is_empty() and unclaimed.previous_chair_id==-1,"old reception contact authority is erased after physical clearance")
	var points:Array[Vector2]=[]
	for cell in m.Checkout.path(m,Vector2i(2,2),Vector2i(4,5)):points.append(m.cell_center(cell))
	points.append(Vector2(5.5,5.5))
	var g={"id":1,"table_id":11,"chair_id":10,"x":2.5,"z":2.5,"phase":"arriving","route":points,"route_index":0,"heading":Vector2.DOWN,"elapsed":0.0,"duration":8.0,"waiting":false,"departure_blocked":false,"dismounting":false,"withdrawn":false,"seated":false,"admitted":true,"paid":false}
	m.customers.assign([g])
	for i in 100:
		if g.phase=="arriving":m._advance_walk(g,.1)
	check(g.phase=="ordering" and g.seated and Vector2(g.x,g.z)==Vector2(5.5,5.5),"actual Model walk arrives at same claimed chair exactly once")
	check(int(g.id)==1 and int(g.chair_id)==10 and int(g.table_id)==11,"seat identity and ownership retained")
	g.phase="arriving";g.x=2.5;g.z=2.5;g.route=points.duplicate();g.route_index=0;g.elapsed=7.25
	m.get_item(10).z=6;m.get_item(11).z=6;m.rebuild_dining_sets()
	check(GuestNav.repair(m,g) and g.route[-1]==Vector2(5.5,6.5) and g.elapsed==7.25,"moved seat reroutes to same immutable chair without clock reset")
	var conflict=g.duplicate(true);conflict.id=9;m.customers.append(conflict)
	var claimed_before=g.route.duplicate()
	check(not GuestNav.repair(m,g) and g.route==claimed_before,"conflicting chair claim cancels movement without route mutation")
	m.customers.assign([g]);m.get_item(10).z=5;m.get_item(11).z=5;m.rebuild_dining_sets()
	var moving={"id":2,"chair_id":-1,"phase":"waiting_seat","x":2.5,"z":2.5,"route":[Vector2(3.5,3.5),Vector2(4.5,4.5),Vector2(5.5,4.5)],"route_index":0,"waiting":false}
	m.items.append({"id":51,"kind":"plant","x":3,"z":3,"rot":0});m.revision+=1
	check(GuestNav.repair(m,moving),"layout obstruction replaces route atomically at safe node")
	check(moving.route[0]!=Vector2(3.5,3.5) and moving.route[-1]==Vector2(5.5,4.5),"replan retains endpoint and discards blocked old leg")
	var trapped={"id":3,"chair_id":-1,"phase":"waiting_seat","x":2.8,"z":2.8,"route":[Vector2(3.5,3.5)],"route_index":0,"waiting":false}
	var before=Vector2(trapped.x,trapped.z)
	check(not GuestNav.repair(m,trapped) and Vector2(trapped.x,trapped.z)==before,"unsafe mid-leg remains frozen without snapping")
	m.items=m.items.filter(func(item):return int(item.id)!=51)
	var safe_leg={"id":3,"chair_id":-1,"phase":"waiting_seat","x":2.8,"z":2.8,"route":[Vector2(3.5,3.5),Vector2(4.5,4.5)],"route_index":0,"waiting":false}
	m.items.append({"id":52,"kind":"plant","x":4,"z":4,"rot":0})
	check(GuestNav.repair(m,safe_leg) and Vector2(safe_leg.x,safe_leg.z)==Vector2(2.8,2.8),"future obstruction allows only the still-legal current leg")
	safe_leg.x=3.5;safe_leg.z=3.5;safe_leg.route_index=1
	check(not GuestNav.repair(m,safe_leg),"blocked immutable endpoint waits at next safe waypoint")
	m.items.clear();m.customers.clear()
	var crossers=[]
	for reverse in [false,true]:
		var start=Vector2(5.5,5.5) if reverse else Vector2(2.5,2.5)
		var finish=Vector2(2.5,2.5) if reverse else Vector2(5.5,5.5)
		var cross=g.duplicate(true);cross.id=6 if reverse else 5;cross.chair_id=-1;cross.table_id=-1
		cross.phase="checkout_walk";cross.x=start.x;cross.z=start.y;cross.checkout_cell=Vector2i(finish.floor())
		cross.route=[];cross.elapsed=7.25;cross.mobility={"kind":"to_checkout","origin":start,"route":m.FurnitureMotion.route_to(m,start,cross.checkout_cell),"route_index":0}
		crossers.append(cross)
	m.customers.assign(crossers)
	for tick in 100:
		for cross in crossers:
			if not cross.mobility.is_empty():m.FurnitureMotion.advance(m,cross,.1)
	check(crossers.all(func(cross):return cross.mobility.is_empty() and Vector2(cross.x,cross.z)==m.cell_center(cross.checkout_cell) and cross.elapsed==7.25),"two actual opposing mobility consumers both arrive with unchanged service clocks")
	var other={"id":4,"phase":"arriving","x":2.6,"z":2.6};m.customers.assign([moving,other])
	check(GuestNav.speed_scale(m,moving)==.85,"crossing actor receives positive soft speed without hard lock")
	var file="user://synthetic_guest_nav_refusal.json";FileAccess.open(file,FileAccess.WRITE).store_string("synthetic control")
	check(not m.save(file) and FileAccess.get_file_as_string(file)=="synthetic control" and not FileAccess.file_exists(file+".tmp"),"default save refuses transient route before writes")
	check(not m.save_reception(file) and FileAccess.get_file_as_string(file)=="synthetic control","private18 writer cannot serialize diagonal capability")
	check(not Model.SaveContract.accepts_version(19,true),"unagreed19 is not accepted by existing contract")
	var main=load("res://scripts/main.gd").new();root.add_child(main);main.set_process(false)
	check(main.navigation_review!=null and main.model.guest_navigation_enabled and main.model.reception_review_enabled,"actual Main strict native triple composition entry active")
	check(main.fresh_start and main.save_writes_suppressed,"actual Main keeps ordinary writes suppressed")
	main.navigation_review.tick();var epoch=main.navigation_review.epoch
	main.model.revision+=1;main.navigation_review.tick()
	check(main.navigation_review.epoch==epoch,"service-only revision does not rebuild staff geometry or cancel search epoch")
	main.model.items.append({"id":1000,"kind":"plant","x":8,"z":8,"rot":0});main.navigation_review.tick()
	check(main.navigation_review.epoch==epoch+1,"actual geometry mutation invalidates shared staff snapshot")
	main.navigation_review.stop();main.queue_free();await process_frame
	print("GUEST_NAVIGATION_REVIEW_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
