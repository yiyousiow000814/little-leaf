extends RefCounted
## A typed, bounded suspension table over the existing service identities.
## Detached fields are -1. Host descriptors resolve only historical bindings;
## they are never furniture, inventory, path obstacles or refundable products.
const FORMAT="little_leaf.layout_hold.v1"
const GUEST_FIELDS=["table_id","chair_id","checkout_register_id"]
const RECORD_FIELDS=["meal_station_id","meal_pass_id","drink_station_id","plate_target_id","drink_target_id","trash_target_id","dish_sink_id"]
const STAFF_FIELDS=["station_id","table_face_id"]
const FLOOR_FIELDS=["trash_target_id"]
const HOST_KINDS=["table","chair","bench","stove","counter","beverage","sink","register","bin"]
static func empty()->Dictionary:
 return {"format":FORMAT,"hosts":[],"guests":[],"staff":[],"dishes":[],"floor":[]}
static func registry(service:Dictionary)->Dictionary:return service.get("layout_hold",{})
static func guest_held(service:Dictionary,id:int)->bool:
 return registry(service).get("guests",[]).any(func(row):return int(row.id)==id)
static func staff_held(service:Dictionary,index:int)->bool:
 return registry(service).get("staff",[]).any(func(row):return int(row.index)==index)
static func dish_held(service:Dictionary,id:int)->bool:
 return registry(service).get("dishes",[]).any(func(row):return int(row.id)==id)
static func floor_held(service:Dictionary,id:int)->bool:
 return registry(service).get("floor",[]).any(func(row):return int(row.id)==id)
static func active_guests(guests:Array,service:Dictionary)->Array:
 return guests.filter(func(g):return not guest_held(service,int(g.id)))
static func active_staff(service:Dictionary)->Array:
 var result=[]
 for index in service.get("staff",[]).size():
  if not staff_held(service,index):result.append(service.staff[index])
 return result
static func descriptor(item:Dictionary)->Dictionary:
 var result={}
 for key in ["id","kind","x","z","rot"]:result[key]=item[key]
 return result
static func _map(rows:Array,key:String)->Dictionary:
 var result={}
 for row in rows:
  if row is Dictionary and (row.get(key) is int or row.get(key) is float):result[int(row[key])]=row
 return result
static func _fail(message:String)->Dictionary:return {"ok":false,"error":message}
static func _shape(row,keys:Array)->bool:
 if not row is Dictionary or row.size()!=keys.size():return false
 for key in keys:
  if not row.has(key):return false
 return true
static func _restore_refs(entry:Dictionary,refs,allowed:Array,hosts:Dictionary,used:Dictionary,codec)->bool:
 if not refs is Dictionary or refs.size()>allowed.size():return false
 for key in refs:
  if key not in allowed or not codec._integer(refs[key],1,1000000000) or not hosts.has(int(refs[key])) or entry.get(key)!=-1:return false
  entry[key]=int(refs[key]);used[int(refs[key])]=true
 return true
static func project(state:Dictionary,items:Array,codec)->Dictionary:
 var service=state.get("service")
 if not service is Dictionary:return _fail("Layout hold requires service state")
 var hold=service.get("layout_hold")
 if not _shape(hold,["format","hosts","guests","staff","dishes","floor"]) or hold.format!=FORMAT:return _fail("Invalid layout hold format")
 for spec in [["hosts",512],["guests",60],["staff",64],["dishes",512],["floor",512]]:
  if not hold[spec[0]] is Array or hold[spec[0]].size()>spec[1]:return _fail("Layout hold exceeds service bounds")
 if not state.get("customers") is Array or not service.get("records") is Array or not service.get("staff") is Array:return _fail("Layout hold is missing its service owners")
 if not service.get("dishwashing",{}) is Dictionary or not service.get("floor_tasks",{}) is Dictionary:return _fail("Invalid held work ledgers")
 if not service.get("dishwashing",{}).get("dishes",[]) is Array or not service.get("floor_tasks",{}).get("messes",[]) is Array:return _fail("Invalid held work entries")
 var projected=state.duplicate(true);projected.erase("layout_hold_format");projected.service.erase("layout_hold")
 var guests=_map(projected.customers,"id");var records=_map(projected.service.records,"guest_id")
 var dishes=_map(projected.service.get("dishwashing",{}).get("dishes",[]),"id")
 var floor=_map(projected.service.get("floor_tasks",{}).get("messes",[]),"id")
 var actual=_map(items,"id");var hosts={};var used={}
 for host in hold.hosts:
  if not _shape(host,["id","kind","x","z","rot"]) or not codec._integer(host.id,1,1000000000) or host.kind not in HOST_KINDS or not codec._integer(host.x,0,17) or not codec._integer(host.z,0,17) or not codec._integer(host.rot,0,3):return _fail("Invalid held host descriptor")
  var id=int(host.id)
  if hosts.has(id) or (actual.has(id) and actual[id].kind!=host.kind):return _fail("Duplicate or incompatible held host")
  hosts[id]=host
 var held_guests={};var held_staff={};var held_dishes={};var held_floor={}
 for row in hold.guests:
  if not _shape(row,["id","token","guest","record"]) or not codec._integer(row.id,1,1000000000) or held_guests.has(int(row.id)) or not guests.has(int(row.id)) or not records.has(int(row.id)):return _fail("Held visit has no unique service owner")
  var id=int(row.id)
  if not codec._integer(row.token,1,1000000000) or row.token!=records[id].get("token"):return _fail("Held visit token mismatch")
  if not _restore_refs(guests[id],row.guest,GUEST_FIELDS,hosts,used,codec) or not _restore_refs(records[id],row.record,RECORD_FIELDS,hosts,used,codec):return _fail("Invalid held visit binding")
  held_guests[id]=true
 for row in hold.staff:
  if not _shape(row,["index","refs"]) or not codec._integer(row.index,0,service.staff.size()-1) or held_staff.has(int(row.index)):return _fail("Invalid held staff index")
  var index=int(row.index)
  if not projected.service.staff[index] is Dictionary or not _restore_refs(projected.service.staff[index],row.refs,STAFF_FIELDS,hosts,used,codec):return _fail("Invalid held staff binding")
  held_staff[index]=true
 for row in hold.dishes:
  if not _shape(row,["id","sink_id"]) or not codec._integer(row.id,1,1000000000) or held_dishes.has(int(row.id)) or not dishes.has(int(row.id)):return _fail("Invalid held dish identity")
  if row.sink_id!=-1 and not _restore_refs(dishes[int(row.id)],{"sink_id":row.sink_id},["sink_id"],hosts,used,codec):return _fail("Invalid held dish sink")
  if row.sink_id==-1 and not codec._integer(dishes[int(row.id)].get("sink_id"),1,1000000000):return _fail("Held dish lost its surviving sink")
  held_dishes[int(row.id)]=true
 for row in hold.floor:
  if not _shape(row,["id","token","refs"]) or not codec._integer(row.id,1,1000000000) or held_floor.has(int(row.id)) or not floor.has(int(row.id)) or row.token!=floor[int(row.id)].get("token"):return _fail("Invalid held floor task identity")
  if not _restore_refs(floor[int(row.id)],row.refs,FLOOR_FIELDS,hosts,used,codec):return _fail("Invalid held floor payload binding")
  held_floor[int(row.id)]=true
 if used.size()!=hosts.size():return _fail("Unreferenced held host")
 # Custody closes over the same job/visit/dish. A held payload may never have
 # a running holder, nor may a running visit acquire a held worker's job.
 for index in service.staff.size():
  var worker=service.staff[index]
  if not worker is Dictionary:return _fail("Invalid held worker")
  for key in ["job_guest_id","job_dish_id","job_mess_id"]:
   if not codec._integer(worker.get(key,-1),-1,1000000000):return _fail("Invalid held worker identity")
  var linked=held_guests.has(int(worker.get("job_guest_id",-1))) or (worker.get("job_kind")=="wash" and held_dishes.has(int(worker.get("job_dish_id",-1)))) or (worker.get("job_kind")=="floor" and held_floor.has(int(worker.get("job_mess_id",-1))))
  if linked!=held_staff.has(index) and worker.get("job_kind","")!="":return _fail("Layout hold does not close over active work")
 for index in service.staff.size():
  if held_staff.has(index):continue
  for field in STAFF_FIELDS:
   var id=int(service.staff[index].get(field,-1))
   if hosts.has(id) and (not actual.has(id) or descriptor(actual[id])!=hosts[id]):return _fail("Running worker references a held historical host")
 var validation_items=[]
 for item in items:validation_items.append(hosts.get(int(item.id),item))
 for id in hosts:
  if not actual.has(id):validation_items.append(hosts[id])
 # A historical descriptor cannot change a running owner's physical host.
 for scope in [[projected.customers,"id",GUEST_FIELDS,held_guests],[projected.service.records,"guest_id",RECORD_FIELDS,held_guests],[dishes.values(),"id",["sink_id"],held_dishes],[floor.values(),"id",FLOOR_FIELDS,held_floor]]:
  for entry in scope[0]:
   if not entry is Dictionary:return _fail("Invalid running owner")
   if scope[3].has(int(entry.get(scope[1],-1))):continue
   for field in scope[2]:
    var id=int(entry.get(field,-1))
    if hosts.has(id) and (not actual.has(id) or descriptor(actual[id])!=hosts[id]):return _fail("Running service references a held historical host")
 return {"ok":true,"state":projected,"items":validation_items}
static func detach(state:Dictionary,hold:Dictionary)->Dictionary:
 var result=state.duplicate(true)
 var guests=_map(result.customers,"id");var records=_map(result.service.records,"guest_id")
 var dishes=_map(result.service.get("dishwashing",{}).get("dishes",[]),"id")
 var floor=_map(result.service.get("floor_tasks",{}).get("messes",[]),"id")
 for row in hold.guests:
  for key in row.guest:guests[int(row.id)][key]=-1
  for key in row.record:records[int(row.id)][key]=-1
 for row in hold.staff:
  for key in row.refs:result.service.staff[int(row.index)][key]=-1
 for row in hold.dishes:
  if int(row.sink_id)>=0:dishes[int(row.id)].sink_id=-1
 for row in hold.floor:
  for key in row.refs:floor[int(row.id)][key]=-1
 result.layout_hold_format=FORMAT;result.service.layout_hold=hold.duplicate(true)
 return result
