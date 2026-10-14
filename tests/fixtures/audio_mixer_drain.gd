extends RefCounted
## Test-only: wait for observed mixer progress after ordinary stop/free.
static func wait_for_mixer_cycles(tree: SceneTree) -> Dictionary:
	var started = Time.get_ticks_usec()
	var cutoff = started + 1000000
	var previous = AudioServer.get_time_since_last_mix()
	var observed = 0
	var invalid = not is_finite(previous) or previous < 0.0
	while observed < 2 and not invalid and Time.get_ticks_usec() < cutoff:
		await tree.process_frame
		var current = AudioServer.get_time_since_last_mix()
		invalid = not is_finite(current) or current < 0.0
		if not invalid and current < previous:
			observed += 1
		previous = current
	# AudioServer's main-thread update reclaims mixer-retired playback refs.
	if observed == 2 and not invalid and Time.get_ticks_usec() < cutoff:
		await tree.process_frame
	var elapsed = Time.get_ticks_usec() - started
	return {"ok": observed == 2 and not invalid and elapsed <= 1000000,
		"observed_cycles": observed, "elapsed_usec": elapsed,
		"timeout_usec": 1000000, "invalid_telemetry": invalid,
		"mix_rate": AudioServer.get_mix_rate()}
