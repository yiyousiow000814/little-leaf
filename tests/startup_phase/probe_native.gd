extends SceneTree
## Offline native contract test only. NOT Web path or performance evidence.
## Calls the real native empty-profile startup without replacing any method.
func _initialize():
	run.call_deferred()

func check(condition: bool, label: String):
	if not condition:
		push_error("STARTUP_PHASE_CONTRACT_FAILED " + label)
		quit(1)

func run():
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	check(game.fresh_start, "disposable profile is fresh")
	check(not game.save_recovery_blocked, "startup is not blocked")
	check(game.illustration != null and game.cafe_intro != null, "inherited real setup completed")
	check(game.get_script().resource_path == "res://qa/startup_phase/main.gd", "entry scene overlay")
	var instrumented = "--instrumented" in OS.get_cmdline_user_args()
	if instrumented:
		check(game._detail_count == 30 and not game._detail_overflow, "all UI/music subphases recorded")
		check(game._phase_count == 16, "all eight wrappers recorded begin and end")
		var expected = [0, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 1]
		for index in expected.size():
			check(game._phase_codes[index] == expected[index], "nested method order %s" % index)
			check(game._phase_ticks[index] >= 0, "nonnegative timestamp")
			if index > 0:
				check(game._phase_ticks[index] >= game._phase_ticks[index - 1], "monotonic timestamp")
		check(not game._phase_active and not game._phase_overflow, "bounded startup collection ended")
		check(not game._phase_emitted, "packet cannot emit before a genuine post-draw")
	else:
		check(not "_phase_count" in game, "control has no recording state")
	print("STARTUP_PHASE_NATIVE_CONTRACT mode=", "instrumented" if instrumented else "control", " passed=true browser=false renderer_measured=false")
	game.queue_free()
	await process_frame
	quit()
