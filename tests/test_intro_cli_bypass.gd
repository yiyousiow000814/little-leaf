extends SceneTree
const Main = preload("res://scripts/main.gd")
const Intro = preload("res://scripts/cafe_intro.gd")
var checks = 0
var failures = []
func _initialize(): run.call_deferred()
func check(ok, label):
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ", label)
func run():
	check("--skip-intro" in OS.get_cmdline_user_args(), "explicit bypass flag")
	check(OS.get_user_data_dir().begins_with(OS.get_environment("XDG_DATA_HOME")), "isolated profile")
	Intro.shown_this_session = false
	var game = Main.new(); game.process_mode = Node.PROCESS_MODE_DISABLED; root.add_child(game)
	check(not game.cafe_intro.active, "CLI bypass leaves intro inactive")
	check(game.cafe_intro.cover == null, "CLI bypass creates no overlay")
	check(game.cafe_intro.hud_colors.is_empty(), "CLI bypass does not fade HUD")
	check(not Intro.shown_this_session, "CLI bypass leaves session flag unused")
	print("INTRO_CLI_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	if game.music_tween != null: game.music_tween.kill()
	for player in game.audio_players.values(): player.stop(); player.stream = null
	await create_timer(.3).timeout
	game.queue_free(); await process_frame; await process_frame
	quit(0 if failures.is_empty() else 1)
