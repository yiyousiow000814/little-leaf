extends RefCounted
const Layout=preload("res://scripts/cafe_stove_layout.gd")
## One physical output slot per stove. Legacy reservations finish in place;
## purchased counters are retained and never refunded or discarded on load.
static func output_id(record:Dictionary)->int:
 if bool(record.get("pass_reserved",false)) or str(record.get("plate_owner",""))=="counter":return int(record.get("meal_pass_id",-1))
 return int(record.get("meal_station_id",-1))

static func deposit(record:Dictionary,target:Dictionary):
 record.plate_owner="counter" if str(target.kind)=="counter" else "station"
 record.plate_staff_index=-1
 record.plate_target_id=int(target.id)

static func prepared(record:Dictionary)->bool:
 return str(record.get("plate_owner",""))=="station" and int(record.get("plate_target_id",-1))==int(record.get("meal_station_id",-2))

static func plate_anchor(rotation:int)->Vector2:
 return preload("res://scripts/kitchen_worktop_geometry.gd").surface(Layout.OUTPUT_CENTER,31.0,rotation)

static func needs_pickup_space(station_id:int,records:Dictionary,workers:Array)->bool:
 for record in records.values():
  if str(record.get("plate_owner",""))=="station" and int(record.get("plate_target_id",-1))==station_id:return true
 for worker in workers:
  if str(worker.get("job_kind",""))=="deliver_meal" and int(worker.get("job_step",-1))==0 and int(worker.get("station_id",-1))==station_id:return true
 return false
