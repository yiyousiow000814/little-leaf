extends SceneTree
const Model=preload("res://scripts/cafe_model.gd")
const Nav=preload("res://scripts/cafe_navigation_candidate.gd")
var checks=0
var failures=[]
func check(ok:bool,label:String):
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func fresh():
	var model=Model.new();model.items.clear();model.dining_sets.clear();model.customers.clear();model.coins=10000
	return model
func _initialize():run.call_deferred()
func run():
	var model=fresh();var before=Nav.from_model(model)
	check(not Nav.sweep_clear(before,Vector2(-.5,2.5),Vector2(.5,2.5)),"original shell blocks physical sweep")
	check(model.remove_wall("shell:west#2"),"remove included shell segment")
	var removed=Nav.from_model(model)
	check(Nav.sweep_clear(removed,Vector2(-.5,2.5),Vector2(.5,2.5)),"removed segment absent from snapshot barriers")
	check(not Nav.sweep_clear(removed,Vector2(-.5,3.5),Vector2(.5,3.5)),"surviving neighboring shell remains solid")
	check(before.revision!=removed.revision and not Nav.sweep_clear(before,Vector2(-.5,2.5),Vector2(.5,2.5)),"old immutable snapshot and changed signature")
	model=fresh();check(model.move_wall("shell:west#2","z",4,3),"move original wall")
	var moved=Nav.from_model(model)
	check(Nav.sweep_clear(moved,Vector2(-.5,2.5),Vector2(.5,2.5)),"moved shell clears old location")
	check(not Nav.can_step(moved,Vector2i(3,3),Vector2i(4,3)),"moved wall blocks new location")
	check(model.remove_wall("z:4:3") and model.place_wall("z",4,3),"replace original with purchased wall")
	check(model.move_wall("z:4:3","z",6,3),"move purchased wall")
	var purchased=Nav.from_model(model)
	check(Nav.can_step(purchased,Vector2i(3,3),Vector2i(4,3)) and not Nav.can_step(purchased,Vector2i(5,3),Vector2i(6,3)),"purchased wall only blocks current position")
	model=fresh();model.wall_attachments[0].offset=3.0;model.wall_attachments[0].width=1.0
	var doorway=Nav.from_model(model)
	check(Nav.sweep_clear(doorway,Vector2(-.5,3),Vector2(.5,3)),"door aperture clips across adjacent shell segments")
	check(not Nav.sweep_clear(doorway,Vector2(-.5,2.6),Vector2(.5,2.6)),"door frame body clearance blocks aperture edge")
	model.wall_attachments[0].kind="window"
	check(not Nav.sweep_clear(Nav.from_model(model),Vector2(-.5,3),Vector2(.5,3)),"window does not open ground collision")
	for kind in ["counter","sink","beverage","register","stove"]:
		for rotation in 4:
			model=fresh();model.items.append({"id":1,"kind":kind,"x":3,"z":2,"rotation":rotation})
			model.items.append({"id":2,"kind":kind,"x":4,"z":2,"rotation":rotation})
			var geometry=Nav.from_model(model)
			check(not Nav.can_step(geometry,Vector2i(2,2),Vector2i(3,3)),"cabinet blocks diagonal corner "+kind+str(rotation))
			check(not Nav.sweep_clear(geometry,Vector2(4,1.5),Vector2(4,3.5)),"adjacent cabinet seam cannot be traversed "+kind+str(rotation))
	model=fresh();model.items.append({"id":1,"kind":"rug","x":3,"z":2,"rotation":0})
	check(Nav.can_step(Nav.from_model(model),Vector2i(2,2),Vector2i(3,3)),"rug remains traversable")
	var coins=model.coins;var items=model.items.duplicate(true);var walls=model.built_walls.duplicate(true)
	Nav.from_model(model,1)
	check(model.coins==coins and model.items==items and model.built_walls==walls,"snapshot leaves authoritative economy and layout unchanged")
	print("NAVIGATION_ADAPTER_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
