extends "res://ll397_acquire_live.gd"
## Controlled retained instant, then a separate natural/observational lane. No natural A−B label.
const ACQUIRE_ARGS:="--diagnostic-backdrop-acquisition-397"
var receipts_failed:=""
func _ready()->void:
	if ACQUIRE_ARGS not in OS.get_cmdline_user_args():return
	output=OS.get_environment("LL397_BACKDROP_ACQUISITION_RAW")
	if output.is_empty() or not output.is_absolute_path() or not environment_ok():fail("gate_env");return
	wait_for_scene()

func open_root()->bool:
	var root:=get_tree().root
	return is_instance_valid(root) and root.visible and root.mode!=Window.MODE_MINIMIZED and root.size==FRAME and root.get_visible_rect().size==Vector2(FRAME) and DisplayServer.get_window_list().size()==1 and not game.compact_ui.viewport_too_small and not game.compact_ui.has_open_popup() and not is_instance_valid(game.startup_readiness) and artist.is_visible_in_tree()

func sample_acquire(acquire:bool, size:Vector2i, token:Array, k:Array, ref:Dictionary)->Dictionary:
	backdrop.discard()
	backdrop.control_mode("original")
	var state:Dictionary=backdrop.drawing_state()
	var resident:bool=int(state.update_mode)!=-1
	if not target_unchanged() or backdrop.pending() or not state.root_original or state.selected or frame_token()!=token or backdrop.key_for(artist)!=k:return {}
	var pre:=forced_pre
	var post:=forced_post
	var start:=Time.get_ticks_usec()
	if acquire and not backdrop.arm(artist):return {}
	var start_mode:int=backdrop.drawing_state().update_mode
	if acquire and start_mode!=RenderingServer.VIEWPORT_UPDATE_ONCE:return {}
	if not acquire and start_mode not in [-1,RenderingServer.VIEWPORT_UPDATE_DISABLED]:return {}
	if not closed_draw():return {}
	var finish_mode:int=backdrop.drawing_state().update_mode
	if acquire and (finish_mode!=RenderingServer.VIEWPORT_UPDATE_DISABLED or not backdrop.finish(artist)):return {}
	var us:=Time.get_ticks_usec()-start
	# Root image already rendered by the closed_draw above. Never draw/read it inside the timer a second time.
	if forced_pre!=pre+1 or forced_post!=post+1 or not target_unchanged() or frame_token()!=token or not open_root() or backdrop.key_for(artist)!=k or not same_guest_cooking():return {}
	if us<=0 or us>2000000 or root_counter()!=ref.counters:return {}
	var image:=get_tree().root.get_texture().get_image()
	if image==null or image.get_size()!=size or image.get_format()!=Image.FORMAT_RGBA8 or image.get_data()!=ref.bytes:return {}
	if acquire and (not matched_target() or int(backdrop.witness().prefix_primitives)!=139288):return {}
	return {"us":us,"acquire":acquire,"producer_resident_before":resident}

func controlled()->Dictionary:
	if not open_root() or not canvas_scene_admitted() or backdrop.drawing_state().update_mode!=-1:return {}
	pinned_root_target=root_target()
	var token:=frame_token()
	var k:Array=backdrop.key_for(artist).duplicate()
	if k.is_empty():return {}
	var ref:=readback(FRAME,false)
	if ref.is_empty() or not repeat_frame(ref,readback(FRAME,false),FRAME,"stock_repeat"):return {}
	# A–B–A for genuine first lazy producer allocation (n=1, never pretend this is a p95).
	var first:=[]
	for want in [false,true,false]:
		var v:=sample_acquire(want,FRAME,token,k,ref)
		if v.is_empty():return {}
		first.append(v)
	if first[0].producer_resident_before or first[1].producer_resident_before or not first[2].producer_resident_before:return {}
	var warm:=[]
	for i in 6:
		var block:=[]
		for want in ([false,true,true,false] if i%2==0 else [true,false,false,true]):
			var v:=sample_acquire(want,FRAME,token,k,ref)
			if v.is_empty() or not v.producer_resident_before:return {}
			block.append(v)
		warm.append(block)
	# Pair full currently displayed root bytes with current cache from a fresh same-generation bake.
	var last:=sample_acquire(true,FRAME,token,k,ref)
	if last.is_empty() or coherent_pair(FRAME,true).is_empty() or not same_guest_cooking() or frame_token()!=token:return {}
	return {"first_aba":first,"warm_counterbalanced_blocks":warm,"matching_root_primitives":ref.counters[0],
		"matching_root_calls":ref.counters[1],"producer_primitives":139288,"same_retained_tick_full_rgba_exact":true}

func measure()->void:
	if not same_guest_cooking() or not open_root() or not environment_ok() or Engine.max_fps!=60:fail("initial_state");return
	saved_vsync=DisplayServer.window_get_vsync_mode()
	backdrop.control_mode("original")
	artist.queue_redraw()
	await get_tree().create_timer(.18,true,false,true).timeout
	RenderingServer.frame_pre_draw.connect(seen_pre)
	RenderingServer.frame_post_draw.connect(seen_post)
	var arms:=controlled()
	if arms.is_empty():fail("same_state_acquisition_not_identified");return
	# Allow live phase after synchronous retained test to settle. No timing crosses either side.
	for i in 5:await RenderingServer.frame_post_draw
	if not same_guest_cooking():fail("live_checkpoint_expired");return
	var live:Dictionary=await run_live()
	if live.is_empty():fail("live_observation");return
	if DisplayServer.window_get_vsync_mode()!=saved_vsync or Engine.max_fps!=60:fail("presentation_changed");return
	write_raw({"schema":"ll397-acquire-private-v1","controlled":arms,"natural":live})
	get_tree().quit()
