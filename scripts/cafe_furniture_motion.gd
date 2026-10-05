extends RefCounted
## Native candidate: a furniture move preserves identities and active work.
## Plan against an isolated model, then publish one complete layout/route change.
const NONE=Vector2i(-100,-100)
const SEAT_PHASES=["ordering","cooking","drinking","eating"]
static func active(guest:Dictionary)->bool:return not guest.get("mobility",{}).is_empty()
static func copy_model(model):
 var shadow=model.get_script().new()
 # Geometry planning never needs payroll, renderer caches or service ledgers.
 # Their original objects remain untouched by the transaction.
 for key in ["catalog","items","customers","dining_sets","built_walls","wall_attachments","shell_material","shell_products","shell_segment_products","owned_parcels","expanded","width","depth","coins","cooks","waiters","cleaners","cashiers","included_checkout_pending","included_bin_pending","revision","_next_item_id","_next_customer_id","next_checkout_ticket","operating_open"]:
  var value=model.get(key)
  shadow.set(key,value.duplicate(true) if value is Array or value is Dictionary else value)
 return shadow
static func fail(reason:String)->Dictionary:return {"ok":false,"error":reason}
static func point(guest:Dictionary)->Vector2:return Vector2(float(guest.x),float(guest.z))
static func cell(point_value:Vector2)->Vector2i:return Vector2i(floori(point_value.x),floori(point_value.y))
static func route_to(model,position:Vector2,destination:Vector2i)->Array[Vector2]:
 var result:Array[Vector2]=[]
 var cells=model.Checkout.path(model,cell(position),destination)
 if cells.is_empty():return result
 for step in cells:
  var next=model.cell_center(step)
  if result.is_empty() and position.distance_to(next)<.00001:continue
  result.append(next)
 if not result.is_empty() and absf(position.x-result[0].x)>.00001 and absf(position.y-result[0].y)>.00001:return []
 return result
static func seat_route(model,guest:Dictionary,reachable=null)->Array[Vector2]:
 var chair=model.get_item(int(guest.chair_id));var target=model.cell_center(Vector2i(int(chair.x),int(chair.z)))
 var best:Array[Vector2]=[];var length=INF;var position=point(guest)
 if position.distance_to(target)<.00001:return [target]
 if cell(position)==cell(target) and active(guest) and str(guest.mobility.kind)=="to_assigned_seat" and int(guest.mobility.route_index)==guest.mobility.route.size()-1 and guest.mobility.route[-1].distance_to(target)<.00001:
  return [target]
 var exits=model.chair_egress_cells(int(guest.chair_id),int(guest.table_id)) if reachable==null else model._chair_egress_cells_in(cell(target),model._chair_table_direction(int(guest.chair_id),int(guest.table_id)),model.built_walls,reachable)
 for approach in exits:
  var route=route_to(model,position,approach)
  if route.is_empty() and position.distance_to(model.cell_center(approach))>.00001:continue
  route.append(target)
  var candidate_length=model._route_length(position,route)
  if candidate_length<length:length=candidate_length;best=route
 return best
static func relocate(guest:Dictionary,kind:String,route:Array[Vector2])->void:
 while not route.is_empty() and point(guest).distance_to(route[0])<.00001:route.pop_front()
 if route.is_empty():
  guest.mobility={};guest.seated=kind=="to_assigned_seat";return
 guest.mobility={"kind":kind,"origin":point(guest),"route":route,"route_index":0}
 guest.seated=false;guest.dismounting=false;guest.egress_cell=NONE;guest.dismount_progress=0.0
 guest.route=[];guest.route_index=0;guest.departure_blocked=false;guest.waiting=false
static func plan(model,id:int,x:int,z:int,rot:int,actors:Array=[])->Dictionary:
 id=model.logical_item_id(id)
 var item=model.get_item(id)
 if item.is_empty():return fail("Select a furnishing first")
 if int(item.x)==x and int(item.z)==z and model.logical_rotation(id)==posmod(rot,4):return {"ok":true,"noop":true}
 var members=model.logical_members(id)
 var shadow=copy_model(model)
 var guests=shadow.customers
 # Existing people and future walking routes are rerouted below; they are not
 # locks on furniture ownership. Static shape/worker escape guards still apply.
 var no_guests:Array[Dictionary]=[]
 shadow.customers=no_guests;shadow.wall_actor_positions.clear();shadow.checkout_staff_claims.clear()
 if not shadow._move_static(id,x,z,rot,actors):return {"ok":false,"error":str(shadow.last_error),"issue":shadow.last_placement_issue.duplicate(true)}
 shadow.customers=guests
 var guest_reachable=shadow._wall_reachable(shadow.built_walls,shadow.items,shadow.owned_parcels)
 var register_moved=str(item.kind)=="register"
 var old_register_front=model.workface_cell(item)
 var old_direction=old_register_front-Vector2i(int(item.x),int(item.z))
 var old_side=Vector2i(-old_direction.y,old_direction.x)
 var new_item=shadow.get_item(id)
 var new_front=shadow.workface_cell(new_item)
 var new_direction=new_front-Vector2i(int(new_item.x),int(new_item.z))
 var new_side=Vector2i(-new_direction.y,new_direction.x)
 for guest in shadow.customers:
  if not guest.has("mobility"):guest.mobility={}
  var phase=str(guest.phase)
  var own_seat_moved=int(guest.table_id) in members or int(guest.chair_id) in members
  if register_moved and int(guest.get("checkout_register_id",-1))==id and guest.get("checkout_cell",NONE)!=NONE:
   if phase=="leaving":guest.checkout_cell=NONE
   elif phase in ["checkout_wait","checkout_walk","paying"]:
    var offset:Vector2i=guest.checkout_cell-old_register_front
    var side_rank=offset.x*old_side.x+offset.y*old_side.y
    guest.checkout_cell=new_front+new_side*side_rank
    if not shadow._walkable(guest.checkout_cell):return fail("Keep the relocated checkout positions clear")
    if phase in ["checkout_wait","paying"]:
     var checkout_route=route_to(shadow,point(guest),guest.checkout_cell)
     if checkout_route.is_empty() and point(guest).distance_to(shadow.cell_center(guest.checkout_cell))>.00001:return fail("Keep a walking route to the moved register")
     relocate(guest,"to_checkout",checkout_route)
  var seating=phase in SEAT_PHASES or (phase=="checkout_wait" and guest.get("checkout_cell",NONE)==NONE)
  if (own_seat_moved and seating) or (active(guest) and str(guest.mobility.kind)=="to_assigned_seat"):
   var route=seat_route(shadow,guest,guest_reachable)
   if route.is_empty():return fail("Keep a walking route to the moved chair")
   guest.service_cell=cell(route[-2]) if route.size()>1 else cell(point(guest))
   relocate(guest,"to_assigned_seat",route)
  elif active(guest) and str(guest.mobility.kind)=="to_checkout":
   var route=route_to(shadow,point(guest),guest.checkout_cell)
   if route.is_empty() and point(guest).distance_to(shadow.cell_center(guest.checkout_cell))>.00001:return fail("Keep a walking route to the register")
   relocate(guest,"to_checkout",route)
  elif phase in ["arriving","leaving","checkout_walk"] and not bool(guest.get("withdrawn",false)):
   # A moved chair no longer anchors the old departure leg. Its current body
   # position stays fixed; continue from that floor point toward the same goal.
   if own_seat_moved and bool(guest.get("dismounting",false)):
    guest.seated=false;guest.dismounting=false;guest.egress_cell=NONE;guest.dismount_progress=0.0
   var final_arrival=phase=="arriving" and not own_seat_moved and int(guest.route_index)==guest.route.size()-1 and not guest.route.is_empty() and cell(point(guest))==cell(guest.route[-1])
   if final_arrival:
    var check_guest=guest.duplicate(true)
    check_guest.mobility={"kind":"to_assigned_seat","origin":point(guest),"route":[guest.route[-1]],"route_index":0}
    if geometry_error(shadow,[check_guest],shadow.items,shadow.built_walls,shadow.owned_parcels,shadow.wall_attachments)!="":return fail("Keep the final chair approach clear")
   elif not shadow.reroute_guest(guest):return fail("Keep each guest's walking route connected")
 for guest in shadow.customers:
  if bool(guest.get("seated",false)) and not bool(guest.get("dismounting",false)):
   var chair=shadow.get_item(int(guest.chair_id))
   var exits=shadow._chair_egress_cells_in(Vector2i(int(chair.x),int(chair.z)),shadow._chair_table_direction(int(guest.chair_id),int(guest.table_id)),shadow.built_walls,guest_reachable)
   if not exits.is_empty() and guest.get("service_cell") not in exits:guest.service_cell=exits[0]
 var geometry_error=geometry_error(shadow,shadow.customers,shadow.items,shadow.built_walls,shadow.owned_parcels,shadow.wall_attachments)
 if geometry_error!="":return fail(geometry_error)
 var checkout_error=shadow.Checkout.layout_error(shadow,shadow.items,shadow.built_walls,shadow.owned_parcels,shadow.customers)
 if checkout_error!="":return fail(checkout_error)
 return {"ok":true,"noop":false,"items":shadow.items,"groups":shadow.dining_sets,"guests":shadow.customers}
static func commit(model,transaction:Dictionary)->bool:
 if not bool(transaction.get("ok",false)):
  model.last_placement_issue=transaction.get("issue",{}).duplicate(true)
  return model._fail(str(transaction.get("error","Invalid furniture move")))
 if bool(transaction.get("noop",false)):return true
 # Keep dictionaries already referenced by service records alive. IDs, money,
 # purchase metadata and physical floor messes are never recreated or reset.
 for proposed in transaction.items:
  var original=model.get_item(int(proposed.id))
  for key in ["x","z","rot"]:original[key]=proposed[key]
 model.dining_sets.assign(transaction.groups)
 for proposed in transaction.guests:
  for original in model.customers:
   if int(original.id)==int(proposed.id):original.merge(proposed,true);break
 model.last_error="";model.last_event="Moved furniture · guests and staff keep their work";model._notify();return true
static func advance(model,guest:Dictionary,delta:float)->void:
 if not active(guest):return
 var invalid="" if model._mobility_validated.get(int(guest.id),-1)==model.revision else geometry_error(model,[guest],model.items,model.built_walls,model.owned_parcels,model.wall_attachments)
 if invalid!="":
  var kind=str(guest.mobility.kind)
  var replacement=seat_route(model,guest) if kind=="to_assigned_seat" else route_to(model,point(guest),guest.checkout_cell)
  if replacement.is_empty():guest.waiting=true;return
  relocate(guest,kind,replacement)
  if not active(guest):return
  if geometry_error(model,[guest],model.items,model.built_walls,model.owned_parcels,model.wall_attachments)!="":guest.waiting=true;return
 model._mobility_validated[int(guest.id)]=model.revision
 var mobility:Dictionary=guest.mobility
 var budget=maxf(0.0,delta)*model.WALK_SPEED
 var position=point(guest)
 while budget>.0000001 and int(mobility.route_index)<mobility.route.size():
  var target:Vector2=mobility.route[int(mobility.route_index)]
  var distance=position.distance_to(target)
  if distance<.0000001:mobility.route_index=int(mobility.route_index)+1;continue
  guest.heading=(target-position)/distance
  var step=minf(distance,budget);position+=guest.heading*step;budget-=step
  if step+.0000001>=distance:position=target;mobility.route_index=int(mobility.route_index)+1
 guest.x=position.x;guest.z=position.y
 if int(mobility.route_index)>=mobility.route.size():
  guest.seated=str(mobility.kind)=="to_assigned_seat";guest.mobility={};guest.waiting=guest.phase=="checkout_wait"
  model._mobility_validated.erase(int(guest.id))
static func geometry_error(model,guests:Array,layout:Array,walls:Array,ownership:Array,openings:Array)->String:
 var by_id={};var solids={}
 for item in layout:
  by_id[int(item.id)]=item
  if str(item.kind)!="rug":solids[Vector2i(int(item.x),int(item.z))]=int(item.id)
 for guest in guests:
  if not active(guest):continue
  var mobility:Dictionary=guest.mobility;var route:Array=mobility.get("route",[])
  if route.is_empty():return "Relocating guest has no walking route"
  var target_id=int(guest.chair_id) if str(mobility.kind)=="to_assigned_seat" else -1
  if target_id>=0 and not by_id.has(target_id):return "Relocating guest lost its chair"
  var chair_cell=Vector2i(int(by_id[target_id].x),int(by_id[target_id].z)) if target_id>=0 else NONE
  var previous=point(guest)
  for index in range(int(mobility.route_index),route.size()):
   var next:Vector2=route[index]
   if absf(previous.x-next.x)>.00001 and absf(previous.y-next.y)>.00001:return "Relocation route must use straight walking lanes"
   var steps=maxi(1,ceili(previous.distance_to(next)*8.0));var prior_cell=cell(previous)
   for sample in range(steps+1):
    var at=previous.lerp(next,float(sample)/steps);var here=cell(at)
    if not model._floor_owned_in(here,ownership):return "Relocation route leaves the owned floor"
    var final_seat=index==route.size()-1 and here==chair_cell and solids.get(here,-1)==target_id
    if solids.has(here) and not final_seat:return "Relocation route is blocked by furniture"
    if here!=prior_cell:
     if absi(here.x-prior_cell.x)+absi(here.y-prior_cell.y)!=1:return "Relocation route skips a walking tile"
     if model._fixed_edge_blocked(prior_cell,here,openings,walls) or model._built_edge_blocked(prior_cell,here,walls,openings):return "Relocation route crosses a wall"
    prior_cell=here
   previous=next
 return ""
