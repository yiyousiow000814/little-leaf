extends SceneTree
const Adapter = preload("res://scripts/customer_appearance_adapter.gd")
const Contract = preload("res://scripts/character_appearance_contract.gd")
const Catalog = preload("res://scripts/customer_wardrobe_catalog.gd")
var checks = 0
var failures: Array = []

func check(ok: bool, label: String):
	checks += 1
	if not ok: failures.append(label)

func canonical(value) -> String:
	return JSON.stringify(value, "", true)

func _initialize():
	var seed: String = "synthetic-adapter-fixture".sha256_text()
	check(Adapter.identity("profile_fixture", 1) == "customer_b81a225c289b3283281af5c852098de2", "frozen namespace identity fixture")
	var expressions: Dictionary = {}
	for species in Catalog.SPECIES:
		var profile_namespace: String = "profile_" + species
		for sequence in range(1, 33):
			var created: Dictionary = Adapter.spawn(profile_namespace, sequence, seed, species)
			check(created.ok, "synthetic spawn")
			if not created.ok: continue
			var customer: Dictionary = created.customer
			var source: String = canonical(customer)
			check(source == canonical(Adapter.spawn(profile_namespace, sequence, seed, species).customer), "repeat spawn deterministic")
			check(Adapter.restore(customer).ok, "full provider validation")
			var appearance: String = canonical(customer.appearance)
			expressions[customer.appearance.expression] = true
			for state in Adapter.STATES:
				var stepped: Dictionary = Adapter.with_state(customer, state)
				check(stepped.ok and canonical(stepped.customer.appearance) == appearance, "lifecycle preserves outfit and expression")
				check(canonical(customer) == source, "state adapter does not mutate caller")
			# JSON is repeatedly decoded rather than regenerated; integer ID and
			# wardrobe format tags are canonicalized without changing appearance.
			for cycle in range(5):
				var loaded: Dictionary = Adapter.decode(Adapter.encode(customer).json, profile_namespace)
				check(loaded.ok and canonical(loaded.customer) == canonical(customer), "repeated load stable")
				if loaded.ok: customer = loaded.customer
			var retained: Dictionary = Adapter.retain_or_spawn(customer, profile_namespace, sequence, "changed".sha256_text(), "dog")
			check(retained.ok and canonical(retained.customer.appearance) == appearance, "reroll request cannot replace saved selection")
			var render: Dictionary = Adapter.render_contract(customer)
			check(render.ok and render.parts.has("shoes") and render.expression.body_facing, "shoes and expression render contracts")
			check(render.expression.status == "pending_art_review", "expression is pending art contract")
			for slot in render.parts:
				check(render.parts[slot].tone == Catalog.PALETTES[customer.appearance.wardrobe.palette][Catalog.COLOR_ROLES[slot]], "adapter keeps coordinated part colors")
	for expression in Contract.EXPRESSIONS: check(expressions.has(expression), "expression selection reachable")
	check(Adapter.identity("profile_fixture", 1) != Adapter.identity("other_profile", 1), "profile namespaces isolate identity")
	check(Adapter.identity("profile_fixture", 1) != Adapter.identity("profile_fixture", 2), "monotonic sequence isolates identity")
	var customer: Dictionary = Adapter.spawn("profile_fixture", 1, seed, "rabbit").customer
	var original: String = canonical(customer)
	var broken: Dictionary = customer.duplicate(true)
	broken.appearance.wardrobe.items.headwear = "headwear_closed_cap"
	check(not Adapter.restore(broken).ok, "rabbit ears reject incompatible hat during restore")
	check(not Adapter.retain_or_spawn(broken, "profile_fixture", 1, seed).ok, "invalid saved hat never rerolls")
	broken = customer.duplicate(true)
	broken.appearance.wardrobe.items.headwear = "headwear_open_cap"
	broken.appearance.wardrobe.items.ribbon = "ribbon_head"
	check(not Adapter.restore(broken).ok, "hat ribbon collision rejects")
	check(canonical(customer) == original, "rejection leaves original fixture unchanged")
	check(not Adapter.decode(Adapter.encode(customer).json, "other_profile").ok, "cross profile load rejects")
	check(not Adapter.retain_or_spawn(customer, "profile_fixture", 2, seed).ok, "cross sequence restore rejects")
	check(not Adapter.retain_or_spawn({}, "profile_fixture", 1, seed).ok, "empty saved object never rerolls")
	check(Adapter.retain_or_spawn(null, "profile_fixture", 1, seed).ok, "explicit null creates new synthetic customer")
	for field in Adapter.FIELDS:
		broken = customer.duplicate(true)
		broken.erase(field)
		check(not Adapter.restore(broken).ok, "missing synthetic field")
	for field in Contract.FIELDS:
		broken = customer.duplicate(true)
		broken.appearance.erase(field)
		check(not Adapter.restore(broken).ok, "missing shared envelope field")
	for value in [null, {}, [], true, 1, "unknown"]:
		for field in ["schema", "actor_kind", "provider", "expression"]:
			broken = customer.duplicate(true)
			broken.appearance[field] = value
			check(not Adapter.restore(broken).ok, "bad shared envelope field")
	for sequence in [0, -1, 1.5, INF, NAN, true, "1", Adapter.MAX_SEQUENCE + 1]:
		broken = customer.duplicate(true)
		broken.id = sequence
		check(not Adapter.restore(broken).ok, "invalid sequence rejects")
	check(Adapter.valid_sequence(Adapter.MAX_SEQUENCE), "max exact JSON sequence accepted")
	check(not Adapter.decode("{").ok and not Adapter.decode("[]").ok, "malformed fixture JSON")
	check(not Adapter.decode(" ".repeat(Adapter.MAX_BYTES + 1)).ok, "bounded fixture JSON")
	var staff_header: Dictionary = customer.appearance.duplicate(true)
	staff_header.actor_kind = "staff"
	staff_header.provider = "staff_provider_candidate"
	check(Contract.validate_header(staff_header, staff_header.identity, "staff").ok, "staff can share header schema")
	check(not Adapter.validate_envelope(staff_header, staff_header.identity).ok, "customer adapter never accepts staff provider")
	var group: Array = []
	var appearances: Dictionary = {}
	for sequence in range(1, 4):
		var member: Dictionary = Adapter.spawn("collection_fixture", sequence, seed).customer
		group.append(member)
		appearances[member.id] = canonical(member.appearance)
	group.reverse()
	group.remove_at(1) # Remove sequence 2; sequence 3 must not become 2.
	var reloaded: Dictionary = Adapter.restore_many(JSON.parse_string(canonical(group)), "collection_fixture")
	check(reloaded.ok and reloaded.customers.size() == 2, "collection reorder removal reload")
	if reloaded.ok:
		for member in reloaded.customers:
			check(member.id in [1, 3] and canonical(member.appearance) == appearances[member.id], "identity survives collection editing")
	check(not Adapter.restore_many([group[0], group[0]]).ok, "duplicate identity rejects atomically")
	var group_before: String = canonical(group)
	var invalid_group: Array = group.duplicate(true)
	invalid_group[1].appearance.expression = "unknown"
	check(not Adapter.restore_many(invalid_group).ok and canonical(group) == group_before, "collection failure leaves original untouched")
	var fixtures = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/customer_appearance_compatibility.json"))
	check(fixtures is Dictionary, "handoff fixtures readable")
	if fixtures is Dictionary:
		for fixture in fixtures.valid_customers: check(Adapter.restore(fixture).ok, "valid shared fixture")
		for fixture in fixtures.invalid_customers:
			var rejected: Dictionary = Adapter.restore(fixture.customer)
			check(not rejected.ok and rejected.error == fixture.expected_error, "fail closed fixture " + fixture.name)
		for fixture in fixtures.staff_headers:
			check(Contract.validate_header(fixture, fixture.identity, "staff").ok, "shared staff header fixture")
			check(not Adapter.validate_envelope(fixture, fixture.identity).ok, "customer provider rejects staff fixture")
	print("CUSTOMER_APPEARANCE_ADAPTER_RESULT ", canonical({"checks": checks, "failures": failures, "synthetic_customers": 192, "player_saves_used": false}))
	quit(0 if failures.is_empty() else 1)
