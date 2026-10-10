extends RefCounted
## Additive common envelope for preview/confirm/restore adapters. Not a save format.
## Providers retain ownership of their wardrobe and role-specific validation.
const SCHEMA = "character-appearance-candidate-1"
const FIELDS = ["schema", "actor_kind", "identity", "provider", "wardrobe", "expression"]
const ACTOR_KINDS = ["customer", "staff"]
const EXPRESSIONS = ["neutral", "soft_smile", "focused", "happy_greeting"]
const EXPRESSION_REVISION = "natural-face-draft-1"

static func valid_token(value, maximum: int = 64) -> bool:
	if not value is String or value.is_empty() or value.length() > maximum: return false
	for c in value:
		if not c in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-": return false
	return true

static func select_expression(seed: String, identity: String) -> String:
	var digest: String = ("%s|%s|%s|expression" % [SCHEMA, seed, identity]).sha256_text()
	return EXPRESSIONS[digest.substr(0, 8).hex_to_int() % EXPRESSIONS.size()]

static func validate_header(envelope, expected_identity: String = "", expected_kind: String = "") -> Dictionary:
	if not envelope is Dictionary or envelope.size() != FIELDS.size(): return {"ok": false, "error": "invalid_envelope"}
	for field in FIELDS:
		if not envelope.has(field): return {"ok": false, "error": "missing_" + field}
	if not envelope.schema is String or envelope.schema != SCHEMA: return {"ok": false, "error": "unknown_schema"}
	if not envelope.actor_kind is String or not envelope.actor_kind in ACTOR_KINDS: return {"ok": false, "error": "unknown_actor_kind"}
	if not expected_kind.is_empty() and envelope.actor_kind != expected_kind: return {"ok": false, "error": "actor_kind_mismatch"}
	if not valid_token(envelope.identity): return {"ok": false, "error": "invalid_identity"}
	if not expected_identity.is_empty() and envelope.identity != expected_identity: return {"ok": false, "error": "identity_mismatch"}
	if not valid_token(envelope.provider): return {"ok": false, "error": "invalid_provider"}
	if not envelope.wardrobe is Dictionary: return {"ok": false, "error": "invalid_provider_payload"}
	if not envelope.expression is String or not envelope.expression in EXPRESSIONS: return {"ok": false, "error": "unknown_expression"}
	return {"ok": true, "envelope": envelope.duplicate(true), "validation": "header_only_provider_validation_required"}

static func expression_contract(expression: String, species: String) -> Dictionary:
	if not expression in EXPRESSIONS or not species in ["bear", "rabbit", "fox", "cat", "dog", "red_panda"]: return {}
	return {"id": "face/%s/%s@%s" % [species, expression, EXPRESSION_REVISION], "status": "pending_art_review", "body_facing": true, "directions": 8, "poses": ["idle", "walk", "seated", "task"]}
