extends SceneTree
## Disposable retained-wall + stock-ground mechanism fixture. No Main.
const F := Vector2i(1360, 880)
const H := Vector2i(680, 440)
const WARM := 12
const SAMPLES := 36
const STATES := ["FP", "HP", "FS", "HS", "FE", "HE"]
const ORDER := [0, 1, 5, 2, 4, 3]
const ENGINE_HASH := "7d41c59c457bd5a245092b4e7eb2d833e3b3f8c3"
var output := ""
var wall_sha := ""
var fixture_sha := ""
var pixel_gate := "pixel_parity"
var setups: Dictionary = {}
var streams: Array = []
var views: Array[SubViewport] = []
var resident_textures: Array[ViewportTexture] = []
var vsync := -1
var measuring := false
var expected_thread := 0
var pre_us := 0
var last_post_us := 0
var n := 0
var bad := false
var draws := PackedInt64Array()
var intervals := PackedInt64Array()

class GroundNode extends "res://scripts/rendering/illustrated_cafe.gd":
	func _ready(): set_process(false)
	func _process(_delta): pass
	func _draw(): pass
	func _parking_owned()->bool: return false
	func prepare_stock()->bool:
		origin = Vector2(680, 260)
		zoom = 1.0
		tile = Vector2(39, 19.5)
		ground_art._build_pavement()
		return background_cache.update(self, origin, Vector2.ZERO)

func _initialize() -> void:
	run.call_deferred()

func fail(reason: String) -> void:
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify({"schema":"ll-render-mechanism-failure-397-v1","stage_code":reason}))
			file.close()
	push_error("MECHANISM_FIXTURE: " + reason)
	finish(2)

func finish(code: int) -> void:
	for row in setups.values():
		for item in row.rids:
			RenderingServer.free_rid(item)
	setups.clear()
	quit(code)

func write(value: Dictionary) -> void:
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		fail("output")
		return
	file.store_string(JSON.stringify(value))
	file.close()
	finish(0)

func hash_data(bytes: PackedByteArray) -> String:
	var h := HashingContext.new()
	if h.start(HashingContext.HASH_SHA256) != OK or h.update(bytes) != OK:
		return ""
	return h.finish().hex_encode()

func stage_parameters() -> bool:
	if Engine.get_version_info().get("hash") != ENGINE_HASH:
		return false
	var args := OS.get_cmdline_user_args()
	if args.size() < 3 or args.size() > 4 or not args[0].is_absolute_path() or not args[2].is_absolute_path():
		return false
	output = args[2]
	wall_sha = FileAccess.get_sha256(args[0])
	fixture_sha = FileAccess.get_sha256("res://mechanism.gd")
	if fixture_sha.length() != 64 or wall_sha != args[1] or wall_sha.length() != 64:
		return false
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not doc is Dictionary or not doc.get("scenes") is Array:
		return false
	var selected: Dictionary = {}
	for slot_scene: Variant in doc.scenes:
		if slot_scene is Dictionary and slot_scene.get("name") == "starter":
			if not selected.is_empty():
				return false
			selected = slot_scene
	if selected.get("slots", []).size() != 84:
		return false
	var quad_count := 0
	var ids := {}
	for slot: Dictionary in selected.slots:
		if not slot.has("id") or ids.has(slot.id) or slot.get("quads", []).is_empty():
			return false
		ids[slot.id] = true
		var encoded := []
		var combined := [PackedVector2Array(), PackedColorArray(), PackedInt32Array()]
		for quad: Dictionary in slot.quads:
			if quad.xy.size() != 4 or quad.rgba.size() != 4 or quad.indices.size() != 6:
				return false
			var vertices := PackedVector2Array()
			var colors := PackedColorArray()
			var indices := PackedInt32Array()
			for j in range(4):
				var pos := Vector2(float(quad.xy[j][0]), float(quad.xy[j][1]))
				var color := Color(float(quad.rgba[j][0]), float(quad.rgba[j][1]), float(quad.rgba[j][2]), float(quad.rgba[j][3]))
				if not pos.is_finite() or not (is_finite(color.r) and is_finite(color.g) and is_finite(color.b) and is_finite(color.a)):
					return false
				vertices.append(pos)
				colors.append(color)
			for index: Variant in quad.indices:
				if int(index) != index or int(index) < 0 or int(index) > 3:
					return false
				indices.append(int(index))
			encoded.append([vertices, colors, indices])
			var offset: int = combined[0].size()
			combined[0].append_array(vertices)
			combined[1].append_array(colors)
			for index in indices:
				combined[2].append(offset + index)
			quad_count += 1
		streams.append({"id":slot.id,"pieces":encoded,"packed":combined})
	return quad_count == 330

func expanded_triangles_equal() -> bool:
	for slot in streams:
		var joined: Array = slot.packed
		var at := 0
		for piece in slot.pieces:
			for v in piece[2]:
				if at >= joined[2].size():
					return false
				var w: int = joined[2][at]
				if joined[0][w] != piece[0][v] or joined[1][w] != piece[1][v]:
					return false
				at += 1
		if at != joined[2].size():
			return false
	return true

func ground_mesh_digest(ground: GroundNode) -> String:
	var inputs := []
	var meshes := [ground.grass_mesh, ground.ground_art.pavement_mesh]
	meshes.append_array(ground.background_cache.meshes)
	for mesh in meshes:
		if not mesh is ArrayMesh:
			return ""
		for surface in range(mesh.get_surface_count()):
			inputs.append(mesh.surface_get_arrays(surface))
	return hash_data(var_to_bytes(inputs))

func build(prefix: String, size: Vector2i) -> bool:
	var vp := SubViewport.new()
	vp.world_2d = World2D.new()
	vp.size = size
	vp.size_2d_override = F
	vp.size_2d_override_stretch = true
	vp.disable_3d = true
	vp.transparent_bg = true
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(vp)
	views.append(vp)
	resident_textures.append(vp.get_texture())
	var ground := GroundNode.new()
	vp.add_child(ground)
	var walls := Node2D.new()
	walls.z_index = 1
	vp.add_child(walls)
	var rids: Array[RID] = []
	setups[prefix] = {"vp":vp,"ground":ground,"walls":walls,"rids":rids}
	if not ground.prepare_stock() or ground.get_viewport_rect().size != Vector2(F) or vp.size != size:
		return false
	var material: ShaderMaterial = ground.background_cache.material
	if material == null or material.shader == null or ground.background_cache.command_count != 6:
		return false
	setups[prefix]["shader"] = material.shader.get_rid()
	setups[prefix]["mesh_sha"] = ground_mesh_digest(ground)
	for i in range(streams.size()):
		var item := RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(item, walls.get_canvas_item())
		RenderingServer.canvas_item_set_draw_index(item, i)
		rids.append(item)
	return true

func submit(item: RID, values: Array) -> void:
	RenderingServer.canvas_item_add_triangle_array(item, values[2], values[0], values[1])

func activate(prefix: String, mode: String) -> bool:
	if measuring:
		return false
	for vp in views:
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var row: Dictionary = setups[prefix]
	row.vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	row.ground.visible = mode != "E"
	row.walls.visible = mode == "P" or mode == "S"
	if row.walls.visible:
		for i in range(streams.size()):
			var rid: RID = row.rids[i]
			RenderingServer.canvas_item_clear(rid)
			if mode == "P":
				submit(rid, streams[i].packed)
			else:
				for piece in streams[i].pieces:
					submit(rid, piece)
	return layouts_fixed(prefix)

func layouts_fixed(prefix: String) -> bool:
	for key in ["F", "H"]:
		var row: Dictionary = setups[key]
		var mode := SubViewport.UPDATE_ALWAYS if key == prefix else SubViewport.UPDATE_DISABLED
		if row.vp.render_target_update_mode != mode or row.vp.size != (F if key == "F" else H) \
				or row.vp.size_2d_override != F or not row.vp.size_2d_override_stretch \
				or row.ground.get_viewport_rect().size != Vector2(F) or row.ground.background_cache.rebuilds != 1:
			return false
	return current_scene == null

func counters(prefix: String) -> Array:
	var rid: RID = setups[prefix].vp.get_viewport_rid()
	return [
		RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS,
			RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
		RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS,
			RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)]

func settled(frames: int) -> void:
	for i in range(frames):
		await RenderingServer.frame_post_draw

func rgba(prefix: String) -> PackedByteArray:
	var image: Image = setups[prefix].vp.get_texture().get_image()
	if image == null or image.get_size() != (F if prefix == "F" else H):
		return PackedByteArray()
	image.convert(Image.FORMAT_RGBA8)
	return image.get_data()

func pixel_at(bytes: PackedByteArray, index: int) -> int:
	return bytes[index] | (bytes[index + 1] << 8) | (bytes[index + 2] << 16) | (bytes[index + 3] << 24)

func diff_bounds(a: PackedByteArray, b: PackedByteArray, size: Vector2i, search: Rect2i) -> Rect2i:
	var lo := size
	var hi := Vector2i(-1, -1)
	for y in range(search.position.y, search.end.y):
		for x in range(search.position.x, search.end.x):
			var j := (y * size.x + x) * 4
			if pixel_at(a, j) != pixel_at(b, j):
				lo.x = mini(lo.x, x); lo.y = mini(lo.y, y)
				hi.x = maxi(hi.x, x); hi.y = maxi(hi.y, y)
	if hi.x < lo.x:
		return Rect2i()
	return Rect2i(lo, hi + Vector2i.ONE - lo)

func same_scaled(a: Rect2i, b: Rect2i) -> bool:
	return a.has_area() and b.has_area() and (Vector2(a.position) * 0.5 - Vector2(b.position)).abs().length_squared() <= 2.0 \
		and (Vector2(a.end) * 0.5 - Vector2(b.end)).abs().length_squared() <= 2.0 \
		and (Vector2(a.position) * 0.5 - Vector2(b.position)).abs().x <= 1.0 \
		and (Vector2(a.position) * 0.5 - Vector2(b.position)).abs().y <= 1.0 \
		and (Vector2(a.end) * 0.5 - Vector2(b.end)).abs().x <= 1.0 \
		and (Vector2(a.end) * 0.5 - Vector2(b.end)).abs().y <= 1.0

func diff_at(bytes: Array, size: Vector2i, at: Vector2i) -> bool:
	if at.x < 0 or at.y < 0 or at.x >= size.x or at.y >= size.y:
		return false
	var index := (at.y * size.x + at.x) * 4
	return pixel_at(bytes[0], index) != pixel_at(bytes[1], index)

func landmarks_match(full: Array, half: Array) -> bool:
	# Use authored triangle centroids, not fitted image coordinates. Require
	# at least three separated corresponding wall marks within a half-size pixel.
	var matched_cells := {}
	for slot in streams:
		for piece in slot.pieces:
			for index in [0, 3]:
				var pos: Vector2 = (piece[0][piece[2][index]] + piece[0][piece[2][index + 1]] + piece[0][piece[2][index + 2]]) / 3.0
				var source := Vector2i(pos.floor())
				var nominal := Vector2i((pos * 0.5).floor())
				if not diff_at(full, F, source):
					continue
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						if diff_at(half, H, nominal + Vector2i(dx, dy)):
							matched_cells[Vector2i(source.x >> 5, source.y >> 5)] = true
	return matched_cells.size() >= 3

func check_images() -> Dictionary:
	var states := {}
	var bounds := {}
	var wall_images := {}
	for prefix in ["F", "H"]:
		var size := F if prefix == "F" else H
		var layers := {}
		for mode in ["E", "G", "P", "S", "E", "P"]:
			if not activate(prefix, mode):
				return {}
			await settled(WARM)
			var bytes := rgba(prefix)
			if bytes.size() != size.x * size.y * 4:
				return {}
			if layers.has(mode) and layers[mode] != bytes:
				return {}
			layers[mode] = bytes
			if mode != "G":
				var count := counters(prefix)
				states[prefix + mode] = {"width":size.x,"height":size.y,"primitive_count":count[0],"draw_calls":count[1],
					"rgba_sha256":hash_data(bytes),"wall_slots":0 if mode == "E" else streams.size(),
					"wall_triangles":0 if mode == "E" else 660}
		if layers.P != layers.S:
			return {}
		if layers.P == layers.G or layers.G == layers.E:
			pixel_gate = "layer_crop"
			return {}
		var all := Rect2i(Vector2i.ZERO, size)
		var wall_bounds := diff_bounds(layers.P, layers.G, size, all)
		var ground_bounds := diff_bounds(layers.G, layers.E, size, all)
		if not wall_bounds.has_area() or not ground_bounds.has_area():
			pixel_gate = "layer_crop"
			return {}
		bounds[prefix] = [wall_bounds, ground_bounds]
		wall_images[prefix] = [layers.P, layers.G]
	if not same_scaled(bounds.F[0], bounds.H[0]) or not same_scaled(bounds.F[1], bounds.H[1]) or not landmarks_match(wall_images.F, wall_images.H):
		pixel_gate = "layer_crop"
		return {}
	return states

func pre() -> void:
	if not measuring:
		return
	if OS.get_thread_caller_id() != expected_thread or pre_us != 0:
		bad = true
		return
	pre_us = Time.get_ticks_usec()

func post() -> void:
	var now := Time.get_ticks_usec()
	if measuring:
		if OS.get_thread_caller_id() != expected_thread or last_post_us <= 0 or pre_us <= last_post_us or now <= pre_us or n >= SAMPLES:
			bad = true
		else:
			draws[n] = now - pre_us
			intervals[n] = now - last_post_us
			n += 1
	pre_us = 0
	last_post_us = now

func arm(state: String, expected: Dictionary) -> Dictionary:
	var prefix := state.substr(0, 1)
	if not activate(prefix, state.substr(1, 1)):
		return {}
	var count := [expected.primitive_count, expected.draw_calls]
	await settled(WARM - 3)
	for i in range(3):
		await RenderingServer.frame_post_draw
		if counters(prefix) != count:
			return {}
	var before := counters(prefix)
	n = 0
	bad = false
	measuring = true
	await settled(SAMPLES)
	measuring = false
	var after := counters(prefix)
	if n != SAMPLES or bad or pre_us != 0 or Engine.max_fps != 60 or DisplayServer.window_get_vsync_mode() != vsync \
			or root.size != F or before != count or after != count or not layouts_fixed(prefix):
		return {}
	return {"state":state,"warm_frames":WARM,"sample_frames":SAMPLES,"primitive_count":after[0],
		"draw_calls":after[1],"draw_us":Array(draws),"interval_us":Array(intervals)}

func run() -> void:
	if not stage_parameters() or not expanded_triangles_equal():
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
	if not build("F", F) or not build("H", H) or setups.F.mesh_sha.is_empty() or setups.F.mesh_sha != setups.H.mesh_sha \
			or setups.F.shader != setups.H.shader or current_scene != null:
		fail("setup"); return
	if setup_only:
		if not activate("F", "P") or not activate("H", "S") or not activate("H", "E"):
			fail("setup"); return
		write({"schema":"ll-render-mechanism-setup-397-v1","setup_only":true,"main_absent":true,
			"fixture_sha256":fixture_sha,"wall_sha256":wall_sha,"wall_slots":84,"wall_triangles":660,"same_ground_meshes":true,
			"same_logical_rect":true,"same_shader":true,"inactive_disabled":true})
		return
	var states := await check_images()
	if states.is_empty():
		fail(pixel_gate); return
	if states.FP.primitive_count < 660 or states.FP.primitive_count != states.HP.primitive_count \
			or states.FP.primitive_count != states.FS.primitive_count or states.FP.primitive_count != states.HS.primitive_count \
			or states.FE.primitive_count != 0 or states.HE.primitive_count != 0 \
			or states.FP.draw_calls <= 0 or states.FS.draw_calls <= 0 or states.HS.draw_calls <= 0 \
			or states.FP.draw_calls != states.HP.draw_calls:
		fail("counter_confound"); return
	expected_thread = OS.get_main_thread_id()
	draws.resize(SAMPLES)
	intervals.resize(SAMPLES)
	RenderingServer.frame_pre_draw.connect(pre)
	RenderingServer.frame_post_draw.connect(post)
	var blocks := []
	for offset in range(STATES.size()):
		var block := []
		for ordinal in ORDER:
			var state: String = STATES[(ordinal + offset) % STATES.size()]
			var timing := await arm(state, states[state])
			if timing.is_empty():
				fail("arm_unstable"); return
			block.append(timing)
		blocks.append(block)
	write({"schema":"ll-render-mechanism-397-v1","source":{"commit":"ce1435afb2329a6c1d2d77a8a19923dfd96bd205",
		"tree":"03632a0d56e4294f5664859656c8809541766d1b"},"fixture_sha256":fixture_sha,"wall_sha256":wall_sha,"renderer_class":"X11_llvmpipe_compatibility",
		"engine_cap":60,"vsync_mode":vsync,"warm_frames":WARM,"sample_frames":SAMPLES,"states":states,"blocks":blocks,
		"proofs":{"main_absent":true,"same_root":true,"same_logical_rect":true,"same_ground_meshes":true,"same_shader":true,
			"same_expanded_triangles":true,"same_wall_slot_ids_per_size":true,"inactive_disabled":true,"full_rgba_equal":true,
			"half_rgba_equal":true,"full_layers_visible":true,"half_layers_visible":true,"bounds_match":true,"redraw_verified":true}})
