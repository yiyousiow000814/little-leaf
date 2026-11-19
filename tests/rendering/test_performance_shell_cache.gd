extends SceneTree
const Model=preload("res://scripts/core/cafe_model.gd")
class ScanSpy extends "res://scripts/core/cafe_model.gd":
	var legacy_lookups:=0
	func _built_edge_blocked(a:Vector2i,b:Vector2i,walls:Array,openings=null,keys=null)->bool:
		if keys==null:legacy_lookups+=1
		return super._built_edge_blocked(a,b,walls,openings,keys)
var checks=0
var failures=[]
func check(value:bool,message:String):
	checks+=1
	if not value:failures.append(message);push_error(message)
func verify(model):
	# Compare cached live queries with independently resolved explicit inputs.
	# Include both directions, closed edges, doorway edges and all installed edges.
	for repeat in 3:
		for x in model.BASE_WIDTH:
			var a=Vector2i(x,-1);var b=Vector2i(x,0)
			var expected=model._built_edge_blocked(a,b,model.built_walls,model.wall_attachments)
			check(model.edge_blocked(a,b)==expected,"back edge parity")
			check(model.edge_blocked(b,a)==expected,"back reverse parity")
		for z in model.BASE_DEPTH:
			var a=Vector2i(-1,z);var b=Vector2i(0,z)
			var expected=model._built_edge_blocked(a,b,model.built_walls,model.wall_attachments)
			check(model.edge_blocked(a,b)==expected,"west edge parity")
			check(model.edge_blocked(b,a)==expected,"west reverse parity")
func verify_scaled_index():
	var model=ScanSpy.new()
	for size in [32,64,128]:
		model.built_walls.clear()
		model.wall_attachments.clear()
		for i in size:
			model.built_walls.append(model.WallGeometry.installed("wall:%d"%(i+1),model.WallGeometry.make("x",i%16,1+i/16),55,55))
		model.wall_attachments.append({"id":1,"kind":"door","wall_ids":["wall:1"],"offset":.5,"width":1.0})
		model._notify()
		var expected:Dictionary={}
		for wall in model.built_walls:
			var sides=model.WallGeometry.adjacent_cells(wall)
			expected[model.WallGeometry.key_of(wall)]=model._built_edge_blocked(sides[0],sides[1],model.built_walls)
		model.legacy_lookups=0
		for wall in model.built_walls:
			var sides=model.WallGeometry.adjacent_cells(wall)
			check(model.edge_blocked(sides[0],sides[1])==expected[model.WallGeometry.key_of(wall)],"scaled live index retains wall and doorway parity")
		check(model.legacy_lookups==0,"live wall index does not rescan the wall list per edge")
		var component=model._furniture_actor_component(Vector2i(4,4),[],model.built_walls)
		check(not component.is_empty() and model.legacy_lookups==0,"proposed wall component uses one index rather than rescanning per edge")
func _initialize():
	var model=Model.new();verify(model)
	var a=Vector2i(-1,5);var b=Vector2i(0,5)
	check(not model.edge_blocked(a,b),"starter doorway open")
	var proposed=[]
	check(model._built_edge_blocked(a,b,model.built_walls,proposed),"proposed door removal bypasses live cache")
	check(not model.edge_blocked(a,b),"preview cannot poison live cache")
	model.wall_attachments.clear();model._notify();verify(model)
	check(model.edge_blocked(a,b),"removed doorway invalidates open result")
	model.reset_new();verify(model)
	check(not model.edge_blocked(a,b),"reset restores doorway and invalidates closed result")
	model.built_walls.append(model.WallGeometry.installed("wall:42",model.WallGeometry.make("x",0,3),0,0));model._notify();verify(model)
	verify_scaled_index()
	print("PERFORMANCE_SHELL_CACHE_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"status":"passed" if failures.is_empty() else "failed"}));quit(0 if failures.is_empty() else 1)
