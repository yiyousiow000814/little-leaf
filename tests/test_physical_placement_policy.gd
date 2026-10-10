extends SceneTree
const Model=preload("res://scripts/cafe_model.gd")
const Plan=preload("res://scripts/cafe_edit_plan.gd")
var checks=0
var failures=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _init():
 var model=Model.new()
 model.coins=100000
 var plan=Plan.new()
 var landing=model.ENTRY_LANDING
 var before=model.items.duplicate(true)
 var wallet=model.coins
 var receipt=plan.prepare(model,"plant",-1,0,landing)
 check(receipt.ok,"owned unoccupied landing permits physical placement despite walking warning")
 check(model.items==before and model.coins==wallet,"preview preserves model and wallet")
 var committed=plan.commit(model,receipt)
 check(committed,"shape-valid preview commits even when it blocks entrance access")
 if committed:
  check(model.coins==wallet-model.price_of("plant"),"commit charges once")
  check(not model.can_place("plant",landing.x,landing.y),"actual occupied footprint still rejects overlap")
  var path="user://physical-placement-fixture.json"
  var saved=model.save(path)
  check(saved,"shape-valid blocked-access layout saves")
  if saved:
   var saved_hash=FileAccess.get_sha256(path)
   var restored=Model.new()
   check(restored.load_save(path) and restored.items==model.items and restored.coins==model.coins,"blocked-access layout round-trips identity and wallet")
   check(FileAccess.get_sha256(path)==saved_hash,"load leaves synthetic input bytes unchanged")
 check(model.placement_warning("plant",landing.x,landing.y)!="","blocked walking is a separate nonblocking warning")
 var cash=model.coins;model.coins=0
 var unfunded=plan.prepare(model,"plant",-1,0,Vector2i(10,8))
 check(unfunded.placement_valid and not unfunded.ok,"wallet changes purchase permission without changing physical validity")
 check(not plan.commit(model,unfunded) and model.coins==0,"physical green never bypasses purchase funds")
 model.coins=cash
 var outside=plan.prepare(model,"plant",-1,0,Vector2i(-1,5))
 check(not outside.ok,"unowned physical footprint still rejects")
 var occupied=model.items[0]
 var overlap=plan.prepare(model,"plant",-1,0,Vector2i(occupied.x,occupied.z))
 check(not overlap.ok,"existing object footprint still rejects")
 var body_model=Model.new()
 check(not body_model.can_place("plant",10,8,-1,0,[Vector2(10.5,8.5)]),"actual staff body overlap remains a physical rejection")
 var enclosed=Model.new()
 enclosed.items.clear();enclosed.dining_sets.clear()
 for at in [Vector2i(9,7),Vector2i(10,6),Vector2i(10,8)]:
  check(enclosed.place("plant",at.x,at.y),"prepare three physical sides")
 check(enclosed.can_place("plant",11,7,-1,0,[Vector2(10.5,7.5)]),"a reachable worker route is not part of idle physical footprint validity")
 var moving=Model.new()
 var moved=moving.items[-1]
 var identity=int(moved.id)
 check(moving.move(identity,landing.x,landing.y),"idle existing furnishing can move onto owned clear landing")
 check(moving.get_item(identity).x==landing.x and moving.get_item(identity).z==landing.y,"move preserves furniture identity")
 print("PHYSICAL_PLACEMENT_POLICY_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 quit(0 if failures.is_empty() else 1)
