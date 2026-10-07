class_name PerformanceProfile
extends SceneTree
# Identical deterministic workload for baseline and candidate. Never loads a save.
class ProfileModel extends "res://scripts/cafe_model.gd":
	var shell_usec=0
	var shell_calls=0
	func _fixed_edge_blocked(a:Vector2i,b:Vector2i,openings=null,walls=null)->bool:
		var start=Time.get_ticks_usec()
		var result=super._fixed_edge_blocked(a,b,openings,walls)
		shell_usec+=Time.get_ticks_usec()-start;shell_calls+=1
		return result
class ProfileMain extends "res://scripts/main.gd":
	var people_usec=0
	var people_calls=0
	var service_usec=0
	func _load_startup():
		save_writes_suppressed=true;fresh_start=true
		model=ProfileModel.new();MinimalStart.apply(model)
	func _save():return true
	func _setup_music():pass
	func _update_people():
		var start=Time.get_ticks_usec();super._update_people()
		people_usec+=Time.get_ticks_usec()-start;people_calls+=1
	func _animate_staff(delta:float):
		var start=Time.get_ticks_usec();super._animate_staff(delta)
		service_usec+=Time.get_ticks_usec()-start
var game
var ticks=[]
var draws=[]
var frames=[]
func _initialize():run.call_deferred()
func run():
	seed(1337);Engine.max_fps=60;root.size=Vector2i(1360,880)
	game=ProfileMain.new();root.add_child(game);game.set_process(false)
	game.cafe_intro.finish();game.illustration.set_process(false)
	game.illustration.zoom=1.0;game.illustration.pan_offset=Vector2.ZERO;game.illustration.update_projection()
	game.model._spawn_customer()
	# Bring the generated guest to its first route waypoint; start with visible service.
	var guest=game.model.customers[0];guest.x=guest.route[0].x;guest.z=guest.route[0].y
	for frame in 120:
		game._process(1.0/60);game.illustration._process(1.0/60);await process_frame
	game.people_usec=0;game.people_calls=0;game.service_usec=0
	game.model.shell_usec=0;game.model.shell_calls=0
	var last=Time.get_ticks_usec()
	for frame in 600:
		var start=Time.get_ticks_usec();game._process(1.0/60);ticks.append(Time.get_ticks_usec()-start)
		start=Time.get_ticks_usec();game.illustration._process(1.0/60)
		await process_frame
		draws.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000000)
		var now=Time.get_ticks_usec();frames.append(now-last);last=now
		if frame==599 and DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			if not OS.has_feature("web"):root.get_texture().get_image().save_png(OS.get_environment("OUTPUT")+"/frame.png")
	var signature={"customers":game.model.customers,"staff":[],"coins":game.model.coins,"served":game.model.served}
	for staff in game.staff_states:
		var record=staff.duplicate(true);record.erase("node");signature.staff.append(record)
	var live_shell_usec=game.model.shell_usec;var live_shell_calls=game.model.shell_calls
	var edge_start=Time.get_ticks_usec();var blocked=0
	for repeat in 1000:
		for x in 12:blocked+=int(game.model._fixed_edge_blocked(Vector2i(x,-1),Vector2i(x,0)))
		for z in 9:blocked+=int(game.model._fixed_edge_blocked(Vector2i(-1,z),Vector2i(0,z)))
	var report={"platform":"web" if OS.has_feature("web") else DisplayServer.get_name(),"engine":Engine.get_version_info().string,"viewport":[1360,880],"dpr":1,"frame_cap":60,"seed":1337,"warmup_frames":120,"sample_frames":600,"step":1.0/60,"tick_us":stats(ticks),"engine_process_us":stats(draws),"frame_interval_us":stats(frames),"people_us":game.people_usec,"people_calls":game.people_calls,"service_us":game.service_usec,"shell_us":live_shell_usec,"shell_calls":live_shell_calls,"edge_batch_us":Time.get_ticks_usec()-edge_start,"edge_blocked":blocked,"signature":signature}
	print("PERFORMANCE_RESULT ",JSON.stringify(report))
	if not OS.has_feature("web"):
		FileAccess.open(OS.get_environment("OUTPUT")+"/profile.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
		quit()
func stats(values:Array)->Dictionary:
	values.sort();var sum=0.0
	for value in values:sum+=value
	return {"mean":sum/values.size(),"median":values[values.size()/2],"p95":values[int(values.size()*.95)]}
