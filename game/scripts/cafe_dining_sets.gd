extends RefCounted
const Money=preload("res://scripts/cafe_money.gd")
## Bound logical objects over stable physical furniture IDs.
const DIRECTIONS=[Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP,Vector2i.RIGHT]
# Product keys are stable UI identities; physical members remain table/chair.
# New purchases use current catalog prices; historical costs keep their resale value.
const PRODUCTS={"table_set":"oak_single","table_set_cottage":"cottage_single","table_set_retro":"retro_single","table_set_refined":"refined_single"}
const VARIANTS={
 "oak_single":{"table":"table","seat":"chair","price":280,"name":"Basic oak","description":"Round oak table · simple wooden chair"},
 "cottage_single":{"table":"table","seat":"chair","price":420,"name":"Cottage","description":"Cream farmhouse table · sage cross-back chair"},
 "retro_single":{"table":"table","seat":"chair","price":1200,"name":"Retro","description":"Mint pedestal table · coral diner chair"},
 "refined_single":{"table":"table","seat":"chair","price":3600,"name":"Refined","description":"Ivory-inlaid walnut table · forest upholstered chair"},
 "legacy_bench":{"table":"table","seat":"bench","price":175,"name":"Table set","description":"Original table and bench"}
}
# Save integrity, matching the floor/wall ledgers: only real historical amounts.
# If a catalog price changes, append that genuine price here and retain prior
# amounts. Never replace an old purchase's paid_cost with today's storefront.
const HISTORICAL_PAID_COSTS={"oak_single":[140,280],"cottage_single":[420],"retro_single":[1200],"refined_single":[3600],"legacy_bench":[175]}
const LEGACY_UNRECORDED_COSTS={"oak_single":140,"legacy_bench":175}
static func is_product(kind:String)->bool:return PRODUCTS.has(kind)
static func variant_for_product(kind:String)->String:return str(PRODUCTS.get(kind,"oak_single"))
static func product_for_variant(variant:String)->String:
 for kind in PRODUCTS:
  if PRODUCTS[kind]==variant:return kind
 return "table_set"
static func style_for_variant(variant:String)->String:
 return {"oak_single":"basic","cottage_single":"cottage","retro_single":"retro","refined_single":"refined"}.get(variant,"basic")
static func inherited_cost(variant:String)->int:return int(LEGACY_UNRECORDED_COSTS.get(variant,-1))
static func _metadata(table:Dictionary,seat:Dictionary,existing:Array)->Dictionary:
 for entry in existing:
  if int(entry.get("table_id",-1))==int(table.id) and int(entry.get("seat_id",-1))==int(seat.id):return entry
 return {}
static func _group(table:Dictionary,seat:Dictionary,rot:int,metadata:Dictionary)->Dictionary:
 var variant=str(metadata.get("variant","legacy_bench" if seat.kind=="bench" else "oak_single"))
 if not VARIANTS.has(variant) or VARIANTS[variant].seat!=seat.kind:variant="legacy_bench" if seat.kind=="bench" else "oak_single"
 return {"id":int(table.id),"table_id":int(table.id),"seat_id":int(seat.id),"variant":variant,"rot":rot,"paid_cost":int(metadata.get("paid_cost",inherited_cost(variant)))}
static func group_for(groups:Array,id:int)->Dictionary:
 for g in groups:
  if int(g.table_id)==id or int(g.seat_id)==id:return g
 return {}
static func orientation(table:Dictionary,seat:Dictionary)->int:
 return DIRECTIONS.find(Vector2i(int(seat.x)-int(table.x),int(seat.z)-int(table.z)))
static func migrate(items:Array,customers:Array,existing:Array=[])->Array[Dictionary]:
 var by_id={};var used={};var result:Array[Dictionary]=[];var candidates=[]
 for item in items:by_id[int(item.id)]=item
 # An admitted diner keeps exactly the same dining association.
 for guest in customers:candidates.append({"table_id":guest.table_id,"seat_id":guest.chair_id})
 candidates.append_array(existing)
 var tables=items.filter(func(i):return i.kind=="table");tables.sort_custom(func(a,b):return int(a.id)<int(b.id))
 var seats=items.filter(func(i):return i.kind in ["chair","bench"]);seats.sort_custom(func(a,b):return int(a.id)<int(b.id))
 for table in tables:
  for seat in seats:
   if orientation(table,seat)>=0:candidates.append({"table_id":table.id,"seat_id":seat.id})
 for candidate in candidates:
  var tid=int(candidate.table_id);var sid=int(candidate.seat_id)
  if used.has(tid) or used.has(sid) or not by_id.has(tid) or not by_id.has(sid):continue
  var table=by_id[tid];var seat=by_id[sid]
  if table.kind!="table" or seat.kind not in ["chair","bench"]:continue
  var rot=orientation(table,seat)
  if rot<0:continue
  result.append(_group(table,seat,rot,_metadata(table,seat,existing)))
  used[tid]=true;used[sid]=true
 return result
static func validate(raw,items:Array,customers:Array)->Dictionary:
 if not raw is Array or raw.size()>items.size()/2:return {"ok":false,"error":"Invalid dining-set list"}
 var by_id={};var used={};var groups:Array[Dictionary]=[]
 for item in items:by_id[int(item.id)]=item
 for entry in raw:
  if not entry is Dictionary:return {"ok":false,"error":"Invalid dining-set entry"}
  for key in ["id","table_id","seat_id","rot"]:
   var v=entry.get(key)
   if not (v is int or v is float) or not is_finite(float(v)) or floorf(float(v))!=float(v):return {"ok":false,"error":"Invalid dining-set identity or direction"}
  var tid=int(entry.table_id);var sid=int(entry.seat_id);var rot=int(entry.rot)
  if int(entry.id)!=tid or tid==sid or used.has(tid) or used.has(sid) or not by_id.has(tid) or not by_id.has(sid) :return {"ok":false,"error":"Missing or duplicated dining-set member"}
  var table=by_id[tid];var seat=by_id[sid]
  var variant=str(entry.get("variant","legacy_bench" if seat.kind=="bench" else "oak_single"))
  if not VARIANTS.has(variant):return {"ok":false,"error":"Unknown dining-set style"}
  var spec=VARIANTS[variant]
  if table.kind!=spec.table or seat.kind!=spec.seat or rot<0 or rot>3 or orientation(table,seat)!=rot:return {"ok":false,"error":"Dining-set footprint is inconsistent"}
  if not entry.has("paid_cost") and not LEGACY_UNRECORDED_COSTS.has(variant):return {"ok":false,"error":"Missing dining-set purchase cost"}
  var paid=entry.get("paid_cost",inherited_cost(variant))
  if not (paid is int or paid is float) or not is_finite(float(paid)) or floorf(float(paid))!=float(paid) or float(paid)<0 or float(paid)>1000000000:return {"ok":false,"error":"Invalid dining-set purchase cost"}
  if int(paid) not in HISTORICAL_PAID_COSTS[variant]:return {"ok":false,"error":"Unrecognized dining-set purchase cost"}
  groups.append(_group(table,seat,rot,entry));used[tid]=true;used[sid]=true
 for guest in customers:
  var group=group_for(groups,int(guest.table_id))
  if not group.is_empty() and int(group.seat_id)!=int(guest.chair_id):return {"ok":false,"error":"Diner association disagrees with its table set"}
 return {"ok":true,"groups":groups}
static func parts(model,x:int,z:int,rot:int,id:int=-1,variant:String="oak_single")->Array[Dictionary]:
 var group=group_for(model.dining_sets,id);var direction:Vector2i=DIRECTIONS[posmod(rot,4)];var table={};var seat={}
 if not group.is_empty():table=model.get_item(int(group.table_id)).duplicate();seat=model.get_item(int(group.seat_id)).duplicate()
 else:table={"id":-100,"kind":"table"};seat={"id":-101,"kind":"chair"}
 if not group.is_empty():variant=str(group.variant)
 table["dining_variant"]=variant;seat["dining_variant"]=variant
 table.merge({"x":x,"z":z,"rot":posmod(rot,4)},true);seat.merge({"x":x+direction.x,"z":z+direction.y,"rot":posmod(rot,4)},true)
 return [table,seat]
static func candidate(model,x:int,z:int,rot:int,id:int=-1)->Dictionary:
 var group=group_for(model.dining_sets,id);var omitted=[]
 if not group.is_empty():omitted=[int(group.table_id),int(group.seat_id)]
 var additions=parts(model,x,z,rot,id);var proposed:Array[Dictionary]=[]
 for item in model.items:
  if int(item.id) not in omitted:proposed.append(item)
 proposed.append_array(additions)
 return {"parts":additions,"layout":proposed,"omitted":omitted,"group":group}
static func can_place(model,x:int,z:int,rot:int,id:int=-1,actor_positions:Array=[])->bool:
 model.last_error="";model.last_placement_issue={};var data=candidate(model,x,z,rot,id)
 for member in data.omitted:
  if model._item_in_use(member):return model._fail("Wait until this table set is cleaned")
 for part in data.parts:
  var cell=Vector2i(int(part.x),int(part.z))
  if not model.is_floor_owned(cell):return model._fail("Both parts need owned floor")
  if cell in [model.ENTRANCE,model.ENTRY_LANDING]:return model._fail("Keep the entrance clear")
  if model._guest_route_uses(cell):return model._fail("A guest is using part of this space")
  for item in model.items:
   if int(item.id) not in data.omitted and int(item.x)==cell.x and int(item.z)==cell.y:return model._fail("Part of this table set is occupied")
 var actor_error=model._furniture_actor_error(data.parts,data.layout,actor_positions)
 if actor_error!="":return model._fail(actor_error)
 if model.edge_blocked(Vector2i(x,z),Vector2i(int(data.parts[1].x),int(data.parts[1].z))):return model._fail("A wall separates the table and chair")
 if not model._placement_workfaces_allowed(data.layout):return false
 var chair_error=model._chair_egress_error(model.built_walls,data.layout,model.owned_parcels,model.customers)
 if chair_error!="":return model._fail(chair_error)
 if not model._layout_has_access(data.layout,model.depth):return model._fail("Leave a walkable service route")
 if not model.built_walls.is_empty():
  var reason=model._wall_egress_error(model.built_walls,[],data.layout,model.owned_parcels,model.customers)
  if reason!="":return model._fail(reason)
 return true
static func place(model,x:int,z:int,rot:int,variant:String="oak_single",actor_positions:Array=[])->bool:
 if not VARIANTS.has(variant) or variant=="legacy_bench":return model._fail("Unknown dining style")
 if not can_place(model,x,z,rot,-1,actor_positions):return false
 var price=int(model.price_of(product_for_variant(variant)))
 if model.coins<price:return model._fail("Not enough coins · need %s"%Money.amount(price))
 var created=parts(model,x,z,rot,-1,variant)
 for part in created:part.erase("dining_variant")
 created[0].id=model._next_item_id;created[1].id=model._next_item_id+1
 model._next_item_id+=2;model.items.append_array(created);model.coins-=price
 model.dining_sets.append({"id":int(created[0].id),"table_id":int(created[0].id),"seat_id":int(created[1].id),"variant":variant,"rot":posmod(rot,4),"paid_cost":price})
 model.record_decoration_purchase(int(created[0].id),price)
 model.rebuild_dining_sets();model.last_event="Placed %s set · −%s"%[VARIANTS[variant].name,Money.amount(price)];model._notify();return true
static func move(model,id:int,x:int,z:int,rot:int,actor_positions:Array=[])->bool:
 var group=group_for(model.dining_sets,id)
 if group.is_empty():return model._fail("Select a table set")
 if not can_place(model,x,z,rot,id,actor_positions):return false
 var changed=parts(model,x,z,rot,id)
 for part in changed:
  var target=model.get_item(int(part.id));target.x=part.x;target.z=part.z;target.rot=part.rot
 group.rot=posmod(rot,4);model.last_event="Moved table set";model._notify();return true
static func refund(model,id:int)->int:
 var group=group_for(model.dining_sets,id)
 if group.is_empty():return int(model.price_of(str(model.get_item(id).get("kind","")))/2)
 return int(int(group.get("paid_cost",inherited_cost(str(group.variant))))/2)
static func remove(model,id:int,refund_value:bool)->bool:
 var group=group_for(model.dining_sets,id)
 if group.is_empty():return model._fail("Select a table set")
 for member in [int(group.table_id),int(group.seat_id)]:
  if model._item_in_use(member):return model._fail("Wait until this table set is cleaned")
 var essential_error=model._essential_removal_error([int(group.table_id),int(group.seat_id)])
 if essential_error!="":return model._fail(essential_error)
 var returned=model.logical_refund(id) if refund_value else 0
 var kept:Array[Dictionary]=[]
 for item in model.items:
  if int(item.id) not in [int(group.table_id),int(group.seat_id)]:kept.append(item)
 model.consume_decoration_purchase([int(group.table_id),int(group.seat_id)])
 model.items.assign(kept);model.dining_sets.erase(group);model.coins+=returned;model.last_error="";model.last_event="Sold table set · +%s"%Money.amount(returned);model._notify();return true
