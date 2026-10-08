extends RefCounted
## One authoritative plan for the current hovered whole furnishing.
## Background floor colors never request hypothetical placement plans.
const StaffRelocation=preload("res://scripts/cafe_staff_relocation.gd")
const Motion=preload("res://scripts/cafe_furniture_motion.gd")
var _state:Array=[]
var _key:Array=[]
var _kind=""
var _id=-1
var _rotation=0
var _receipt:Dictionary={}
var _plan_result:Dictionary={}
var validations=0
func stamp(model,actors:Array)->Array:
 return [
  # Owner and layout, including direct changes that have no notification.
  model.get_instance_id(),model.revision,
  hash(model.items),hash(model.dining_sets),hash(model.built_walls),
  hash(model.wall_attachments),hash(model.shell_products),hash(model.shell_segment_products),model.shell_material,
  hash(model.owned_parcels),model.width,model.depth,
  # Runtime routes, physical reservations, and directional safety policy.
  hash(model.customers),hash(model.wall_actor_positions),
  hash(model.checkout_staff_claims),hash(actors),
  # Purchase entitlement and staffing used by the existing planners.
  model.coins,model._next_item_id,hash(model.catalog),
  model.decoration_session_active,hash(model.decoration_purchases),
  model.included_checkout_pending,model.included_bin_pending,
  model.cashiers,model.cooks,model.waiters,model.cleaners,model.operating_open,
  hash(model.duty_counts),hash(model.duty_targets),
 ]

func prepare(model,kind:String,id:int,rotation:int,cell:Vector2i,actors:Array=[])->Dictionary:
 id=model.logical_item_id(id) if id>=0 else -1
 if id>=0:kind=model.logical_kind(id)
 var next_state=stamp(model,actors)
 var next=next_state+[kind,id,posmod(rotation,4),cell]
 if next==_key:return _receipt
 invalidate();_state=next_state;_key=next;_kind=kind;_id=id;_rotation=posmod(rotation,4)
 validations+=1
 var problem=_footprint_problem(model,cell)
 if problem!="":_plan_result={"ok":false,"error":problem}
 else:
  _plan_result=_plan(model,cell,actors)
  if not _plan_result.ok and not actors.is_empty() and str(_plan_result.get("error","")).to_lower().contains("staff"):
   var relocation=StaffRelocation.plan(model,_kind,_id,cell.x,cell.y,_rotation,actors)
   if relocation.ok:
    _plan_result=_plan(model,cell,relocation.positions)
    if _plan_result.ok and not relocation.moves.is_empty():_plan_result["staff_positions"]=relocation.positions
   else:_plan_result=relocation
 _receipt={"ok":bool(_plan_result.ok),"error":str(_plan_result.get("error","")),"issue":_plan_result.get("issue",{}).duplicate(true),"cell":cell}
 return _receipt

func _footprint_problem(model,cell:Vector2i)->String:
 var current=model.get_item(_id)
 if _id>=0 and not current.is_empty() and Vector2i(current.x,current.z)==cell and model.logical_rotation(_id)==_rotation:return ""
 var omitted=model.logical_members(_id) if _id>=0 else []
 for part in model.placement_parts(_kind,cell.x,cell.y,_rotation,_id):
  var name=str(part.kind).capitalize()
  if not model.is_floor_owned(Vector2i(part.x,part.z)):return name+" needs owned floor"
  var existing=model.item_at(part.x,part.z)
  if not existing.is_empty() and int(existing.id) not in omitted:return name+" overlaps "+str(existing.kind)
 return ""

func _plan(model,cell:Vector2i,actors:Array)->Dictionary:
 if _id>=0:return Motion.plan(model,_id,cell.x,cell.y,_rotation,actors)
 var shadow=Motion.copy_model(model)
 shadow.duty_counts=model.duty_counts.duplicate(true);shadow.duty_targets=model.duty_targets.duplicate(true)
 shadow.wall_actor_positions.assign(model.wall_actor_positions)
 shadow.checkout_staff_claims.assign(model.checkout_staff_claims)
 var ok=shadow.place(_kind,cell.x,cell.y,_rotation,actors)
 var plan={"ok":ok,"error":shadow.last_error,"issue":shadow.last_placement_issue.duplicate(true)}
 if ok:
  plan.merge({
   "items":shadow.items,"groups":shadow.dining_sets,
   "coins":shadow.coins,"next_id":shadow._next_item_id,
   "decoration_purchases":shadow.decoration_purchases,
   "checkout_pending":shadow.included_checkout_pending,
   "bin_pending":shadow.included_bin_pending,"event":shadow.last_event,
   "cashiers":shadow.cashiers,
   "cashier_count":shadow.duty_counts.get("cashier",0),
   "cashier_target":shadow.duty_targets.get("cashier",0),
  })
 return plan

func commit(model,receipt:Dictionary,actors:Array=[],apply_staff:Callable=Callable())->bool:
 if _state.is_empty() or stamp(model,actors)!=_state:return model._fail("Placement changed · review the floor again")
 if not is_same(receipt,_receipt):return model._fail("Placement belongs to another preview")
 var plan:Dictionary=_plan_result
 if not bool(plan.get("ok",false)):
  model.last_placement_issue=plan.get("issue",{}).duplicate(true)
  return model._fail(str(plan.get("error","Invalid placement")))
 # A model-only caller cannot accept a plan without its live staff half.
 if plan.has("staff_positions"):
  if not apply_staff.is_valid() or not apply_staff.call(actors,plan.staff_positions):return model._fail("Staff changed · review the floor again")
 if _id>=0:
  if not Motion.commit(model,plan):return false
 else:
  # Preserve existing dictionaries referenced by service jobs; append only
  # validated purchases, never publish the planner's cloned old furniture.
  for item in plan.items:
   if int(item.id)>=model._next_item_id:model.items.append(item.duplicate(true))
  model.dining_sets.assign(plan.groups.duplicate(true))
  model.decoration_purchases=plan.decoration_purchases.duplicate(true)
  model.coins=int(plan.coins)
  model._next_item_id=int(plan.next_id)
  model.included_checkout_pending=bool(plan.checkout_pending)
  model.included_bin_pending=bool(plan.bin_pending)
  model.last_error=""
  model.last_event=str(plan.event)
  if _kind=="register":
   model.cashiers=int(plan.cashiers)
   model.duty_counts["cashier"]=int(plan.cashier_count)
   model.duty_targets["cashier"]=int(plan.cashier_target)
  model._notify()
 invalidate()
 return true

func invalidate():
 _state=[];_key=[];_receipt={};_plan_result={};_kind="";_id=-1;_rotation=0
