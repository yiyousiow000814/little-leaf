extends SceneTree
func _initialize() -> void:
	_test.call_deferred()
func _test() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	if game.save_recovery_blocked or not game.model.operating_open or game.model.built_walls.size() != 21 or game.model.customers.size() != 1:
		push_error("LL fixture rejected or changed from expected 21 walls, 1 guest, open cafe")
		quit(2)
		return
	print("LL_FIXTURE_OK walls=",game.model.built_walls.size()," guests=",game.model.customers.size()," open=",game.model.operating_open)
	quit(0)
