extends RefCounted
## Opt-in import boundary for authored sprites. Not a character generator/save format.
## One owner retains one texture; frame selection never loads or builds resources.
const FORMAT = "little_leaf.character_sprite_pack.v1"
const CELL = Vector2i(80, 80)
const PIVOT = Vector2(40, 73)
const DENSITY = 8
const FACINGS = ["e", "se", "s", "sw", "w", "nw", "n", "ne"]
const POSES = ["idle", "walk", "seated", "task"]
const SPECIES = ["bear", "rabbit", "fox", "cat", "dog", "red_panda"]
const MAX_FRAMES = 4096
var _texture: Texture2D
var _frames: Dictionary = {}
var _metadata: Dictionary = {}

static func _sha(value) -> bool:
	if not value is String or value.length() != 64: return false
	for c in value:
		if not c in "0123456789abcdef": return false
	return true

static func _integer(value, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value == floor(value) and value >= minimum and value <= maximum

static func _key(pose: String, facing: String, frame: int) -> String:
	return "%s/%s/%d" % [pose, facing, frame]

static func _pair(value, x: int, y: int) -> bool:
	return value is Array and value.size() == 2 and _integer(value[0], x, x) and _integer(value[1], y, y)

func import_pack(manifest_path: String, expected_source_sha256: String) -> Dictionary:
	# Validate into local temporaries. A rejected replacement leaves the live pack intact.
	if not _sha(expected_source_sha256): return {"ok": false, "error": "invalid_source_authority"}
	var file := FileAccess.open(manifest_path, FileAccess.READ)
	if file == null or file.get_length() > 262144: return {"ok": false, "error": "manifest_unavailable_or_too_large"}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK: return {"ok": false, "error": "invalid_json"}
	var m = parser.data
	if not m is Dictionary or m.get("format") != FORMAT: return {"ok": false, "error": "unknown_format"}
	if m.get("source_sha256") != expected_source_sha256: return {"ok": false, "error": "source_authority_mismatch"}
	if not m.get("species") in SPECIES or not _pair(m.get("cell"), 80, 80) or not _pair(m.get("pivot"), 40, 73) or not _integer(m.get("density"), DENSITY, DENSITY):
		return {"ok": false, "error": "incompatible_geometry"}
	# Accept only one sibling PNG; manifests cannot traverse directories or load URIs.
	var filename = m.get("image")
	if not filename is String or filename.is_empty() or filename.get_file() != filename or filename.contains("\\") or filename.contains(":") or filename.get_extension() != "png":
		return {"ok": false, "error": "invalid_image_path"}
	if not _sha(m.get("image_sha256")): return {"ok": false, "error": "invalid_image_hash"}
	var image_path := manifest_path.get_base_dir().path_join(filename)
	var image_file := FileAccess.open(image_path, FileAccess.READ)
	if image_file == null or image_file.get_length() > 134217728: return {"ok": false, "error": "image_unavailable_or_too_large"}
	if FileAccess.get_sha256(image_path) != m.image_sha256: return {"ok": false, "error": "image_hash_mismatch"}
	# Bound decoded memory before invoking the PNG decoder (not just compressed bytes).
	if image_file.get_length() < 33 or image_file.get_buffer(8) != PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]): return {"ok": false, "error": "invalid_image"}
	image_file.big_endian = true
	if image_file.get_32() != 13 or image_file.get_buffer(4).get_string_from_ascii() != "IHDR": return {"ok": false, "error": "invalid_image"}
	var width := image_file.get_32()
	var height := image_file.get_32()
	if width < 1 or height < 1 or width > 8192 or height > 8192 or width * height > 16777216: return {"ok": false, "error": "invalid_dimensions_or_alpha"}
	var image := Image.new()
	if image.load(image_path) != OK or image.is_empty(): return {"ok": false, "error": "invalid_image"}
	if image.get_width() > 8192 or image.get_height() > 8192 or not image.detect_alpha(): return {"ok": false, "error": "invalid_dimensions_or_alpha"}
	var entries = m.get("frames")
	if not entries is Array or entries.is_empty() or entries.size() > MAX_FRAMES: return {"ok": false, "error": "invalid_frames"}
	var validated: Dictionary = {}
	for entry in entries:
		if not entry is Dictionary: return {"ok": false, "error": "invalid_frame"}
		var pose = entry.get("pose")
		var facing = entry.get("facing")
		var frame = entry.get("frame")
		var rect = entry.get("rect")
		if not pose in POSES or not facing in FACINGS or not _integer(frame, 0, 255): return {"ok": false, "error": "invalid_frame_identity"}
		if not rect is Array or rect.size() != 4: return {"ok": false, "error": "invalid_frame_rect"}
		for coordinate in rect:
			if not _integer(coordinate, 0, 8192): return {"ok": false, "error": "invalid_frame_rect"}
		if rect[2] != CELL.x * DENSITY or rect[3] != CELL.y * DENSITY or rect[0] + rect[2] > image.get_width() or rect[1] + rect[3] > image.get_height():
			return {"ok": false, "error": "out_of_bounds_frame"}
		var key := _key(pose, facing, int(frame))
		if validated.has(key): return {"ok": false, "error": "duplicate_frame"}
		validated[key] = Rect2(rect[0], rect[1], rect[2], rect[3])
	# Incomplete poses are explicit: missing task/walk frames return false, never another facing.
	for facing in FACINGS:
		if not validated.has(_key("idle", facing, 0)): return {"ok": false, "error": "missing_idle_facing"}
	_texture = ImageTexture.create_from_image(image)
	_frames = validated
	_metadata = {"species": m.species, "source_sha256": expected_source_sha256, "image_sha256": m.image_sha256, "frame_count": entries.size()}
	return {"ok": true, "metadata": _metadata.duplicate(true)}

func has_frame(pose: String, facing: String, frame: int = 0) -> bool:
	return _texture != null and _frames.has(_key(pose, facing, frame))

func draw_frame(canvas: CanvasItem, floor_root: Vector2, pose: String, facing: String, frame: int = 0, scale_factor: float = 1.0) -> bool:
	if not is_finite(scale_factor) or scale_factor <= 0.0 or not has_frame(pose, facing, frame): return false
	canvas.draw_texture_rect_region(_texture, Rect2(floor_root - PIVOT * scale_factor, Vector2(CELL) * scale_factor), _frames[_key(pose, facing, frame)])
	return true

func metadata() -> Dictionary:
	return _metadata.duplicate(true)

func clear() -> void:
	_texture = null
	_frames.clear()
	_metadata.clear()
