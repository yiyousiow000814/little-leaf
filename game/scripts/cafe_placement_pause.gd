extends RefCounted
## Explicit v17 historical intent. A pending route is never executable geometry.
const Contract=preload("res://scripts/cafe_save_contract.gd")
const NONE=Vector2i(-100,-100)
static func blocked(guest:Dictionary)->bool:
 var mobility=guest.get("mobility",{})
 return mobility is Dictionary and mobility.get("kind","")=="blocked"
static func point(guest:Dictionary)->Vector2:return Vector2(float(guest.x),float(guest.z))
static func historical_guest(guest:Dictionary)->Dictionary:
 var result=guest.duplicate(true)
 if blocked(guest):result.mobility=guest.mobility.previous.duplicate(true)
 return result
static func historical_items(guest:Dictionary,items:Dictionary)->Dictionary:
 var result=items.duplicate()
 if blocked(guest):
  for anchor in guest.mobility.anchors:result[int(anchor.id)]=anchor
 return result
static func pause(model,guest:Dictionary)->void:
 if blocked(guest):return
 var anchors=[]
 for id in [int(guest.table_id),int(guest.chair_id),int(guest.get("checkout_register_id",-1))]:
  if id<0:continue
  var item=model.get_item(id)
  anchors.append({"id":id,"kind":str(item.kind),"x":int(item.x),"z":int(item.z),"rot":int(item.get("rot",0))})
 var previous:Dictionary=guest.get("mobility",{}).duplicate(true)
 var goal=str(previous.get("kind",""))
 if goal=="":
  goal="resume_walk" if guest.phase in ["arriving","leaving","checkout_walk"] else ("to_checkout" if guest.get("checkout_cell",NONE)!=NONE else "to_assigned_seat")
 guest.mobility={"kind":"blocked","format":Contract.FOOTPRINT_PLACEMENT_FORMAT,"goal":goal,"position":point(guest),"anchors":anchors,"previous":previous}
static func needs_pause(model,guest:Dictionary,old_model)->bool:
 if blocked(guest):return true
 if guest.phase in ["dirty","cleaning"]:return false
 for id in [int(guest.table_id),int(guest.chair_id),int(guest.get("checkout_register_id",-1))]:
  if id<0:continue
  var before=old_model.get_item(id);var after=model.get_item(id)
  if before.x!=after.x or before.z!=after.z or before.get("rot",0)!=after.get("rot",0):return true
 if not guest.get("mobility",{}).is_empty():
  return model.FurnitureMotion.geometry_error(model,[guest],model.items,model.built_walls,model.owned_parcels,model.wall_attachments)!=""
 if guest.phase in ["arriving","leaving","checkout_walk"]:
  return route_error(model,guest,guest.route,int(guest.route_index))!=""
 if guest.phase in ["checkout_wait","paying"] and guest.get("checkout_cell",NONE)!=NONE:
  var item=model.get_item(int(guest.checkout_register_id))
  return not model._walkable(guest.checkout_cell) or not model.workface_accessible(item) or not model.workface_accessible(item,true)
 return false
static func reconcile(model,old_model)->void:
 for guest in model.customers:
  if needs_pause(model,guest,old_model):pause(old_model,guest)
static func body_error(model,guests:Array,layout:Array,ownership:Array)->String:
 for guest in guests:
  if guest.phase in ["dirty","cleaning"]:continue
  var position=point(guest);var at=Vector2i(floori(position.x),floori(position.y))
  if blocked(guest) and not model._floor_owned_in(at,ownership):
   # Existing public arrival/exit lanes remain valid, never arbitrary grass.
   var arriving=guest.phase=="arriving"
   var extent=Vector2(model._width_for(ownership),model._depth_for(ownership))
   var front=maxf(model.EXTERIOR_ARRIVAL_FRONT,extent.y+.5) if arriving else maxf(model.EXTERIOR_EXIT_FRONT,extent.y+1.4)
   var right=maxf(model.EXTERIOR_ARRIVAL_RIGHT,extent.x+1.76) if arriving else maxf(model.EXTERIOR_EXIT_RIGHT,extent.x+.85)
   var left=model.ARRIVAL_LANE_X if arriving else -.85
   var outside=model.cell_center(guest.entry_outside)
   var jagged_x=outside.x-.26 if arriving else outside.x+.26
   var public_lane=absf(position.x-left)<.00001 or absf(position.x-right)<.00001 or absf(position.y-front)<.00001 or absf(position.y+1.76)<.00001
   if not public_lane and guest.entry_outside.y>=model.BASE_DEPTH:
    public_lane=absf(position.x-jagged_x)<.00001 and position.y>=minf(outside.y,front) and position.y<=maxf(outside.y,front)
   var entry_center=model.cell_center(guest.entry_cell)
   var doorway=Geometry2D.get_closest_point_to_segment(position,entry_center,model.cell_center(guest.entry_outside)).distance_to(position)<.00001
   if guest.phase not in ["arriving","leaving"] or not (public_lane or doorway):return "Pending guest is outside its owned floor or public lane"
  for item in layout:
   if str(item.kind)=="rug":continue
   var minimum=Vector2(int(item.x),int(item.z));var maximum=minimum+Vector2.ONE
   if int(item.id)==int(guest.chair_id) and (bool(guest.seated) or bool(guest.get("dismounting",false))):
    if not blocked(guest):continue
    var original=historical_items(guest,{})[int(guest.chair_id)]
    if original.x==item.x and original.z==item.z:continue
   var motion:Dictionary=guest.get("mobility",{})
   if int(item.id)==int(guest.chair_id) and motion.get("kind","")=="to_assigned_seat" and int(motion.route_index)==motion.route.size()-1:continue
   if position.distance_squared_to(position.clamp(minimum,maximum))<.23*.23:return "Guest body overlaps solid furniture"
 return ""
static func route_error(model,guest:Dictionary,route:Array,index:int)->String:
 var previous=point(guest)
 for i in range(index,route.size()):
  var next:Vector2=route[i]
  if absf(previous.x-next.x)>.00001 and absf(previous.y-next.y)>.00001:return "Guest replacement route is not cardinal"
  if model.segment_blocked(previous,next):return "Guest replacement route crosses a wall"
  var steps=maxi(1,ceili(previous.distance_to(next)*8.0))
  for sample in range(steps+1):
   var at=previous.lerp(next,float(sample)/steps)
   for item in model.items:
    if str(item.kind)=="rug":continue
    var final_seat=int(item.id)==int(guest.chair_id) and (guest.phase=="arriving" or guest.get("mobility",{}).get("kind","")=="to_assigned_seat") and i==route.size()-1
    var dismount=int(item.id)==int(guest.chair_id) and bool(guest.get("dismounting",false)) and i==0
    if final_seat or dismount:continue
    var minimum=Vector2(int(item.x),int(item.z));var maximum=minimum+Vector2.ONE
    if at.distance_squared_to(at.clamp(minimum,maximum))<.23*.23:return "Guest replacement body sweep is blocked"
  previous=next
 return ""
static func retry(model,guest:Dictionary)->bool:
 if not blocked(guest):return true
 var key=[model.revision,hash(model.checkout_claims())]
 if model._placement_pause_revision.get(int(guest.id),[])==key:return false
 model._placement_pause_revision[int(guest.id)]=key
 if body_error(model,[guest],model.items,model.owned_parcels)!="":return false
 var proposed=historical_guest(guest);var goal=str(guest.mobility.goal)
 var elapsed=guest.elapsed;var duration=guest.duration
 if goal=="to_assigned_seat":
  var route=model.FurnitureMotion.seat_route(model,proposed)
  if route.is_empty():return false
  proposed.service_cell=Vector2i(floori(route[-2].x),floori(route[-2].y)) if route.size()>1 else Vector2i(floori(guest.x),floori(guest.z))
  model.FurnitureMotion.relocate(proposed,goal,route)
 elif goal=="to_checkout" or guest.phase=="checkout_walk":
  var item=model.get_item(int(guest.checkout_register_id))
  if item.is_empty() or not model.workface_accessible(item) or not model.workface_accessible(item,true):return false
  var waiting=model.Checkout.queue(model);var rank=-1
  for i in waiting.size():
   if int(waiting[i].id)==int(guest.id):rank=i;break
  var destination=model.workface_cell(item) if rank==0 else (model.Checkout._optional_wait(model,item) if rank==1 else NONE)
  if destination==NONE or model.Checkout.claimed_cells(model,int(guest.id)).has(destination):return false
  proposed.checkout_cell=destination
  if goal=="to_checkout":
   var route=model.FurnitureMotion.route_to(model,point(guest),destination)
   if route.is_empty() and point(guest).distance_to(model.cell_center(destination))>.00001:return false
   model.FurnitureMotion.relocate(proposed,goal,route)
  elif not model.reroute_guest(proposed):return false
 else:
  # A moved chair cancels its old dismount only when the current body is free.
  var anchors=historical_items(guest,{})
  var chair=model.get_item(int(guest.chair_id));var old=anchors[int(guest.chair_id)]
  if bool(proposed.get("dismounting",false)) and (old.x!=chair.x or old.z!=chair.z):
   proposed.seated=false;proposed.dismounting=false;proposed.egress_cell=NONE;proposed.dismount_progress=0.0
  if not model.reroute_guest(proposed):return false
 proposed.elapsed=elapsed;proposed.duration=duration
 if not proposed.get("mobility",{}).is_empty():
  if model.FurnitureMotion.geometry_error(model,[proposed],model.items,model.built_walls,model.owned_parcels,model.wall_attachments)!="":return false
  if route_error(model,proposed,proposed.mobility.route,int(proposed.mobility.route_index))!="":return false
 elif proposed.phase in ["arriving","leaving","checkout_walk"] and route_error(model,proposed,proposed.route,int(proposed.route_index))!="":return false
 if body_error(model,[proposed],model.items,model.owned_parcels)!="":return false
 guest.merge(proposed,true)
 model._placement_pause_revision.erase(int(guest.id));model._mobility_validated.erase(int(guest.id))
 return true
