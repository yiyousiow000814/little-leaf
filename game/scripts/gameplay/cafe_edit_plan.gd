extends RefCounted
## One authoritative plan for the current hovered whole furnishing.
## Background floor colors never request hypothetical placement plans.
const Motion=preload("res://scripts/gameplay/cafe_furniture_motion.gd")
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
  hash(model.wall_attachments),
  hash(model.owned_parcels),model.width,model.depth,
  # Runtime routes, physical reservations, and directional safety policy.
  hash(model.customers),hash(model.wall_actor_positions),
  hash(model.checkout_staff_claims),hash(actors),
  # Purchase entitlement and staffing used by the existing planners.
  model.coins,model._next_item_id,hash(model.catalog),
  model.decoration_session_active,hash(model.decoration_purchases),
  model.included_checkout_pending,model.register_unplaced,model.included_bin_pending,
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
 var problem=_physical_problem(model,cell,actors)
 if problem!="":_plan_result={"ok":false,"error":problem}
 else:_plan_result=_plan(model,cell,actors)
 # Physical fit drives the footprint. Funds and runtime custody still govern
 # the separate atomic transaction, so a fitting preview can remain unbuyable.
 _receipt={"ok":bool(_plan_result.ok),"physical_ok":problem=="","error":str(_plan_result.get("error","")),"issue":_plan_result.get("issue",{}).duplicate(true),"cell":cell}
 return _receipt

func _physical_problem(model,cell:Vector2i,actors:Array)->String:
 var current=model.get_item(_id)
 if _id>=0 and not current.is_empty() and Vector2i(current.x,current.z)==cell and model.logical_rotation(_id)==_rotation:return ""
 # The geometry predicate reports its failure through model scratch fields;
 # preview planning must preserve the caller's current diagnostic objects.
 var previous_error=model.last_error
 var previous_issue=model.last_placement_issue
 var physical_ok=model.can_place(_kind,cell.x,cell.y,_id,_rotation,actors)
 var problem="" if physical_ok else str(model.last_error)
 model.last_error=previous_error;model.last_placement_issue=previous_issue
 return problem

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
   "checkout_pending":shadow.included_checkout_pending,"register_unplaced":shadow.register_unplaced,
   "bin_pending":shadow.included_bin_pending,"event":shadow.last_event,
   "cashiers":shadow.cashiers,
   "cashier_count":shadow.duty_counts.get("cashier",0),
   "cashier_target":shadow.duty_targets.get("cashier",0),
  })
 return plan

func commit(model,receipt:Dictionary,actors:Array=[])->bool:
 if _state.is_empty() or stamp(model,actors)!=_state:return model._fail("Placement changed · review the floor again")
 if not is_same(receipt,_receipt):return model._fail("Placement belongs to another preview")
 var plan:Dictionary=_plan_result
 if not bool(plan.get("ok",false)):
  model.last_placement_issue=plan.get("issue",{}).duplicate(true)
  return model._fail(str(plan.get("error","Invalid placement")))
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
  model.register_unplaced=bool(plan.register_unplaced)
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
