extends SceneTree
const ServiceSfx = preload("res://scripts/audio/cafe_service_sfx.gd")
const Model = preload("res://scripts/core/cafe_model.gd")

class Settings extends RefCounted:
	var sfx_enabled = true
	var sfx_volume = 55.0
	var effects = {"click": AudioStreamWAV.new(), "coin": AudioStreamWAV.new(), "place": AudioStreamWAV.new()}
	var sfx_player: AudioStreamPlayer

class Illustration extends RefCounted:
	var zoom = 2.2
	func camera_zoom_limits() -> Vector2: return Vector2(0.3, 2.2)

class Owner extends Node:
	var model = Model.new()
	var settings_controls = Settings.new()
	var illustration = Illustration.new()
	var staff_states = []
	var service_guests = {}
	var paused = false
	var editing = false
	var loading = false
	var save_recovery_blocked = false
	var browser_suspended = false
	var cafe_intro = null
	var compact_ui = null

class Probe extends "res://scripts/audio/cafe_service_sfx.gd":
	var starts = []
	func _play_ambient(kind: String): starts.append(kind)

var checks = 0
var failures = []

func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)

func _initialize():
	run.call_deferred()

func fixture() -> Owner:
	var owner = Owner.new()
	root.add_child(owner)
	owner.settings_controls.sfx_player = AudioStreamPlayer.new()
	owner.settings_controls.sfx_player.max_polyphony = 4
	owner.add_child(owner.settings_controls.sfx_player)
	owner.model.items = [
		{"id": 1, "kind": "stove", "x": 1, "z": 1, "rot": 0},
		{"id": 2, "kind": "table", "x": 4, "z": 2, "rot": 0},
		{"id": 3, "kind": "chair", "x": 4, "z": 3, "rot": 2},
		{"id": 4, "kind": "table", "x": 6, "z": 2, "rot": 0},
		{"id": 5, "kind": "chair", "x": 6, "z": 3, "rot": 2},
	]
	var cook_guest = {"id": 7, "phase": "cooking", "table_id": 2, "chair_id": 3, "seated": true}
	var diner = {"id": 8, "phase": "eating", "table_id": 4, "chair_id": 5, "seated": true, "mobility": {}}
	owner.model.customers = [cook_guest, diner]
	owner.service_guests = {
		7: {"guest": cook_guest, "token": 11, "meal_ready": false, "meal_station_id": 1},
		8: {"guest": diner, "token": 12, "meal_done": true, "plate_owner": "table", "plate_target_id": 4},
	}
	var face = owner.model.workface_cell(owner.model.get_item(1))
	owner.staff_states = [{"job_kind": "cook", "job_step": 1, "job_elapsed": 0.5,
		"job_guest_id": 7, "job_token": 11, "station_id": 1, "destination": face,
		"pos": Vector2(face) + Vector2(0.5, 0.5), "blocked_reason": "", "yield_time": 0.0}]
	return owner

func run():
	if AudioServer.get_bus_index("SFX") < 0:
		var index = AudioServer.bus_count
		AudioServer.set_bus_count(index + 1)
		AudioServer.set_bus_name(index, "SFX")
	var owner = fixture()
	var click = owner.settings_controls.effects.click
	var audio = ServiceSfx.new(owner)
	audio.setup_audio()
	check(owner.settings_controls.effects.coin == ServiceSfx.CASH, "existing cash hook receives supplied sample")
	check(owner.settings_controls.effects.place == ServiceSfx.PLACE, "existing placement hook receives supplied sample")
	check(owner.settings_controls.effects.click == click, "UI click unchanged")
	check(audio.player.bus == "SFX" and audio.player.max_polyphony == 1, "one service voice on existing SFX bus")
	var child_count = owner.get_child_count()
	audio.setup_audio()
	check(owner.get_child_count() == child_count, "audio setup idempotent")
	for stream in [ServiceSfx.CASH, ServiceSfx.PLACE, ServiceSfx.AMBIENT.cooking, ServiceSfx.AMBIENT.eating]:
		check(stream.get_length() > 0.0 and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "imported recording is finite one-shot")
	check(is_equal_approx(ServiceSfx.CASH.get_length(), 1.5), "cash duration retained")
	check(is_equal_approx(ServiceSfx.AMBIENT.cooking.get_length(), 2.25), "cooking duration retained")
	check(ServiceSfx.activities(owner) == {"cooking": true, "eating": true}, "real work and seated plate custody eligible")
	var staff: Dictionary = owner.staff_states[0]
	var invalid_staff = {"job_kind": "", "job_step": 0, "job_elapsed": 0.0, "job_token": 99,
		"station_id": -1, "blocked_reason": "Blocked", "yield_time": 1.0, "pos": Vector2.ZERO}
	for field in invalid_staff:
		var before = staff[field]
		staff[field] = invalid_staff[field]
		check(not ServiceSfx.activities(owner).cooking, "cooking excludes " + field)
		staff[field] = before
	var record: Dictionary = owner.service_guests[7]
	record.meal_ready = true
	check(not ServiceSfx.activities(owner).cooking, "prepared meal is not cooking")
	record.meal_ready = false
	var guest: Dictionary = record.guest
	record.guest = guest.duplicate(true)
	check(not ServiceSfx.activities(owner).cooking, "stale copied guest cannot sound")
	record.guest = guest
	var diner: Dictionary = owner.model.customers[1]
	var invalid_diner = {"phase": "leaving", "seated": false, "withdrawn": true,
		"meal_abandoned": true, "mobility": {"moving": true}}
	for field in invalid_diner:
		var before = diner.get(field)
		var had = diner.has(field)
		diner[field] = invalid_diner[field]
		check(not ServiceSfx.activities(owner).eating, "eating excludes " + field)
		if had: diner[field] = before
		else: diner.erase(field)
	owner.service_guests[8].plate_owner = "staff"
	check(not ServiceSfx.activities(owner).eating, "missing table plate excludes eating")
	owner.service_guests[8].plate_owner = "table"
	var limits = Vector2(0.3, 2.2)
	check(ServiceSfx.zoom_gain(limits.x, limits) == 0.0, "far zoom silent")
	check(ServiceSfx.zoom_gain(lerpf(limits.x, limits.y, 0.60), limits) == 0.0, "near threshold silent")
	check(ServiceSfx.zoom_gain(lerpf(limits.x, limits.y, 0.725), limits) > 0.0, "near transition audible")
	check(ServiceSfx.zoom_gain(limits.y, limits) == 1.0, "closest zoom full candidate level")
	check(ServiceSfx.zoom_gain(NAN, limits) == 0.0, "invalid zoom silent")
	var probe = Probe.new(owner)
	probe.setup_audio()
	var immutable = JSON.stringify([owner.model.coins, owner.model.items, owner.model.customers, owner.staff_states, owner.service_guests])
	probe.tick(0.01)
	check(probe.starts.is_empty(), "entry does not start immediately")
	for frame in 1200: probe.tick(0.1)
	check(probe.starts.count("cooking") <= 21 and probe.starts.count("eating") <= 24, "many frames stay globally rate bounded")
	check(probe.starts.has("cooking") and probe.starts.has("eating"), "both categories receive opportunities")
	check(JSON.stringify([owner.model.coins, owner.model.items, owner.model.customers, owner.staff_states, owner.service_guests]) == immutable, "audio does not mutate jobs, customers, wallet or save inputs")
	for field in ["paused", "editing", "loading", "save_recovery_blocked", "browser_suspended"]:
		owner.set(field, true)
		probe.tick(0.1)
		check(not probe.player.playing and not probe._active.cooking, "suppression clears voice and clocks: " + field)
		owner.set(field, false)
		var count = probe.starts.size()
		probe.tick(0.1)
		check(probe.starts.size() == count, "resume never bursts: " + field)
	for control in ["sfx_enabled", "sfx_volume"]:
		owner.settings_controls.set(control, false if control == "sfx_enabled" else 0.0)
		probe.tick(0.1)
		check(not probe.player.playing and not probe._active.eating, "SFX control clears reminders: " + control)
		owner.settings_controls.set(control, true if control == "sfx_enabled" else 55.0)
	AudioServer.set_bus_mute(0, true)
	probe.tick(0.1)
	check(not probe._active.cooking, "platform Master mute suppresses service cues")
	AudioServer.set_bus_mute(0, false)
	owner.cafe_intro = {"active": true}
	probe.tick(0.1)
	check(not probe._active.cooking, "intro suppresses service cues")
	owner.cafe_intro = null
	owner.compact_ui = {"viewport_too_small": true}
	probe.tick(0.1)
	check(not probe._active.cooking, "unavailable viewport suppresses service cues")
	owner.compact_ui = null
	probe.tick(0.1)
	probe.tick(100.0)
	var count = probe.starts.size()
	probe.tick(100.0)
	check(probe.starts.size() <= count + 1, "large delta permits at most one opportunity per update")
	probe.tick(0.01)
	check(probe.starts.size() <= count + 1, "large delta leaves no backlog")
	owner.illustration.zoom = limits.x
	for frame in 10: probe.tick(0.1)
	count = probe.starts.size()
	for frame in 100: probe.tick(0.1)
	check(probe.starts.size() == count and probe._gain == 0.0, "far zoom fades out and stays silent")
	owner.illustration.zoom = limits.y
	probe.tick(0.1)
	check(probe.starts.size() == count, "zooming near schedules a future cue")
	owner.settings_controls.sfx_player.stream = ServiceSfx.CASH
	owner.settings_controls.sfx_player.play()
	probe.tick(2.0)
	check(probe.starts.size() == count, "foreground cash wins over due reminders")
	owner.settings_controls.sfx_player.stop()
	probe.tick(0.1)
	check(probe.starts.size() == count, "busy foreground opportunity was consumed")
	audio._play_ambient("cooking")
	check(audio.player.playing, "actual imported voice starts")
	audio.suspend()
	check(not audio.player.playing, "actual imported voice stops")
	probe.suspend()
	owner.queue_free()
	await process_frame
	await process_frame
	check(not is_instance_valid(audio.player) and not is_instance_valid(probe.player), "scene exit releases owned players")
	print("SERVICE_SFX_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
