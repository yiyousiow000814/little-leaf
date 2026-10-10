extends RefCounted
## Opt-in synthetic spawn/load integration. Never connects to CafeModel or saves.
const Contract = preload("res://scripts/character_appearance_contract.gd")
const Wardrobe = preload("res://scripts/customer_wardrobe.gd")
const PROVIDER = "customer_wardrobe_draft_1"
const KIND = "synthetic_customer"
const FIELDS = ["kind", "namespace", "id", "state", "appearance"]
const STATES = ["arriving", "walking", "turning", "seated", "task", "departed", "reentry"]
const MAX_SEQUENCE = 9007199254740991 # Exact JSON integer across native/Web consumers.
const MAX_BYTES = 8192
const MAX_CUSTOMERS = 256

static func valid_sequence(value) -> bool:
	if not (value is int or value is float): return false
	return is_finite(float(value)) and value >= 1 and value <= MAX_SEQUENCE and value == floor(value)

static func identity(profile_namespace: String, sequence: int) -> String:
	if not Contract.valid_token(profile_namespace) or not valid_sequence(sequence): return ""
	return "customer_" + ("customer-identity-v1|%s|%d" % [profile_namespace, sequence]).sha256_text().substr(0, 32)

static func spawn(profile_namespace: String, sequence: int, world_seed: String, species: String = "") -> Dictionary:
	var customer_identity: String = identity(profile_namespace, sequence)
	if customer_identity.is_empty() or not Wardrobe.valid_seed(world_seed): return {"ok": false, "error": "invalid_spawn_identity_or_seed"}
	# This independent seed does not advance model/gameplay random state.
	var appearance_seed: String = ("customer-appearance-v1|%s|%s" % [world_seed, customer_identity]).sha256_text()
	var generated: Dictionary = Wardrobe.generate(customer_identity, appearance_seed, species)
	if not generated.ok: return generated
	var envelope: Dictionary = {"schema": Contract.SCHEMA, "actor_kind": "customer", "identity": customer_identity, "provider": PROVIDER, "wardrobe": generated.record, "expression": Contract.select_expression(appearance_seed, customer_identity)}
	return {"ok": true, "customer": {"kind": KIND, "namespace": profile_namespace, "id": sequence, "state": "arriving", "appearance": envelope}}

static func validate_envelope(envelope, expected_identity: String) -> Dictionary:
	if not Contract.valid_token(expected_identity): return {"ok": false, "error": "invalid_expected_identity"}
	var checked: Dictionary = Contract.validate_header(envelope, expected_identity, "customer")
	if not checked.ok: return checked
	if envelope.provider != PROVIDER: return {"ok": false, "error": "unknown_customer_provider"}
	var wardrobe: Dictionary = Wardrobe.validate(envelope.wardrobe, expected_identity)
	if not wardrobe.ok: return wardrobe
	var restored: Dictionary = checked.envelope
	restored.wardrobe = wardrobe.record
	return {"ok": true, "envelope": restored}

static func restore(customer, expected_namespace: String = "") -> Dictionary:
	if not customer is Dictionary or customer.size() != FIELDS.size(): return {"ok": false, "error": "invalid_synthetic_customer"}
	for field in FIELDS:
		if not customer.has(field): return {"ok": false, "error": "missing_" + field}
	if not customer.kind is String or customer.kind != KIND: return {"ok": false, "error": "not_synthetic_customer"}
	if not Contract.valid_token(customer["namespace"]): return {"ok": false, "error": "invalid_namespace"}
	if not expected_namespace.is_empty() and customer["namespace"] != expected_namespace: return {"ok": false, "error": "namespace_mismatch"}
	if not valid_sequence(customer.id): return {"ok": false, "error": "invalid_sequence"}
	if not customer.state is String or not customer.state in STATES: return {"ok": false, "error": "unknown_state"}
	var customer_identity: String = identity(customer["namespace"], int(customer.id))
	var appearance: Dictionary = validate_envelope(customer.appearance, customer_identity)
	if not appearance.ok: return appearance
	var restored: Dictionary = customer.duplicate(true)
	restored.id = int(customer.id)
	restored.appearance = appearance.envelope
	return {"ok": true, "customer": restored}

static func with_state(customer, state: String) -> Dictionary:
	if not state in STATES: return {"ok": false, "error": "unknown_state"}
	var checked: Dictionary = restore(customer)
	if not checked.ok: return checked
	checked.customer.state = state
	return checked

static func restore_many(customers, expected_namespace: String = "") -> Dictionary:
	# Validate the whole collection before returning any replacement. Array
	# order/removal never reallocates a sequence or regenerates an appearance.
	if not customers is Array or customers.size() > MAX_CUSTOMERS: return {"ok": false, "error": "invalid_customer_collection"}
	var restored: Array = []
	var seen: Dictionary = {}
	for customer in customers:
		var checked: Dictionary = restore(customer, expected_namespace)
		if not checked.ok: return checked
		var customer_identity: String = checked.customer.appearance.identity
		if seen.has(customer_identity): return {"ok": false, "error": "duplicate_customer_identity"}
		seen[customer_identity] = true
		restored.append(checked.customer)
	return {"ok": true, "customers": restored}

static func retain_or_spawn(existing, profile_namespace: String, sequence: int, world_seed: String, species: String = "") -> Dictionary:
	# Only explicit null requests creation. Existing appearance is authoritative.
	var expected_identity: String = identity(profile_namespace, sequence)
	if expected_identity.is_empty(): return {"ok": false, "error": "invalid_expected_identity"}
	if existing == null: return spawn(profile_namespace, sequence, world_seed, species)
	var checked: Dictionary = restore(existing, profile_namespace)
	if not checked.ok: return checked
	if checked.customer.id != sequence: return {"ok": false, "error": "sequence_mismatch"}
	return checked

static func encode(customer) -> Dictionary:
	var checked: Dictionary = restore(customer)
	if not checked.ok: return checked
	return {"ok": true, "json": JSON.stringify(checked.customer, "", true)}

static func decode(text: String, expected_namespace: String = "") -> Dictionary:
	if text.to_utf8_buffer().size() > MAX_BYTES: return {"ok": false, "error": "customer_too_large"}
	var parser = JSON.new()
	if parser.parse(text) != OK: return {"ok": false, "error": "invalid_json"}
	return restore(parser.data, expected_namespace)

static func render_contract(customer) -> Dictionary:
	var checked: Dictionary = restore(customer)
	if not checked.ok: return checked
	var result: Dictionary = Wardrobe.render_contract(checked.customer.appearance.wardrobe)
	result.expression = Contract.expression_contract(checked.customer.appearance.expression, checked.customer.appearance.wardrobe.species)
	return result
