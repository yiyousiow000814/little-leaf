extends SceneTree
## Diagnostic only. Real renderer measurements require CI's supported display.
## Uses a generated fresh cafe and suppresses every progress write.
const Main=preload("res://scripts/main.gd")
class ProfileGame extends Main:
	var stages=[]
	func mark_stage(name:String,start:int):stages.append({"name":name,"start_us":start,"duration_us":Time.get_ticks_usec()-start})
	func _load_startup():
		var start=Time.get_ticks_usec()
		save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
		mark_stage("generated_fresh_model",start)
	func _setup_world():
		var start=Time.get_ticks_usec();super();mark_stage("setup_world",start)
	func _build_ui():
		var start=Time.get_ticks_usec();super();mark_stage("build_ui",start)
	func _setup_music():
		var start=Time.get_ticks_usec();super();mark_stage("setup_music",start)
	func _rebuild_room():
		var start=Time.get_ticks_usec();super();mark_stage("rebuild_room",start)
	func _rebuild_furniture():
		var start=Time.get_ticks_usec();super();mark_stage("rebuild_furniture",start)
	func _restore_service_runtime():
		var start=Time.get_ticks_usec();super();mark_stage("restore_service_runtime",start)
	func _autosave():return
	func _save():return true
var game
var started_us=0
var previous_us=0
var frames=[]
var rendered=[]
var startup_us=0
var peak_texture_bytes=0
var initial_atlases=[]
var atlas_ids=[]
var finished=false
var trials=[]
var trial_name="cold_atlases"
func _initialize():
	RenderingServer.frame_post_draw.connect(after_draw)
	run.call_deferred()
func run():
	finished=false
	frames=[];rendered=[];peak_texture_bytes=0
	preload("res://scripts/cafe_intro.gd").shown_this_session=false
	root.size=Vector2i(1360,880)
	initial_atlases=[preload("res://scripts/illustrated_furniture.gd").static_atlas.state,Main.Illustration.head_atlas.state,Main.Illustration.moving_atlas.state]
	started_us=Time.get_ticks_usec();previous_us=started_us
	game=ProfileGame.new();root.add_child(game)
	startup_us=Time.get_ticks_usec()-started_us
	if game.cafe_intro==null or game.illustration==null:
		finished=true;push_error("Startup probe could not initialize the actual scene");quit(1);return
	var art=game.illustration
	atlas_ids=[art.furniture_art.static_atlas.get_instance_id(),art.head_atlas.get_instance_id(),art.moving_atlas.get_instance_id()]
func phase()->String:
	if is_instance_valid(game.get("startup_readiness")) and not game.get("startup_readiness").completed:return "opening_preparation"
	if game.cafe_intro.active:
		return "welcome_hold" if game.cafe_intro.elapsed<game.cafe_intro.DESCENT_START else "descent"
	return "restaurant"
func _process(_delta):
	if game==null or finished or game.cafe_intro==null:return false
	var now=Time.get_ticks_usec()
	var art=game.illustration
	frames.append({"at_us":now-started_us,"interval_us":now-previous_us,"phase":phase(),"intro_elapsed":game.cafe_intro.elapsed,"background_rebuilds":art.background_cache.rebuilds,"shell_rebuilds":art.shell_draw_cache.rebuilds,"atlases":[art.furniture_art.static_atlas.state,art.head_atlas.state,art.moving_atlas.state],"music_state":game.music_state})
	previous_us=now
	if now-started_us>12000000:finish.call_deferred();finished=true
	return false
func after_draw():
	peak_texture_bytes=maxi(peak_texture_bytes,RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED))
	if not finished and game!=null and game.cafe_intro!=null:rendered.append({"at_us":Time.get_ticks_usec()-started_us,"phase":phase()})
func finish():
	var art=game.illustration
	var report={"trial":trial_name,"engine":Engine.get_version_info().string,"display":DisplayServer.get_name(),"renderer_measured":DisplayServer.get_name()!="headless","player_data_used":false,"save_writes_suppressed":game.save_writes_suppressed,"viewport":[1360,880],"os":OS.get_name(),"video_adapter":RenderingServer.get_video_adapter_name(),"rendering_method":RenderingServer.get_current_rendering_method(),"audio_driver":AudioServer.get_driver_name(),"texture_memory_bytes":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED),"sampled_peak_texture_memory_bytes":peak_texture_bytes,"static_memory_peak_bytes":OS.get_static_memory_peak_usage(),"initial_atlas_states":initial_atlases,"atlas_instance_ids":atlas_ids,"started_us":started_us,"startup_us":startup_us,"opening_preparation":game.get("startup_preparation_report"),"initialization_stages":game.stages,"process_frames":frames,"post_draw_events":rendered,"atlas_stats":{"furniture":art.furniture_art.static_atlas.stats.duplicate(true),"heads":art.head_atlas.stats.duplicate(true),"moving":art.moving_atlas.stats.duplicate(true)},"scope":"Source-bound generated fresh model. Native process/draw event intervals, not browser FPS or audible audio. Script preload time is outside startup_us."}
	trials.append(report)
	print("STARTUP_PROFILE_TRIAL ",JSON.stringify({"trial":trial_name,"frames":frames.size(),"draw_events":rendered.size(),"renderer_measured":report.renderer_measured,"startup_us":startup_us,"opening_preparation":game.get("startup_preparation_report"),"initialization_stages":game.stages}))
	game.queue_free();await process_frame;game=null
	if trial_name=="cold_atlases":
		trial_name="warm_atlases";run.call_deferred();return
	var output=OS.get_environment("OUTPUT")
	if output!="":FileAccess.open(output.path_join("startup-profile.json"),FileAccess.WRITE).store_string(JSON.stringify({"trials":trials},"  "))
	print("STARTUP_PROFILE_RESULT ",JSON.stringify({"trials":trials.size(),"renderer_measured":report.renderer_measured,"player_data_used":false}))
	quit()
