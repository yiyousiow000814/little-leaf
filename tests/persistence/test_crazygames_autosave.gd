extends SceneTree
const Policy=preload("res://scripts/cafe_autosave_policy.gd")
var checks=0
var failures=[]
func check(ok:bool,label:String):
	checks+=1
	if not ok:failures.append(label)
func _init():
	check(not Policy.due(true,true,4.999,false,false,false),"platform waits five seconds")
	check(Policy.due(true,true,5.0,false,false,false),"dirty platform submits at five seconds")
	check(not Policy.due(true,false,100.0,false,false,false),"clean platform never rewrites idle payload")
	check(not Policy.due(true,true,10.0,true,false,false),"inflight write cannot queue repeated autosaves")
	check(not Policy.due(true,true,10.0,false,true,false),"recovery/suppressed writes stay blocked")
	check(not Policy.due(true,true,10.0,false,false,true),"active drag waits")
	check(Policy.due(true,true,10.0,false,false,false),"release allows retained dirty work")
	check(not Policy.due(false,true,5.0,false,false,false),"normal Web/native cadence unchanged")
	check(not Policy.due(false,true,15.0,false,false,false),"legacy strict fifteen-second boundary preserved")
	check(Policy.due(false,false,15.01,true,true,false),"ordinary cadence preserves existing request guards")
	print("CRAZYGAMES_AUTOSAVE_RESULT "+JSON.stringify({"checks":checks,"failures":failures,"remote_confirmation":false}))
	quit(0 if failures.is_empty() else 1)
