extends SceneTree
const Model=preload("res://scripts/cafe_model.gd")
var checks=0
var failures=[]
func check(value:bool,message:String):
	checks+=1
	if not value:failures.append(message);push_error(message)
func verify(model):
	# Compare cached live queries with independently resolved explicit inputs.
	# Include both directions, closed edges, doorway edges and shortened shell.
	for repeat in 3:
		for x in model.BASE_WIDTH:
			var a=Vector2i(x,-1);var b=Vector2i(x,0)
			var expected=model._fixed_edge_blocked(a,b,model.wall_attachments,model.built_walls)
			check(model._fixed_edge_blocked(a,b)==expected,"back edge parity")
			check(model._fixed_edge_blocked(b,a)==expected,"back reverse parity")
		for z in model.BASE_DEPTH:
			var a=Vector2i(-1,z);var b=Vector2i(0,z)
			var expected=model._fixed_edge_blocked(a,b,model.wall_attachments,model.built_walls)
			check(model._fixed_edge_blocked(a,b)==expected,"west edge parity")
			check(model._fixed_edge_blocked(b,a)==expected,"west reverse parity")
func _initialize():
	var model=Model.new();verify(model)
	var a=Vector2i(-1,5);var b=Vector2i(0,5)
	check(not model._fixed_edge_blocked(a,b),"starter doorway open")
	var proposed=[]
	check(model._fixed_edge_blocked(a,b,proposed,model.built_walls),"proposed door removal bypasses live cache")
	check(not model._fixed_edge_blocked(a,b),"preview cannot poison live cache")
	model.wall_attachments.clear();model._notify();verify(model)
	check(model._fixed_edge_blocked(a,b),"removed doorway invalidates open result")
	model.reset_new();verify(model)
	check(not model._fixed_edge_blocked(a,b),"reset restores doorway and invalidates closed result")
	model.built_walls.append({"id":42,"x":0,"z":3,"axis":"x","height":"full","material":"original","paid_cost":0});model._notify();verify(model)
	print("PERFORMANCE_SHELL_CACHE_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"status":"passed" if failures.is_empty() else "failed"}));quit(0 if failures.is_empty() else 1)
