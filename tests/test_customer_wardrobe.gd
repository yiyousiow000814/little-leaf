extends SceneTree
## Only pure candidate modules and synthetic identities; no Main or player save.
const Catalog = preload("res://scripts/customer_wardrobe_catalog.gd")
const Wardrobe = preload("res://scripts/customer_wardrobe.gd")
const Record = preload("res://scripts/customer_wardrobe_record.gd")
var checks = 0
var failures: Array = []

func check(ok: bool, label: String):
	checks += 1
	if not ok: failures.append(label)

func canonical(value) -> String:
	return JSON.stringify(value, "", true)

func _initialize():
	var seed: String = "synthetic-fixture".sha256_text()
	check(seed == "3a3436765885cdf2edc179512c22dd4c4259410f0d18f391cbc8d83a837c678e", "cross target SHA256 seed")
	var golden: Dictionary = Wardrobe.generate("fixture", seed).record
	check(golden.species == "bear" and golden.appearance == "masculine" and golden.palette == "sage_cream" and golden.fur == "brown_muzzle", "golden identity choices")
	check(canonical(golden.items) == canonical({"top": "top_cardigan", "lower": "lower_skirt", "shoes": "shoes_boots", "legwear": "none", "glasses": "glasses_oval", "headwear": "headwear_closed_cap", "ribbon": "none", "back_bow": "none"}), "golden modular choices")
	var seen: Dictionary = {}
	for species in Catalog.SPECIES:
		var combinations: Dictionary = {}
		var observed: Dictionary = {}
		for i in range(256):
			var identity: String = "fixture_%s_%d" % [species, i]
			var result: Dictionary = Wardrobe.generate(identity, seed, species)
			check(result.ok, "generate " + identity)
			if not result.ok: continue
			var record: Dictionary = result.record
			check(Wardrobe.validate(record, identity).ok, "compatible " + identity)
			check(canonical(record) == canonical(Wardrobe.generate(identity, seed, species).record), "repeat deterministic " + identity)
			var bytes: String = Record.encode(record).json
			var restored: Dictionary = Record.decode(bytes, identity)
			check(restored.ok and canonical(restored.record) == canonical(record), "JSON roundtrip " + identity)
			# The owner carries this value through all lifecycle states. No state is
			# accepted by this API and changed seed/species cannot overwrite it.
			for state in ["walk", "turn", "seated", "task", "outside", "reentry"]:
				var retained: Dictionary = Record.retain_or_generate(record, identity, "replacement".sha256_text(), "dog")
				check(canonical(retained.record) == canonical(record), "retain " + state)
			var contract: Dictionary = Wardrobe.render_contract(record)
			check(contract.ok and contract.status == "pending_art_review", "pending asset contracts")
			for slot in contract.parts:
				var part: Dictionary = contract.parts[slot]
				check(part.body_facing and part.directions == 8 and part.poses.size() == 4, "body attachment contract")
				check(part.tone == Catalog.PALETTES[record.palette][Catalog.COLOR_ROLES[slot]], "coherent palette")
			combinations[canonical(record.items)] = true
			for slot in Catalog.SLOTS:
				observed[record.items[slot]] = true
			seen[record.appearance] = true
			seen[species + "/" + record.fur] = true
		check(combinations.size() > 32, "modular variety " + species)
		for item_id in Catalog.ITEMS:
			if species in Catalog.ITEMS[item_id].get("species", Catalog.SPECIES):
				check(observed.has(item_id), "reachable item " + species + "/" + item_id)
		for fur in Catalog.FUR[species]: check(seen.has(species + "/" + fur.id), "reachable natural fur")
	check(seen.has("masculine") and seen.has("feminine"), "both appearance choices")
	var record: Dictionary = Wardrobe.generate("fixture", seed, "rabbit").record
	var original: String = canonical(record)
	var retained: Dictionary = Wardrobe.validate(record)
	retained.record.items.top = "top_cardigan"
	check(canonical(record) == original, "validation returns owned deep copy")
	for field in Wardrobe.FIELDS:
		var broken: Dictionary = record.duplicate(true)
		broken.erase(field)
		check(not Wardrobe.validate(broken).ok, "missing field " + field)
	for replacement in [null, [], {}, true, 1, "record"]:
		check(not Wardrobe.validate(replacement).ok, "wrong record type")
	for field in ["species", "palette", "fur", "appearance", "catalog", "seed", "identity"]:
		for value in [null, {}, [], true, 17, "bad|identity" if field == "identity" else "unknown"]:
			var broken: Dictionary = record.duplicate(true)
			broken[field] = value
			check(not Wardrobe.validate(broken).ok, "bad field " + field)
	for value in [null, true, "1", 0, 2, 1.5]:
		var broken: Dictionary = record.duplicate(true)
		broken.format = value
		check(not Wardrobe.validate(broken).ok, "unknown format")
	for field in ["top", "lower", "shoes"]:
		var broken: Dictionary = record.duplicate(true)
		broken.items[field] = "none"
		check(not Wardrobe.validate(broken).ok, "required garment " + field)
	var broken: Dictionary = record.duplicate(true)
	broken.items.top = "lower_skirt"
	check(not Wardrobe.validate(broken).ok, "wrong slot")
	broken = record.duplicate(true)
	broken.items.headwear = "headwear_closed_cap"
	check(not Wardrobe.validate(broken).ok, "rabbit ears reject closed cap")
	broken = record.duplicate(true)
	broken.items.lower = "lower_trousers"
	broken.items.legwear = "legwear_tights"
	check(not Wardrobe.validate(broken).ok, "tights require skirt")
	broken = record.duplicate(true)
	broken.items.shoes = "shoes_boots"
	broken.items.legwear = "legwear_socks"
	check(not Wardrobe.validate(broken).ok, "boot sock overlap")
	broken = record.duplicate(true)
	broken.items.headwear = "headwear_open_cap"
	broken.items.ribbon = "ribbon_head"
	check(not Wardrobe.validate(broken).ok, "head accessory collision")
	broken = Wardrobe.generate("fox_fixture", seed, "fox").record
	broken.items.back_bow = "bow_low_back"
	check(not Wardrobe.validate(broken).ok, "bushy tail bow collision")
	check(not Record.retain_or_generate(broken, "fox_fixture", seed).ok, "invalid existing never rerolls")
	check(not Record.retain_or_generate(record, "", seed).ok, "empty owner cannot bypass identity validation")
	check(not Record.decode("[]").ok and not Record.decode("{").ok, "malformed JSON")
	check(not Record.decode(" ".repeat(Record.MAX_BYTES + 1)).ok, "bounded JSON")
	check(not Record.decode(Record.encode(record).json, "other").ok, "cross identity restore rejects")
	check(Record.retain_or_generate(null, "new_fixture", seed).ok, "explicit new identity")
	check(not Wardrobe.generate("bad|identity", seed).ok, "identity delimiters reject")
	check(not Wardrobe.generate("fixture", "bad").ok, "seed format rejects")
	check(not Wardrobe.generate("fixture", seed, "unknown").ok, "unknown species rejects")
	print("CUSTOMER_WARDROBE_RESULT ", canonical({"checks": checks, "failures": failures, "synthetic_customers": 1536, "player_saves_used": false}))
	quit(0 if failures.is_empty() else 1)
