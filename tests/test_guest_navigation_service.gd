extends SceneTree
const Reception=preload("res://scripts/cafe_reception.gd")
class ReviewMain extends "res://scripts/main.gd":
	var allow_cleanup=false
	func _load_startup():
		save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
		model.first_guest_pending=false;model.first_guest_start=Vector2.INF
	func _cleanup_ready(guest:Dictionary)->bool:return allow_cleanup and super._cleanup_ready(guest)
var checks=0
var failures=[]
var captures=[]
func _initialize():
	create_timer(100).timeout.connect(func():printerr("GUEST_NAV_SERVICE_TIMEOUT");quit(2))
	run.call_deferred()
func check(ok,label):
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func diagonal(route:Array,origin:Vector2=Vector2.INF)->bool:
	var previous=origin
	for point in route:
		if previous.is_finite() and absf(previous.x-point.x)>.001 and absf(previous.y-point.y)>.001:return true
		previous=point
	return false
func run():
	root.size=Vector2i(1360,880)
	var game=ReviewMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false)
	check(game.navigation_review!=null and game.model.guest_navigation_enabled and game.model.reception_review_enabled,"real Main native composition enabled")
	game.model.set_operating_open(true)
	check(Reception.add(game.model),"original physical admission request accepted")
	var second=false;var new_id=-1;var old_id=-1;var old_token=-1
	var guest_diagonal=false;var staff_diagonal=false;var claim_error=false;var ordered=false;var wiping=false
	var paid_id=-1;var saw_departure_body=false;var body_finished=false;var walking_capture=false;var departure_capture=false
	for frame in 3600:
		if frame%100==0:
			print("GUEST_NAV_SERVICE_PROGRESS ",JSON.stringify({"frame":frame,"served":game.model.served,"guest_phases":game.model.customers.map(func(g):return [g.id,g.phase,g.x,g.z,g.route_index,g.route]),"visitors":game.model.reception_visits.map(func(v):return [v.id,v.phase]),"departures":game.model.departing_bodies.size()}))
			await process_frame
		game.model._arrival_elapsed=0;game._tick_live_service(.1);game._animate_staff(.1)
		for guest in game.model.customers:
			if guest.phase=="leaving" and guest.paid:
				paid_id=int(guest.id)
				if not departure_capture:
					await capture(game,"paid-physical-departure");departure_capture=true
		if paid_id>=0:
			if game.model.departing_bodies.any(func(body):return int(body.id)==paid_id):saw_departure_body=true
			elif saw_departure_body:body_finished=true
		for visitor in game.model.reception_visits:
			guest_diagonal=guest_diagonal or diagonal(visitor.route,visitor.route_origin)
			if not walking_capture and int(visitor.chair_id)>=0 and not visitor.route.is_empty() and absf(visitor.heading.x)>.001 and absf(visitor.heading.y)>.001:
				await capture(game,"guest-diagonal-seat-approach");walking_capture=true
			if visitor.phase=="waiting_cleaning" and visitor.seated and new_id<0:
				new_id=int(visitor.id);old_id=int(visitor.cleanup_owner_id);old_token=int(game.service_guests[old_id].token)
				check(not game.service_guests.has(new_id),"new chair owner waits without borrowing old meal")
				await capture(game,"dirty-chair-original-cleanup")
				game.allow_cleanup=true
		for record in game.navigation_review.actors.values():
			if not record.follower.is_empty():
				var points=[]
				for cell in record.follower.plan.route:points.append(game.model.cell_center(cell))
				staff_diagonal=staff_diagonal or diagonal(points)
		if not game.model.TableOccupancy.inspect(game.model).error.is_empty():claim_error=true
		if not second and game.model.customers.any(func(g):return g.phase in ["dirty","cleaning"]):second=Reception.add(game.model)
		if old_id>=0:
			for staff in game.staff_states:
				if staff.job_kind=="cleanup" and int(staff.job_guest_id)==old_id:
					if int(staff.job_token)!=old_token:claim_error=true
					if staff.art_action=="wiping":wiping=true
			if not game.service_guests.has(old_id) and game.service_guests.has(new_id):ordered=true;break
	check(guest_diagonal,"actual reception route contains indoor diagonal movement")
	check(staff_diagonal,"actual staff service route contains diagonal movement")
	check(not claim_error,"exclusive seat ownership and cleanup token remain authoritative")
	check(ordered and wiping,"same waiting visitor resumes ordering after actual staff cleanup")
	check(game.model.served==1 and game.model.total_earned==game.Model.MEAL_PAYMENT,"one completed meal earns exactly one original payment")
	check(paid_id==old_id and saw_departure_body,"same paid identity transfers to physical departing body before cleanup ownership ends")
	check(body_finished and not game.model.departing_bodies.any(func(body):return int(body.id)==paid_id),"paid body completes street departure without a duplicate diner before replacement service")
	check(game.model.ReceptionReview.scope_allowed()==false,"old private18 gate still refuses composition flags")
	check(not game.model.save_reception("user://composition-refusal.json") and not FileAccess.file_exists("user://composition-refusal.json"),"private18 cannot serialize combined diagonals")
	var staff_receipt=[]
	for staff in game.staff_states:staff_receipt.append({"pos":staff.pos,"destination":staff.destination,"job":staff.job_kind,"step":staff.job_step,"elapsed":staff.job_elapsed,"blocked":staff.blocked_reason})
	print("GUEST_NAV_SERVICE_STATE ",JSON.stringify(game.Model.RuntimeCodec.new().encode({"customers":game.model.customers,"visitors":game.model.reception_visits,"departures":game.model.departing_bodies,"staff":staff_receipt,"served":game.model.served,"earned":game.model.total_earned})))
	var out=OS.get_environment("LL_RECEPTION_CAPTURE")
	if not out.is_empty():FileAccess.open(out+"/frames.json",FileAccess.WRITE).store_string(JSON.stringify(captures,"  "))
	game.queue_free();await process_frame;await process_frame
	print("GUEST_NAVIGATION_SERVICE_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"guest_diagonal":guest_diagonal,"staff_diagonal":staff_diagonal,"served":1 if ordered else 0,"paid_id":paid_id,"departing_body_observed":saw_departure_body,"body_finished":body_finished,"frames":captures.size()}))
	quit(0 if failures.is_empty() else 1)

func capture(game,label:String):
	var out=OS.get_environment("LL_RECEPTION_CAPTURE")
	if out.is_empty():return
	game._update_ui();game.illustration._process(.1);game.illustration.queue_redraw()
	for frame in 5:await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(out+"/"+label+".png")==OK,label+" actual viewport captured")
	captures.append({"label":label,"customers":game.Model.RuntimeCodec.new().encode(game.model.customers),"visitors":game.Model.RuntimeCodec.new().encode(game.model.reception_visits),"departures":game.Model.RuntimeCodec.new().encode(game.model.departing_bodies),"served":game.model.served,"earned":game.model.total_earned})
