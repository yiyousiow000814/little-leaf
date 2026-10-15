extends SceneTree
const AudioDrain = preload("res://tests/fixtures/audio_mixer_drain.gd")
const Feedback = preload("res://scripts/audio/cafe_feedback_sfx.gd")
const Main = preload("res://scripts/main.gd")
const Model = preload("res://scripts/core/cafe_model.gd")
const Start = preload("res://scripts/minimal_start.gd")

class DisposableSettings extends "res://scripts/ui/cafe_settings.gd":
	# Exercise actual playback/controls without reading original preferences.
	func load_preferences(): _apply_buses()
	var cues: Array[String] = []
	func play_sfx(kind = "click"):
		cues.append(kind)
		super.play_sfx(kind)

class Owner extends Node:
	var audio_players = {}
	var music_enabled = true
	var save_writes_suppressed = true
	var pause_button: Button
	var paused = false
	var illustration
	var model
	var interaction
	var settings_controls
	var staff_states = []
	var editing = true
	var save_recovery_blocked = false
	var rotation_step = 0
	var saves = 0
	var rebuilds = 0
	var asynchronous_save = true
	var pending_save = false
	var native_save_success = true
	func _save():
		saves += 1
		if asynchronous_save:
			pending_save = true
			return false
		return native_save_success
	func complete_save(): pending_save = false
	func _apply_edit_staff_positions(previous: Array, positions: Array) -> bool:
		return previous.is_empty() and positions.is_empty()
	func _cancel_selection():
		if interaction != null: interaction.cancel(false)
	func _rebuild_furniture(): rebuilds += 1
	func _update_ui(): pass

class PlacementPointer extends "res://scripts/gameplay/cafe_interaction.gd":
	# Replace only viewport projection. Release, EditPlan validation/commit and
	# feedback use the real caller; no successful transaction is stubbed.
	func _init(owner): super(owner)
	func refresh(screen: Vector2):
		last_pointer = screen
		if drag_active: _update_validity(screen)
	func _update_validity(_screen: Vector2):
		placement_receipt = edit_plan.prepare(game.model, drag_kind, drag_item_id, drag_rotation, drag_cell, _staff_positions())
		drag_valid = bool(placement_receipt.ok)

var checks = 0
var failures = []

func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)


func arm(pointer, kind: String, id: int, cell: Vector2i):
	pointer.drag_kind = kind
	pointer.drag_item_id = id
	pointer.drag_cell = cell
	pointer.drag_rotation = 0
	pointer.drag_active = true
	pointer._left_down = true
	pointer._gesture = "drag"

func placement_callers(owner, settings, voice):
	owner.model = Model.new()
	Start.apply(owner.model)
	owner.model.begin_decoration_session()
	owner.settings_controls = settings
	var pointer = PlacementPointer.new(owner)
	owner.interaction = pointer
	settings.cues.clear()
	var id = owner.model._next_item_id
	var coins = owner.model.coins
	arm(pointer, "plant", -1, Vector2i(8, 6))
	pointer._release_left(Vector2.ZERO)
	check(not owner.model.get_item(id).is_empty() and owner.model.coins == coins - owner.model.price_of("plant"), "real release commits a purchase once")
	check(owner.pending_save and owner.saves == 1, "submitted Web-style save stays pending and returns false")
	check(settings.cues == ["place"] and voice.playing and voice.stream == Feedback.PLACE, "accepted purchase starts supplied placement feedback before save completes")
	var revision = owner.model.revision
	pointer._release_left(Vector2.ZERO)
	check(owner.model.revision == revision and owner.saves == 1 and settings.cues == ["place"], "duplicate release cannot purchase, save or cue again")
	owner.complete_save()
	check(not owner.pending_save and settings.cues == ["place"], "late save completion does not replay placement feedback")
	voice.stop()
	arm(pointer, "plant", id, Vector2i(8, 7))
	pointer._release_left(Vector2.ZERO)
	var moved = owner.model.get_item(id)
	check(Vector2i(moved.x, moved.z) == Vector2i(8, 7) and owner.model.coins == coins - owner.model.price_of("plant"), "real move commits without another purchase")
	check(owner.pending_save and owner.saves == 2 and settings.cues == ["place", "place"] and voice.playing, "accepted move cues once with an asynchronous save")
	voice.stop()
	var before = JSON.stringify([owner.model.items, owner.model.coins, owner.model.revision])
	arm(pointer, "plant", id, Vector2i(8, 7))
	pointer._release_left(Vector2.ZERO)
	check(JSON.stringify([owner.model.items, owner.model.coins, owner.model.revision]) == before and owner.saves == 2 and settings.cues.size() == 2 and not voice.playing, "same-cell same-rotation move is silent and unsaved")
	arm(pointer, "plant", -1, Vector2i(8, 7))
	pointer._release_left(Vector2.ZERO)
	check(JSON.stringify([owner.model.items, owner.model.coins, owner.model.revision]) == before and owner.saves == 2 and settings.cues.size() == 2 and not voice.playing, "invalid overlapping purchase is silent and unsaved")
	arm(pointer, "plant", -1, Vector2i(8, 6))
	pointer.cancel(false)
	pointer._release_left(Vector2.ZERO)
	check(JSON.stringify([owner.model.items, owner.model.coins, owner.model.revision]) == before and owner.saves == 2 and settings.cues.size() == 2 and not voice.playing, "cancelled preview cannot commit or cue on release")
	owner.save_recovery_blocked = true
	arm(pointer, "plant", -1, Vector2i(8, 6))
	pointer._release_left(Vector2.ZERO)
	check(JSON.stringify([owner.model.items, owner.model.coins, owner.model.revision]) == before and owner.saves == 2 and settings.cues.size() == 2 and not voice.playing, "recovery-blocked release stays silent and unsaved")
	owner.save_recovery_blocked = false
	owner.complete_save()
	owner.asynchronous_save = false
	arm(pointer, "plant", -1, Vector2i(8, 6))
	pointer._release_left(Vector2.ZERO)
	check(owner.saves == 3 and settings.cues.size() == 3 and voice.playing, "native successful save retains one placement cue")
	voice.stop()
	owner.native_save_success = false
	arm(pointer, "plant", -1, Vector2i(9, 6))
	pointer._release_left(Vector2.ZERO)
	check(owner.saves == 4 and settings.cues.size() == 4 and voice.playing and not owner.model.get_item(owner.model._next_item_id - 1).is_empty(), "accepted layout feedback does not misreport failed persistence as a rejected placement")
	voice.stop()
	pointer.cancel(false)
	owner.interaction = null

func _initialize(): run.call_deferred()

func run():
	check(Main.FeedbackSfx == Feedback, "actual Main compiles with supplied feedback")
	var owner = Owner.new()
	root.add_child(owner)
	var music = AudioStreamPlayer.new()
	owner.add_child(music)
	owner.audio_players.service = music
	var settings = DisposableSettings.new(owner)
	settings.persist_enabled = false
	settings.setup_audio()
	var voice = settings.sfx_player
	var click = settings.effects.click
	var children = owner.get_child_count()
	Feedback.install(settings)
	check(settings.effects.coin == Feedback.CASH, "cash catalog uses prepared recording")
	check(settings.effects.place == Feedback.PLACE, "placement catalog uses prepared recording")
	check(settings.effects.click == click, "UI click unchanged")
	check(owner.get_child_count() == children and settings.sfx_player == voice, "no added voice or player")
	check(voice.bus == "SFX" and voice.max_polyphony == 4, "existing SFX routing and voice bound retained")
	check(music.bus == "BGM" and owner.audio_players.service == music, "music player and routing unchanged")
	Feedback.install(settings)
	check(owner.get_child_count() == children, "catalog installation idempotent")
	check(Feedback.CASH is AudioStreamMP3 and not Feedback.CASH.loop and Feedback.PLACE.loop_mode == AudioStreamWAV.LOOP_DISABLED, "finite selected MP3 cash and WAV placement")
	var cash_hash = HashingContext.new();cash_hash.start(HashingContext.HASH_SHA256);cash_hash.update(Feedback.CASH.data)
	check(cash_hash.finish().hex_encode() == "95c0a024f0b1b82cd20f64a89e176943c1152074c45f0df47edd3c3b6370d862" and Feedback.CASH.get_length() > 0.0, "selected SfxCash compressed source bytes retained")
	check(absf(Feedback.PLACE.get_length() - 4608.0 / 11025.0) < 0.0001, "placement duration retained")
	for kind in ["coin", "place"]:
		settings.play_sfx(kind)
		check(voice.playing and voice.stream == settings.effects[kind], "actual imported feedback starts: " + kind)
		voice.stop()
	settings.set_audio_enabled("SFX", false)
	settings.play_sfx("coin")
	check(not voice.playing and AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "disabled SFX suppresses cash")
	settings.set_audio_enabled("SFX", true)
	settings.set_audio_volume("SFX", 0.0)
	settings.play_sfx("place")
	check(not voice.playing and AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "zero volume suppresses placement")
	settings.set_audio_volume("SFX", 55.0)
	check(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX")) - linear_to_db(0.55)) < 0.001, "existing default SFX55 bus gain retained")
	settings.play_sfx("place")
	check(voice.playing, "re-enabled feedback starts normally")
	voice.stop()
	placement_callers(owner, settings, voice)
	owner.queue_free()
	await process_frame
	await process_frame
	var audio_drain = await AudioDrain.wait_for_mixer_cycles(self)
	check(audio_drain.ok, "audio teardown observes two mixer cycles within 1s")
	print("AUDIO_TEARDOWN_RESULT ", JSON.stringify(audio_drain))
	check(not is_instance_valid(voice), "scene exit releases existing voice")
	print("FEEDBACK_SFX_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
