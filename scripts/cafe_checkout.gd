extends RefCounted
## Pure checkout authority. No wallet writes outside commit(), no renderer clocks.
const NONE = Vector2i(-100,-100)
const STAGES = ["checkout_wait","checkout_walk","paying"]
const PAYMENT_SECONDS = 1.6
const PENDING_NOTICE = "Included cashier and register waiting for space · current service continues"

static func register(m)->Dictionary:
 for item in m.items:
  if item.kind=="register":return item
 return {}
static func rear(m,item:Dictionary)->Vector2i:
 return Vector2i(int(item.x),int(item.z))*2-m.workface_cell(item)
static func point(guest:Dictionary)->Vector2:
 return Vector2(float(guest.x),float(guest.z))
static func guest_by_id(m,id:int)->Dictionary:
 for guest in m.customers:
  if int(guest.id)==id:return guest
 return {}
static func queue(m)->Array:
 var result=[]
 for guest in m.customers:
  if str(guest.get("settlement_mode","legacy"))=="register" and not guest.paid and int(guest.get("checkout_ticket",0))>0 and str(guest.phase) in STAGES:result.append(guest)
 result.sort_custom(func(a,b):return int(a.checkout_ticket)<int(b.checkout_ticket))
 return result
static func claimed_cells(m,except_id:int=-1)->Dictionary:
 var result={}
 for guest in m.customers:
  if int(guest.id)==except_id:continue
  var cell=guest.get("checkout_cell",NONE)
  if cell!=NONE and (str(guest.phase) in STAGES or (guest.phase=="leaving" and point(guest).distance_to(m.cell_center(cell))<.8)):
   result[cell]=int(guest.id)
 return result
static func busy(m,id:int)->bool:
 for guest in m.customers:
  if int(guest.get("checkout_register_id",-1))!=id:continue
  if guest.phase=="paying" or (int(guest.get("checkout_token",-1))>0 and not guest.paid) or claimed_cells(m).values().has(int(guest.id)):return true
 return false
static func is_door_landing(m,cell:Vector2i)->bool:
 if cell in [m.ENTRANCE,m.ENTRY_LANDING]:return true
 for attachment in m.wall_attachments:
  if attachment.kind!="door":continue
  var opening=m.OpeningGeometry.aperture(attachment,m.built_walls,m.shell_material)
  if not opening.is_empty() and Geometry2D.get_closest_point_to_segment(m.cell_center(cell),opening.a,opening.b).distance_to(m.cell_center(cell))<.76:return true
 return false
static func path(m,start:Vector2i,finish:Vector2i,blocked:Dictionary={},layout:Array=[])->Array[Vector2i]:
 var empty:Array[Vector2i]=[]
 var furniture=m.items if layout.is_empty() else layout
 var solids={}
 for item in furniture:
  if item.kind!="rug":solids[Vector2i(int(item.x),int(item.z))]=true
 if not m.is_floor_owned(start) or not m.is_floor_owned(finish) or solids.has(start) or solids.has(finish) or blocked.has(finish):return empty
 var previous={start:start};var cells:Array[Vector2i]=[start];var cursor=0
 while cursor<cells.size():
  var cell=cells[cursor];cursor+=1
  if cell==finish:
   var route:Array[Vector2i]=[finish]
   while route[-1]!=start:route.append(previous[route[-1]])
   route.reverse();return route
  for direction in m.DIRECTIONS:
   var next:Vector2i=cell+direction
   if previous.has(next) or solids.has(next) or blocked.has(next) or not m.is_floor_owned(next) or m.edge_blocked(cell,next):continue
   previous[next]=cell;cells.append(next)
 return empty
static func placement_error(m,item:Dictionary,layout:Array,actors:Array)->String:
 actors=actors.duplicate();actors.append_array(m.checkout_staff_claims)
 for guest in m.customers:
  if guest.phase not in ["dirty","cleaning"]:actors.append(point(guest))
 var front=m.workface_cell(item);var back=rear(m,item)
 if is_door_landing(m,front) or is_door_landing(m,back):return "Keep the register away from door landings"
 for face in [front,back]:
  if face.x<1 or not m.is_floor_owned(face) or m.edge_blocked(Vector2i(int(item.x),int(item.z)),face):return "Clear the register's customer and staff sides"
  for other in layout:
   if str(other.kind)!="rug" and Vector2i(int(other.x),int(other.z))==face:return "Clear the register's customer and staff sides"
  for actor in actors:
   if m.cell_center(face).distance_to(actor)<.9:return "Register deployment is waiting for a clear workface"
  if m._guest_route_uses(face):return "Register deployment is waiting for an active guest route"
 for other in m.items:
  if int(other.id)==int(item.id) or other.kind not in ["stove","beverage","sink","counter","bin"]:continue
  if other.kind=="bin":
   # The bin only needs one free reachable side; do not reserve four faces
   # forever or treat its saved rotation as an operational front.
   var before=false;var after=false
   for cell in m.bin_service_cells(other):
    if not path(m,m.ENTRY_LANDING,cell).is_empty():before=true
   for cell in m.bin_service_cells(other,layout):
    if cell not in [front,back] and not path(m,m.ENTRY_LANDING,cell,{},layout).is_empty():after=true
   if before and not after:return "Keep an adjacent bin side reachable"
   continue
  var workfaces=[m.workface_cell(other)]
  if other.kind=="counter":workfaces.append(rear(m,other))
  for face in workfaces:
   if face in [front,back]:return "Keep the register clear of existing staff work tiles"
   if not path(m,m.ENTRY_LANDING,face).is_empty() and path(m,m.ENTRY_LANDING,face,{},layout).is_empty():return "Keep existing staff work tiles reachable"
 if path(m,m.ENTRY_LANDING,front,{},layout).is_empty() or path(m,m.ENTRY_LANDING,back,{front:true},layout).is_empty():return "Keep a bypass to the register's staff side"
 for actor in actors:
  if m.cell_center(Vector2i(int(item.x),int(item.z))).distance_to(actor)<.9:return "Register deployment is waiting for a clear tile"
 return ""
static func ensure(m,actors:Array=[])->bool:
 if not m.included_checkout_pending:return not register(m).is_empty() and m.cashiers==1
 if not register(m).is_empty():return m._fail("Included register entitlement is inconsistent")
 var candidates:Array[Vector2i]=[Vector2i(6,4),Vector2i(8,4),Vector2i(5,1)]
 for z in range(1,m.depth-1):
  for x in range(2,m.width-1):
   var cell=Vector2i(x,z)
   if not candidates.has(cell):candidates.append(cell)
 for cell in candidates:
  for rotation in range(4):
   if not m.can_place("register",cell.x,cell.y,-1,rotation):continue
   var item={"id":m._next_item_id,"kind":"register","x":cell.x,"z":cell.y,"rot":rotation}
   var layout=m.items.duplicate(true);layout.append(item)
   if placement_error(m,item,layout,actors)!="":continue
   adopt(m,item);return true
 m.last_error=PENDING_NOTICE
 return false
static func adopt(m,item:Dictionary):
 m.items.append(item);m._next_item_id+=1;m.included_checkout_pending=false;m.cashiers=1
 m.duty_targets["cashier"]=1;m.duty_counts["cashier"]=1
 m.last_error="";m.last_event="Included cashier and register ready · existing progress preserved";m._notify()
static func init_guest(m,guest:Dictionary):
 guest.settlement_mode="legacy" if m.included_checkout_pending else "register"
 guest.checkout_ticket=0;guest.checkout_register_id=-1;guest.checkout_cell=NONE
 guest.checkout_token=-1;guest.checkout_reason="";guest.checkout_stall=0.0
static func finish_meal(m,guest:Dictionary):
 guest.phase="checkout_wait";guest.elapsed=0.0;guest.duration=0.0;guest.waiting=true
 guest.checkout_ticket=m.next_checkout_ticket;m.next_checkout_ticket+=1
 guest.checkout_reason="Waiting for a safe place at the register"
 guest.route=[];guest.route_index=0
static func _clear_body(m,cell:Vector2i,id:int)->bool:
 # A queue destination has one owner, but passing bodies/routes do not own it.
 return not claimed_cells(m,id).has(cell)
static func _optional_wait(m,item:Dictionary)->Vector2i:
 var front=m.workface_cell(item);var direction=front-Vector2i(int(item.x),int(item.z))
 for side in [Vector2i(-direction.y,direction.x),Vector2i(direction.y,-direction.x)]:
  var cell:Vector2i=front+side
  if is_door_landing(m,cell) or not m._walkable(cell) or m.edge_blocked(front,cell):continue
  if path(m,m.ENTRY_LANDING,rear(m,item)).is_empty():continue
  if path(m,front,m.ENTRY_LANDING).is_empty():continue
  return cell
 return NONE
static func _route_to(m,guest:Dictionary,destination:Vector2i)->bool:
 var start=Vector2i(floori(float(guest.x)),floori(float(guest.z)))
 var route:Array[Vector2]=[];var landing=NONE;var best=INF
 if bool(guest.get("dismounting",false)):
  landing=guest.egress_cell
  var cells=path(m,landing,destination)
  if cells.is_empty():return false
  for cell in cells:route.append(m.cell_center(cell))
 elif bool(guest.seated):
  for candidate in m.chair_egress_cells(int(guest.chair_id),int(guest.table_id)):
   var cells=path(m,candidate,destination)
   if cells.is_empty():continue
   if cells.size()<best:
    best=cells.size();landing=candidate;route.clear()
    for cell in cells:route.append(m.cell_center(cell))
  if route.is_empty():return false
 else:
  var cells=path(m,start,destination)
  if cells.is_empty():return false
  for cell in cells:route.append(m.cell_center(cell))
  # Anchor a mid-edge position before turning; never make a diagonal shortcut.
  if not route.is_empty() and absf(point(guest).x-route[0].x)>.001 and absf(point(guest).y-route[0].y)>.001:return false
 guest.phase="checkout_walk";guest.checkout_cell=destination;guest.route=route;guest.route_index=0
 guest.duration=m._route_length(point(guest),route)/m.WALK_SPEED;guest.elapsed=0.0;guest.departure_blocked=false
 if landing!=NONE:
  guest.egress_cell=landing;guest.dismounting=true
  if not guest.has("dismount_progress"):guest.dismount_progress=0.0
 guest.checkout_reason="";return true
static func advance(m,delta:float):
 for guest in m.customers:
  if guest.phase=="leaving" and guest.paid and str(guest.get("settlement_mode","legacy"))=="register" and guest.departure_blocked:depart(m,guest)
  if guest.phase=="leaving" and guest.get("checkout_cell",NONE)!=NONE and point(guest).distance_to(m.cell_center(guest.checkout_cell))>=.8:guest.checkout_cell=NONE
 var waiting=queue(m)
 if waiting.is_empty():return
 var item=register(m)
 if item.is_empty():
  for guest in waiting:guest.checkout_reason="Add the included register in Decorate"
  return
 var front=m.workface_cell(item);var back=rear(m,item);var slot=_optional_wait(m,item)
 for rank in range(waiting.size()):
  var guest:Dictionary=waiting[rank]
  guest.checkout_register_id=int(item.id)
  if not guest.get("mobility",{}).is_empty() or guest.phase in ["paying","checkout_walk"]:continue
  var destination=front if rank==0 else (slot if rank==1 else NONE)
  if destination==NONE:
   guest.checkout_reason="Waiting seated for the register";continue
  if not bool(guest.seated) and guest.checkout_cell==destination and point(guest).distance_to(m.cell_center(destination))<.01:
   guest.heading=(m.cell_center(Vector2i(int(item.x),int(item.z)))-point(guest)).normalized()
   guest.checkout_reason="Waiting for the cashier" if rank==0 else "Waiting in line"
   continue
  if not m._walkable(front) or m.edge_blocked(front,Vector2i(int(item.x),int(item.z))):guest.checkout_reason="Register front blocked";continue
  if not m._walkable(back) or m.edge_blocked(back,Vector2i(int(item.x),int(item.z))):guest.checkout_reason="Clear the register's staff side";continue
  if not _clear_body(m,destination,int(guest.id)):guest.checkout_reason="Register front blocked" if rank==0 else "Waiting for queue space";continue
  # Destination claims are exclusive, but they are never transit obstacles.
  if path(m,m.ENTRY_LANDING,back).is_empty():guest.checkout_reason="Clear the register's staff side";continue
  if path(m,destination,m.ENTRY_LANDING).is_empty():guest.checkout_reason="Register exit blocked";continue
  if not _route_to(m,guest,destination):
   guest.checkout_reason="Waiting for a clear chair exit";guest.checkout_stall=minf(3600.0,float(guest.checkout_stall)+delta)
static func arrived(m,guest:Dictionary):
 if m._walking_customer_id==int(guest.id):m._walking_customer_id=-1
 guest.phase="checkout_wait";guest.seated=false;guest.dismounting=false;guest.waiting=true
 guest.elapsed=0.0;guest.duration=0.0;guest.checkout_reason="Waiting for the cashier"
 var item=register(m)
 if not item.is_empty():guest.heading=(m.cell_center(Vector2i(int(item.x),int(item.z)))-point(guest)).normalized()
static func ready(m,guest:Dictionary,register_id:int)->bool:
 if not guest.get("mobility",{}).is_empty():return false
 var item=m.get_item(register_id)
 if item.is_empty() or item.kind!="register" or guest.is_empty() or guest.paid or bool(guest.get("meal_abandoned",false)) or str(guest.get("settlement_mode","legacy"))!="register":return false
 var waiting=queue(m)
 if waiting.is_empty() or int(waiting[0].id)!=int(guest.id) or str(guest.phase) not in ["checkout_wait","paying"] or guest.seated:return false
 var face=m.workface_cell(item)
 return guest.checkout_cell==face and point(guest).distance_to(m.cell_center(face))<.01 and m.workface_accessible(item) and m.workface_accessible(item,true)
static func begin(m,id:int,ticket:int,register_id:int,token:int)->bool:
 var guest=guest_by_id(m,id)
 if guest.is_empty() or int(guest.checkout_ticket)!=ticket or token<1 or not ready(m,guest,register_id):return false
 if int(guest.get("checkout_token",-1)) not in [-1,token]:return false
 guest.checkout_token=token;guest.phase="paying";guest.checkout_reason="";return true
static func depart(m,guest:Dictionary)->bool:
 var position=point(guest);var start=Vector2i(floori(position.x),floori(position.y))
 var best={};var route:Array[Vector2]=[];var length=INF
 for entry in m.boundary_entries():
  var cells=path(m,start,entry.cell)
  if cells.is_empty():continue
  var candidate:Array[Vector2]=[]
  for cell in cells:candidate.append(m.cell_center(cell))
  candidate.append_array(m._exterior_approach(entry,false,m._departure_exit_z(int(guest.id))))
  var distance=m._route_length(position,candidate)
  if distance<length:length=distance;route=candidate;best=entry
 guest.phase="leaving";guest.seated=false;guest.dismounting=false;guest.elapsed=0.0;guest.route_index=0
 guest.exterior_exit=false;guest.waiting=true;guest.departure_blocked=route.is_empty();guest.route=route
 guest.duration=0.0 if route.is_empty() else length/m.WALK_SPEED
 if best.is_empty():guest.checkout_reason="Register exit blocked";return false
 guest.entry_cell=best.cell;guest.entry_direction=best.direction;guest.entry_outside=best.outside;guest.checkout_reason="";return true
static func commit(m,id:int,ticket:int,register_id:int,token:int)->bool:
 var guest=guest_by_id(m,id)
 if guest.is_empty() or guest.phase!="paying" or int(guest.get("checkout_token",-1))!=token or int(guest.checkout_ticket)!=ticket or not ready(m,guest,register_id):return false
 # All authoritative fields commit before any observer sees the money event.
 guest.paid=true;m.coins+=m.MEAL_PAYMENT;m.total_earned+=m.MEAL_PAYMENT;m.served+=1
 depart(m,guest)
 m.last_event="Payment received · +%s coins"%m.Money.amount(m.MEAL_PAYMENT)
 m.meal_completed.emit(id,m.MEAL_PAYMENT)
 return true
static func layout_error(m,layout:Array,walls:Array,ownership:Array,guests:Array,openings=null)->String:
 var by_id={}
 for item in layout:by_id[int(item.id)]=item
 var reachable=m._wall_reachable(walls,layout,ownership,openings)
 for guest in guests:
  if str(guest.phase) in STAGES and not m._floor_owned_in(Vector2i(floori(float(guest.x)),floori(float(guest.z))),ownership):return "Unpaid checkout guest is outside owned floor"
  var cell=guest.get("checkout_cell",NONE)
  if cell==NONE:continue
  var item=by_id.get(int(guest.get("checkout_register_id",-1)),{})
  if item.is_empty():return "A checkout reservation has no register"
  var center=Vector2i(int(item.x),int(item.z));var front=m.workface_cell(item);var back=rear(m,item)
  for face in [cell,front,back]:
   if not m._floor_owned_in(face,ownership) or not reachable.has(face):return "Keep active register and queue cells clear and reachable"
  for face in [front,back]:
   if m._fixed_edge_blocked(center,face,openings,walls) or m._built_edge_blocked(center,face,walls,openings):return "A guest is checking out · keep both register faces clear"
  if cell!=front and (m._fixed_edge_blocked(cell,front,openings,walls) or m._built_edge_blocked(cell,front,walls,openings)):return "A guest is queued · keep the path to the register clear"
 return ""
static func state_error(pending:bool,cashiers:int,layout:Array,guests:Array,targets:Dictionary,duties:Dictionary)->String:
 var registers=0
 for item in layout:
  if item.kind=="register":registers+=1
 if cashiers not in [0,1] or pending!=(cashiers==0) or registers!=cashiers:return "Cashier/register deployment disagrees with entitlement"
 if int(targets.get("cashier",-1))!=cashiers or int(duties.get("cashier",-1))!=cashiers:return "Cashier duty disagrees with deployment"
 if pending:
  for guest in guests:
   if str(guest.get("settlement_mode","legacy"))=="register":return "Register-mode guest exists before cashier deployment"
 return ""
static func staff_floor_error(m,service:Dictionary,ownership:Array,layout:Array)->String:
 for staff in service.get("staff",[]):
  if staff.role!="cashier":continue
  var cell=Vector2i(floori(staff.pos.x),floori(staff.pos.y))
  if not m._floor_owned_in(cell,ownership):return "Cashier is outside owned floor"
  for item in layout:
   if item.kind!="rug" and Vector2i(int(item.x),int(item.z))==cell:return "Cashier is inside solid furniture"
 return ""
