extends SceneTree
const Feedback = preload("res://scripts/audio/cafe_feedback_sfx.gd")
const Main = preload("res://scripts/main.gd")

class DisposableSettings extends "res://scripts/ui/cafe_settings.gd":
	# Exercise actual playback/controls without reading original preferences.
	func load_preferences(): _apply_buses()

class Owner extends Node:
	var audio_players = {}
	var music_enabled = true
	var save_writes_suppressed = true
	var pause_button: Button
	var paused = false

var checks = 0
var failures = []

func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)

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
	check(Feedback.CASH.loop_mode == AudioStreamWAV.LOOP_DISABLED and Feedback.PLACE.loop_mode == AudioStreamWAV.LOOP_DISABLED, "finite imported one-shots")
	check(is_equal_approx(Feedback.CASH.get_length(), 1.5), "cash duration retained")
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
	owner.queue_free()
	await process_frame
	await process_frame
	check(not is_instance_valid(voice), "scene exit releases existing voice")
	print("FEEDBACK_SFX_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
