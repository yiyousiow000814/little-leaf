extends RefCounted
## Independent walking-origin floor work. It outlives the originating diner.
# Keep legacy stage numbers and durations: active old pickups resume as sweeps
# at their saved elapsed time. Already-held litter is now contained in a pan.
const STEPS=[{"kind":"floor","action":"sweeping","debris_kind":"banana","seconds":.85},{"kind":"floor","action":"sweeping","debris_kind":"crumbs","seconds":1.25},{"kind":"bin","action":"disposing_trash","seconds":.9},{"kind":"floor","action":"mopping","seconds":1.5}]
const MAX_MESSES=24
const MAX_NEW_LITTER=12
const DROP_CHANCE_PERCENT=10
const LITTER_SCALE=1.08
const WALKING_PHASES=["arriving","checkout_walk","leaving"]
const KITCHEN_KINDS=["stove","beverage","sink","counter"]
const Geometry=preload("res://scripts/cafe_floor_geometry.gd")
var geometry
var game
var messes={}
var walks={}
var next_id=1
var completed=0
# Layout owners can exclude future toilets or staff-only zones with rectangles.
# This is a spawn policy, not saved state; old jobs keep their physical targets.
var litter_exclusions:Array[Rect2i]=[]
func _init(owner=null):game=owner;geometry=Geometry.new(owner)
func snapshot()->Dictionary:return {"next_id":next_id,"completed":completed,"messes":messes.values().duplicate(true),"walks":walks.values().duplicate(true)}
func restore(data:Dictionary):
 messes.clear();walks.clear();next_id=int(data.get("next_id",1));completed=int(data.get("completed",0))
 for entry in data.get("messes",[]):
  var restored=entry.duplicate(true);Geometry.canonicalize_metadata(restored);messes[int(entry.id)]=restored
 for entry in data.get("walks",[]):walks[int(entry.guest_id)]=entry.duplicate(true)
func observe_walks():
 var live={}
 for guest in game.model.customers:
  var id=int(guest.id);live[id]=true;var pos=Vector2(float(guest.x),float(guest.z));var cell=Vector2i(floori(pos.x),floori(pos.y))
  if not walks.has(id):walks[id]={"guest_id":id,"pos":pos,"cell":cell,"inside_steps":0,"dropped":false};continue
  var track=walks[id];var old_cell:Vector2i=track.cell;var moved=pos.distance_to(track.pos)>.00001
  var adjacent=absi(cell.x-old_cell.x)+absi(cell.y-old_cell.y)==1
  if moved and adjacent and str(guest.phase) in WALKING_PHASES and not bool(guest.get("withdrawn",false)) and not game.model.segment_blocked(track.pos,pos) and litter_allowed(old_cell):
   track.inside_steps+=1
   # Each eligible crossing offers a small repeatable chance, so aggregate
   # frequency grows with customer traffic, not an every-footstep guarantee.
   var roll=posmod(id*53+int(track.inside_steps)*17,100)
   if not track.dropped and int(track.inside_steps)>=3 and roll<DROP_CHANCE_PERCENT:
    var kind=["banana","crumbs"][posmod(id+int(track.inside_steps),2)]
    var spawned=spawn(old_cell,kind,id,int(track.inside_steps))
    if spawned>=0:track.dropped=true
  track.pos=pos;track.cell=cell
 for id in walks.keys():
  if not live.has(id):walks.erase(id)
func spawn(cell:Vector2i,kind:String,guest_id=-1,path_step=0)->int:
 if messes.size()>=MAX_NEW_LITTER or kind not in ["banana","crumbs"] or not litter_allowed(cell):return -1
 for entry in messes.values():
  var separation:Vector2i=entry.floor_cell-cell
  if absi(separation.x)<=1 and absi(separation.y)<=1:return -1
 var center=Vector2(cell)+Vector2(.5,.5);var id=next_id
 var entry={"id":id,"token":id,"floor_cell":cell,"floor_target":center,"debris_target":center+Vector2(.1,-.08),"spill_target":center+Vector2(-.1,.08),"floor_debris":"none" if kind=="spill" else kind,"floor_spill":kind=="spill","spill_remaining":1.0 if kind=="spill" else 0.0,"spill_cleaned":kind!="spill","trash_owner":"none" if kind=="spill" else "floor","trash_staff_index":-1,"trash_target_id":-1,"floor_dirty":true,"floor_cleaned":false,"source_guest_id":guest_id,"spawn_path_step":path_step}
 if not geometry.generate(entry,posmod(id*47+int(guest_id)*13,1000000000),LITTER_SCALE,true):return -1
 # Every visible piece must stay inside the actually traversed eligible tile.
 for point in entry.mess_shape.outline:
  if Vector2i(floori(point.x),floori(point.y))!=cell:return -1
 messes[id]=entry;next_id+=1
 return id
func litter_allowed(cell:Vector2i)->bool:
 if not game._staff_walkable(cell) or game._is_station_workface(cell):return false
 for zone in litter_exclusions:
  if zone.has_point(cell):return false
 # There are no persisted zone labels in this baseline. Reserve the kitchen
 # station neighborhoods; future explicit zones use litter_exclusions above.
 for item in game.model.items:
  if str(item.kind) in KITCHEN_KINDS and Rect2i(Vector2i(int(item.x)-1,int(item.z)-1),Vector2i(3,3)).has_point(cell):return false
 return true
func record(staff:Dictionary)->Dictionary:return messes.get(int(staff.get("job_mess_id",-1)),{})
func needed(entry:Dictionary,action:String,debris_kind="")->bool:
 match action:
  "sweeping":return entry.floor_debris in ["banana","crumbs"] and entry.trash_owner=="floor" and (debris_kind=="" or entry.floor_debris==debris_kind)
  "disposing_trash":return entry.trash_owner in ["staff","bin"]
  "mopping":return entry.floor_spill and not entry.spill_cleaned
 return false
func assign(staff:Dictionary,index:int):
 if staff.role!="cleaner" or staff.job_kind!="":return
 var from=Vector2i(floori(staff.pos.x),floori(staff.pos.y));var chosen={};var blocked={};var shortest=1000000
 for entry in messes.values():
  var busy=false
  for other in game.staff_states:
   if other.job_kind=="floor" and int(other.get("job_mess_id",-1))==int(entry.id):busy=true;break
  if busy:continue
  var work_cell=geometry.destination(entry,staff,from,[])
  if work_cell==Vector2i(-1,-1):
   if blocked.is_empty():blocked=entry
   continue
  var route=game._static_service_path(from,work_cell)
  if route.size()<shortest:chosen=entry;shortest=route.size()
 if chosen.is_empty():
  if not blocked.is_empty():
   staff.blocked_reason="Floor cleanup side blocked · make space beside the mess in Decorate";staff.blocked_target_id=-1000000-int(blocked.id);staff.blocked_guest_id=-1
  return
 staff.job_kind="floor";staff.job_mess_id=int(chosen.id);staff.job_guest_id=-1;staff.job_token=int(chosen.token);staff.job_step=0;staff.job_elapsed=0.0;staff.station_id=-1;staff.path.clear();staff.index=0;staff.destination=Vector2i(-100,-100);staff.yield_time=0.0;staff.blocked_reason="";staff.blocked_target_id=-1;staff.blocked_guest_id=-1
 prepare(staff,index)
func release_blocked(staff:Dictionary):
 # Unstarted floor work is a claim, not physical possession. Let another
 # reachable task proceed while the saved mess waits for its space to clear.
 # Started gestures and held/bin trash retain their stage, time and owner.
 if staff.job_kind!="floor" or float(staff.job_elapsed)>0.0 or int(staff.job_step)==2:return
 var entry=record(staff)
 if entry.is_empty() or str(entry.trash_owner) in ["staff","bin"]:return
 var from=Vector2i(floori(staff.pos.x),floori(staff.pos.y))
 if geometry.destination(entry,staff,from,[])==Vector2i(-1,-1):game._clear_service_job(staff)
func prepare(staff:Dictionary,index:int):
 if staff.job_kind!="floor":return
 var entry=record(staff)
 if entry.is_empty():game._clear_service_job(staff);return
 var current=mini(int(staff.job_step),STEPS.size()-1);var action=str(STEPS[current].action)
 var forced=entry.trash_owner=="staff" and int(entry.trash_staff_index)==index and action not in ["sweeping","disposing_trash"]
 var desired=int(staff.job_step)
 if forced:desired=2
 elif float(staff.job_elapsed)<=0:
  desired=STEPS.size()
  for i in range(STEPS.size()):
   if needed(entry,STEPS[i].action,STEPS[i].get("debris_kind","")):desired=i;break
 if desired>=STEPS.size():
  messes.erase(int(entry.id));completed+=1;game._clear_service_job(staff);return
 if desired!=int(staff.job_step):staff.job_step=desired;staff.job_elapsed=0.0;staff.path.clear();staff.index=0;staff.destination=Vector2i(-100,-100)
 if STEPS[desired].kind=="floor":staff.station_id=-1;return
 var station=game.model.get_item(int(staff.station_id))
 if not station.is_empty() and station.kind=="bin":return
 station=game._service_station("bin",Vector2i(floori(staff.pos.x),floori(staff.pos.y)),index)
 staff.station_id=int(station.id) if not station.is_empty() else -1
 staff.blocked_reason="" if not station.is_empty() else "Bin sides blocked · clear any adjacent side"
func target(staff:Dictionary)->Dictionary:
 var entry=record(staff)
 if entry.is_empty() or int(staff.job_step)>=STEPS.size():return {}
 if STEPS[int(staff.job_step)].kind=="bin":return game.model.get_item(int(staff.station_id))
 return {"id":-1000000-int(entry.id),"kind":"floor","x":entry.floor_cell.x,"z":entry.floor_cell.y,"rot":0}
func destination(staff:Dictionary,from:Vector2i,claimed:Array)->Vector2i:
 var entry=record(staff)
 if entry.is_empty():return Vector2i(-1,-1)
 return geometry.destination(entry,staff,from,claimed)
func destination_for_record(entry:Dictionary,staff:Dictionary,from:Vector2i,claimed:Array)->Vector2i:
 return geometry.destination(entry,staff,from,claimed)
func contact_target(entry:Dictionary,staff:Dictionary,action:String)->Vector2:
 return geometry.contact_target(entry,staff,action)
static func validate_geometry(entry:Dictionary,codec)->String:
 return Geometry.validate(entry,codec)
func payload(staff:Dictionary,index:int)->String:
 var entry=record(staff)
 return "trash" if not entry.is_empty() and entry.trash_owner=="staff" and int(entry.trash_staff_index)==index else "none"
func contact(staff:Dictionary,index:int,action:String,target_item:Dictionary,phase:float):
 var entry=record(staff)
 if entry.is_empty():return
 if action=="sweeping" and phase>=1.0:entry.trash_owner="staff";entry.trash_staff_index=index;entry.trash_target_id=-1
 elif action=="disposing_trash" and phase>=.65:
  entry.trash_owner="disposed" if phase>=1 else "bin";entry.trash_staff_index=-1;entry.trash_target_id=int(target_item.id) if phase<1 else -1
 elif action=="mopping":
  entry.spill_remaining=minf(float(entry.spill_remaining),1.0-smoothstep(0.0,1.0,phase))
  if phase>=1:entry.spill_cleaned=true;entry.spill_remaining=0.0
func complete_step(staff:Dictionary,index:int):
 staff.job_step+=1;staff.job_elapsed=0.0;prepare(staff,index)
static func _walk_position_valid(walk:Dictionary,guest:Dictionary,codec)->bool:
 if codec._point(walk.get("pos")) and codec._cell(walk.get("cell")):return true
 # Only customer provenance can extend to the original street ends. The
 # runtime codec validates this guest before passing it to this ledger.
 # Require its exact current position and derived cell; staff/litter targets
 # retain their ordinary bounds, and earned drop history stays untouched.
 var pos=walk.get("pos");var cell=walk.get("cell")
 if not codec._street_point(pos) or not cell is Vector2i or cell!=Vector2i(pos.floor()):return false
 if guest.get("street_route_format")!="little_leaf.street_endpoints.v1":return false
 if guest.get("phase")!="arriving" and not (guest.get("phase")=="leaving" and guest.get("withdrawn",false)):return false
 return pos.distance_to(Vector2(float(guest.x),float(guest.z)))<.00001
static func validate_snapshot(data,staff:Array,item_map:Dictionary,guests:Dictionary,codec)->Dictionary:
 if not data is Dictionary or not codec._integer(data.get("next_id"),1,1000000000) or not codec._integer(data.get("completed"),0,1000000000) or not data.get("messes") is Array or data.messes.size()>MAX_MESSES or not data.get("walks") is Array or data.walks.size()>60:return {"ok":false,"error":"Invalid independent floor task ledger"}
 var ids={};var cells={};var hands={}
 for entry in data.messes:
  if not entry is Dictionary or not codec._integer(entry.get("id"),1,int(data.next_id)-1) or ids.has(int(entry.id)) or entry.get("token")!=entry.id or not codec._cell(entry.get("floor_cell")):return {"ok":false,"error":"Invalid floor task identity"}
  if cells.has(entry.floor_cell):return {"ok":false,"error":"Two messes occupy one floor cell"}
  cells[entry.floor_cell]=true
  for key in ["floor_target","debris_target","spill_target"]:
   if not codec._point(entry.get(key)):return {"ok":false,"error":"Invalid floor mess position"}
  var geometry_error=validate_geometry(entry,codec)
  if geometry_error!="":return {"ok":false,"error":geometry_error}
  if entry.get("floor_debris") not in ["none","banana","crumbs"] or entry.get("trash_owner") not in ["none","floor","staff","bin","disposed"] or not codec._number(entry.get("spill_remaining"),0,1):return {"ok":false,"error":"Invalid floor payload"}
  for key in ["floor_spill","spill_cleaned","floor_dirty","floor_cleaned"]:
   if not entry.get(key) is bool:return {"ok":false,"error":"Invalid floor flag"}
  if entry.spill_cleaned and float(entry.spill_remaining)>0:return {"ok":false,"error":"Clean floor retains water"}
  if entry.floor_debris=="none" and entry.trash_owner!="none":return {"ok":false,"error":"Floor trash has no debris"}
  if not codec._integer(entry.get("trash_staff_index"),-1,staff.size()-1) or not codec._integer(entry.get("trash_target_id"),-1,1000000000):return {"ok":false,"error":"Invalid floor owner"}
  if entry.trash_owner=="staff":
   var index=int(entry.trash_staff_index)
   if index<0 or hands.has(index) or not staff[index] is Dictionary or staff[index].get("role")!="cleaner" or staff[index].get("job_kind")!="floor" or int(staff[index].get("job_mess_id",-1))!=int(entry.id):return {"ok":false,"error":"Floor garbage holder mismatch"}
   if int(staff[index].get("job_step",-1)) not in [0,1,2]:return {"ok":false,"error":"Floor dustpan held during incompatible work"}
   hands[index]=true
  elif int(entry.trash_staff_index)!=-1:return {"ok":false,"error":"Unheld floor trash retains hand"}
  if entry.trash_owner=="bin":
   if not item_map.has(int(entry.trash_target_id)) or item_map[int(entry.trash_target_id)].kind!="bin":return {"ok":false,"error":"Floor garbage bin missing"}
  elif int(entry.trash_target_id)!=-1:return {"ok":false,"error":"Unplaced floor trash retains bin"}
  ids[int(entry.id)]=entry
 var walkers={}
 for walk in data.walks:
  if not walk is Dictionary or not codec._integer(walk.get("guest_id"),1,1000000000) or walkers.has(int(walk.guest_id)) or not guests.has(int(walk.guest_id)) or not _walk_position_valid(walk,guests[int(walk.guest_id)],codec) or not codec._integer(walk.get("inside_steps"),0,1000000) or not walk.get("dropped") is bool:return {"ok":false,"error":"Invalid walking mess source"}
  walkers[int(walk.guest_id)]=true
 return {"ok":true,"records":ids}
