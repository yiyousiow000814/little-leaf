extends Node
## Source-bound active-cooking checkpoint; no cadence sampler or timing mode.
const FRAME:=Vector2i(1360,880)
const ENGINE_HASH:="7d41c59c457bd5a245092b4e7eb2d833e3b3f8c3"
var output:=""
var game:Node
var artist:Node
var backdrop:RefCounted
var tracked:=-1
var forced_pre:=0
var forced_post:=0
## Local QA proposal: no timings, no cadence mode, no full-game recapture.
const Differ=preload("res://ll397_forensic_diff.gd")
var observations:Dictionary={}
var baseline_root:RID
var baseline_texture:RID
var baseline_token:Array
var baseline_target:Window
var captures:Dictionary={}
var stage:="initial"
var halted:=false
const STATUSES=["initial","no_scene","preflight","baseline","sentinel","first_bake","legacy","matched_bake","matched","complete"]
func _ready()->void:
	if not "--diagnostic-active-backdrop-forensic" in OS.get_cmdline_user_args():return
	output=OS.get_environment("LL_ACTIVE_BACKDROP_FORENSIC")
	if not output.is_absolute_path() or not environment_ok():fail("gate_env");return
	wait_for_scene()

func fail(reason:String)->void:
	if halted:return
	halted=true
	if adapter_ok() and is_instance_valid(artist):backdrop.control_mode("original")
	var code=reason if reason in ["gate_env","adapter","scene_wait","preflight","scenario","target_policy","positive_alpha","first_bake","matched_bake","baseline","sentinel","original_restore","read_failure","selection_not_expected","primitive_conservation","cached_composite_pixel_difference"] else "unclassified"
	write_raw({"schema":"ll397-backdrop-forensic-v1","stage":stage,"result":"unqualified","failure":code,"captures":captures,"observations":observations})
	get_tree().quit(2)

func sample(id:String)->Dictionary:
	# Nonempty only after an actual root capture; metadata makes pre/post/RID/size/format failures distinct.
	var pre:=forced_pre
	var post:=forced_post
	RenderingServer.force_draw(false,0.0)
	RenderingServer.force_sync()
	var root:=get_tree().root
	var tex:=root.get_texture()
	var stable:bool=root==baseline_target and root.get_viewport_rid()==baseline_root and tex!=null and tex.get_rid()==baseline_texture and root.size==FRAME
	var im:Image=tex.get_image() if stable else null
	var dims:bool=im!=null and im.get_size()==FRAME
	var fmt:int=im.get_format() if im!=null else -1
	var format_ok:=fmt==Image.FORMAT_RGBA8
	var bytes:=PackedByteArray()
	if dims and format_ok:bytes=im.get_data()
	var cnt:=root_counter()
	var rec={"target_stable":stable,"pre":forced_pre-pre,"post":forced_post-post,"same_tick":frame_token()==baseline_token,
		"read_present":im!=null,"dimensions_ok":dims,"rgba8":format_ok,"byte_count":bytes.size(),"primitive_count":cnt[0],"draw_calls":cnt[1]}
	captures[id]=rec
	if not (stable and rec.pre==1 and rec.post==1 and rec.same_tick and dims and format_ok and bytes.size()==FRAME.x*FRAME.y*4 and cnt[0]>0 and cnt[1]>0):return {}
	return {"pix":bytes,"cnt":cnt}

func sentinel_check(a:Dictionary)->bool:
	var layer=CanvasLayer.new();layer.layer=127
	get_tree().root.add_child(layer)
	var rid=RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(rid,layer.get_canvas())
	RenderingServer.canvas_item_add_rect(rid,Rect2(14,14,43,39),Color(0.9,0.1,0.6,1))
	var plus=sample("sentinel_on")
	RenderingServer.free_rid(rid);get_tree().root.remove_child(layer);layer.free()
	var off=sample("sentinel_off")
	if plus.is_empty() or off.is_empty():return false
	var delta:Dictionary=Differ.summarize(a.pix,plus.pix,FRAME,true)
	var restore=Differ.summarize(a.pix,off.pix,FRAME)
	observations.sentinel={"diff":delta,"restore":restore,"counter_restored":a.cnt==off.cnt}
	return delta.changed>0 and delta.changed<=43*39 and mini(delta.outside_sentinel,delta.outside_sentinel_flipped)==0 and restore.changed==0 and a.cnt==off.cnt

func arm(label:String,match_root:bool,ref:Dictionary)->String:
	stage="matched_bake" if match_root else "first_bake"
	var pre:=forced_pre;var post:=forced_post
	if not mode("original",false) or not backdrop.target_policy(match_root,artist):return "target_policy"
	if not backdrop.bake_once(artist):return stage
	RenderingServer.force_sync()
	var witness=backdrop.witness()
	var trace={"target_flags":backdrop.target_class(),"producer_once_events":[forced_pre-pre,forced_post-post],
		"producer_disabled":witness.producer_disabled,"producer_primitives":witness.prefix_primitives,
		"producer_alpha_255":backdrop.producer_is_rgba_opaque()}
	observations[label]=trace
	if trace.producer_once_events!=[1,1] or not trace.producer_disabled or not trace.producer_alpha_255:return "positive_alpha"
	stage=label
	if not mode("original",false):return "selection_not_expected"
	var a=sample(label+"_original")
	if a.is_empty():return "read_failure"
	trace.after_bake_stock=Differ.summarize(ref.pix,a.pix,FRAME)
	if trace.after_bake_stock.changed!=0 or a.cnt!=ref.cnt:return "original_restore"
	if not mode("cache",true):return "selection_not_expected"
	var c=sample(label+"_cached")
	if not mode("original",false):return "selection_not_expected"
	var restored=sample(label+"_restored")
	if c.is_empty() or restored.is_empty():return "read_failure"
	trace.cached_diff=Differ.summarize(a.pix,c.pix,FRAME)
	trace.restored_diff=Differ.summarize(a.pix,restored.pix,FRAME)
	trace.actual_removed=a.cnt[0]-c.cnt[0]
	trace.expected_removed=int(witness.prefix_primitives)-2
	trace.counter_ok=(witness.prefix_primitives>2 and c.cnt[0]>0 and c.cnt[1]>0 and trace.actual_removed==trace.expected_removed)
	trace.restore_counter_ok=a.cnt==restored.cnt
	if trace.restored_diff.changed!=0 or not trace.restore_counter_ok:return "original_restore"
	if not trace.counter_ok:return "primitive_conservation"
	if trace.cached_diff.changed>0:return "cached_composite_pixel_difference"
	return "exact_parity"

func measure()->void:
	stage="preflight"
	if not same_guest_cooking() or not canvas_scene_admitted() or get_tree().root.size!=FRAME or Engine.max_fps!=60 \
			or not backdrop.has_method("target_policy") or get_tree().root.transparent_bg or get_tree().root.use_hdr_2d:
		fail("preflight");return
	backdrop.control_mode("original");artist.queue_redraw()
	await get_tree().create_timer(0.18,true,false,true).timeout
	if not same_guest_cooking() or backdrop.key_for(artist).is_empty():fail("preflight");return
	baseline_token=frame_token();baseline_target=get_tree().root;baseline_root=baseline_target.get_viewport_rid();baseline_texture=baseline_target.get_texture().get_rid()
	RenderingServer.frame_pre_draw.connect(seen_pre);RenderingServer.frame_post_draw.connect(seen_post)
	stage="baseline"
	if not mode("original",false):fail("baseline");return
	var a=sample("stock_0");var repeat=sample("stock_1")
	if a.is_empty() or repeat.is_empty():fail("read_failure");return
	observations.stock_repeat=Differ.summarize(a.pix,repeat.pix,FRAME)
	observations.stock_counts_stable=a.cnt==repeat.cnt
	if observations.stock_repeat.changed>0 or not observations.stock_counts_stable:fail("baseline");return
	stage="sentinel"
	if not sentinel_check(a):fail("sentinel");return
	var legacy=arm("legacy",false,a);observations.legacy_decision=legacy
	# No A/B inference unless original state restored and pixels/counters/readback independently qualified.
	if not legacy in ["exact_parity","cached_composite_pixel_difference"]:
		fail(legacy);return
	var corrected=arm("matched",true,a);observations.matched_decision=corrected
	if not corrected in ["exact_parity","cached_composite_pixel_difference"]:
		fail(corrected);return
	if frame_token()!=baseline_token or not same_guest_cooking():fail("scenario");return
	stage="complete";write_raw({"schema":"ll397-backdrop-forensic-v1","stage":stage,"result":"pair_only_no_timing","observations":observations,"captures":captures})
	get_tree().quit()

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


func frame_token() -> Array:
	return [Engine.get_process_frames(), Engine.get_physics_frames(), get_tree().current_scene.get_instance_id()]


func seen_pre() -> void:
	forced_pre += 1


func seen_post() -> void:
	forced_post += 1


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

