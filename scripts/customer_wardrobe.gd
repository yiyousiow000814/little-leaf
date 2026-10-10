extends RefCounted
## Pure candidate generation. No global RNG, scene, file, save, economy or art access.
const Catalog = preload("res://scripts/customer_wardrobe_catalog.gd")
const FORMAT = 1 # Standalone record format; NOT a game save version.
const FIELDS = ["format", "catalog", "identity", "seed", "species", "appearance", "fur", "palette", "items"]

static func valid_identity(value) -> bool:
	if not value is String or value.is_empty() or value.length() > 64: return false
	for c in value:
		if not c in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-": return false
	return true

static func valid_seed(value) -> bool:
	if not value is String or value.length() != 64: return false
	for c in value:
		if not c in "0123456789abcdef": return false
	return true

static func _pick(seed: String, identity: String, label: String, choices: Array):
	# Per-slot digest labels isolate selection from call ordering and gameplay RNG.
	var digest: String = ("%s|%s|%s|%s" % [Catalog.REVISION, seed, identity, label]).sha256_text()
	return choices[digest.substr(0, 8).hex_to_int() % choices.size()]

static func generate(identity: String, seed: String, species: String = "") -> Dictionary:
	if not valid_identity(identity) or not valid_seed(seed): return {"ok": false, "error": "invalid_identity_or_seed"}
	if species.is_empty(): species = _pick(seed, identity, "species", Catalog.SPECIES)
	if not species in Catalog.SPECIES: return {"ok": false, "error": "unknown_species"}
	var palette_ids: Array = Catalog.PALETTES.keys()
	palette_ids.sort()
	var items: Dictionary = {}
	for slot in Catalog.SLOTS:
		var choices: Array = Catalog.candidates(slot, species, items)
		if choices.is_empty(): return {"ok": false, "error": "no_compatible_" + slot}
		items[slot] = _pick(seed, identity, "item/" + slot, choices)
	return {"ok": true, "record": {"format": FORMAT, "catalog": Catalog.REVISION, "identity": identity, "seed": seed, "species": species, "appearance": _pick(seed, identity, "appearance", ["masculine", "feminine"]), "fur": _pick(seed, identity, "fur/" + species, Catalog.FUR[species]).id, "palette": _pick(seed, identity, "palette", palette_ids), "items": items}}

static func validate(record, expected_identity: String = "") -> Dictionary:
	if not record is Dictionary or record.size() != FIELDS.size(): return {"ok": false, "error": "invalid_record_shape"}
	for field in FIELDS:
		if not record.has(field): return {"ok": false, "error": "missing_" + field}
	if not (record.format is int or record.format is float) or record.format != FORMAT: return {"ok": false, "error": "unknown_format"}
	if not record.catalog is String or record.catalog != Catalog.REVISION: return {"ok": false, "error": "unknown_catalog"}
	if not valid_identity(record.identity) or not valid_seed(record.seed): return {"ok": false, "error": "invalid_identity_or_seed"}
	if not expected_identity.is_empty() and record.identity != expected_identity: return {"ok": false, "error": "identity_mismatch"}
	if not record.species is String or not record.species in Catalog.SPECIES: return {"ok": false, "error": "unknown_species"}
	if not record.appearance is String or not record.appearance in ["masculine", "feminine"]: return {"ok": false, "error": "unknown_appearance"}
	if not record.palette is String or not Catalog.PALETTES.has(record.palette): return {"ok": false, "error": "unknown_palette"}
	if not record.fur is String or not Catalog.FUR[record.species].any(func(f): return f.id == record.fur): return {"ok": false, "error": "species_fur_mismatch"}
	if not record.items is Dictionary or record.items.size() != Catalog.SLOTS.size(): return {"ok": false, "error": "invalid_items"}
	for slot in Catalog.SLOTS:
		var item_id = record.items.get(slot)
		if not item_id is String: return {"ok": false, "error": "missing_item_" + slot}
		if item_id == "none":
			if not slot in Catalog.OPTIONAL: return {"ok": false, "error": "required_item_" + slot}
		elif not Catalog.ITEMS.has(item_id) or Catalog.ITEMS[item_id].slot != slot or not Catalog.compatible(item_id, record.species, record.items):
			return {"ok": false, "error": "incompatible_item_" + slot}
	var restored: Dictionary = record.duplicate(true)
	# Godot JSON reads numbers as floats. Canonicalize the accepted integer tag
	# without changing any selected identity, fur, palette or clothing values.
	restored.format = FORMAT
	return {"ok": true, "record": restored}

static func render_contract(record) -> Dictionary:
	var checked: Dictionary = validate(record)
	if not checked.ok: return checked
	var parts: Dictionary = {}
	for slot in Catalog.SLOTS:
		var item_id: String = record.items[slot]
		if item_id == "none": continue
		parts[slot] = Catalog.asset_contract(item_id, record.species)
		parts[slot]["tone"] = Catalog.PALETTES[record.palette][Catalog.COLOR_ROLES[slot]]
	return {"ok": true, "species_fit": Catalog.FIT[record.species].duplicate(true), "fur": Catalog.FUR[record.species].filter(func(f): return f.id == record.fur)[0].duplicate(true), "parts": parts, "status": "pending_art_review"}
