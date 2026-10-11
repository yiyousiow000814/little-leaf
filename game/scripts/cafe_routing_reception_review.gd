extends RefCounted
## Version19 route validation and prepared publication fields. No profile discovery.
const FloorGeometry=preload("res://scripts/cafe_floor_geometry.gd")
class GeometryContext extends RefCounted:
 var model
 func _init(value):model=value
 func _staff_walkable(cell:Vector2i)->bool:
  return cell.x>=1 and model.is_floor_owned(cell) and model._walkable(cell)
const Nav=preload("res://scripts/cafe_navigation_candidate.gd")
const LOADED_FIELDS=["items","dining_sets","built_walls","wall_attachments","_next_wall_id","_next_attachment_id","floor_finishes","floor_style","shell_material","shell_products","shell_segment_products","coins","owned_parcels","cooks","waiters","cleaners","cashiers","included_checkout_pending","next_checkout_ticket","duty_targets","duty_counts","payroll_elapsed","payroll_accrued","wages_due","total_wages_paid","served","total_earned","total_cleaned","_next_item_id","customers","outside_queue","reception_visits","departing_bodies","parking_owned","parking_paid_cost","parking_visits","service_snapshot","operating_open","included_bin_pending","tutorial_state","first_guest_pending","first_guest_start","loaded_save_version","_reception_fresh_eligible","_next_customer_id","_arrival_elapsed","_walking_customer_id"]

static func geometry_error(m,state:Dictionary)->String:
 # The reception validator owns visitor/departure provenance and custody.
 # Validate actual and remaining guest motion using the same reviewed planner
 # geometry, never granting a diagonal chair/contact exception.
 for guest in state.customers:
  if str(guest.phase) in ["dirty","cleaning"]:continue
  var at=Vector2(guest.x,guest.z)
  if guest.heading.length()>1.001:return "Guest heading is not a unit direction"
  if bool(guest.seated) and not bool(guest.dismounting):
   var seat=m.get_item(int(guest.chair_id))
   if seat.is_empty() or at.distance_to(m.cell_center(Vector2i(int(seat.x),int(seat.z))))>.000001:return "Seated guest body lost its owned chair"
  var mobility:Dictionary=guest.mobility
  var route:Array=mobility.route if not mobility.is_empty() else guest.route
  var index=int(mobility.route_index) if not mobility.is_empty() else int(guest.route_index)
  var chair=int(guest.chair_id) if str(guest.phase) not in ["checkout_walk","paying","leaving"] or str(mobility.get("kind",""))=="to_assigned_seat" else -1
  if not route.is_empty() and index==route.size() and at.distance_to(route[-1])>.000001:return "Guest exhausted route lost its final body position"
  var cell=Vector2i(at.floor())
  if not m.is_floor_owned(cell) and str(guest.phase)!="leaving" and not m.Reception._public(m,at):return "Guest body is outside its owned/public movement domain"
  if m.is_floor_owned(cell):
   var body_facts=m.GuestNavigation._contact_snapshot(m,[int(guest.chair_id)])
   if not Nav.sweep_clear(body_facts,at,at):return "Guest body overlaps blocked geometry"
  if not route.is_empty() and index<route.size():
   if not mobility.is_empty():
    var start:Vector2=mobility.origin if index==0 else route[index-1]
    if Geometry2D.get_closest_point_to_segment(at,start,route[index]).distance_to(at)>.000001:return "Guest body is off its active route"
   elif index>0 and Geometry2D.get_closest_point_to_segment(at,route[index-1],route[index]).distance_to(at)>.000001:return "Guest body is off its active route"
   for i in range(index,route.size()):
    if not m.GuestNavigation.leg_clear(m,at,route[i],int(guest.chair_id),chair):return "Guest route crosses blocked geometry"
    # Ordinary admitted guests retain all existing exterior lanes, including
    # the selected south/right exit. Reception's west-corridor-only validator
    # owns waiting visitors, not these already admitted guest routes.
    var count=maxi(1,ceili(at.distance_to(route[i])*8))
    for sample in range(count+1):
     var here=Vector2i(at.lerp(route[i],float(sample)/count).floor())
     if m.is_floor_owned(here) and not m._walkable(here):
      var seat=m.get_item(int(guest.chair_id))
      if seat.is_empty() or here!=Vector2i(int(seat.x),int(seat.z)) or (i!=index and i!=route.size()-1):return "Guest route crosses furniture"
    at=route[i]
  if str(guest.phase)=="arriving" and (route.is_empty() or route[-1].distance_to(m.cell_center(Vector2i(m.get_item(int(guest.chair_id)).x,m.get_item(int(guest.chair_id)).z)))>.000001):return "Guest route misses assigned seat"
 var facts=Nav.from_model(m,1)
 var claims={};var jobs={}
 for staff in state.service.get("staff",[]):
  if staff.job_kind not in ["","floor","wash"]:
   var key=Vector2i(int(staff.job_guest_id),int(staff.job_token))
   if jobs.has(key):return "Two staff own one guest service token"
   jobs[key]=true
  var route:Array=staff.path;var index=int(staff.index)
  if not Nav.open_cell(facts,Vector2i(staff.pos.floor())) or not Nav.sweep_clear(facts,staff.pos,staff.pos):return "Staff body overlaps blocked geometry"
  if staff.has("navigation_phase"):
   # Consumed route history may cross subsequently edited furniture. Only the
   # actual current leg and remaining route is restored as live authority.
   if index<route.size():
    if not Nav.can_step(facts,route[index-1],route[index]) or not Nav.sweep_clear(facts,staff.pos,Nav.center(route[index])):return "Staff current leg crosses blocked geometry"
   for i in range(index+1,route.size()):
    if not Nav.can_step(facts,route[i-1],route[i]):return "Staff route crosses blocked geometry"
  else:
   var at:Vector2=staff.pos
   for i in range(index,route.size()):
    var next=Nav.center(route[i])
    if absf(at.x-next.x)>.000001 and absf(at.y-next.y)>.000001:return "Unmarked staff route is not cardinal"
    if not Nav.sweep_clear(facts,at,next):return "Staff route crosses blocked geometry"
    at=next
  if staff.job_kind!="" and staff.destination!=Vector2i(-100,-100):
   if not Nav.open_cell(facts,staff.destination) or not Nav.sweep_clear(facts,Nav.center(staff.destination),Nav.center(staff.destination)):return "Staff endpoint is blocked or unowned"
   var endpoint=endpoint_error(m,state,staff)
   if endpoint!="":return endpoint
   if claims.has(staff.destination):return "Two staff own one work endpoint"
   claims[staff.destination]=true
 return ""

static func endpoint_error(m,state:Dictionary,staff:Dictionary)->String:
 # Resolve the current service step from its authoritative record. A retained
 # stove ID is provenance, not the chef's later pass-counter destination.
 var kind=str(staff.job_kind);var step=int(staff.job_step)
 var rows=state.service.get("records",[]).filter(func(r):return int(r.guest_id)==int(staff.job_guest_id))
 var record:Dictionary=rows[0] if rows.size()==1 else {}
 var guests=state.customers.filter(func(g):return int(g.id)==int(staff.job_guest_id))
 var guest:Dictionary=guests[0] if guests.size()==1 else {}
 if kind=="cleanup" and step==5 or kind=="floor" and step==2:return "" # Existing local floor disposal.
 if kind=="floor" or kind=="cleanup" and step in [3,4,6]:
  if kind=="floor":
   var messes=state.service.get("floor_tasks",{}).get("messes",[]).filter(func(r):return int(r.id)==int(staff.job_mess_id))
   if messes.size()!=1:return "Floor endpoint lost its mess"
   record=messes[0]
  var action="mopping" if (kind=="floor" and step==3) or (kind=="cleanup" and step==6) else "sweeping"
  var geometry=FloorGeometry.new(GeometryContext.new(m))
  if record.is_empty() or staff.destination!=record.get("floor_work_cell",Vector2i(-1,-1)) or not geometry.work_cells(record.duplicate(true),action).has(staff.destination):return "Floor endpoint lost its saved work approach"
  return ""
 var table_job=kind=="order" or kind in ["deliver_meal","deliver_drink"] and step==1 or kind=="brew" and step==2 or kind=="cleanup" and step in [0,2]
 if table_job:
  if guest.is_empty() or not m.table_service_cells(m.get_item(int(guest.table_id))).has(staff.destination):return "Staff endpoint is not its guest table face"
  if int(staff.get("table_face_id",-1))!=-1 and (int(staff.table_face_id)!=int(guest.table_id) or staff.table_face_cell!=staff.destination):return "Staff endpoint lost its reserved table face"
  return ""
 var id=int(staff.station_id);var expected=""
 match kind:
  "cook":
   expected="counter" if step==3 else "stove"
   id=int(record.get("meal_pass_id",-1)) if step==3 else int(record.get("meal_station_id",-1))
  "brew","deliver_drink":expected="beverage";id=int(record.get("drink_station_id",-1))
  "deliver_meal":expected="counter";id=int(record.get("meal_pass_id",-1))
  "cleanup":expected="sink";id=int(record.get("dish_sink_id",-1))
  "take_payment":expected="register";id=int(guest.get("checkout_register_id",-1))
  "wash":
   expected="sink"
   var dishes=state.service.get("dishwashing",{}).get("dishes",[]).filter(func(d):return int(d.id)==int(staff.job_dish_id))
   id=int(dishes[0].sink_id) if dishes.size()==1 else -1
 var target=m.get_item(id)
 if target.is_empty() or expected=="" or str(target.kind)!=expected:return "Staff endpoint lost its authoritative station kind/identity"
 if not (kind=="cook" and step==3) and int(staff.station_id)!=id:return "Staff station differs from current service authority"
 var face=m.workface_cell(target)
 if expected=="counter" and staff.role=="chef" or expected=="register" and staff.role=="cashier":face=Vector2i(int(target.x),int(target.z))*2-face
 if staff.destination!=face or m.edge_blocked(Vector2i(int(target.x),int(target.z)),face):return "Staff endpoint is not its owned station workface"
 return ""
