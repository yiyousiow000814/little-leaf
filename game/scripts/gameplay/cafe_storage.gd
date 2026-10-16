extends RefCounted
## Owned, unplaced furniture. Quantities are a view over stable asset identities.
## Service jobs remain in their existing ledgers, never inside this stock.
const FORMAT="little_leaf.storage.v1"
const Dining=preload("res://scripts/gameplay/cafe_dining_sets.gd")
static func empty()->Dictionary:return {"items":[],"dining_sets":[]}
static func group_for(model,id:int)->Dictionary:return Dining.group_for(model.storage.dining_sets,id)
static func item_for(model,id:int)->Dictionary:
 for item in model.storage.items:
  if int(item.id)==id:return item
 return {}
static func kind_for(model,id:int)->String:
 var group=group_for(model,id)
 return Dining.product_for_variant(str(group.variant)) if not group.is_empty() else str(item_for(model,id).get("kind",""))
static func ids_for(model,kind:String)->Array:
 var result=[];var grouped={}
 for group in model.storage.dining_sets:
  grouped[int(group.table_id)]=true;grouped[int(group.seat_id)]=true
  if Dining.product_for_variant(str(group.variant))==kind:result.append(int(group.table_id))
 for item in model.storage.items:
  if not grouped.has(int(item.id)) and str(item.kind)==kind:result.append(int(item.id))
 result.sort();return result
static func validate(model,raw,placed:Array,next_id:int)->Dictionary:
 var bad={"ok":false,"error":"Invalid owned Storage"}
 if not raw is Dictionary or raw.size()!=2 or not raw.get("items") is Array or not raw.get("dining_sets") is Array:return bad
 var ids={};var registers=0;var stored:Array[Dictionary]=[]
 for item in placed:
  if not model._valid_int(item.get("id"),1,1000000000) or ids.has(int(item.id)) or int(item.id)>=next_id:return bad
  if item.has("paid_cost") and not model._valid_int(item.paid_cost,0,1000000000):return bad
  ids[int(item.id)]=true
  if item.kind=="register":registers+=1
 for entry in raw.items:
  if not entry is Dictionary:return bad
  for key in entry:
   if key not in ["id","kind","x","z","rot","paid_cost"]:return bad
  if not model._valid_int(entry.get("id"),1,1000000000) or ids.has(int(entry.id)) or int(entry.id)>=next_id:return bad
  if not entry.get("kind") is String or model.price_of(entry.kind)<0 or model.is_dining_product(entry.kind):return bad
  if not model._valid_int(entry.get("x"),0,model.MAX_WIDTH-1) or not model._valid_int(entry.get("z"),0,model.MAX_DEPTH-1) or not model._valid_int(entry.get("rot"),0,3):return bad
  if entry.has("paid_cost") and not model._valid_int(entry.paid_cost,0,1000000000):return bad
  var item={"id":int(entry.id),"kind":str(entry.kind),"x":int(entry.x),"z":int(entry.z),"rot":int(entry.rot)}
  if entry.has("paid_cost"):item.paid_cost=int(entry.paid_cost)
  stored.append(item);ids[int(item.id)]=true
  if item.kind=="register":registers+=1
 if registers>1:return bad
 for group in raw.dining_sets:
  if not group is Dictionary or group.size()!=6:return bad
  for key in ["id","table_id","seat_id","variant","rot","paid_cost"]:
   if not group.has(key):return bad
 var groups=Dining.validate(raw.dining_sets,stored,[])
 if not groups.ok:return {"ok":false,"error":groups.error}
 return {"ok":true,"storage":{"items":stored,"dining_sets":groups.groups}}
static func held_error(stock:Dictionary,service:Dictionary)->String:
 var owned={}
 for item in stock.items:owned[int(item.id)]=item
 for host in service.get("layout_hold",{}).get("hosts",[]):
  if owned.has(int(host.id)) and owned[int(host.id)].kind!=host.kind:return "Stored furnishing disagrees with its held service identity"
 return ""
static func store(model,id:int)->bool:
 if not model.decoration_session_active:return model._fail("Open Decorate first")
 id=model.logical_item_id(id)
 var item=model.get_item(id)
 if item.is_empty():return model._fail("Select a furnishing first")
 var members=model.logical_members(id);var group=model.dining_set_for(id)
 # The planner owns actor-independent geometry. Apply owns service reconciliation.
 for member in members:
  if not item_for(model,int(member)).is_empty():return model._fail("This furnishing is already in Storage")
 for member in members:
  var physical=model.get_item(int(member))
  model.storage.items.append(physical.duplicate(true));model.items.erase(physical)
 if not group.is_empty():model.storage.dining_sets.append(group.duplicate(true));model.dining_sets.erase(group)
 if item.kind=="register":model.register_unplaced=true
 model.storage_used=true
 model.last_error="";model.last_event="Stored %s · no charge"%model.name_of(kind_for(model,id));model._notify();return true
static func place(model,id:int,x:int,z:int,rot:int,actors:Array=[])->bool:
 if not model.decoration_session_active:return model._fail("Open Decorate first")
 var item=item_for(model,id)
 if item.is_empty():return model._fail("This furnishing is no longer in Storage")
 var group=group_for(model,id);var members=[int(group.table_id),int(group.seat_id)] if not group.is_empty() else [id]
 var previous_items=model.items.duplicate();var previous_groups=model.dining_sets.duplicate()
 for member in members:model.items.append(item_for(model,int(member)).duplicate(true))
 if not group.is_empty():model.dining_sets.append(group.duplicate(true));id=int(group.table_id)
 var kind=model.logical_kind(id)
 var ok=model.can_place(kind,x,z,id,rot,actors)
 if ok:
  if group.is_empty():
   var placed=model.get_item(id);placed.x=x;placed.z=z;placed.rot=posmod(rot,4)
  else:
   var parts=Dining.parts(model,x,z,rot,id)
   for part in parts:
    var placed=model.get_item(int(part.id));placed.x=part.x;placed.z=part.z;placed.rot=part.rot
   model.dining_set_for(id).rot=posmod(rot,4)
 if not ok:
  model.items.assign(previous_items);model.dining_sets.assign(previous_groups);return false
 var remaining=[]
 for stored in model.storage.items:
  if int(stored.id) not in members:remaining.append(stored)
 model.storage.items=remaining
 if not group.is_empty():model.storage.dining_sets.erase(group)
 if item.kind=="register":model.register_unplaced=false
 model.storage_used=true;model.last_error="";model.last_event="Placed %s from Storage · no charge"%model.name_of(kind);model._notify();return true
