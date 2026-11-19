extends "res://mechanism.gd"
## #397 settled native-size opaque backdrop cache diagnostic; no Main/game loop.
const HOME_CAMERA := Vector2(680, 260)
const SHIFTED_CAMERA := Vector2(695, 270)
const BLOCKS := 6
var producer: SubViewport
var capture_ground: GroundNode
var capture_sprite: Sprite2D
var target_texture: ViewportTexture
var cache_key: Array = []
var camera := HOME_CAMERA
var bake_count := 0
var script_sha := ""

func fail(reason: String) -> void:
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify({"schema":"ll-backdrop-cache-failure-397-v1","stage_code":reason}))
			file.close()
	push_error("BACKDROP_FIXTURE: " + reason)
	finish(2)

func build_producer() -> bool:
	producer = SubViewport.new()
	producer.world_2d = World2D.new()
	producer.size = F
	producer.size_2d_override = F
	producer.size_2d_override_stretch = true
	producer.disable_3d = true
	producer.transparent_bg = true
	producer.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	producer.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(producer)
	capture_ground = GroundNode.new()
	producer.add_child(capture_ground)
	if not capture_ground.prepare_stock() or capture_ground.get_viewport_rect().size != Vector2(F):
		return false
	if capture_ground.background_cache.material == null or not capture_ground.background_cache.canvas.is_valid() \
			or capture_ground.background_cache.material.shader.get_rid() != setups.F.shader \
			or ground_mesh_digest(capture_ground) != setups.F.mesh_sha:
		return false
	target_texture = producer.get_texture()
	capture_sprite = Sprite2D.new()
	capture_sprite.texture = target_texture
	capture_sprite.position = Vector2.ZERO
	capture_sprite.centered = false
	capture_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	capture_sprite.visible = false
	setups.F.vp.add_child(capture_sprite)
	return native_nearest()

func clean_ground(node: GroundNode, host: SubViewport) -> bool:
	return node.get_parent() == host and node.get_global_transform_with_canvas() == Transform2D.IDENTITY \
		and node._art_transform == Transform2D.IDENTITY and node.self_modulate == Color.WHITE and node.modulate == Color.WHITE \
		and node.material == null and not node.use_parent_material and node.clip_children == CanvasItem.CLIP_CHILDREN_DISABLED \
		and node.texture_filter == CanvasItem.TEXTURE_FILTER_PARENT_NODE and node.texture_repeat == CanvasItem.TEXTURE_REPEAT_PARENT_NODE \
		and node.opacity == 1.0 and node.ui_scale == 1.0 and node.zoom == 1.0 and node.tile == Vector2(39, 19.5) \
		and node.use_batched_ground and node.use_grass_mesh and not node._parking_owned()

func native_nearest() -> bool:
	return producer.size == F and setups.F.vp.size == F and setups.F.vp.size_2d_override == F \
		and producer.size_2d_override == F and producer.size_2d_override_stretch and setups.F.vp.size_2d_override_stretch \
		and capture_sprite.texture == target_texture and capture_sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST \
		and not capture_sprite.centered and capture_sprite.get_global_transform_with_canvas() == Transform2D.IDENTITY \
		and capture_sprite.self_modulate == Color.WHITE and capture_sprite.modulate == Color.WHITE \
		and capture_sprite.material == null and not capture_sprite.use_parent_material \
		and capture_sprite.clip_children == CanvasItem.CLIP_CHILDREN_DISABLED \
		and capture_sprite.get_parent() == setups.F.vp and producer.canvas_item_default_texture_filter == setups.F.vp.canvas_item_default_texture_filter \
		and clean_ground(setups.F.ground, setups.F.vp) and clean_ground(capture_ground, producer) \
		and (DisplayServer.get_name() == "headless" or is_equal_approx(DisplayServer.screen_get_scale(), 1.0))

func change_camera(next: Vector2) -> bool:
	if measuring:
		return false
	var live: GroundNode = setups.F.ground
	live.origin = next
	# Preserve the source ordered wall slot stream; translate every wall RID by
	# moving its single parent in both arms, as the isolated camera pans.
	setups.F.walls.position = next - HOME_CAMERA
	camera = next
	return live.background_cache.update(live, next, Vector2.ZERO)

func state_key() -> Array:
	var live: GroundNode = setups.F.ground
	return [camera, live.origin, live.tile, live.zoom, live.opacity, live.ui_scale,
		live._parking_owned(), live.background_cache.signature, live.background_cache.material.shader.get_rid(),
		live.get_global_transform_with_canvas(), live.get_viewport_rect().size, setups.F.vp.size]

func can_use_cache() -> bool:
	return not cache_key.is_empty() and camera == camera.round() and native_nearest() \
		and producer.render_target_update_mode == SubViewport.UPDATE_DISABLED and state_key() == cache_key

func layer(use_cache: bool, show_walls: bool = true) -> String:
	# Even cache misses draw exactly one backdrop, via the original path.
	var selected := use_cache and can_use_cache()
	setups.F.ground.visible = not selected
	capture_sprite.visible = selected
	setups.F.walls.visible = show_walls
	return "C" if selected else "R"

func prepare_bake() -> bool:
	if measuring or camera != camera.round() or not native_nearest():
		return false
	var live: GroundNode = setups.F.ground
	capture_ground.origin = camera
	capture_ground.tile = live.tile
	capture_ground.zoom = live.zoom
	capture_ground.opacity = live.opacity
	capture_ground.ui_scale = live.ui_scale
	if not capture_ground.background_cache.update(capture_ground, camera, Vector2.ZERO):
		return false
	# The source has no walls and the bake is untimed and consumed only later.
	return true

func framed_image(texture: ViewportTexture) -> PackedByteArray:
	var image := texture.get_image()
	if image == null or image.get_size() != F:
		return PackedByteArray()
	image.convert(Image.FORMAT_RGBA8)
	return image.get_data()

func fully_opaque(bytes: PackedByteArray) -> bool:
	if bytes.size() != F.x * F.y * 4:
		return false
	for offset in range(3, bytes.size(), 4):
		if bytes[offset] != 255:
			return false
	return true

func bake(reference: PackedByteArray) -> bool:
	if not prepare_bake():
		return false
	# Retire previous cache before issuing real capture work.
	cache_key = []
	capture_sprite.visible = false
	setups.F.ground.visible = true
	producer.render_target_update_mode = SubViewport.UPDATE_ONCE
	await settled(2)
	producer.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var produced := framed_image(target_texture)
	if not fully_opaque(produced):
		pixel_gate = "ground_alpha"
		return false
	if produced != reference:
		return false
	cache_key = state_key().duplicate(true)
	bake_count += 1
	return can_use_cache()

func cache_only_matches(reference: PackedByteArray) -> bool:
	if layer(true, false) != "C":
		return false
	await settled(3)
	return rgba("F") == reference

func images_and_invalidation() -> Dictionary:
	if layer(false, false) != "R":
		return {}
	await settled(3)
	var only_ground := rgba("F")
	if not fully_opaque(only_ground):
		pixel_gate = "ground_alpha"
		return {}
	if not await bake(only_ground) or not await cache_only_matches(only_ground):
		return {}
	layer(false)
	await settled(3)
	var original := rgba("F")
	if original == only_ground or not fully_opaque(original):
		return {}
	if layer(true) != "C":
		return {}
	await settled(3)
	if rgba("F") != original:
		return {}
	# Invalidate a material-independent sprite assumption and prove fallback
	# never overlays the unsupported sprite with the valid original.
	pixel_gate = "fallback_parity"
	capture_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if layer(true) != "R" or capture_sprite.visible or not setups.F.ground.visible:
		return {}
	await settled(3)
	if rgba("F") != original:
		return {}
	capture_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if layer(true) != "C":
		return {}
	await settled(3)
	if rgba("F") != original:
		return {}
	pixel_gate = "shifted_parity"
	# Test stale camera rejection with a non-integer transition and a new,
	# settled integer camera. Both keep all ordered walls live.
	if not change_camera(HOME_CAMERA + Vector2(0.5, 0.0)) or layer(true) != "R":
		return {}
	if not change_camera(SHIFTED_CAMERA) or layer(true) != "R":
		return {}
	await settled(3)
	var moved_fallback := rgba("F")
	layer(false)
	await settled(3)
	if rgba("F") != moved_fallback or moved_fallback == original:
		return {}
	layer(false, false)
	await settled(3)
	var moved_ground := rgba("F")
	if not fully_opaque(moved_ground):
		pixel_gate = "ground_alpha"
		return {}
	if moved_ground == only_ground or not await bake(moved_ground) or not await cache_only_matches(moved_ground):
		return {}
	if layer(true) != "C":
		return {}
	await settled(3)
	if rgba("F") != moved_fallback:
		return {}
	pixel_gate = "restored_parity"
	if not change_camera(HOME_CAMERA) or layer(true, false) != "R":
		return {}
	await settled(3)
	if rgba("F") != only_ground or not await bake(only_ground) or not await cache_only_matches(only_ground):
		return {}
	var checks := {}
	for label in ["R", "C"]:
		if layer(label == "C") != label:
			return {}
		await settled(WARM)
		var pixels := rgba("F")
		var counter := counters("F")
		if pixels != original:
			return {}
		if counter[1] <= 0 or (label == "C" and counter[0] != 662) or (label == "R" and counter[0] <= 662):
			pixel_gate = "counter_confound"
			return {}
		checks[label] = {"primitive_count":counter[0],"draw_calls":counter[1],"rgba_sha256":hash_data(pixels)}
	return checks

func current_masks(label: String, wall_ids: Array) -> bool:
	var row: Dictionary = setups.F
	return current_scene == null and root.size == F and Engine.max_fps == 60 \
		and DisplayServer.window_get_vsync_mode() == vsync and row.vp.render_target_update_mode == SubViewport.UPDATE_ALWAYS \
		and producer.render_target_update_mode == SubViewport.UPDATE_DISABLED and native_nearest() \
		and row.walls.visible and row.rids == wall_ids and bake_count == 3 \
		and (row.ground.visible == (label == "R")) and (capture_sprite.visible == (label == "C")) \
		and camera == HOME_CAMERA and (label == "R" or can_use_cache())

func timed_arm(label: String, expected: Dictionary, wall_ids: Array) -> Dictionary:
	if layer(label == "C") != label or not current_masks(label, wall_ids):
		return {}
	var count := [expected.primitive_count, expected.draw_calls]
	await settled(WARM - 3)
	for i in range(3):
		await RenderingServer.frame_post_draw
		if counters("F") != count:
			return {}
	var before := counters("F")
	n = 0
	bad = false
	measuring = true
	await settled(SAMPLES)
	measuring = false
	var after := counters("F")
	if n != SAMPLES or bad or pre_us != 0 or before != count or after != count or not current_masks(label, wall_ids):
		return {}
	return {"state":label,"warm_frames":WARM,"sample_frames":SAMPLES,"primitive_count":after[0],
		"draw_calls":after[1],"draw_us":Array(draws),"interval_us":Array(intervals)}

func run() -> void:
	if not stage_parameters() or not expanded_triangles_equal():
		fail("geometry"); return
	script_sha = FileAccess.get_sha256("res://backdrop.gd")
	if script_sha.length() != 64:
		fail("geometry"); return
	var args := OS.get_cmdline_user_args()
	var setup_only := args.size() == 4 and args[3] == "--setup-only"
	if args.size() == 4 and not setup_only:
		fail("gate_env"); return
	if setup_only:
		if DisplayServer.get_name() != "headless":
			fail("gate_env"); return
	elif DisplayServer.get_name() != "X11" or OS.get_name() != "Linux" or root.size != F or Engine.max_fps != 60 \
			or RenderingServer.get_current_rendering_method() != "gl_compatibility" \
			or RenderingServer.get_current_rendering_driver_name() != "opengl3" \
			or not RenderingServer.get_video_adapter_name().to_lower().contains("llvmpipe") \
			or not (RenderingServer.get_video_adapter_vendor() + " " + RenderingServer.get_video_adapter_api_version()).to_lower().contains("mesa"):
		fail("gate_env"); return
	vsync = DisplayServer.window_get_vsync_mode()
	RenderingServer.set_default_clear_color(Color(0.08, 0.09, 0.1, 1.0))
	if not build("F", F) or not build_producer() or not prepare_bake() or current_scene != null:
		fail("setup"); return
	setups.F.vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var ids: Array = setups.F.rids.duplicate()
	for i in range(streams.size()):
		submit(ids[i], streams[i].packed)
	if setup_only:
		if can_use_cache() or layer(true) != "R" or not change_camera(SHIFTED_CAMERA) \
				or can_use_cache() or layer(true) != "R" or not prepare_bake() or setups.F.rids != ids:
			fail("setup"); return
		write({"schema":"ll-backdrop-cache-setup-397-v1","setup_only":true,"main_absent":true,
			"fixture_sha256":script_sha,"wall_sha256":wall_sha,"mechanism_sha256":fixture_sha,"wall_slots":84,
			"wall_triangles":660,"native_nearest_1to1":true,"fallback_without_bake":true,"wall_rids_same":true})
		return
	var states := await images_and_invalidation()
	if states.is_empty() or setups.F.rids != ids or bake_count != 3:
		fail(pixel_gate); return
	expected_thread = OS.get_main_thread_id()
	draws.resize(SAMPLES)
	intervals.resize(SAMPLES)
	RenderingServer.frame_pre_draw.connect(pre)
	RenderingServer.frame_post_draw.connect(post)
	var blocks := []
	for index in range(BLOCKS):
		var block := []
		for label in (["R", "C", "C", "R"] if index % 2 == 0 else ["C", "R", "R", "C"]):
			var timing := await timed_arm(label, states[label], ids)
			if timing.is_empty():
				fail("arm_unstable"); return
			block.append(timing)
		blocks.append(block)
	write({"schema":"ll-backdrop-cache-397-v1","source":{"commit":"ce1435afb2329a6c1d2d77a8a19923dfd96bd205",
		"tree":"03632a0d56e4294f5664859656c8809541766d1b"},"fixture_sha256":script_sha,"wall_sha256":wall_sha,
		"mechanism_sha256":fixture_sha,"renderer_class":"X11_llvmpipe_compatibility","engine_cap":60,"vsync_mode":vsync,
		"warm_frames":WARM,"sample_frames":SAMPLES,"states":states,"blocks":blocks,
		"proofs":{"main_absent":true,"ground_opaque":true,"exact_rgba":true,"wall_rids_same":true,
			"producer_disabled_during_samples":true,"native_nearest_1to1":true,"camera_miss_falls_back":true,
			"moved_rebuild_rgba":true,"restored_rgba":true,"no_double_draw":true}})
