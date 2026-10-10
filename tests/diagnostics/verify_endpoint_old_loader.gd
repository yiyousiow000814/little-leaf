extends SceneTree
const Model=preload("res://scripts/cafe_model.gd")
func _init():
	var path=OS.get_environment("LL_STREET_OLD_LOADER_INPUT")
	assert(path!="" and FileAccess.file_exists(path))
	var original_hash=FileAccess.get_sha256(path)
	var model=Model.new();var before=[model.coins,model.items.duplicate(true),model.customers.duplicate(true),model.owned_parcels.duplicate(),model._next_customer_id]
	assert(model.save("user://before-rejection.json"))
	var loaded=model.load_save(path)
	var rejection_error=model.last_error
	var unchanged=before==[model.coins,model.items,model.customers,model.owned_parcels,model._next_customer_id]
	assert(model.save("user://after-rejection.json"))
	var full_state_unchanged=FileAccess.get_sha256("user://before-rejection.json")==FileAccess.get_sha256("user://after-rejection.json")
	var failures=[]
	if loaded:failures.append("Old loader unexpectedly accepted a new outer-road position")
	if not unchanged:failures.append("Old loader mutated its active cafe while rejecting the new file")
	if not full_state_unchanged:failures.append("Old loader changed the complete serialized active cafe")
	if original_hash!=FileAccess.get_sha256(path):failures.append("Old loader rewrote the new source save")
	print("OLD_ENDPOINT_LOADER_RESULT ",JSON.stringify({"checks":4,"failures":failures,"rejected":not loaded,"active_model_unchanged":unchanged,"complete_serialized_state_unchanged":full_state_unchanged,"source_bytes_unchanged":original_hash==FileAccess.get_sha256(path),"error":rejection_error}))
	quit(0 if failures.is_empty() else 1)
