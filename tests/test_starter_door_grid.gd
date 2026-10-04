extends SceneTree
const Model=preload("res://scripts/cafe_model.gd")
const Openings=preload("res://scripts/cafe_wall_openings.gd")
const Footprint=preload("res://scripts/cafe_footprint.gd")
const Codec=preload("res://scripts/cafe_runtime_codec.gd")
const Contract=preload("res://scripts/cafe_save_contract.gd")
const OUT="user://door-grid-fixtures"
var checks=0
var failures=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func same(a,b)->bool:
 if (a is int or a is float) and (b is int or b is float):return float(a)==float(b)
 if a is Dictionary and b is Dictionary:
  if a.size()!=b.size():return false
  for key in a:
   if not b.has(key) or not same(a[key],b[key]):return false
  return true
 if a is Array and b is Array:
  if a.size()!=b.size():return false
  for i in range(a.size()):
   if not same(a[i],b[i]):return false
  return true
 return a==b
func read(path:String)->Dictionary:return JSON.parse_string(FileAccess.get_file_as_string(path))
func write(path:String,data:Dictionary):
 var file=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(data,"\t",true,true));file.close()
func legacy():
 var model=Model.new();model.coins=54321;model.wall_attachments[0].width=1.5
 return model
func roundtrip(model,label:String,expected_width:float):
 var path=OUT+"/"+label+".json"
 check(model.save(path),label+" synthetic save: "+model.last_error)
 if not FileAccess.file_exists(path):return null
 var source_hash=FileAccess.get_sha256(path);var before=read(path)
 var loaded=Model.new()
 check(loaded.load_save(path),label+" load: "+loaded.last_error)
 check(loaded.wall_attachments[0].width==expected_width,label+" aperture width")
 check(FileAccess.get_sha256(path)==source_hash,label+" source bytes unchanged")
 var expected=model.wall_attachments.duplicate(true);expected[0].width=expected_width
 check(same(loaded.wall_attachments,expected),label+" exact attachment identity/host/value")
 check(loaded.coins==model.coins and loaded.owned_parcels==model.owned_parcels,label+" wallet and plots preserved")
 check(same(loaded.items,model.items) and same(loaded.floor_finishes,model.floor_finishes) and same(loaded.built_walls,model.built_walls),label+" furniture/walls/floors preserved")
 check(same(loaded.customers,model.customers) and same(loaded.service_snapshot,model.service_snapshot),label+" actors/jobs/routes preserved")
 check(loaded.save(OUT+"/roundtrip.json"),label+" save again")
 var again=Model.new();check(again.load_save(OUT+"/roundtrip.json"),label+" reload")
 check(same(again.wall_attachments,loaded.wall_attachments),label+" stable repeated load")
 return loaded
func staff_snapshot(position:Vector2,route:Array=[],index:int=0)->Dictionary:
 var staff=[]
 for role in ["chef","waiter","cleaner"]:
  staff.append({"role":role,"on_duty":true,"duty_pending":false,"pos":position if role=="chef" else Vector2(2.5,6.5 if role=="waiter" else 7.5),"destination":Vector2i(-100,-100),"path":route if role=="chef" else [],"index":index if role=="chef" else 0,"job_kind":"","job_step":0,"job_elapsed":0.0,"station_id":-1,"job_guest_id":-1,"job_token":-1})
 return {"version":Contract.SERVICE_VERSION,"checkout_format":Contract.CHECKOUT_FORMAT,"serial":0,"records":[],"staff":staff,"animation_time":0.0}
func _init():
 if not "geometry-saveguard" in OS.get_user_data_dir():printerr("SAVEGUARD FAILED");quit(2);return
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
 var model=Model.new();var door=model.wall_openings()[0]
 check(door.a==Vector2(0,5) and door.b==Vector2(0,6),"fresh rendered aperture exactly meets grid boundaries 5/6")
 check(door.width==1.0 and (door.a+door.b)*.5==Vector2(0,5.5),"fresh center unchanged and one tile wide")
 check(Model.ENTRANCE==Footprint.ENTRANCE and Model.ENTRY_LANDING==Footprint.ENTRY_LANDING and Model.EXTERIOR_DOOR.y==Footprint.DOOR_CENTER,"landing and arrival share footprint source")
 check(Model.ENTRANCE==Vector2i(0,5) and Model.ENTRY_LANDING==Vector2i(1,5),"protected cells remain original grid row")
 for z in range(9):
  check(model.edge_blocked(Vector2i(-1,z),Vector2i(0,z))==(z!=5),"grid crossing at row "+str(z))
  check(model.edge_blocked(Vector2i(0,z),Vector2i(-1,z))==(z!=5),"reverse grid crossing at row "+str(z))
 for z in [4.8,4.99,5.01,5.24,5.5,5.76,5.99,6.01,6.2]:
  check(model.segment_blocked(Vector2(-.6,z),Vector2(.6,z))==(z<5.0 or z>6.0),"continuous crossing at "+str(z))
  check(Openings.point_in_door(Vector2(0,z),door.host,[],model.wall_attachments,.23)==(z>5.23 and z<5.77),"body clearance at "+str(z))
 check(model._opening_body_error([],model.wall_attachments,[Vector2(-.1,5.5)])=="","saved body fits center lane")
 check(not model.path_between(Vector2i(0,5),Vector2i(2,5)).is_empty(),"arrival path reaches landing")
 check(not model.path_between(Vector2i(2,5),Vector2i(0,5)).is_empty(),"exit path crosses centered door")
 for cell in [Model.ENTRANCE,Model.ENTRY_LANDING]:check(not model.can_place("plant",cell.x,cell.y),"landing stays protected "+str(cell))
 roundtrip(model,"fresh",1.0)
 roundtrip(legacy(),"old-clear",1.0)
 # A matching legacy door only: altered IDs/host/position/paid value stay exact.
 for change in [{"id":9},{"offset":5.6},{"offset":5.50001},{"host_id":"shell:back"},{"paid_cost":40}]:
  var customized=legacy()
  for key in change:customized.wall_attachments[0][key]=change[key]
  customized._next_attachment_id=10
  var label="custom-"+str(checks)
  roundtrip(customized,label,1.5)
 # Purchased standard-width and moved aligned free doors stay valid.
 var moved=legacy();moved.wall_attachments[0].width=.76;moved.wall_attachments[0].paid_cost=40
 roundtrip(moved,"paid-standard",.76)
 moved=Model.new();moved.wall_attachments[0].offset=5.6
 roundtrip(moved,"aligned-moved",1.0)
 # Real model save/load with a guest crossing each newly occupied side strip.
 for z in [5.05,5.95,5.5]:
  var crossing=legacy();crossing._spawn_customer();crossing.customers.resize(1)
  crossing.customers[0].x=-.12;crossing.customers[0].z=z
  crossing.customers[0].route=[Vector2(.5,z),Vector2(.5,5.5)]
  roundtrip(crossing,"guest-body-"+str(z),1.0 if z==5.5 else 1.5)
 for z in [5.05,5.95,5.5]:
  var approaching=legacy();approaching._spawn_customer();approaching.customers.resize(1)
  approaching.customers[0].x=-.8;approaching.customers[0].z=z
  approaching.customers[0].route=[Vector2(.5,z),Vector2(.5,5.5)]
  roundtrip(approaching,"guest-route-"+str(z),1.0 if z==5.5 else 1.5)
 # Completed route prefixes don't prevent a clear migration.
 var completed=legacy();completed._spawn_customer();completed.customers.resize(1)
 completed.customers[0].x=.5;completed.customers[0].z=5.5
 completed.customers[0].route=[Vector2(.5,5.05),Vector2(.5,5.5)];completed.customers[0].route_index=1
 roundtrip(completed,"completed-prefix",1.0)
 for z in [5.05,5.95,5.5]:
  var worker=legacy();worker.service_snapshot=staff_snapshot(Vector2(-.12,z))
  var loaded=roundtrip(worker,"staff-body-"+str(z),1.0 if z==5.5 else 1.5)
  if loaded!=null and z!=5.5:
   loaded.service_snapshot.staff[0].pos=Vector2(1.5,5.5)
   roundtrip(loaded,"staff-clear-later-"+str(z),1.0)
 var worker=legacy();worker.service_snapshot=staff_snapshot(Vector2(-.8,5.05),[Vector2i(0,5)])
 roundtrip(worker,"staff-diagonal-route",1.5)
 # Future relocation and later route legs are checked, not only current bodies.
 var relocating=legacy();relocating._spawn_customer();relocating.customers.resize(1)
 var guest=relocating.customers[0];guest.phase="ordering";guest.x=.1;guest.z=5.5;guest.route=[];guest.route_index=0;guest.admitted=true
 var chair=relocating.get_item(int(guest.chair_id));var seat=Vector2(float(chair.x)+.5,float(chair.z)+.5)
 guest.mobility={"kind":"to_assigned_seat","origin":Vector2(.1,5.5),"route":[Vector2(.1,5.05),Vector2(seat.x,5.05),seat],"route_index":0}
 roundtrip(relocating,"mobility-future-jamb",1.5)
 guest.mobility.route_index=2;guest.x=seat.x;guest.z=5.05
 roundtrip(relocating,"mobility-consumed-jamb",1.0)
 var later=legacy();later._spawn_customer();later.customers.resize(1)
 later.customers[0].x=-.8;later.customers[0].z=5.5
 later.customers[0].route=[Vector2(-.8,5.05),Vector2(.5,5.05),Vector2(.5,5.5)]
 roundtrip(later,"guest-later-route",1.5)
 var worker_later=legacy();worker_later.service_snapshot=staff_snapshot(Vector2(-.8,5.5),[Vector2i(-1,4),Vector2i(0,5)])
 roundtrip(worker_later,"staff-later-route",1.5)
 worker_later.service_snapshot.staff[0].pos=Vector2(.5,5.5);worker_later.service_snapshot.staff[0].index=2
 roundtrip(worker_later,"staff-consumed-route",1.0)
 # Older versions with implicit starter doors still take the same safety gate.
 model=legacy();check(model.save(OUT+"/legacy-base.json"),"legacy base save")
 for version in [1,3,5,11,15]:
  var data=read(OUT+"/legacy-base.json");data.version=version
  if version<15:data.erase("layout_motion_format");data.runtime.erase("layout_motion_format")
  if version<13:data.duty_counts.erase("cashier");data.duty_targets.erase("cashier");data.runtime.erase("checkout_format");data.runtime.erase("next_checkout_ticket")
  var path=OUT+"/legacy-v%d.json"%version;write(path,data);var hash=FileAccess.get_sha256(path)
  var loaded=Model.new();check(loaded.load_save(path),"legacy version %d loads: "%version+loaded.last_error)
  check(loaded.wall_attachments[0].width==1.0,"legacy version %d aligns"%version)
  check(FileAccess.get_sha256(path)==hash,"legacy version %d source unchanged"%version)
 var report={"checks":checks,"failures":failures};write(OUT+"/REPORT.json",report)
 print("STARTER_DOOR_GRID_RESULT ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
