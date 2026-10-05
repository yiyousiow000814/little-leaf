extends SceneTree
class TestMain extends "res://scripts/main.gd":
	func _load_startup():
		save_writes_suppressed=true;fresh_start=true;model.reset_new();model.ensure_basic_bin();model.ensure_basic_register()
class PreviewArt extends "res://scripts/illustrated_cafe.gd":
	var fixed_overview=false
	func update_projection(clamp_camera:bool=true):
		if not fixed_overview:super.update_projection(clamp_camera)
func _init():call_deferred("run")
func run():
	var game=TestMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false)
	if game.cafe_intro!=null:game.cafe_intro.finish()
	for player in game.audio_players.values():player.stop();player.stream=null
	game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
	var old_art=game.illustration;game.remove_child(old_art);old_art.queue_free()
	var art=PreviewArt.new();art.game=game;game.illustration=art;game.add_child(art);art.set_process(false)
	var output=OS.get_environment("LL_STREET_CAPTURE")
	assert(output!="")
	DirAccess.make_dir_recursive_absolute(output)
	var records=[]
	for mode in ["desktop","minimum_starter","minimum_expanded","road_overview"]:
		root.size=Vector2i(1360,880) if mode in ["desktop","road_overview"] else Vector2i(844,390)
		art.fixed_overview=false
		game.model.owned_parcels.assign(game.model.PARCEL_IDS if mode=="minimum_expanded" else [])
		game.model._sync_floor_bounds()
		await process_frame;await process_frame
		game._sync_window_scale();game._update_ui()
		art._camera_view_size=Vector2.ZERO;art.pan_offset=Vector2.ZERO;art.zoom=1.15 if mode=="desktop" else .85
		art.update_projection()
		if mode.begins_with("minimum"):
			art.fit_overview();art.zoom=art.camera_zoom_limits().x
			art.pan_offset=Vector2(1e6,0);art.update_projection()
			art.pan_offset.y+=285.0-art.iso(-2.76,82.0).y;art.update_projection()
		if mode=="road_overview":
			art.fixed_overview=true;art.zoom=1.0;art.ui_scale=.18;art.tile=Vector2(39,19.5)*.18;art.origin=Vector2(680,500)
		if mode=="mobile":
			art.pan_offset+=Vector2(195,400)-art.iso(-1.5,5.5);art.update_projection()
		for frame in range(45):
			if "street_pedestrians" in art:art._update_street_pedestrians(1.0/60.0)
			art.queue_redraw();await process_frame
		game.model.customers.clear();game.model._spawn_customer()
		art.update_motion(1.0/60.0);art.queue_redraw()
		await process_frame;await RenderingServer.frame_post_draw
		var spawn=[]
		for guest in game.model.customers:spawn.append({"x":guest.x,"z":guest.z,"duration":guest.duration,"screen":[art.iso(guest.x,guest.z).x,art.iso(guest.x,guest.z).y]})
		var path=output+"/"+mode+".png"
		assert(root.get_texture().get_image().save_png(path)==OK)
		for frame in range(30):
			game.model.tick(.1);art.update_motion(.1)
			if "street_pedestrians" in art:art._update_street_pedestrians(.1)
		art.queue_redraw();await process_frame;await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png(output+"/"+mode+"-three-seconds.png")==OK)
		var moved=[]
		for guest in game.model.customers:moved.append({"id":guest.id,"x":guest.x,"z":guest.z})
		var frame_times=[]
		var visible=0
		if "street_pedestrians" in art:visible=art.street_pedestrians.entries(art.origin,art.tile,art.get_viewport_rect()).size()
		for frame in range(60):
			var start=Time.get_ticks_usec()
			if "street_pedestrians" in art:art._update_street_pedestrians(1.0/60.0)
			art.queue_redraw();await process_frame
			frame_times.append(float(Time.get_ticks_usec()-start)/1000.0)
		frame_times.sort()
		records.append({"view":mode,"image":path,"qa_camera_override":mode=="road_overview","new_customer_positions":spawn,"after_three_seconds":moved,"visible_street_people":visible,"frame_ms_p50":frame_times[30],"frame_ms_p95":frame_times[57],"origin":[art.origin.x,art.origin.y],"tile":[art.tile.x,art.tile.y],"zoom":art.zoom})
	var file=FileAccess.open(output+"/native-capture.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"records":records,"native_engine_pixels":true,"synthetic_fixture":true,"player_save_used":false,"mobile_device_benchmark":false},"\t"));file.close()
	print("STREET_NATIVE_CAPTURE ",JSON.stringify(records))
	for tween in get_processed_tweens():tween.kill()
	game.queue_free();await process_frame;await process_frame;quit()
