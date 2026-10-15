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
func check_active_access_save_boundary(directory:String):
 # Physical-only placement is legal while idle, but active saves must match
 # the existing strict reader before replacing either destination file.
 for center in ["bin","plant"]:
  var model=fixture();model.begin_decoration_session()
  var unblock_id=-1
  for spec in [[center,8,6],["plant",7,6],["plant",9,6],["plant",8,5],["plant",8,7]]:
   check(model.place(spec[0],spec[1],spec[2]),center+" boundary fixture uses ordinary physical placement")
   if spec[1]==7:unblock_id=model._next_item_id-1
  model.finish_decoration_session()
  var path=directory+"/active-access-"+center+".json"
  check(model.save(path),center+" idle layout saves before normal arrival")
  var loaded=Model.new()
  check(loaded.load_save(path),center+" idle layout reloads before normal arrival")
  var previous_hash=FileAccess.get_sha256(path)
  var temp_path=path+".tmp"
  check(synthetic_file(temp_path,"{\"synthetic\":\"previous temporary file\"}"),"existing temporary bytes seeded")
  var temp_hash=FileAccess.get_sha256(temp_path)
  loaded.tick(4.1)
  check(loaded.customers.size()==1,"ordinary tick admits one guest without changing the optional furnishing")
  var saved=loaded.save(path)
  check(saved==(center=="plant"),center+" active save agrees with the unchanged reader access policy")
  var restored=Model.new()
  if center=="bin":
   check(loaded.last_error=="Saved layout blocks access to service stations","blocked optional bin reports the existing reader access error")
   check(FileAccess.get_sha256(path)==previous_hash,"active access refusal preserves last-good primary bytes")
   check(FileAccess.get_sha256(temp_path)==temp_hash,"active access refusal preserves preexisting temporary bytes")
   check(restored.load_save(path) and restored.customers.is_empty(),"previous idle save remains readable after active refusal")
   check(loaded.remove(unblock_id),"ordinary plant removal restores access without clearing the live guest")
   check(loaded.save(path),"unblocked active cafe saves")
   check(restored.load_save(path) and restored.customers.size()==1,"unblocked active cafe reloads its live guest")
  else:
   check(restored.load_save(path) and restored.customers.size()==1,"non-service center control preserves ordinary active save and reload")
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
 # Moving the default door releases its original two placement cells.
 var moved=fixture();var original_door=moved.get_wall_attachment(1).duplicate(true)
 check(moved.move_wall_attachment(1,"wall:16",.5),"default door moves to another valid shell tile")
 var moved_door=moved.get_wall_attachment(1)
 check(moved_door.id==original_door.id and moved_door.width==original_door.width and moved_door.paid_cost==original_door.paid_cost,"door move retains identity, width and payment")
 for former_cell in [Model.ENTRANCE,Model.ENTRY_LANDING]:
  var former_plan=EditPlan.new();var former_receipt=former_plan.prepare(moved,"plant",-1,0,former_cell)
  check(former_receipt.physical_ok and former_receipt.ok,"former default-door cell is no longer reserved: "+str(former_cell))
  check(former_plan.commit(moved,former_receipt),"former default-door cell accepts ordinary atomic placement: "+str(former_cell))
  check(not former_plan.prepare(moved,"plant",-1,0,former_cell).physical_ok,"real overlap still blocks the former door cell: "+str(former_cell))
 var moved_path=directory+"/moved-door-former-cells.json"
 check(moved.save(moved_path),"moved door and former-cell furniture save in the current idle contract")
 var moved_loaded=Model.new();var moved_load_ok=moved_loaded.load_save(moved_path)
 check(moved_load_ok,"moved door and former-cell furniture reload")
 if moved_load_ok:
  check(moved_loaded.items==moved.items and moved_loaded.coins==moved.coins,"former-cell furniture and payment survive roundtrip")
  check(moved_loaded.wall_attachments==moved.wall_attachments and is_equal_approx(float(moved_loaded.get_wall_attachment(1).offset),3.5),"reload keeps the moved door at its new host offset")
 check_active_access_save_boundary(directory)
 print("PHYSICAL_PLACEMENT_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"original_player_save_used":false,"generated_fixture":path}))
 quit(0 if failures.is_empty() else 1)
