extends SceneTree
## Synthetic geometry/transaction contract; run only in a disposable profile.
## The ordinary idle save roundtrip also requires the Gameplay reader bridge.
const Model=preload("res://scripts/core/cafe_model.gd")
const MinimalStart=preload("res://scripts/minimal_start.gd")
const EditPlan=preload("res://scripts/gameplay/cafe_edit_plan.gd")
const Openings=preload("res://scripts/gameplay/cafe_wall_openings.gd")
var checks=0
var failures=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func state(model)->String:
 return JSON.stringify([model.items,model.dining_sets,model.customers,model.coins,model.revision,model._next_item_id,model.decoration_purchases,model.wall_attachments,model.service_snapshot])
func fixture():
 var model=Model.new();MinimalStart.apply(model)
 return model
func staff_snapshot(position:Vector2)->Dictionary:
 var staff=[]
 for role in ["chef","waiter","cleaner"]:
  staff.append({"role":role,"on_duty":true,"duty_pending":false,"pos":position if role=="chef" else Vector2(2.5,6.5 if role=="waiter" else 7.5),"destination":Vector2i(-100,-100),"path":[],"index":0,"job_kind":"","job_step":0,"job_elapsed":0.0,"station_id":-1,"job_guest_id":-1,"job_token":-1})
 return {"version":Model.SaveContract.SERVICE_VERSION,"checkout_format":Model.SaveContract.CHECKOUT_FORMAT,"serial":0,"records":[],"staff":staff,"animation_time":0.0,"dishwashing":{"format":"little_leaf.dishwashing.v1","next_id":1,"completed":0,"dishes":[]}}
func synthetic_file(path:String,text:String)->bool:
 var file=FileAccess.open(path,FileAccess.WRITE)
 if file==null:return false
 file.store_string(text);file.close();return true
func _init():
 if not "placement-saveguard" in OS.get_user_data_dir():printerr("Use isolated placement-saveguard profile");quit(2);return
 var model=fixture();var plan=EditPlan.new();var target=Model.ENTRY_LANDING
 var before=state(model);var old_error="prior diagnostic";var old_issue={"prior":true}
 model.last_error=old_error;model.last_placement_issue=old_issue
 var receipt=plan.prepare(model,"plant",-1,0,target)
 check(receipt.physical_ok,"owned empty entrance landing is a physical fit")
 check(receipt.ok,"idle blocked-entrance transaction prepares")
 check(state(model)==before,"preview preserves items, wallet, revision, provenance and service")
 check(model.last_error==old_error and is_same(model.last_placement_issue,old_issue),"preview preserves existing diagnostic objects")
 check(is_same(plan.prepare(model,"plant",-1,0,target),receipt) and plan.validations==1,"unchanged preview reuses its receipt")
 var wallet=model.coins;var next_id=model._next_item_id
 check(plan.commit(model,receipt),"idle blocked-entrance purchase commits")
 check(model.coins==wallet-model.price_of("plant") and model._next_item_id==next_id+1,"purchase spends stated price and allocates once")
 var placed=model.get_item(next_id)
 check(not placed.is_empty() and Vector2i(placed.x,placed.z)==target,"committed furnishing occupies only requested landing")
 before=state(model)
 check(not plan.commit(model,receipt) and state(model)==before,"replaying receipt cannot spend or allocate again")
 var directory="user://placement-fixtures"
 check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))==OK,"private synthetic output directory")
 var path=directory+"/idle-blocked-entrance.json"
 var saved=model.save(path)
 check(saved,"ordinary blocked-entrance save: "+model.last_error)
 if saved:
  var source_hash=FileAccess.get_sha256(path);var loaded=Model.new()
  var load_ok=loaded.load_save(path)
  check(load_ok,"ordinary blocked-entrance reload: "+loaded.last_error)
  if load_ok:
   check(loaded.items==model.items and loaded.coins==model.coins and loaded._next_item_id==model._next_item_id,"roundtrip preserves furniture identities, wallet and allocation")
   check(loaded.wall_attachments==model.wall_attachments and loaded.customers.is_empty(),"roundtrip preserves openings and empty service")
  check(FileAccess.get_sha256(path)==source_hash,"reload never rewrites fixture bytes")
 var body_model=Model.new();body_model.service_snapshot=staff_snapshot(Vector2(1.5,1.5))
 var body_path=directory+"/saved-body-refusal.json"
 check(synthetic_file(body_path,"{\"synthetic\":\"previous destination\"}"),"synthetic prior destination seeded")
 var body_hash=FileAccess.get_sha256(body_path)
 var body_saved=body_model.save(body_path)
 check(not body_saved and body_model.last_error.contains("physical layout"),"saved staff body overlapping furniture still rejects write through the physical guard")
 check(FileAccess.get_sha256(body_path)==body_hash,"body refusal preserves existing destination bytes")
 var malformed_path=directory+"/malformed.json"
 check(synthetic_file(malformed_path,"{\"schema\":\"foreign\",\"items\":[]}"),"synthetic malformed input seeded")
 var malformed_hash=FileAccess.get_sha256(malformed_path);var receiver=fixture();before=state(receiver)
 check(not receiver.load_save(malformed_path) and state(receiver)==before,"malformed input cannot publish partial state")
 check(FileAccess.get_sha256(malformed_path)==malformed_hash,"malformed input bytes remain unchanged")
 model=fixture();plan=EditPlan.new();model.coins=0;before=state(model)
 receipt=plan.prepare(model,"plant",-1,0,Vector2i(4,6))
 check(receipt.physical_ok and not receipt.ok,"funds do not recolor an otherwise fitting footprint")
 check(not plan.commit(model,receipt) and state(model)==before,"unaffordable transaction remains atomic")
 model=fixture();plan=EditPlan.new();before=state(model)
 receipt=plan.prepare(model,"plant",-1,0,Vector2i(8,1))
 check(not receipt.physical_ok and not receipt.ok,"actual furniture overlap is rejected")
 check(not plan.commit(model,receipt) and state(model)==before,"overlap refusal does not mutate state")
 receipt=plan.prepare(model,"plant",-1,0,Vector2i(-1,5))
 check(not receipt.physical_ok and not receipt.ok,"unowned footprint is rejected")
 receipt=plan.prepare(model,"plant",-1,0,target,[Vector2(target)+Vector2(.5,.5)])
 check(not receipt.physical_ok and not receipt.ok,"present staff body rejects footprint without hypothetical relocation")
 check(state(model)==before,"body and bounds previews preserve state")
 model.customers.append({"id":999,"phase":"arriving","x":float(target.x)+.5,"z":float(target.y)+.5})
 receipt=plan.prepare(model,"plant",-1,0,target)
 check(not receipt.physical_ok and not receipt.ok,"present guest body rejects footprint")
 model=fixture();plan=EditPlan.new()
 var station=model.get_item(2);var face=model.workface_cell(station)
 receipt=plan.prepare(model,"plant",-1,0,face)
 check(receipt.physical_ok and receipt.ok,"empty station workface is operational space rather than a placement veto")
 var parts=model.placement_parts("table_set",4,6,0)
 check(parts.size()==2 and model.can_place("table_set",4,6),"both logical dining parts fit on owned clear floor")
 check(not model.can_place("table_set",3,2),"one colliding dining part rejects the whole set")
 var wrong_mount={"id":999,"kind":"door","host_id":"missing-host","offset":.5,"width":1.0,"paid_cost":model.attachment_price("door")}
 check(Openings.compatible_error(wrong_mount,model.built_walls,model.wall_attachments)!="","opening without a compatible host remains invalid")
 plan=EditPlan.new();receipt=plan.prepare(model,"plant",-1,0,target);before=state(model)
 model.coins+=1;var changed=state(model)
 check(not plan.commit(model,receipt) and state(model)==changed,"changed wallet invalidates receipt before commit")
 print("PHYSICAL_PLACEMENT_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"original_player_save_used":false,"generated_fixture":path}))
 quit(0 if failures.is_empty() else 1)
