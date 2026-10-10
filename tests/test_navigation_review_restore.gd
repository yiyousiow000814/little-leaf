extends SceneTree
const Main=preload("res://scripts/main.gd")
const Nav=preload("res://scripts/cafe_navigation_candidate.gd")
const Codec=preload("res://scripts/cafe_runtime_codec.gd")
const Contract=preload("res://scripts/cafe_save_contract.gd")
var checks=0
var failures=[]
var game
var codec=Codec.new()
var native="--native-observe" in OS.get_cmdline_user_args()
var output=OS.get_environment("LL_NAV_RESTORE_OUTPUT")
var frames=[]
func _initialize():root.size=Vector2i(1360,880);run.call_deferred()
func check(ok:bool,label:String):
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func same(a,b)->bool:
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		for key in a:
			if not b.has(key) or not same(a[key],b[key]):return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size():return false
		for index in a.size():
			if not same(a[index],b[index]):return false
		return true
	if (a is int or a is float) and (b is int or b is float):return float(a)==float(b)
	return a==b
func wire_same(a,b)->bool:
	# Godot JSON rounds double clocks; compare their actual codec wire precision.
	return same(JSON.parse_string(JSON.stringify(a)),JSON.parse_string(JSON.stringify(b)))
func step():
	game.model._arrival_elapsed=0.0
	if native:await create_timer(.05).timeout
	else:
		game._tick_live_service(.05);game._animate_staff(.05);game.animation_time+=.05
func capture(label:String):
	if not native:return
	game._update_ui();game._update_service_props();game.illustration.queue_redraw()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))
	frames.append({"file":label+".png","animation_time":game.animation_time,"staff":codec.encode(game._service_save_snapshot(true).staff)})
func checkpoint(label:String,phase:String,slot:int):
	game.set_process(false)
	var before=game._service_save_snapshot(true)
	var row:Dictionary=before.staff[slot]
	var wallet=[game.model.coins,game.model.total_earned,game.model.served,game.model.payroll_elapsed,game.model.payroll_accrued,game.model.wages_due,game.model.total_wages_paid]
	var guests=codec.encode(game.model.customers)
	check(row.navigation_phase==phase,label+" exports actual follower disposition")
	await capture(label+"-before")
	check(game.save_navigation_review(),label+" explicit synthetic v16 write: "+game.model.last_error)
	var wire=JSON.parse_string(FileAccess.get_file_as_string(Contract.STAFF_NAVIGATION_FILE))
	check(wire.version==16 and wire.navigation_format==Contract.STAFF_NAVIGATION_FORMAT,label+" capable envelope")
	check(game.load_navigation_review(),label+" actual Main capable restore: "+game.model.last_error)
	var after=game._service_save_snapshot(true)
	check(wire_same(codec.encode(before),codec.encode(after)),label+" routes/index/order/clocks/claims/payload ledgers preserved at codec wire precision")
	var exact_positions=true
	for index in before.staff.size():exact_positions=exact_positions and before.staff[index].pos==after.staff[index].pos
	check(exact_positions,label+" all actual staff positions preserved exactly")
	check(wire_same(guests,codec.encode(game.model.customers)) and wire_same(wallet,[game.model.coins,game.model.total_earned,game.model.served,game.model.payroll_elapsed,game.model.payroll_accrued,game.model.wages_due,game.model.total_wages_paid]),label+" guest payment state and economy preserved at codec wire precision")
	if not wire_same(codec.encode(before),codec.encode(after)):print("RESTORE_COMPARE ",JSON.stringify({"label":label,"before":codec.encode(before),"after":codec.encode(after)}))
	await capture(label+"-restored")
	game.set_process(native)
func run():
	var scope=OS.get_environment("LL_NAVIGATION_REVIEW_ROOT")
	if scope=="" or not "saveguard" in scope or not OS.get_user_data_dir().replace("\\","/").begins_with(scope.replace("\\","/")+"/"):printerr("Disposable generated profile required");quit(2);return
	if native and (output=="" or DisplayServer.get_name()=="headless"):quit(2);return
	game=Main.new();root.add_child(game);game.set_process(native)
	if not native:game.illustration.set_process(false)
	check(Contract.VERSION==15 and game.navigation_review!=null and game.save_writes_suppressed,"default15 and both native flags/save suppression retained")
	OS.set_environment("LL_NAVIGATION_REVIEW_ROOT","")
	check(not game.save_navigation_review() and not game.load_navigation_review(),"private persistence requires declared disposable profile")
	OS.set_environment("LL_NAVIGATION_REVIEW_ROOT",scope)
	game.model._spawn_customer()
	var slot=-1
	for frame in range(6000):
		await step()
		for index in game.navigation_review.actors:
			var record=game.navigation_review.actors[index]
			if record.follower.is_empty():continue
			var next=int(record.follower.index);var route:Array=record.follower.plan.route
			var staff:Dictionary=game.staff_states[index]
			if staff.job_kind=="" or next<1 or next>=route.size():continue
			var leg:Vector2i=route[next]-route[next-1]
			if absi(leg.x)==1 and absi(leg.y)==1 and staff.pos.distance_to(Nav.center(Vector2i(staff.pos.floor())))>.01:slot=index;break
		if slot>=0:break
	check(slot>=0,"actual Main service worker interrupted on diagonal")
	if slot>=0:
		await checkpoint("01-follow-leg","follow",slot)
		var record=game.navigation_review.actors[slot];var route:Array=record.follower.plan.route
		var placed=false
		var positions=[]
		for staff in game.staff_states:positions.append(staff.pos)
		for index in range(int(record.follower.index)+2,route.size()-1):
			var cell:Vector2i=route[index]
			if game.model.place("plant",cell.x,cell.y,0,positions):placed=true;break
		check(placed,"ordinary placement blocks future tail while preserving current leg")
		if placed:
			await step()
			await checkpoint("02-replan-leg","replan",slot)
			var request=0;var owner;var epoch=0
			if not native:
				# A final legal movement below the art threshold must still reach its anchor.
				record=game.navigation_review.actors[slot]
				var leg:Array=record.follower.plan.route
				game.staff_states[slot].pos=Nav.center(leg[-1]).move_toward(Nav.center(leg[-2]),.00005)
				game._animate_staff(.05)
			for frame in range(300):
				record=game.navigation_review.actors[slot]
				request=int(record.request)
				if request!=0:owner=record.request_scheduler;epoch=int(record.request_epoch);break
				await step()
			check(request!=0,"legal next anchor queues fresh search")
			check(request!=0 and game.staff_states[slot].pos==Nav.center(record.get("origin",Vector2i(-1,-1))),"sub-art-threshold final leg retains exact safe anchor")
			if request!=0:
				await checkpoint("03-replan-center","replan",slot)
				check(owner.take_result(request,epoch).status=="unknown","restore cancels/consumes prior scheduler owner request")
		for frame in range(6000):
			await step()
			if native and frame%300==0:print("NATIVE_PROGRESS ",JSON.stringify({"frame":frame,"animation_time":game.animation_time,"paused":game.paused,"editing":game.editing,"recovery_blocked":game.save_recovery_blocked,"processing":game.is_processing(),"served":game.model.served,"staff":codec.encode(game._service_save_snapshot(true).get("staff",[]))}))
			if game.model.served==1:break
		check(game.model.served==1 and game.model.total_earned==game.model.MEAL_PAYMENT,"restored obligation settles exactly one original meal")
		game.set_process(false);await capture("04-paid" if game.model.served==1 else "04-unsettled")
		check(not FileAccess.file_exists(Contract.PRIMARY_FILE),"synthetic v16 work never creates default primary save")
		game._save()
		check(not FileAccess.file_exists(Contract.PRIMARY_FILE),"normal Main save remains suppressed")
	if native:FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE).store_string(JSON.stringify({"frames":frames,"renderer":RenderingServer.get_video_adapter_name(),"ordinary_speed":true,"checks":checks,"failures":failures,"player_save_used":false},"  "))
	print("NAVIGATION_REVIEW_RESTORE_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"native":native,"served":game.model.served,"earned":game.model.total_earned,"player_save_used":false,"production_persistence":false}))
	for player in game.audio_players.values():player.stop();player.stream=null
	game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
	for tween in get_processed_tweens():tween.kill()
	game.queue_free();await process_frame;await process_frame
	quit(0 if failures.is_empty() else 1)
