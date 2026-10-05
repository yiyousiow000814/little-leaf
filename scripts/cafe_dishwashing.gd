extends RefCounted
## A dish leaves its diner only at the physical sink drop-off. The independent
## queue then survives table turnover; progress advances only at its workface.
const FORMAT="little_leaf.dishwashing.v1"
const CAPACITY=6
const MAX_DISHES=512
const WASH_SECONDS=20.0
const DROP_SECONDS=.75
const STEPS=[{"kind":"sink","action":"washing","seconds":WASH_SECONDS}]
var game
var dishes={}
var next_id=1
var completed=0
func _init(owner=null):game=owner
func snapshot()->Dictionary:
 return {"format":FORMAT,"next_id":next_id,"completed":completed,"dishes":dishes.values().duplicate(true)}
func restore(data:Dictionary):
 dishes.clear();next_id=int(data.get("next_id",1));completed=int(data.get("completed",0))
 for entry in data.get("dishes",[]):dishes[int(entry.id)]=entry.duplicate(true)
func count_at(sink_id:int)->int:
 var count=0
 for dish in dishes.values():
  if int(dish.sink_id)==sink_id:count+=1
 return count
func load_at(sink_id:int,except_record:Dictionary={})->int:
 var count=count_at(sink_id)
 for record in game.service_guests.values():
  if not is_same(record,except_record) and int(record.get("dish_sink_id",-1))==sink_id:count+=1
 return count
func busy(sink_id:int)->bool:return load_at(sink_id)>0
func reserve(record:Dictionary,staff:Dictionary)->Dictionary:
 var from=Vector2i(floori(staff.pos.x),floori(staff.pos.y))
 var current=game.model.get_item(int(record.get("dish_sink_id",-1)))
 if not current.is_empty() and current.kind=="sink" and load_at(int(current.id),record)<CAPACITY and game._service_cell(current,from)!=Vector2i(-1,-1):return current
 record.dish_sink_id=-1
 var total_load=dishes.size()
 for live in game.service_guests.values():
  if int(live.get("dish_sink_id",-1))>=0:total_load+=1
 if total_load>=MAX_DISHES:return {}
 var chosen={};var best_load=CAPACITY;var shortest=1000000
 for sink in game.model.items:
  if sink.kind!="sink":continue
  var count=load_at(int(sink.id),record)
  if count>=CAPACITY:continue
  var face=game._service_cell(sink,from)
  if face==Vector2i(-1,-1):continue
  var distance=game._static_service_path(from,face).size()
  if count<best_load or (count==best_load and distance<shortest):chosen=sink;best_load=count;shortest=distance
 if not chosen.is_empty():record.dish_sink_id=int(chosen.id)
 return chosen
func deposit(record:Dictionary,staff:Dictionary,index:int,target:Dictionary)->bool:
 # Contact can be replayed after load; its ownership transition is idempotent.
 if record.plate_owner=="dish_queue":return true
 if dishes.size()>=MAX_DISHES or record.plate_owner!="staff" or int(record.plate_staff_index)!=index or int(record.get("dish_sink_id",-1))!=int(target.id) or load_at(int(target.id),record)>=CAPACITY:return false
 var id=next_id;next_id+=1
 dishes[id]={"id":id,"sink_id":int(target.id),"elapsed":0.0}
 record.plate_owner="dish_queue";record.plate_staff_index=-1;record.plate_target_id=-1
 record.dish_id=id;record.dish_sink_id=-1
 return true
func entry(staff:Dictionary)->Dictionary:return dishes.get(int(staff.get("job_dish_id",-1)),{})
func target(staff:Dictionary)->Dictionary:
 var dish=entry(staff)
 return {} if dish.is_empty() else game.model.get_item(int(dish.sink_id))
func assign(staff:Dictionary,index:int)->bool:
 if staff.role!="cleaner" or staff.job_kind!="":return false
 var from=Vector2i(floori(staff.pos.x),floori(staff.pos.y));var chosen={};var shortest=1000000
 for dish in dishes.values():
  var sink=game.model.get_item(int(dish.sink_id))
  if sink.is_empty():continue
  var assigned=false
  for other in game.staff_states:
   if other.job_kind=="wash" and int(other.station_id)==int(sink.id):assigned=true;break
  if assigned:continue
  var face=game._service_cell(sink,from)
  if face==Vector2i(-1,-1):continue
  var distance=game._static_service_path(from,face).size()
  # FIFO within one sink; choose the nearest available sink between queues.
  if distance<shortest:chosen=dish;shortest=distance
 if chosen.is_empty():return false
 staff.job_kind="wash";staff.job_guest_id=-1;staff.job_dish_id=int(chosen.id);staff.job_token=int(chosen.id)
 staff.job_step=0;staff.job_elapsed=float(chosen.elapsed);staff.station_id=int(chosen.sink_id)
 staff.path.clear();staff.index=0;staff.destination=Vector2i(-100,-100);staff.table_face_id=-1;staff.table_face_cell=Vector2i(-1,-1)
 staff.blocked_reason="";staff.blocked_target_id=-1;staff.blocked_guest_id=-1
 return true
func workface_available(staff:Dictionary,sink_id:int)->bool:
 # Do not let the earlier waiter index steal an in-progress cleaner's face.
 # Once a wash ends, waiting drop-offs get the next turn before another wash.
 var own_index=game.staff_states.find(staff)
 var winner=-1;var best=-1
 for i in game.staff_states.size():
  var other=game.staff_states[i]
  var dropping=other.job_kind=="cleanup" and int(other.job_step)==1
  if not dropping and other.job_kind!="wash":continue
  if int(other.station_id)!=sink_id:continue
  var rank=3 if float(other.job_elapsed)>0.0 else (2 if dropping else 1)
  if rank>best:best=rank;winner=i
 return winner<0 or winner==own_index
func contact(staff:Dictionary):
 var dish=entry(staff)
 if not dish.is_empty():dish.elapsed=minf(WASH_SECONDS,float(staff.job_elapsed))
func complete(staff:Dictionary):
 var dish=entry(staff)
 if dish.is_empty():game._clear_service_job(staff);return
 if float(dish.elapsed)+.000001<WASH_SECONDS:return
 var id=int(dish.id)
 for record in game.service_guests.values():
  if record.plate_owner=="dish_queue" and int(record.get("dish_id",-1))==id:
   record.plate_owner="clean";record.dish_id=-1
 dishes.erase(id);completed+=1;game._clear_service_job(staff)
func migrate_legacy():
 # Direct runtime restores (rather than codec loads) also support old snapshots.
 var data={"records":[],"staff":game.staff_states}
 for record in game.service_guests.values():
  if not record.has("dish_sink_id"):record.dish_sink_id=-1
  if not record.has("dish_id"):record.dish_id=-1
  if record.plate_owner=="sink":
   record.guest_id=int(record.guest.id);data.records.append(record)
 if data.records.is_empty():return
 data.dishwashing=snapshot();migrate_snapshot(data)
 restore(data.dishwashing)
 for record in data.records:record.erase("guest_id")
static func migrate_snapshot(service:Dictionary):
 var data=service.get("dishwashing",{"format":FORMAT,"next_id":1,"completed":0,"dishes":[]})
 for record in service.records:
  record.dish_sink_id=-1;record.dish_id=-1
  if record.plate_owner!="sink":continue
  var id=int(data.next_id);data.next_id=id+1;var elapsed=0.0;var legacy_worker={}
  for worker in service.staff:
   if worker.job_kind=="cleanup" and int(worker.job_guest_id)==int(record.guest_id) and int(worker.job_step)==1:
    elapsed=clampf(float(worker.job_elapsed)/1.5,0.0,1.0)*WASH_SECONDS;legacy_worker=worker;break
  data.dishes.append({"id":id,"sink_id":int(record.plate_target_id),"elapsed":elapsed})
  record.plate_owner="dish_queue";record.plate_target_id=-1;record.plate_staff_index=-1;record.dish_id=id
  if not legacy_worker.is_empty():
   if legacy_worker.role=="cleaner":
    legacy_worker.job_kind="wash";legacy_worker.job_guest_id=-1;legacy_worker.job_dish_id=id;legacy_worker.job_token=id;legacy_worker.job_step=0;legacy_worker.job_elapsed=elapsed
   else:legacy_worker.job_step=2;legacy_worker.job_elapsed=0.0;legacy_worker.station_id=-1
 service.dishwashing=data
static func validate_snapshot(data,staff:Array,records:Dictionary,item_map:Dictionary,codec)->Dictionary:
 if not data is Dictionary or data.get("format")!=FORMAT or not codec._integer(data.get("next_id"),1,1000000000) or not codec._integer(data.get("completed"),0,1000000000) or not data.get("dishes") is Array or data.dishes.size()>MAX_DISHES:return {"ok":false,"error":"Invalid dishwashing ledger"}
 for worker in staff:
  if not worker is Dictionary:return {"ok":false,"error":"Invalid dishwashing staff record"}
  for key in ["job_guest_id","job_token","job_step","station_id"]:
   if not codec._integer(worker.get(key),-1,1000000000):return {"ok":false,"error":"Invalid dishwashing staff identity"}
 var ids={};var loads={};var links={};var jobs={};var stations={}
 for dish in data.dishes:
  if not dish is Dictionary or not codec._integer(dish.get("id"),1,int(data.next_id)-1) or ids.has(int(dish.id)) or not codec._integer(dish.get("sink_id"),1,1000000000) or not item_map.has(int(dish.sink_id)) or item_map[int(dish.sink_id)].kind!="sink" or not codec._number(dish.get("elapsed"),0,WASH_SECONDS):return {"ok":false,"error":"Invalid queued dish identity, sink or progress"}
  ids[int(dish.id)]=dish;loads[int(dish.sink_id)]=int(loads.get(int(dish.sink_id),0))+1
 for record in records.values():
  if not codec._integer(record.get("dish_sink_id",-1),-1,1000000000) or not codec._integer(record.get("dish_id",-1),-1,1000000000):return {"ok":false,"error":"Invalid dish reservation"}
  var sink_id=int(record.get("dish_sink_id",-1));var dish_id=int(record.get("dish_id",-1))
  if sink_id!=-1:
   var cup_only=record.plate_owner=="clean" and record.drink_owner=="table" and not record.dishes_collected
   if not item_map.has(sink_id) or item_map[sink_id].kind!="sink" or (record.plate_owner not in ["table","staff"] and not cup_only):return {"ok":false,"error":"Dish reservation has no valid sink or payload"}
   var owner_found=false
   for worker in staff:
    if worker.get("job_kind")=="cleanup" and int(worker.get("job_guest_id",-1))==int(record.guest_id) and int(worker.get("job_step",-1)) in [0,1]:owner_found=true;break
   if not owner_found:return {"ok":false,"error":"Dish reservation has no transporting worker"}
   loads[sink_id]=int(loads.get(sink_id,0))+1
  if record.plate_owner=="dish_queue":
   if not ids.has(dish_id) or links.has(dish_id) or int(record.plate_target_id)!=-1 or not record.dishes_collected or record.drink_owner!="cleared":return {"ok":false,"error":"Queued dish ownership mismatch"}
   links[dish_id]=true
  elif dish_id!=-1:return {"ok":false,"error":"Dish link retained by another payload owner"}
 for sink_id in loads:
  if int(loads[sink_id])>CAPACITY:return {"ok":false,"error":"Sink exceeds six dishes including reservations"}
 for worker in staff:
  if worker.get("job_kind")!="wash":continue
  if not codec._integer(worker.get("job_dish_id"),1,int(data.next_id)-1):return {"ok":false,"error":"Invalid dishwashing job identity"}
  var id=int(worker.job_dish_id)
  if worker.get("role")!="cleaner" or int(worker.get("job_guest_id",-1))!=-1 or not ids.has(id) or int(worker.get("job_token",-1))!=id or int(worker.get("station_id",-1))!=int(ids[id].sink_id) or int(worker.get("job_step",-1))!=0 or not codec._number(worker.get("job_elapsed"),0,WASH_SECONDS) or not is_equal_approx(float(worker.job_elapsed),float(ids[id].elapsed)):return {"ok":false,"error":"Dishwashing worker ownership or progress mismatch"}
  if jobs.has(id) or stations.has(int(worker.station_id)):return {"ok":false,"error":"Duplicate dishwashing worker or sink"}
  jobs[id]=true;stations[int(worker.station_id)]=true
 return {"ok":true,"records":ids}
