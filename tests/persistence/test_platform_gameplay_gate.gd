extends SceneTree
const Gate=preload("res://scripts/cafe_platform_state.gd")
var checks=0
var failures=[]
func check(value:bool,label:String):
	checks+=1
	if not value:failures.append(label)
func _init():
	check(not Gate.playable(false,false,false,false,true,false),"too small never starts")
	check(Gate.playable(false,false,false,false,false,false),"valid resize accepts actual play")
	check(not Gate.playable(false,false,false,false,true,false),"valid to too small stops")
	check(not Gate.playable(false,false,false,true,false,false),"intro remains loading")
	check(not Gate.playable(false,false,false,false,false,true),"menus stop gameplay")
	check(not Gate.playable(true,false,false,false,false,false),"pause stops gameplay")
	check(not Gate.playable(false,true,false,false,false,false),"editing stops gameplay")
	check(not Gate.playable(false,false,true,false,false,false),"recovery stops gameplay")
	check(not Gate.playable(false,false,false,true,true,true),"resize cannot start while intro/menu blocked")
	check(Gate.playable(false,false,false,false,false,false),"unblocked resume permits play")
	print("PLATFORM_GATE_RESULT "+JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
