extends RefCounted

# Supplied recordings, with only the prepared gain changes baked in.
# Scene-owned audio state never enters the model or a saved service snapshot.
const CASH = preload("res://assets/audio/sfx/cash_volume_v01.wav")
const PLACE = preload("res://assets/audio/sfx/placement_volume_v01.wav")
const AMBIENT = {
	"cooking": preload("res://assets/audio/sfx/cooking_volume_v01.wav"),
	"eating": preload("res://assets/audio/sfx/eating_volume_v01.wav"),
}
const ENTRY_DELAY = {"cooking": 0.8, "eating": 1.2}
const INTERVAL = {"cooking": 6.0, "eating": 5.0}
const OBSERVATION_SECONDS = 0.1
const FADE_PER_SECOND = 5.0

var game
var player: AudioStreamPlayer
var _due = ENTRY_DELAY.duplicate()
var _active = {"cooking": false, "eating": false}
var _observed = {"cooking": false, "eating": false}
var _sample_remaining = 0.0
var _target_gain = 0.0
var _gain = 0.0
var _current_kind = ""

func _init(owner_game):
	game = owner_game

func setup_audio():
	if is_instance_valid(player): return
	# Keep existing transaction hooks, click feedback, bus and preferences.
	game.settings_controls.effects["coin"] = CASH
	game.settings_controls.effects["place"] = PLACE
	player = AudioStreamPlayer.new()
	player.name = "ServiceSfx"
	player.bus = "SFX"
	player.max_polyphony = 1
	player.volume_db = -80.0
	game.add_child(player)

func can_play() -> bool:
	var settings = game.settings_controls
	return settings != null and settings.sfx_enabled and settings.sfx_volume > 0.0 \
		and not game.paused and not game.editing and not game.loading \
		and not game.save_recovery_blocked and not game.browser_suspended \
		and not (game.cafe_intro != null and game.cafe_intro.active) \
		and not (game.compact_ui != null and game.compact_ui.viewport_too_small) \
		and not AudioServer.is_bus_mute(0)

func suspend():
	if is_instance_valid(player): player.stop()
	for kind in ENTRY_DELAY:
		_due[kind] = ENTRY_DELAY[kind]
		_active[kind] = false
		_observed[kind] = false
	_sample_remaining = 0.0
	_target_gain = 0.0
	_gain = 0.0
	_current_kind = ""
	if is_instance_valid(player): player.volume_db = -80.0

func tick(delta: float):
	if delta <= 0.0 or not can_play():
		suspend()
		return
	_sample_remaining -= delta
	if _sample_remaining <= 0.0:
		_sample_remaining = OBSERVATION_SECONDS
		_observed = activities(game)
		_target_gain = zoom_gain(game.illustration.zoom, game.illustration.camera_zoom_limits())
		if _current_kind != "" and not _observed[_current_kind]:
			player.stop()
			_current_kind = ""
	var previous_gain = _gain
	_gain = move_toward(_gain, _target_gain, delta * FADE_PER_SECOND)
	if not is_equal_approx(previous_gain, _gain):
		player.volume_db = linear_to_db(maxf(0.0001, _gain))
	if _gain <= 0.0001:
		player.stop()
		_current_kind = ""
	var foreground_busy = game.settings_controls.sfx_player.playing
	if foreground_busy:
		player.stop()
		_current_kind = ""
	var started = false
	for kind in ENTRY_DELAY:
		if not _observed[kind] or _target_gain <= 0.0001:
			_active[kind] = false
			_due[kind] = ENTRY_DELAY[kind]
			continue
		if not _active[kind]:
			_active[kind] = true
			_due[kind] = ENTRY_DELAY[kind]
			continue
		_due[kind] -= delta
		if _due[kind] > 0.0: continue
		# Consume busy opportunities. Never queue historical sounds or catch up.
		_due[kind] = INTERVAL[kind]
		if started or player.playing or foreground_busy or _gain <= 0.0001: continue
		_play_ambient(kind)
		started = true

func _play_ambient(kind: String):
	player.stream = AMBIENT[kind]
	player.play()
	_current_kind = kind

static func zoom_gain(zoom: float, limits: Vector2) -> float:
	if not is_finite(zoom) or not limits.is_finite() or limits.y <= limits.x: return 0.0
	# Only the near end of the same camera range is audible, on any viewport.
	var start = lerpf(limits.x, limits.y, 0.60)
	var full = lerpf(limits.x, limits.y, 0.85)
	return smoothstep(start, full, zoom)

static func _live_record(owner, id: int) -> Dictionary:
	var record: Dictionary = owner.service_guests.get(id, {})
	if record.is_empty(): return {}
	for guest in owner.model.customers:
		if int(guest.id) == id and is_same(record.guest, guest): return record
	return {}

static func activities(owner) -> Dictionary:
	var result = {"cooking": false, "eating": false}
	for staff in owner.staff_states:
		if str(staff.get("job_kind", "")) != "cook" or int(staff.get("job_step", -1)) != 1: continue
		if float(staff.get("job_elapsed", 0.0)) <= 0.0 or str(staff.get("blocked_reason", "")) != "": continue
		if float(staff.get("yield_time", 0.0)) > 0.0: continue
		var record = _live_record(owner, int(staff.get("job_guest_id", -1)))
		if record.is_empty() or int(record.token) != int(staff.get("job_token", -1)): continue
		var guest: Dictionary = record.guest
		if str(guest.phase) != "cooking" or bool(guest.get("withdrawn", false)) or bool(guest.get("meal_abandoned", false)): continue
		var station_id = int(staff.get("station_id", -1))
		if bool(record.get("meal_ready", false)) or int(record.get("meal_station_id", -1)) != station_id: continue
		var stove: Dictionary = owner.model.get_item(station_id)
		if str(stove.get("kind", "")) != "stove": continue
		var destination: Vector2i = staff.destination
		if destination != owner.model.workface_cell(stove): continue
		if staff.pos.distance_to(Vector2(destination) + Vector2(0.5, 0.5)) >= 0.03: continue
		result.cooking = true
		break
	for guest in owner.model.customers:
		if str(guest.phase) != "eating" or not bool(guest.get("seated", false)): continue
		if bool(guest.get("withdrawn", false)) or bool(guest.get("meal_abandoned", false)) or not guest.get("mobility", {}).is_empty(): continue
		var record: Dictionary = owner.service_guests.get(int(guest.id), {})
		if record.is_empty() or not is_same(record.guest, guest) or not bool(record.get("meal_done", false)): continue
		if str(record.get("plate_owner", "")) != "table" or int(record.get("plate_target_id", -1)) != int(guest.table_id): continue
		if str(owner.model.get_item(int(guest.table_id)).get("kind", "")) != "table": continue
		if str(owner.model.get_item(int(guest.chair_id)).get("kind", "")) != "chair": continue
		result.eating = true
		break
	return result
