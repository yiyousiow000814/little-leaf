extends SceneTree
const Model=preload("res://scripts/cafe_model.gd")
const Approach=preload("res://scripts/floor_cleaning_approach.gd")
const Walls=preload("res://scripts/cafe_walls.gd")
var checks=0
var failures=[]
func check(value:bool,label:String):
	checks+=1
	if not value:failures.append(label);printerr("FAIL ",label)
func compare(model,position,contact,current,cache):
	var expected=Approach.offset(position,contact,model,current)
	check(Approach.cached_offset(position,contact,model,current,cache)==expected,"fresh/cache geometry parity")
	check(Approach.cached_offset(position,contact,model,current,cache)==expected,"repeat settled query parity")
func _initialize():
	var model=Model.new();model.items.clear();model.revision+=1
	var position=Vector2(5.5,5.5);var cache={}
	for angle in range(0,360,5):
		var direction=Vector2.from_angle(deg_to_rad(angle))
		for distance in [.49,.51,.8,1.15]:
			for current in [Vector2.ZERO,direction*.12,direction*.45]:
				compare(model,position,position+direction*distance,current,cache)
	var contact=position+Vector2.RIGHT*1.15
	compare(model,position,contact,Vector2(.45,0),cache)
	model.items.append({"id":100,"kind":"chair","x":6,"z":5,"rot":0});model._notify()
	compare(model,position,contact,Vector2(.45,0),cache)
	check(cache.offset==Vector2.ZERO,"new furniture invalidates settled positive approach")
	model.items.clear();model.built_walls.append(Walls.make("z",6,5));model._notify()
	compare(model,position,contact,Vector2(.45,0),cache)
	check(cache.offset==Vector2.ZERO,"new wall invalidates settled approach")
	model.built_walls.clear();model._notify();compare(model,position,contact,Vector2(.45,0),cache)
	var other=Model.new();other.items.clear();other.revision=model.revision
	other.items.append({"id":101,"kind":"chair","x":6,"z":5,"rot":0})
	compare(other,position,contact,Vector2(.45,0),cache)
	check(cache.offset==Vector2.ZERO,"model identity prevents cross-profile reuse at matching revision")
	compare(model,position+Vector2(.1,0),contact,Vector2(.2,0),cache)
	compare(model,position,position+Vector2.DOWN*1.15,Vector2.ZERO,cache)
	print("FLOOR_APPROACH_CACHE_RESULT ",JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
