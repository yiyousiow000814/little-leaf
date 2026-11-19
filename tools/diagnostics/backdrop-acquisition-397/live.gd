extends "res://ll397_gain_probe.gd"
## Ordinary UPDATE_ONCE observes natural frame signals only. This is elapsed
## cadence/interval accounting, not the controlled acquisition counterfactual.
const LIVE_FRAMES := 8
const LIVE_DEADLINE_US := 5000000
const LIVE_PREFIX_PRIMITIVES := 139288
var live_kind := ""
var live_size := Vector2i.ZERO
var live_key: Array = []
var live_old_key: Array = []
var live_rid: Array = []
var live_rows: Array = []
var live_pre: Dictionary = {}
var live_fault := ""
var live_done := false
var live_last_post := 0
var live_thread := 0
var live_last_global_post := -1
var live_arm_started := 0
var live_arm_ended := 0
var live_prior_post := 0

func live_begin(kind: String, size: Vector2i, key: Array = [], old_key: Array = [], prior_post: int = 0) -> void:
	live_kind = kind
	live_size = size
	live_key = key.duplicate(true)
	live_old_key = old_key.duplicate(true)
	live_rid = []
	live_rows = []
	live_pre = {}
	live_fault = ""
	live_done = false
	live_last_post = prior_post
	if prior_post == 0:
		live_last_global_post = -1

func live_bad(code: String) -> void:
	live_fault = code
	live_kind = ""

func live_visible(size: Vector2i) -> bool:
	var root := get_tree().root
	return DisplayServer.get_name() == "X11" and root.visible and root.mode != Window.MODE_MINIMIZED 		and root.size == size and root.get_visible_rect().size == Vector2(size) and DisplayServer.get_window_list().size() == 1 		and is_instance_valid(game.compact_ui) and not game.compact_ui.viewport_too_small and not game.compact_ui.has_open_popup() 		and not is_instance_valid(game.startup_readiness) and artist.is_visible_in_tree()

func live_frame_pre() -> void:
	if live_kind.is_empty():
		return
	if OS.get_thread_caller_id() != live_thread or not live_pre.is_empty() \
			or (live_last_global_post >= 0 and forced_post != live_last_global_post):
		live_bad("live_pre_order")
		return
	var size := get_tree().root.size
	# X11 resize delivery is asynchronous. Keep ordinary old-size posts as
	# interval anchors, not new-size misses or acquisition frames.
	var awaiting_resize := live_kind == "transition" and live_size == SMALL and size == FRAME
	if (size != live_size and not awaiting_resize) or not live_visible(size) or not same_guest_cooking() or not matched_target() 			or Engine.max_fps != 60 or DisplayServer.window_get_vsync_mode() != saved_vsync:
		live_bad("live_environment")
		return
	var current := root_target()
	if current.is_empty() or (not awaiting_resize and not live_rid.is_empty() and live_rid != current):
		live_bad("live_root_target")
		return
	if not awaiting_resize:
		live_rid = current
	# Explicit guard precedes the timestamp, before the native root draw.
	backdrop.refresh_before_root(artist)
	var state: Dictionary = backdrop.drawing_state()
	var key: Array = backdrop.key_for(artist)
	live_pre = {"started":Time.get_ticks_usec(),"state":state,"key":key,"frame":Engine.get_process_frames(),
		"waiting_resize":awaiting_resize,"target":current}

func live_frame_post() -> void:
	var now := Time.get_ticks_usec()
	if live_kind.is_empty():
		return
	if live_pre.is_empty():
		live_bad("live_post_order")
		return
	var start := int(live_pre.started)
	var prior: Dictionary = live_pre.state
	var old_frame := int(live_pre.frame)
	var key: Array = live_pre.key
	var awaiting_resize := bool(live_pre.waiting_resize)
	var expected_rid: Array = live_pre.target
	live_pre = {}
	var current: Dictionary = backdrop.drawing_state()
	if OS.get_thread_caller_id() != live_thread or now <= start or now - start > LIVE_DEADLINE_US \
			or root_target() != expected_rid or Engine.get_process_frames() != old_frame \
			or not same_guest_cooking() or backdrop.key_for(artist) != key:
		live_bad("live_post_order")
		return
	var counts := root_counter()
	if counts[0] <= 0 or counts[1] <= 0 or int(prior.get("generation", -1)) < 0 \
			or prior.get("generation") != current.get("generation"):
		live_bad("live_counters_or_generation")
		return
	var elapsed := now - start
	var interval := 0 if live_last_post == 0 else now - live_last_post
	if interval < 0 or interval > LIVE_DEADLINE_US:
		live_bad("live_interval")
		return
	live_last_post = now
	live_last_global_post = forced_post
	if awaiting_resize:
		return
	if live_kind == "transition":
		if key == live_old_key or prior.get("selected") != false or not bool(prior.get("root_original")) \
				or current.get("selected") != false or not bool(current.get("root_original")) or backdrop.pending() or interval <= 0:
			live_bad("live_immediate_miss")
			return
		live_rows.append({"new_target_original":true,"pending":false,"pre_to_post_us":elapsed,"post_interval_us":interval})
	elif live_kind == "static":
		if not prior.get("root_original", false) or prior.get("selected") != false \
				or not current.get("root_original", false) or current.get("selected") != false or backdrop.pending():
			live_bad("live_static_not_original")
			return
		if key.is_empty() or key != live_key:
			live_rows.clear()
			live_key = key
			interval = 0
		if key.is_empty():
			live_last_post = 0
			return
		live_rows.append({"pre_to_post_us":elapsed,"post_interval_us":interval})
	elif live_kind == "acquire":
		if key.is_empty() or key != live_key or not prior.get("root_original", false) or prior.get("selected") != false \
				or not current.get("root_original", false) or current.get("selected") != false \
				or prior.get("pending") != true or current.get("pending") != true or not backdrop.pending() \
				or prior.get("update_mode") != SubViewport.UPDATE_ONCE or current.get("update_mode") != SubViewport.UPDATE_DISABLED 				or live_prior_post <= 0 or interval <= 0 or now - live_prior_post != interval 				or live_arm_started <= live_prior_post or live_arm_ended < live_arm_started or start < live_arm_ended:
			live_bad("live_acquisition_not_original")
			return
		# No force, readback or tick here. Native AFTER-draw owner verifies the
		# fresh producer, key/generation and exact counter, then commits.
		if not backdrop.finish(artist):
			live_bad("live_commit")
			return
		var finish_us := Time.get_ticks_usec()
		var committed: Dictionary = backdrop.drawing_state()
		var producer: Dictionary = backdrop.witness()
		if backdrop.pending() or committed.get("selected") != true or committed.get("root_original") != false \
				or committed.get("update_mode") != SubViewport.UPDATE_DISABLED \
				or committed.get("generation") != prior.get("generation") or producer.get("prefix_primitives") != LIVE_PREFIX_PRIMITIVES:
			live_bad("live_commit_evidence")
			return
		if finish_us < now or finish_us - live_arm_started > LIVE_DEADLINE_US:
			live_bad("live_acquisition_elapsed")
			return
		live_rows.append({"pre_to_post_us":elapsed,"post_interval_us":interval,
			"arm_setup_us":live_arm_ended - live_arm_started,"arm_to_finish_us":finish_us - live_arm_started,
			"producer_primitives":producer.prefix_primitives,
			"original_primitives":counts[0],"original_draw_calls":counts[1],"original_through_post":true,
			"commit_after_post":true,"producer_disabled":true,"native_once_consumed":true})
	elif live_kind == "hits" or live_kind == "anchor":
		if key != live_key or prior.get("selected") != true or current.get("selected") != true \
				or prior.get("root_original") != false or current.get("root_original") != false \
				or prior.get("pending") != false or current.get("pending") != false \
				or current.get("update_mode") != SubViewport.UPDATE_DISABLED or backdrop.pending():
			live_bad("live_expected_hit")
			return
		live_rows.append({"pre_to_post_us":elapsed,"post_interval_us":interval})
	else:
		live_bad("live_bad_stage")
		return
	var limit := LIVE_FRAMES if live_kind == "static" or live_kind == "hits" else 1
	if live_rows.size() == limit:
		live_done = true
		live_kind = ""

func live_await() -> Array:
	var deadline := Time.get_ticks_usec() + LIVE_DEADLINE_US
	while not live_done and live_fault.is_empty() and Time.get_ticks_usec() < deadline:
		await get_tree().create_timer(0.002, true, false, true).timeout
	if not live_done:
		if live_fault.is_empty():
			live_bad("live_timeout")
		return []
	return live_rows.duplicate(true)

func live_plan_rebuild(size: Vector2i) -> Dictionary:
	if backdrop.pending():
		live_bad("live_pending")
		return {}
	live_begin("static", size)
	var originals := await live_await()
	if originals.size() != LIVE_FRAMES or live_key.is_empty() or backdrop.pending():
		return {}
	var bind := live_key.duplicate(true)
	live_prior_post = live_last_post
	live_begin("acquire", size, bind, [], live_prior_post)
	live_arm_started = Time.get_ticks_usec()
	var armed: bool = backdrop.arm(artist)
	live_arm_ended = Time.get_ticks_usec()
	if not armed:
		live_bad("live_arm")
		return {}
	var acquisition := await live_await()
	if acquisition.size() != 1 or not backdrop.drawing_state().get("selected", false):
		return {}
	live_begin("hits", size, bind)
	var hits := await live_await()
	if hits.size() != LIVE_FRAMES:
		return {}
	var parity := coherent_pair(size, false)
	if parity.is_empty():
		live_bad("live_parity")
		return {}
	# coherent_pair selects original after byte/counter verification. Restore
	# cache selection outside measured windows so the next pan/resize can miss.
	if not mode("cache", true):
		live_bad("live_reselect")
		return {}
	return {"original_frames":originals,"acquisition":acquisition[0],"hit_frames":hits,"parity":parity}

func live_elapsed() -> float:
	for guest in game.model.customers:
		if int(guest.id) == tracked:
			return float(guest.get("elapsed", -1.0))
	return -1.0

func live_confirm_hit(size: Vector2i) -> bool:
	var key: Array = backdrop.key_for(artist)
	if key.is_empty():
		live_bad("live_anchor_key")
		return false
	live_begin("anchor", size, key)
	var confirmed := await live_await()
	return confirmed.size() == 1 and live_last_post > 0

func live_cases() -> Dictionary:
	var elapsed := live_elapsed()
	var animation := float(game.animation_time)
	var frames := Engine.get_process_frames()
	var pan: Vector2 = artist.pan_offset
	var previous_size := get_tree().root.size
	if previous_size != FRAME or elapsed < 0.0 or backdrop.pending():
		live_bad("live_entry")
		return {}
	backdrop.control_mode("original")
	backdrop.discard()
	backdrop.control_mode("cache")
	if not mode("cache", false):
		live_bad("live_cold_selection")
		return {}
	var home := await live_plan_rebuild(FRAME)
	if home.is_empty() or not await live_confirm_hit(FRAME):
		return {}
	var old_key: Array = backdrop.key_for(artist).duplicate(true)
	live_begin("transition", FRAME, [], old_key, live_last_post)
	artist.pan_offset = pan + Vector2(31, 22)
	if game.interaction != null:
		game.interaction.pan_offset = artist.pan_offset
	artist.update_projection()
	artist.queue_redraw()
	if artist.pan_offset.x <= pan.x or artist.pan_offset.y <= pan.y:
		live_bad("live_pan_direction")
		return {}
	var pan_miss := await live_await()
	if pan_miss.size() != 1 or not miss_pair(FRAME):
		live_bad("live_pan_fallback")
		return {}
	backdrop.control_mode("cache")
	var moved := await live_plan_rebuild(FRAME)
	if moved.is_empty() or not await live_confirm_hit(FRAME):
		return {}
	old_key = backdrop.key_for(artist).duplicate(true)
	live_begin("transition", SMALL, [], old_key, live_last_post)
	get_tree().root.size = SMALL
	var resize_miss := await live_await()
	if resize_miss.size() != 1 or not miss_pair(SMALL):
		live_bad("live_resize_fallback")
		return {}
	backdrop.control_mode("cache")
	var resized := await live_plan_rebuild(SMALL)
	if resized.is_empty():
		return {}
	if not same_guest_cooking() or live_elapsed() <= elapsed or Engine.get_process_frames() <= frames or float(game.animation_time) <= animation:
		live_bad("live_progress")
		return {}
	return {"home":home,"pan":moved,"resize":resized,"pan_first_miss":pan_miss[0],"resize_first_miss":resize_miss[0],
		"process_frames_advanced":true,"animation_advanced":true,"service_progressed":true,"same_guest_cooking":true,"warm_process_reuse":true,
		"no_forced_draws_during_observation":true,"no_readbacks_during_observation":true}

func run_live() -> Dictionary:
	if not backdrop.has_method("arm") or not backdrop.has_method("finish") or not backdrop.has_method("discard") \
			or not backdrop.has_method("pending") or not backdrop.has_method("drawing_state") \
			or not backdrop.has_method("refresh_before_root"):
		note("live_adapter")
		return {}
	live_thread = OS.get_main_thread_id()
	RenderingServer.frame_pre_draw.connect(live_frame_pre)
	RenderingServer.frame_post_draw.connect(live_frame_post)
	var result := await live_cases()
	live_kind = ""
	RenderingServer.frame_pre_draw.disconnect(live_frame_pre)
	RenderingServer.frame_post_draw.disconnect(live_frame_post)
	backdrop.discard()
	backdrop.control_mode("original")
	if result.is_empty() and not live_fault.is_empty() and not detail.has("detail_code"):
		note(live_fault)
	return result
