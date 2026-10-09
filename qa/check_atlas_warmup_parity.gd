extends SceneTree
## Separate, untimed render check: concurrent baseline builds versus FIFO builds.
## No game instance, player save, screenshot or timing-claim side effects.
const Furniture = preload("res://scripts/furniture_static_atlas.gd")
const Moving = preload("res://scripts/moving_art_atlas.gd")
const Heads = preload("res://scripts/character_head_atlas.gd")
var failures = []
func _initialize():run.call_deferred()
func wait_ready(atlases: Array) -> bool:
	var deadline = Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		var ready = true
		for atlas in atlases:
			if atlas.state == "failed_fallback":return false
			ready = ready and atlas.is_ready()
		if ready:return true
		await process_frame
	return false
func digest(atlas) -> String:
	var hash = HashingContext.new();hash.start(HashingContext.HASH_SHA256)
	hash.update(atlas.texture.get_image().get_data())
	return hash.finish().hex_encode()
func run():
	if DisplayServer.get_name() == "headless":
		printerr("Rendered atlas parity requires the approved native CI renderer")
		quit(2);return
	var baseline = [Furniture.new(), Moving.new(), Heads.new()]
	for atlas in baseline:
		atlas.state = "warming"
		atlas._build.call_deferred(self)
	if not await wait_ready(baseline):
		printerr("Baseline atlas preparation failed or timed out");quit(1);return
	var expected = []
	for atlas in baseline:expected.append(digest(atlas))
	# Drop reference textures before the second set; both use identical render inputs.
	baseline.clear()
	var artist = Node2D.new();root.add_child(artist)
	var candidate = [Furniture.new(), Moving.new(), Heads.new()]
	for atlas in candidate:atlas.request(artist)
	if not await wait_ready(candidate):
		printerr("Candidate atlas preparation failed or timed out");quit(1);return
	var actual = []
	for atlas in candidate:actual.append(digest(atlas))
	for i in range(expected.size()):
		if expected[i] != actual[i]:failures.append("Atlas %d differs" % i)
	print("ATLAS_RENDER_PARITY_RESULT ", JSON.stringify({"checks":3,"baseline_sha256":expected,"candidate_sha256":actual,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
