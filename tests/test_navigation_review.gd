extends SceneTree
const Main=preload("res://scripts/main.gd")
const Review=preload("res://scripts/cafe_navigation_review.gd")
const Nav=preload("res://scripts/cafe_navigation_candidate.gd")
var checks=0
var failures=[]
func _initialize():run.call_deferred()
func check(ok:bool,label:String):
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func run():
	root.size=Vector2i(1360,880)
	check(OS.get_environment("XDG_DATA_HOME")!="" and OS.get_user_data_dir().begins_with(OS.get_environment("XDG_DATA_HOME")),"disposable profile")
	var game=Main.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false)
	if OS.get_environment("LL_NAV_INACTIVE")=="1":
		check(game.navigation_review==null and not Review.allowed(game),"either missing flag keeps Main inactive")
		await finish(game,0.0,false);return
	check(game.navigation_review!=null and Review.allowed(game),"actual Main activates with both flags")
	game.fresh_start=false;check(not Review.allowed(game),"fresh startup required");game.fresh_start=true
	game.save_writes_suppressed=false;check(not Review.allowed(game),"save suppression required");game.save_writes_suppressed=true
	game.model._spawn_customer()
	var diagonal=false
	var seconds=0.0
	for frame in range(4000):
		var positions=[]
		for staff in game.staff_states:positions.append(staff.pos)
		game.model._arrival_elapsed=0.0;game._tick_live_service(.1);game._animate_staff(.1);game.animation_time+=.1;seconds+=.1
		for index in range(mini(positions.size(),game.staff_states.size())):
			var direction:Vector2=game.staff_states[index].pos-positions[index]
			if absf(direction.x)>.00001 and absf(direction.y)>.00001:diagonal=true
		if game.model.served==1:break
	check(diagonal,"actual staff/cashier transit consumes diagonal route")
	check(game.model.served==1 and game.model.total_earned==game.model.MEAL_PAYMENT,"real fresh customer served and paid through original contacts")
	check(not game.model.customers.is_empty() and not game.model.customers[0].meal_abandoned,"original meal timing retains customer")
	var old_epoch=game.navigation_review.epoch
	game.model.revision+=1;game._animate_staff(.1)
	check(game.navigation_review.epoch>old_epoch,"Main invalidates snapshot after layout revision")
	# A generated transit context exercises actual adapter cancellation/replan.
	game.navigation_review.stop();game.model.items.clear();game.model.revision+=1;game.navigation_review.tick()
	var route=[]
	for a in game.navigation_review.snapshot.cells:
		for b in game.navigation_review.snapshot.cells:
			var planned=Nav.plan(game.navigation_review.snapshot,a,b)
			if planned.route.size()>=5:route=planned.route;break
		if not route.is_empty():break
	check(not route.is_empty(),"synthetic legal transit available")
	if not route.is_empty():
		var staff:Dictionary=game.staff_states[0];game._clear_service_job(staff)
		staff.pos=Nav.center(route[0]);staff.destination=route[-1]
		for frame in range(30):
			game.navigation_review.tick()
			var motion=game.navigation_review.move(staff,0,staff.destination,.03);staff.pos=motion.position
			if staff.pos.distance_to(Nav.center(route[0]))>.001:break
		var anchor:Vector2=Nav.center(route[1])
		var obstacle:Vector2i=route[3]
		game.model.items.append({"id":99999,"kind":"chair","x":obstacle.x,"z":obstacle.y,"rot":0})
		game.model.revision+=1;game.navigation_review.tick()
		var reached_anchor=false;var legal=true
		for frame in range(600):
			game.navigation_review.tick()
			var before:Vector2=staff.pos
			var motion=game.navigation_review.move(staff,0,staff.destination,.03);staff.pos=motion.position
			if staff.pos.distance_to(anchor)<.000001:reached_anchor=true
			legal=legal and Nav.sweep_clear(game.navigation_review.snapshot,before,staff.pos)
			if motion.status=="arrived":break
		check(reached_anchor,"future obstruction completes legal current leg to safe anchor")
		check(legal and staff.pos.distance_to(Nav.center(staff.destination))<.000001,"replan reaches original endpoint without crossing new furniture")
	game._save()
	check(game.save_writes_suppressed,"native save guard retained")
	game.navigation_review.stop()
	check(game.navigation_review.actors.is_empty(),"lifecycle cancels all owned transient followers")
	await finish(game,seconds,diagonal)
func finish(game,seconds:float,diagonal:bool):
	print("NAVIGATION_REVIEW_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"payment_seconds":seconds,"diagonal":diagonal,"player_save_used":false}))
	for player in game.audio_players.values():player.stop();player.stream=null
	game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
	for tween in get_processed_tweens():tween.kill()
	game.queue_free();await process_frame;await process_frame
	quit(0 if failures.is_empty() else 1)
