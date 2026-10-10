extends RefCounted
## Standalone bounded JSON contract only. Does not read/write a game save.
const Wardrobe = preload("res://scripts/customer_wardrobe.gd")
const MAX_BYTES = 4096

static func encode(record) -> Dictionary:
	var checked: Dictionary = Wardrobe.validate(record)
	if not checked.ok: return checked
	return {"ok": true, "json": JSON.stringify(checked.record, "", true)}

static func decode(text: String, expected_identity: String = "") -> Dictionary:
	if text.to_utf8_buffer().size() > MAX_BYTES: return {"ok": false, "error": "record_too_large"}
	var parser = JSON.new()
	if parser.parse(text) != OK: return {"ok": false, "error": "invalid_json"}
	return Wardrobe.validate(parser.data, expected_identity)

static func retain_or_generate(existing, identity: String, seed: String, species: String = "") -> Dictionary:
	# null is explicitly new. An invalid/unknown saved record must never reroll.
	if not Wardrobe.valid_identity(identity): return {"ok": false, "error": "invalid_identity"}
	if existing == null: return Wardrobe.generate(identity, seed, species)
	return Wardrobe.validate(existing, identity)
