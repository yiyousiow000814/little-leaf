extends SceneTree
## Script-only timing. Headless raster/cache placeholders cannot establish GPU,
## native pixel equivalence, browser pacing, mobile battery or thermal results.
class ProfileArt extends "res://scripts/illustrated_cafe.gd":
	var calls={}
	var durations=[]
	func _draw():
		calls={};var started=Time.get_ticks_usec();super._draw();durations.append(Time.get_ticks_usec()-started)
	func poly(points:Array,c):calls.poly=calls.get("poly",0)+1;super.poly(points,c)
	func ellipse(p:Vector2,size:Vector2,c):calls.ellipse=calls.get("ellipse",0)+1;super.ellipse(p,size,c)
	func art_polyline(points:PackedVector2Array,tint:Color,width:float):calls.polyline=calls.get("polyline",0)+1;super.art_polyline(points,tint,width)
class ProfileGame extends "res://scripts/main.gd":
	func _load_startup():save_writes_suppressed=true;fresh_start=true;model=Model.new();MinimalStart.apply(model)
	func _save():return true
	func _setup_music():pass
var game
func _initialize():run.call_deferred()
func stats(values:Array)->Dictionary:
	if values.is_empty():return {"samples":0,"median":0,"p95":0,"mean":0}
	values.sort();var total=0.0
	for value in values:total+=value
	return {"samples":values.size(),"mean":total/values.size(),"median":values[values.size()/2],"p95":values[int(values.size()*.95)]}
func run():
	seed(1337);Engine.max_fps=0;root.size=Vector2i(1360,880)
	game=ProfileGame.new();root.add_child(game);game.set_process(false);game.cafe_intro.finish();game.paused=true
	var old=game.illustration;old.set_process(false);old.hide();old.queue_free()
	var art=ProfileArt.new();art.game=game;game.illustration=art;root.add_child(art);art.set_process(false)
	for tween in get_processed_tweens():tween.kill()
	var records=[]
	for cached in [false,true]:
		if cached:
			for atlas in [art.furniture_art.static_atlas,art.head_atlas,art.moving_atlas]:
				atlas.texture=ImageTexture.create_from_image(Image.create(1,1,false,Image.FORMAT_RGBA8));atlas.state="ready"
		for viewport in [Vector2i(1360,880),Vector2i(390,844)]:
			root.size=viewport;game._sync_window_scale();art.zoom=1.0;art.pan_offset=Vector2.ZERO
			for mode in ["forced_redraw","settled_pause"]:
				if "use_idle_retention" in art:art.use_idle_retention=mode=="settled_pause"
				for frame in 12:art._process(1.0/60);await process_frame
				for tween in get_processed_tweens():tween.kill()
				art.durations=[];var process_us=[]
				for frame in 100:
					var start=Time.get_ticks_usec();art._process(1.0/60);process_us.append(Time.get_ticks_usec()-start);await process_frame
				records.append({"mode":mode,"cache_placeholder":cached,"viewport":str(viewport),"draw_cpu_us":stats(art.durations.duplicate()),"process_cpu_us":stats(process_us),"primitive_helpers_last_draw":art.calls.duplicate(),"frames":100,"items":game.model.items.size(),"staff":game.staff_states.size(),"customers":game.model.customers.size()})
	print("RENDER_PROFILE_RESULT ",JSON.stringify(records))
	var output=OS.get_environment("OUTPUT")
	if output!="":FileAccess.open(output.path_join("render-profile.json"),FileAccess.WRITE).store_string(JSON.stringify(records,"  "))
	game.queue_free();await process_frame;quit()
