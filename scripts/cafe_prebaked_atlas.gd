extends RefCounted
## Lossless snapshots of the unchanged native 4x atlas output. CI binds these
## resources to the procedural source and compares regenerated RGBA bytes.
const PATHS = {
	"furniture":"res://assets/cache/furniture-atlas.png",
	"moving":"res://assets/cache/moving-atlas.png",
	"heads":"res://assets/cache/heads-atlas.png"
}

static func try_load(atlas, name: String, expected_size: Vector2i) -> bool:
	# Diagnostic legacy/mipmap paths remain available for source comparisons.
	if "--runtime-atlases" in OS.get_cmdline_user_args():return false
	if name == "furniture" and atlas.use_mipmaps_for_qa:return false
	var path: String = PATHS[name]
	if not ResourceLoader.exists(path, "Texture2D"):return false
	var started = Time.get_ticks_usec()
	var texture = load(path) as Texture2D
	if texture == null or Vector2i(texture.get_size()) != expected_size:return false
	atlas.texture = texture
	atlas.state = "ready"
	atlas.stats["state"] = "ready"
	atlas.stats["prebaked"] = true
	atlas.stats["warmup_ms"] = (Time.get_ticks_usec() - started) / 1000.0
	atlas.stats["retained_image_bytes"] = expected_size.x * expected_size.y * 4
	atlas.stats["bake_draws"] = 0
	return true
