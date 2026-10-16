extends RefCounted
## One Apply/retry transaction over existing service records. No runtime owner,
## allocator, timer or new actor/order ledger lives here.
const Hold=preload("res://scripts/persistence/cafe_layout_hold.gd")
const Codec=preload("res://scripts/persistence/cafe_runtime_codec.gd")
const Contract=preload("res://scripts/persistence/cafe_save_contract.gd")
const NONE=Vector2i(-100,-100)
static func _state(model,snapshot:Dictionary)->Dictionary:
 var result={"customers":model.customers.duplicate(true),"service":snapshot.duplicate(true),"next_customer_id":model._next_customer_id,"arrival_elapsed":model._arrival_elapsed,"walking_customer_id":model._walking_customer_id,"next_checkout_ticket":model.next_checkout_ticket,"checkout_format":Contract.CHECKOUT_FORMAT,"layout_motion_format":Contract.LAYOUT_MOTION_FORMAT}
 if snapshot.has("layout_hold"):result.layout_hold_format=Hold.FORMAT
 return result
static func _copy(model):
 var shadow=model.get_script().new();var state={}
 for key in model.DECORATION_STATE:state[key]=model.get(key)
 shadow._copy_decoration_state(state);shadow.catalog=model.catalog.duplicate(true)
 shadow.decoration_session_active=false
 return shadow
static func _refs(node:Dictionary)->Array:
 var result=[]
 for pair in node.parts:
  for field in pair.fields:
   var id=int(pair.value.get(field,-1))
   if id>=0 and id not in result:result.append(id)
 return result
static func _nodes(state:Dictionary)->Array:
 var nodes=[];var records=Hold._map(state.service.records,"guest_id")
 for guest in state.customers:
  nodes.append({"kind":"guest","id":int(guest.id),"parts":[{"value":guest,"fields":Hold.GUEST_FIELDS},{"value":records[int(guest.id)],"fields":Hold.RECORD_FIELDS}]})
 for index in state.service.staff.size():nodes.append({"kind":"staff","id":index,"parts":[{"value":state.service.staff[index],"fields":Hold.STAFF_FIELDS}]})
 for dish in state.service.get("dishwashing",{}).get("dishes",[]):nodes.append({"kind":"dish","id":int(dish.id),"parts":[{"value":dish,"fields":["sink_id"]}]})
 for mess in state.service.get("floor_tasks",{}).get("messes",[]):nodes.append({"kind":"floor","id":int(mess.id),"parts":[{"value":mess,"fields":Hold.FLOOR_FIELDS}]})
 return nodes
static func _groups(nodes:Array)->Array:
 var groups=[];var remaining=nodes.duplicate()
 while not remaining.is_empty():
  var group=[remaining.pop_front()];var cursor=0
  while cursor<group.size():
   var current=group[cursor];cursor+=1;var refs=_refs(current)
   for index in range(remaining.size()-1,-1,-1):
    var other=remaining[index];var linked=false
    for id in _refs(other):
     if id in refs:linked=true;break
    for pair in [[current,other],[other,current]]:
     if pair[0].kind=="staff":
      var worker=pair[0].parts[0].value
      linked=linked or (pair[1].kind=="guest" and int(worker.get("job_guest_id",-1))==pair[1].id)
      linked=linked or (pair[1].kind=="dish" and worker.job_kind=="wash" and int(worker.get("job_dish_id",-1))==pair[1].id)
      linked=linked or (pair[1].kind=="floor" and worker.job_kind=="floor" and int(worker.get("job_mess_id",-1))==pair[1].id)
     if pair[0].kind=="guest" and pair[1].kind=="dish":linked=linked or int(pair[0].parts[1].value.get("dish_id",-1))==pair[1].id
    if linked:group.append(other);remaining.remove_at(index)
  groups.append(group)
 return groups
static func _floor(model,cell:Vector2i)->bool:
 return cell.x>=1 and model.is_floor_owned(cell) and model._walkable(cell)
static func _point_clear(model,point:Vector2)->bool:
 return model._furniture_body_error(model.items,[point])=="" and model._opening_body_error(model.built_walls,model.wall_attachments,[point])==""
static func _usable(model,item:Dictionary,reachable:Dictionary)->bool:
 if item.is_empty():return false
 var cell=Vector2i(int(item.x),int(item.z));var kind=str(item.kind)
 if kind in ["chair","bench"]:return true # The dining pair checks its own egress.
 if kind=="table":return model.table_service_cells(item).any(func(at):return reachable.has(at))
 if kind=="bin":return model.bin_service_cells(item).any(func(at):return reachable.has(at))
 var faces=[model.workface_cell(item)]
 if kind in ["counter","register"]:faces.append(cell*2-faces[0])
 for at in faces:
  if not _floor(model,at) or not reachable.has(at) or model.edge_blocked(cell,at):return false
 return true
static func _pair_usable(model,group:Dictionary,reachable:Dictionary)->bool:
 var table=model.get_item(int(group.table_id));var seat=model.get_item(int(group.seat_id))
 return not table.is_empty() and not seat.is_empty() and _usable(model,table,reachable) and not model.edge_blocked(Vector2i(table.x,table.z),Vector2i(seat.x,seat.z)) and not model.chair_egress_cells(int(seat.id),int(table.id)).is_empty()
static func _nearest_floor(model,point:Vector2,reachable:Dictionary)->Vector2:
 var best=Vector2.INF;var distance=INF
 for cell in reachable:
  if not _floor(model,cell):continue
  var at=model.cell_center(cell);var next=point.distance_squared_to(at)
  if next<distance:best=at;distance=next
 return best
static func _path_valid(model,worker:Dictionary)->bool:
 var previous:Vector2=worker.pos
 for index in range(int(worker.index),worker.path.size()):
  var cell:Vector2i=worker.path[index]
  if not _floor(model,cell) or model.segment_blocked(previous,model.cell_center(cell)):return false
  previous=model.cell_center(cell)
 return true
static func _guest_position(model,guest:Dictionary,old:Dictionary,old_hosts:Dictionary,reachable:Dictionary)->bool:
 var table=model.get_item(int(guest.table_id));var seat=model.get_item(int(guest.chair_id))
 if table.is_empty() or seat.is_empty():return false
 var seat_changed=Hold.descriptor(seat)!=Hold.descriptor(old_hosts[int(old.chair_id)])
 var checkout_changed=false;var position_changed=false
 var position=Vector2(float(guest.x),float(guest.z))
 if guest.get("checkout_cell",NONE)!=NONE:
  var register=model.get_item(int(guest.checkout_register_id));var previous=old_hosts[int(old.checkout_register_id)]
  checkout_changed=Hold.descriptor(register)!=Hold.descriptor(previous)
  var old_front=model.workface_cell(previous);var old_dir=old_front-Vector2i(previous.x,previous.z)
  var side=Vector2i(-old_dir.y,old_dir.x);var offset:Vector2i=old.checkout_cell-old_front;var rank=offset.x*side.x+offset.y*side.y
  var front=model.workface_cell(register);var direction=front-Vector2i(register.x,register.z)
  guest.checkout_cell=front+Vector2i(-direction.y,direction.x)*rank
  if not _floor(model,guest.checkout_cell):return false
  if str(guest.phase) in ["checkout_wait","paying"]:
   guest.x=float(guest.checkout_cell.x)+.5;guest.z=float(guest.checkout_cell.y)+.5
   guest.mobility={};guest.route=[];guest.route_index=0
 elif bool(guest.seated) and not bool(guest.dismounting):
  if seat_changed or not guest.get("mobility",{}).is_empty():
   guest.x=float(seat.x)+.5;guest.z=float(seat.z)+.5;guest.mobility={}
  var exits=model.chair_egress_cells(int(seat.id),int(table.id))
  if exits.is_empty():return false
  if guest.service_cell not in exits:guest.service_cell=exits[0]
 elif not bool(guest.get("exterior_exit",false)) and model.is_floor_owned(Vector2i(position.floor())) and (not _floor(model,Vector2i(position.floor())) or not _point_clear(model,position)) and not bool(guest.dismounting):
  position=_nearest_floor(model,position,reachable)
  if not position.is_finite():return false
  guest.x=position.x;guest.z=position.y;position_changed=true
 if not guest.get("mobility",{}).is_empty():
  if model._layout_motion_geometry_error([guest],model.items,model.built_walls,model.owned_parcels,model.wall_attachments)!="":return false
 if str(guest.phase) in ["arriving","leaving","checkout_walk"]:
  var needs_route=seat_changed or checkout_changed or position_changed;var prior=Vector2(float(guest.x),float(guest.z))
  for index in range(int(guest.route_index),guest.route.size()):
   if model.segment_blocked(prior,guest.route[index]):needs_route=true;break
   prior=guest.route[index]
  if needs_route:
   if not model.reroute_guest(guest):return false
   guest.elapsed=old.elapsed;guest.duration=old.duration
 return true
static func _attempt(model,group:Array,old_hosts:Dictionary,used:Dictionary,loads:Dictionary,reserved:Dictionary,reachable:Dictionary,only_survivors:bool)->Dictionary:
 var mapping={};var required={};var need_load={}
 for node in group:
  for id in _refs(node):required[id]=true
  if node.kind=="dish":
   var id=int(node.parts[0].value.sink_id);need_load[id]=int(need_load.get(id,0))+1
  if node.kind=="guest":
   var id=int(node.parts[1].value.get("dish_sink_id",-1))
   if id>=0:need_load[id]=int(need_load.get(id,0))+1
 for node in group:
  if node.kind!="guest":continue
  var guest=node.parts[0].value;var choice={}
  var candidates=model.dining_sets.duplicate()
  candidates.sort_custom(func(a,b):return int(a.table_id)==int(guest.table_id) and int(b.table_id)!=int(guest.table_id))
  for pair in candidates:
   if only_survivors and (int(pair.table_id)!=int(guest.table_id) or int(pair.seat_id)!=int(guest.chair_id)):continue
   if used.has(int(pair.table_id)) or used.has(int(pair.seat_id)) or (reserved.has(int(pair.table_id)) and not required.has(int(pair.table_id))) or (reserved.has(int(pair.seat_id)) and not required.has(int(pair.seat_id))) or int(pair.table_id) in mapping.values() or not _pair_usable(model,pair,reachable):continue
   choice=pair;break
  if choice.is_empty():return {"ok":false}
  mapping[int(guest.table_id)]=int(choice.table_id);mapping[int(guest.chair_id)]=int(choice.seat_id)
 for id in required:
  if mapping.has(id):continue
  if not old_hosts.has(id):return {"ok":false}
  var kind=str(old_hosts[id].kind);var candidates=model.items.duplicate()
  candidates.sort_custom(func(a,b):return int(a.id)==id and int(b.id)!=id)
  var chosen=-1
  for item in candidates:
   if item.kind!=kind or (only_survivors and int(item.id)!=id) or not _usable(model,item,reachable):continue
   if kind=="sink":
    var already=int(loads.get(int(item.id),0))-int(need_load.get(int(item.id),0))
    for old_id in mapping:
     if mapping[old_id]==int(item.id):already+=int(need_load.get(old_id,0))
    if already+int(need_load.get(id,0))>6:continue
   elif used.has(int(item.id)) or (reserved.has(int(item.id)) and not required.has(int(item.id))) or int(item.id) in mapping.values():continue
   chosen=int(item.id);break
  if chosen<0:return {"ok":false}
  mapping[id]=chosen
 # A visit with no assigned job still needs the unfinished service chain.
 # Waiting here prevents patience/departure from running after Apply removed
 # an unassigned stove/pass/drink station. Existing allocators choose jobs
 # and stations after release; this probe creates no new bindings or claims.
 for node in group:
  if node.kind!="guest":continue
  var guest=node.parts[0].value;var record=node.parts[1].value;var needs=[]
  if not bool(record.get("meal_done",false)):
   if record.plate_owner in ["kitchen","station"]:needs.append("stove")
   if record.plate_owner in ["kitchen","station"] or (record.plate_owner=="staff" and group.any(func(n):return n.kind=="staff" and n.parts[0].value.job_kind=="cook")):needs.append("counter")
  if not bool(record.get("drink_done",false)) and record.drink_owner in ["beverage","station"]:needs.append("beverage")
  if str(guest.get("settlement_mode","legacy"))=="register" and not bool(guest.paid):needs.append("register")
  for kind in needs:
   var available=false
   for item in model.items:
    if item.kind!=kind or not _usable(model,item,reachable):continue
    var id=int(item.id)
    if kind!="register" and id not in mapping.values() and (used.has(id) or (reserved.has(id) and not required.has(id))):continue
    available=true;break
   if not available:return {"ok":false}
 var proposed=group.duplicate(true)
 for node in proposed:
  for part in node.parts:
   for field in part.fields:
    var id=int(part.value.get(field,-1))
    if mapping.has(id):part.value[field]=mapping[id]
  if node.kind=="guest":
   var old=group.filter(func(n):return n.kind=="guest" and n.id==node.id)[0].parts[0].value
   if not _guest_position(model,node.parts[0].value,old,old_hosts,reachable):return {"ok":false}
  elif node.kind=="floor":
   if not _floor(model,node.parts[0].value.floor_cell) or not reachable.has(node.parts[0].value.floor_cell):return {"ok":false}
  elif node.kind=="staff":
   var worker=node.parts[0].value;var changed=false
   if not _floor(model,Vector2i(worker.pos.floor())) or not reachable.has(Vector2i(worker.pos.floor())) or not _point_clear(model,worker.pos):
    var at=_nearest_floor(model,worker.pos,reachable)
    if not at.is_finite():return {"ok":false}
    worker.pos=at;changed=true
   for field in Hold.STAFF_FIELDS:
    var old=group.filter(func(n):return n.kind=="staff" and n.id==node.id)[0].parts[0].value
    var id=int(old.get(field,-1))
    if id>=0 and Hold.descriptor(model.get_item(int(worker[field])))!=Hold.descriptor(old_hosts[id]):changed=true
   if changed or not _path_valid(model,worker):
    worker.path=[];worker.index=0;worker.destination=NONE;worker.table_face_id=-1;worker.table_face_cell=Vector2i(-1,-1)
 return {"ok":true,"nodes":proposed,"mapping":mapping,"loads":need_load}
static func _held_refs(entry:Dictionary,fields:Array,hosts:Dictionary,hold:Dictionary,actual:Dictionary)->Dictionary:
 var refs={}
 for field in fields:
  var id=int(entry.get(field,-1))
  if id<0:continue
  if actual.has(id) and (fields!=Hold.GUEST_FIELDS or Hold.descriptor(actual[id])==Hold.descriptor(hosts[id])):continue
  refs[field]=id
  if not hold.hosts.any(func(host):return int(host.id)==id):hold.hosts.append(Hold.descriptor(hosts[id]))
 return refs
static func _hold_group(group:Array,hosts:Dictionary,hold:Dictionary,actual:Dictionary):
 for node in group:
  var value=node.parts[0].value
  match node.kind:
   "guest":hold.guests.append({"id":node.id,"token":node.parts[1].value.token,"guest":_held_refs(value,Hold.GUEST_FIELDS,hosts,hold,actual),"record":_held_refs(node.parts[1].value,Hold.RECORD_FIELDS,hosts,hold,actual)})
   "staff":hold.staff.append({"index":node.id,"refs":_held_refs(value,Hold.STAFF_FIELDS,hosts,hold,actual)})
   "dish":
    var refs=_held_refs(value,["sink_id"],hosts,hold,actual)
    hold.dishes.append({"id":node.id,"sink_id":int(refs.get("sink_id",-1))})
   "floor":hold.floor.append({"id":node.id,"token":value.token,"refs":_held_refs(value,Hold.FLOOR_FIELDS,hosts,hold,actual)})
static func plan(model,prior_items:Array,snapshot:Dictionary)->Dictionary:
 var codec=Codec.new();var original=_state(model,snapshot)
 var checked=codec.validate(codec.encode(original),prior_items,model.cooks,model.PHASES,Contract.LAYOUT_HOLD_VERSION if snapshot.has("layout_hold") else Contract.VERSION,model.staff_roster(),model.duty_counts)
 if not checked.ok:return {"ok":false,"error":"Before Apply: "+checked.error}
 var projected=Hold.project(checked.state,prior_items,codec) if snapshot.has("layout_hold") else {"ok":true,"state":checked.state,"items":prior_items}
 if not projected.ok:return projected
 var shadow=_copy(model);var state=projected.state
 shadow.customers.assign(state.customers);shadow.service_snapshot=state.service
 var nodes=_nodes(state);var groups=_groups(nodes);var hosts=Hold._map(projected.items,"id")
 var reachable=shadow._wall_reachable(shadow.built_walls,shadow.items,shadow.owned_parcels)
 var used={};var loads={};var pending=[];var hold=Hold.empty();var reserved={}
 # Surviving bindings retain priority even when another host in their
 # component is missing. Replacements cannot steal a held owner's equipment.
 for node in nodes:
  for id in _refs(node):
   if not shadow.get_item(id).is_empty():reserved[id]=true
  var sink=-1
  if node.kind=="dish":sink=int(node.parts[0].value.sink_id)
  elif node.kind=="guest":sink=int(node.parts[1].value.get("dish_sink_id",-1))
  if sink>=0 and not shadow.get_item(sink).is_empty():loads[sink]=int(loads.get(sink,0))+1
 # All surviving components reserve first; later replacements cannot steal an
 # incumbent's table, plate host or workstation due to record ordering.
 for group in groups:
  var proposal=_attempt(shadow,group,hosts,used,loads,reserved,reachable,true)
  if not proposal.ok:pending.append(group);continue
  _accept(group,proposal,used,loads,hosts)
 for group in pending:
  var proposal=_attempt(shadow,group,hosts,used,loads,reserved,reachable,false)
  if proposal.ok:_accept(group,proposal,used,loads,hosts)
  else:_hold_group(group,hosts,hold,Hold._map(shadow.items,"id"))
 state=Hold.detach(state,hold);shadow.customers.assign(state.customers);shadow.service_snapshot=state.service
 var data=shadow.save_data()
 if data.is_empty():return {"ok":false,"error":"Apply reconciliation: "+shadow.last_error}
 return {"ok":true,"customers":shadow.customers,"service":shadow.service_snapshot,"data":data}
static func _accept(group:Array,proposal:Dictionary,used:Dictionary,loads:Dictionary,hosts:Dictionary):
 for index in group.size():
  for part in group[index].parts.size():group[index].parts[part].value.merge(proposal.nodes[index].parts[part].value,true)
 for old_id in proposal.mapping:
  var id=int(proposal.mapping[old_id])
  if hosts[old_id].kind=="sink":
   var amount=int(proposal.loads.get(old_id,0))
   loads[old_id]=maxi(0,int(loads.get(old_id,0))-amount)
   loads[id]=int(loads.get(id,0))+amount
  else:used[id]=true
