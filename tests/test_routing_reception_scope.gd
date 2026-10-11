extends SceneTree
const Model=preload("res://scripts/cafe_model.gd")
class Owner extends RefCounted:
	var model=Model.new()
	var fresh_start=true
	var save_writes_suppressed=true
var failures=[]
var checks=0
func check(ok,label):
	checks+=1
	if not ok:failures.append(label)
func _initialize():run.call_deferred()
func run():
	var owner=Owner.new();var m=owner.model
	Model.GuestNavigation.enable(owner)
	check(not m.enable_routing_reception_review(),"missing/foreign flags or unsafe scope cannot enable19")
	check(not m.routing_reception_review_enabled,"refused entry does not publish19 capability")
	var path=Model.SaveContract.ROUTING_RECEPTION_REVIEW_FILE
	check(not m.save_routing_reception_review(path) and not m.load_routing_reception_review(path),"explicit APIs refuse before I/O")
	check(not FileAccess.file_exists(path) and not FileAccess.file_exists(path+".tmp") and m.coins==Model.INITIAL_COINS,"no target/staging/economy mutation")
	print("ROUTING_RECEPTION_SCOPE_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
