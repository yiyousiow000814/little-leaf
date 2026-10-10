extends "res://scripts/cafe_model.gd"
## Visit-local candidate. Existing codecs persist visit IDs, so a pinned recipe
## reconstructs clothing on reload without changing saves or gameplay RNG.
const Adapter = preload("res://scripts/customer_appearance_adapter.gd")
const RECIPE = "customer_visit_bear_v1"
var _outfit_cache: Dictionary = {}

func appearance_for(visit_id: int) -> Dictionary:
	if visit_id < 1 or visit_id >= _next_customer_id:
		return {"ok": false, "error": "unknown_visit"}
	if not _outfit_cache.has(visit_id):
		# Cache eviction only drops memoized data; digest generation is identical.
		if _outfit_cache.size() >= 256: _outfit_cache.clear()
		var selected: Dictionary = Adapter.spawn(RECIPE, visit_id, RECIPE.sha256_text(), "bear")
		if not selected.ok: return selected
		_outfit_cache[visit_id] = selected.customer
	return Adapter.restore(_outfit_cache[visit_id], RECIPE)
