extends Node
## Disposable, exact #397 active-scene experiment. NOT natural FPS.
const FRAME := Vector2i(1360, 880)
const SMALL := Vector2i(1280, 820)
const ENGINE_HASH := "7d41c59c457bd5a245092b4e7eb2d833e3b3f8c3"
const REPEATS := 8
const WARM := 2
const BLOCKS := 6
var output := ""
var game: Node
var artist: Node
var backdrop: RefCounted
var tracked := -1
var saved_vsync := -1
var logs: Dictionary = {}
var forced_pre := 0
var forced_post := 0

func _ready() -> void:
	if not "--diagnostic-active-backdrop" in OS.get_cmdline_user_args():
		return
	output = OS.get_environment("LL_ACTIVE_BACKDROP_RAW")
	if output.is_empty() or not output.is_absolute_path() or not environment_ok():
		fail("gate_env")
		return
	wait_for_scene()

func environment_ok() -> bool:
	return Engine.get_version_info().get("hash") == ENGINE_HASH and DisplayServer.get_name() == "X11" \
		and OS.get_name() == "Linux" and DisplayServer.screen_get_scale() == 1.0 \
		and RenderingServer.get_current_rendering_driver_name() == "opengl3" \
		and RenderingServer.get_current_rendering_method() == "gl_compatibility" \
		and RenderingServer.get_video_adapter_name().to_lower().contains("llvmpipe") \
		and (RenderingServer.get_video_adapter_vendor() + " " + RenderingServer.get_video_adapter_api_version()).to_lower().contains("mesa")

func wait_for_scene() -> void:
	var deadline := Time.get_ticks_msec() + 180000
	while Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.2, true, false, true).timeout
		game = get_tree().current_scene
		if not active_game():
			continue
		for guest in game.model.customers:
			if guest.phase == "cooking" and guest.seated:
				tracked = int(guest.id)
				artist = game.illustration
				backdrop = artist.background_cache
				if not adapter_ok():
					fail("adapter")
					return
				measure.call_deferred()
				return
	fail("scene_wait")

func active_game() -> bool:
	return is_instance_valid(game) and "model" in game and game.model != null \
		and game.model.operating_open and not game.paused and not game.editing and not game.save_recovery_blocked \
		and (game.cafe_intro == null or (not game.cafe_intro.active and not game.cafe_intro.preparing))

func same_guest_cooking() -> bool:
	if not active_game():
		return false
	for guest in game.model.customers:
		if int(guest.id) == tracked:
			return guest.phase == "cooking" and guest.seated
	return false

func adapter_ok() -> bool:
	return backdrop != null and backdrop.has_method("control_mode") and backdrop.has_method("bake_once") \
		and backdrop.has_method("refresh_selection") and backdrop.has_method("key_for") and backdrop.has_method("witness") \
		and backdrop.has_method("producer_is_rgba_opaque") and backdrop.has_method("projection_for")

func write_raw(value: Dictionary) -> void:
	if output.is_empty():
		return
	var f := FileAccess.open(output, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(value))
		f.close()

func fail(reason: String) -> void:
	if adapter_ok() and is_instance_valid(artist):
		backdrop.control_mode("original")
		backdrop.refresh_selection(artist)
	write_raw({"schema":"ll-active-backdrop-failure-397-v1","stage_code":reason})
	push_error("ACTIVE_BACKDROP_FIXTURE: " + reason)
	get_tree().quit(2)

func frame_token() -> Array:
	return [Engine.get_process_frames(), Engine.get_physics_frames(), get_tree().current_scene.get_instance_id()]

func seen_pre() -> void:
	forced_pre += 1

func seen_post() -> void:
	forced_post += 1

func closed_draw() -> bool:
	var prior_pre := forced_pre
	var prior_post := forced_post
	RenderingServer.force_draw(false, 0.0)
	RenderingServer.force_sync()
	return forced_pre - prior_pre == 1 and forced_post - prior_post == 1

func pngless_pixels(size: Vector2i) -> PackedByteArray:
	if not closed_draw():
		return PackedByteArray()
	var image := get_tree().root.get_texture().get_image()
	if image == null or image.get_size() != size:
		return PackedByteArray()
	image.convert(Image.FORMAT_RGBA8)
	return image.get_data()

func digest(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK or context.update(bytes) != OK:
		return ""
	return context.finish().hex_encode()

func mode(which: String, wanted: bool) -> bool:
	backdrop.control_mode(which)
	var selected: bool = backdrop.refresh_selection(artist)
	var proof: Dictionary = backdrop.witness()
	return selected == wanted and proof.get("selected") == wanted

func root_counter() -> Array:
	var rid := get_tree().root.get_viewport_rid()
	return [RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS,
		RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
		RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS,
		RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)]

func counter_receipt(values: Array) -> Dictionary:
	return {"primitive_count":values[0],"draw_calls":values[1]}

func sensitivity(original: PackedByteArray, size: Vector2i) -> bool:
	# Inject a single native overlay after production UI without ticking scripts.
	# This only proves the root readback responds to output change.
	var layer := CanvasLayer.new()
	layer.layer = 127
	get_tree().root.add_child(layer)
	var rid := RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(rid, layer.get_canvas())
	RenderingServer.canvas_item_add_rect(rid, Rect2(14, 14, 43, 39), Color(0.9, 0.1, 0.6, 1))
	var changed := pngless_pixels(size)
	RenderingServer.free_rid(rid)
	get_tree().root.remove_child(layer)
	layer.free()
	return changed.size() == original.size() and changed != original and pngless_pixels(size) == original

func canvas_scene_admitted() -> bool:
	var parent := artist.get_parent()
	while parent != null:
		if parent is CanvasItem:
			return false
		parent = parent.get_parent()
	var pending: Array[Node] = [get_tree().root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is CanvasModulate or node is CanvasGroup or node is PointLight2D or node is DirectionalLight2D \
				or node is BackBufferCopy or node is WorldEnvironment:
			return false
		if node is CanvasItem and node.material is ShaderMaterial:
			var shader: Shader = node.material.shader
			if shader == null or shader.code.is_empty() or "hint_screen_texture" in shader.code \
					or "hint_depth_texture" in shader.code or "hint_normal_roughness_texture" in shader.code \
					or "SCREEN_UV" in shader.code or "render_mode" in shader.code and "blend_mul" in shader.code:
				return false
		pending.append_array(node.get_children())
	return environment_ok()

func coherent_pair(size: Vector2i, check_sensitivity: bool) -> Dictionary:
	if not canvas_scene_admitted():
		return {}
	# No await inside this complete root viewport A/C/A, including readbacks.
	var token := frame_token()
	if not mode("original", false):
		return {}
	var a := pngless_pixels(size)
	var counter_a := root_counter()
	if a.size() != size.x * size.y * 4 or counter_a[0] <= 0 or counter_a[1] <= 0:
		return {}
	if not mode("cache", true):
		return {}
	var b := pngless_pixels(size)
	var counter_b := root_counter()
	var prefix := int(backdrop.witness().get("prefix_primitives", -1))
	if a != b or counter_b[0] <= 0 or counter_b[1] <= 0 or prefix <= 2 or counter_a[0] - counter_b[0] != prefix - 2:
		return {}
	if not mode("original", false) or pngless_pixels(size) != a or root_counter() != counter_a:
		return {}
	if check_sensitivity and not sensitivity(a, size):
		return {}
	if frame_token() != token or not same_guest_cooking():
		return {}
	var sha := digest(a)
	if sha.length() != 64:
		return {}
	return {"width":size.x,"height":size.y,"rgba_sha256":sha,
		"original":counter_receipt(counter_a),"cache":counter_receipt(counter_b),"prefix_primitives":prefix}

func miss_pair(size: Vector2i) -> bool:
	if not canvas_scene_admitted():
		return false
	var token := frame_token()
	if not mode("original", false):
		return false
	var a := pngless_pixels(size)
	var count := root_counter()
	if a.size() != size.x * size.y * 4 or not mode("cache", false) or pngless_pixels(size) != a \
			or root_counter() != count or not mode("original", false) or frame_token() != token:
		return false
	return same_guest_cooking()

func bake(size: Vector2i) -> Dictionary:
	if not canvas_scene_admitted():
		return {}
	var token := frame_token()
	var before: Dictionary = backdrop.witness()
	var started := Time.get_ticks_usec()
	var accepted: bool = backdrop.bake_once(artist)
	RenderingServer.force_sync()
	var elapsed := Time.get_ticks_usec() - started
	var after: Dictionary = backdrop.witness()
	if not accepted or elapsed <= 0 or elapsed > 60000000 or frame_token() != token \
			or int(after.get("bakes", -1)) != int(before.get("bakes", -1)) + 1 \
			or int(after.get("pixel_bytes", -1)) != size.x * size.y * 4 \
			or not backdrop.producer_is_rgba_opaque() or frame_token() != token:
		return {}
	return {"wall_us":elapsed,"pixel_bytes":after["pixel_bytes"]}

func new_checkpoint(size: Vector2i, pan: Vector2, zoom: float, resize: bool = true) -> bool:
	# Outside the frozen chunks only, allow normal redraw + projection after
	# window/HUD reflow. Each new pair still freezes one logical instant.
	if resize:
		get_tree().root.size = size
	artist.pan_offset = pan
	artist.zoom = zoom
	if game.interaction != null:
		game.interaction.pan_offset = pan
	artist.update_projection()
	artist.queue_redraw()
	await get_tree().create_timer(0.18, true, false, true).timeout
	return get_tree().root.size == size and same_guest_cooking() and not backdrop.key_for(artist).is_empty()

func elapsed_slot(which: String, expected: Dictionary, size: Vector2i) -> Dictionary:
	if not mode(which, which == "cache"):
		return {}
	for i in range(WARM):
		if not closed_draw():
			return {}
	if counter_receipt(root_counter()) != expected:
		return {}
	var samples := PackedInt64Array()
	samples.resize(REPEATS)
	for i in range(REPEATS):
		var start := Time.get_ticks_usec()
		if not closed_draw():
			return {}
		var duration := Time.get_ticks_usec() - start
		if duration <= 0 or duration > 2000000:
			return {}
		samples[i] = duration
	if counter_receipt(root_counter()) != expected or get_tree().root.size != size:
		return {}
	return {"arm":which,"warm_draws":WARM,"sample_draws":REPEATS,"draw_us":Array(samples),
		"primitive_count":expected.primitive_count,"draw_calls":expected.draw_calls}

func pairs(steady: Dictionary) -> Array:
	var token := frame_token()
	var before: Dictionary = backdrop.witness()
	var blocks: Array = []
	for block_index in range(BLOCKS):
		var block := []
		for arm_name in (["original", "cache", "cache", "original"] if block_index % 2 == 0 else ["cache", "original", "original", "cache"]):
			var record := elapsed_slot(arm_name, steady[arm_name], FRAME)
			if record.is_empty() or Engine.max_fps != 60 or DisplayServer.window_get_vsync_mode() != saved_vsync:
				return []
			block.append(record)
		blocks.append(block)
	var after: Dictionary = backdrop.witness()
	if frame_token() != token or not same_guest_cooking() or before.get("bakes") != after.get("bakes") \
			or before.get("draw_updates") != after.get("draw_updates"):
		return []
	return blocks

func witness_delta(before: Dictionary, after: Dictionary) -> Dictionary:
	var delta := {}
	for metric in ["changes","draw_updates","eligible_updates","hits","misses"]:
		if not before.has(metric) or not after.has(metric):
			return {}
		var count := int(after[metric]) - int(before[metric])
		if count < 0:
			return {}
		delta[metric] = count
	return delta

func camera_observation(base_pan: Vector2) -> Dictionary:
	# Natural redraws and stock projection, not production telemetry or a
	# general estimate of how often a real player changes the key.
	var before: Dictionary = backdrop.witness()
	var frames := Engine.get_process_frames()
	await get_tree().create_timer(0.18, true, false, true).timeout
	var after: Dictionary = backdrop.witness()
	var steady := witness_delta(before, after)
	var steady_frames := Engine.get_process_frames() - frames
	if steady.is_empty() or steady.changes != 0 or steady.draw_updates <= 0 or steady_frames <= 0 or not same_guest_cooking() \
			or steady.hits <= 0 or steady.misses != 0 or steady.hits != steady.draw_updates \
			or steady.eligible_updates != steady.draw_updates:
		return {}
	frames = Engine.get_process_frames()
	var prior_key: Array = backdrop.key_for(artist).duplicate(true)
	for offset in [Vector2(8.5, 3.0), Vector2(18.0, 11.5), Vector2(29.5, 18.0)]:
		artist.pan_offset = base_pan + offset
		if game.interaction != null:
			game.interaction.pan_offset = artist.pan_offset
		artist.update_projection()
		artist.queue_redraw()
		await get_tree().create_timer(0.08, true, false, true).timeout
		if not same_guest_cooking() or get_tree().root.size != FRAME:
			return {}
	var moving := witness_delta(after, backdrop.witness())
	var moving_frames := Engine.get_process_frames() - frames
	if moving.is_empty() or moving.changes <= 0 or moving.draw_updates <= 0 or moving_frames <= 0 \
			or moving.misses <= 0 or moving.hits + moving.misses != moving.draw_updates \
			or moving.eligible_updates > moving.draw_updates \
			or backdrop.key_for(artist) == prior_key:
		return {}
	steady["process_frames"] = steady_frames
	moving["process_frames"] = moving_frames
	return {"stationary":steady,"camera_pan_including_fractional":moving}

func measure() -> void:
	if not same_guest_cooking() or get_tree().root.size != FRAME or Engine.max_fps != 60 or not environment_ok():
		fail("gate_env")
		return
	saved_vsync = DisplayServer.window_get_vsync_mode()
	var home_pan: Vector2 = artist.pan_offset
	var home_zoom: float = artist.zoom
	backdrop.control_mode("original")
	artist.queue_redraw()
	await get_tree().create_timer(0.18, true, false, true).timeout
	var home_key: Array = backdrop.key_for(artist).duplicate(true)
	var home_projection: Array = backdrop.projection_for(artist).duplicate(true)
	if home_key.is_empty() or home_projection.is_empty() or not same_guest_cooking() or not canvas_scene_admitted():
		fail("settled_key")
		return
	RenderingServer.frame_pre_draw.connect(seen_pre)
	RenderingServer.frame_post_draw.connect(seen_post)
	var bakes := {}
	var passes := {}
	bakes["first"] = bake(FRAME)
	if bakes.first.is_empty():
		fail("first_bake")
		return
	passes["settled"] = coherent_pair(FRAME, true)
	if passes.settled.is_empty():
		fail("settled_parity")
		return
	# control_mode itself can account one transition; put it before the
	# observation baseline. No manual selection calls or forced draws inside.
	backdrop.control_mode("cache")
	if not bool(backdrop.witness().get("selected", false)):
		fail("natural_observation")
		return
	var observations := await camera_observation(home_pan)
	if observations.is_empty():
		fail("natural_observation")
		return
	var pan := home_pan + Vector2(31, 22)
	if not await new_checkpoint(FRAME, pan, home_zoom, false) or backdrop.key_for(artist) == home_key or not miss_pair(FRAME):
		fail("pan_miss")
		return
	bakes["pan"] = bake(FRAME)
	if bakes.pan.is_empty():
		fail("pan_bake")
		return
	passes["pan"] = coherent_pair(FRAME, false)
	if passes.pan.is_empty():
		fail("pan_parity")
		return
	if not await new_checkpoint(SMALL, pan, home_zoom) or not miss_pair(SMALL):
		fail("resize_miss")
		return
	bakes["resize"] = bake(SMALL)
	if bakes.resize.is_empty():
		fail("resize_bake")
		return
	passes["resize"] = coherent_pair(SMALL, false)
	if passes.resize.is_empty():
		fail("resize_parity")
		return
	# A second, post-resize stock projection assignment restores the exact
	# original camera after HUD/viewport reflow has finished.
	if not await new_checkpoint(FRAME, home_pan, home_zoom) or not await new_checkpoint(FRAME, home_pan, home_zoom, false) \
			or backdrop.projection_for(artist) != home_projection or backdrop.key_for(artist) == home_key \
			or not miss_pair(FRAME):
		fail("restore_miss")
		return
	bakes["restored"] = bake(FRAME)
	if bakes.restored.is_empty():
		fail("restore_bake")
		return
	passes["restored"] = coherent_pair(FRAME, false)
	if passes.restored.is_empty():
		fail("restore_parity")
		return
	var blocks := pairs(passes.restored)
	if blocks.size() != BLOCKS or not mode("original", false):
		fail("arm_unstable")
		return
	var end_witness: Dictionary = backdrop.witness()
	write_raw({"schema":"ll-active-backdrop-397-v1","passes":passes,"bakes":bakes,"blocks":blocks,
		"observations":observations,"final_witness":end_witness,
		"policies":{"cap":60,"unchanged_vsync":saved_vsync,"closed_loop_swap":false,"frame_step_arg":0.0,
			"rendering_server_force_sync":true,"natural_fps":false},
		"proofs":{"same_logical_instant_each_pair":true,"exact_root_rgba":true,"positive_root_sensitivity":true,
			"restored_home_projection":true,"restored_new_generation":true,"unsupported_canvas_effects_absent":true,"pan_cache_miss":true,"resize_cache_miss":true,"producer_opaque":true,
			"exact_one_pre_and_post_per_draw":true,"no_readback_in_steady_samples":true}})
	get_tree().quit()
