extends SceneTree
const Model=preload("res://scripts/core/cafe_model.gd")
const Openings=preload("res://scripts/gameplay/cafe_wall_openings.gd")
const Footprint=preload("res://scripts/gameplay/cafe_footprint.gd")
const Codec=preload("res://scripts/persistence/cafe_runtime_codec.gd")
const Building=preload("res://scripts/persistence/cafe_building_codec.gd")
const Contract=preload("res://scripts/persistence/cafe_save_contract.gd")
const OUT="user://door-grid-fixtures"
# Immutable pre-unification writer output, not a relabelled current save.
const LEGACY_SHA="28e44539834a07dd7e4066bc0dfce41b682e121d0b31f2e39a2c56cb8bdb62eb"
var checks=0
var failures=[]
var guest_template={}
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
func same_saved_attachments(before:Array,after:Array)->bool:
 # Import geometry uses Vector2 precision; the full-precision JSON reader can
 # then round a scalar offset by one float64 ULP. Match that exact wire form,
 # not a blanket epsilon. All identity/support/width/value fields stay exact,
 # and the normalized offset must still represent the identical Vector2.
 if before.size()!=after.size():return false
 for index in before.size():
  var expected=before[index].duplicate(true)
  var wire=JSON.parse_string(JSON.stringify({"offset":expected.offset},"",true,true))
  if Vector2(float(wire.offset),0)!=Vector2(float(expected.offset),0):return false
  expected.offset=wire.offset
  if not same(after[index],expected):return false
 return true
func read(path:String)->Dictionary:return JSON.parse_string(FileAccess.get_file_as_string(path))
func write(path:String,data:Dictionary):
 var file=FileAccess.open(path,FileAccess.WRITE)
 if file==null:check(false,"write generated fixture "+path);return
 file.store_string(JSON.stringify(Codec.new().encode(data),"\t",true,true));file.close()
func fixture_path()->String:
 var directory=OS.get_environment("UNIFIED_LEGACY_FIXTURE_DIR")
 return ("res://tests/fixtures/unified_building" if directory=="" else directory).path_join("historical.json")
func legacy(width:float=1.5)->Dictionary:
 var data=read(fixture_path());data.coins=54321;data.wall_attachments[0].width=width
 return data
func guest_fixture()->Dictionary:
 # Only the runtime record comes from the real current customer factory. The
 # building/header/items below remain the actual legacy fixture schema.
 var data=legacy();data.runtime.customers=[guest_template.duplicate(true)]
 data.runtime.next_customer_id=int(guest_template.id)+1
 return data
func rear_threshold(data:Dictionary,clear_bookshelf:bool=true):
 # Keep the historical bookshelf move and real corridor gap in source data.
 # A rear opening alone is not a public exit under the corridor rule.
 if clear_bookshelf:
  for item in data.items:
   if int(item.id)==12:item.x=7;item.z=0
 data.shell_segment_products["shell:west#7"].removed=true
func current_roundtrip(model,label:String,expected_width:float,original_hash:String=""):
 var path=OUT+"/"+label+"-current.json"
 var saved=model.save(path);check(saved,label+" current save: "+model.last_error)
 if not saved:return null
 var source_hash=FileAccess.get_sha256(path);var payload=read(path)
 check(payload.wall_format==Building.WALL_FORMAT and payload.building_format==Building.FORMAT and payload.wall_attachment_format==Building.ATTACHMENT_FORMAT,label+" current building header")
 if original_hash!="":check(FileAccess.get_sha256(path+".pre-grid-"+original_hash+".json")==original_hash,label+" exact original recovery bytes")
 var loaded=Model.new();var ok=loaded.load_save(path)
 check(ok,label+" current load: "+loaded.last_error)
 if not ok:return null
 check(FileAccess.get_sha256(path)==source_hash,label+" current source bytes unchanged")
 check(loaded.wall_attachments[0].width==expected_width,label+" aperture width preserved")
 check(same_saved_attachments(model.wall_attachments,loaded.wall_attachments),label+" exact attachment identity/support/width/value and saved offset")
 check(loaded.coins==model.coins and loaded.owned_parcels==model.owned_parcels,label+" wallet and plots preserved")
 check(same(loaded.items,model.items) and same(loaded.floor_finishes,model.floor_finishes) and same(loaded.built_walls,model.built_walls),label+" furniture/walls/floors preserved")
 check(same(loaded.customers,model.customers) and same(loaded.service_snapshot,model.service_snapshot),label+" actors/jobs/routes preserved")
 var again_path=OUT+"/"+label+"-again.json"
 saved=loaded.save(again_path);check(saved,label+" save again: "+loaded.last_error)
 if not saved:return null
 var again=Model.new();ok=again.load_save(again_path);check(ok,label+" reload: "+again.last_error)
 if ok:
  check(same(again.wall_attachments,loaded.wall_attachments) and same(again.built_walls,loaded.built_walls),label+" stable repeated building load")
  check(same(again.customers,loaded.customers) and same(again.service_snapshot,loaded.service_snapshot),label+" stable repeated runtime load")
 return loaded
func check_imported_openings(model,data:Dictionary,label:String):
 var originals=data.wall_attachments
 if int(data.version)<5:
  originals=[{"id":1,"kind":"door","host_id":"shell:west","offset":5.5,"width":1.5,"paid_cost":0}]
 check(model.wall_attachments.size()==originals.size(),label+" attachment count preserved")
 if model.wall_attachments.size()!=originals.size():return
 for index in originals.size():
  var old=originals[index];var installed=model.wall_attachments[index]
  var root=str(old.host_id);var center=float(old.offset);var width=float(old.width)
  var low=center-width*.5;var high=center+width*.5;var supports=[]
  for unit in range(Footprint.WIDTH if root=="shell:back" else Footprint.DEPTH):
   if minf(high,float(unit+1))-maxf(low,float(unit))>.00001:supports.append(root+"#"+str(unit))
  check(not installed.has("host_id") and installed.wall_ids==supports,label+" exact ordered supporting wall IDs "+str(index))
  check(installed.id==old.id and installed.kind==old.kind and installed.paid_cost==old.paid_cost and float(installed.width)==width,label+" attachment identity/width/value preserved "+str(index))
  var aperture=Openings.aperture(installed,model.built_walls)
  check(not aperture.is_empty(),label+" supported aperture "+str(index))
  if aperture.is_empty():continue
  var a=Vector2(low,0) if root=="shell:back" else Vector2(0,low)
  var b=Vector2(high,0) if root=="shell:back" else Vector2(0,high)
  check(aperture.a.distance_to(a)<.000001 and aperture.b.distance_to(b)<.000001,label+" exact world aperture and center "+str(index))
  # Match the scalar projected from the legacy aperture's actual Vector2
  # endpoints, not float64 subtraction of the original decimal center.
  var direction=Vector2.RIGHT if root=="shell:back" else Vector2.DOWN
  var legacy_center=direction*center
  var legacy_a=legacy_center-direction*width*.5;var legacy_b=legacy_center+direction*width*.5
  var relative=(legacy_a+legacy_b)*.5-direction*float(supports[0].get_slice("#",1))
  var projected_offset=relative.x if root=="shell:back" else relative.y
  check(float(installed.offset)==projected_offset,label+" exact projected offset relative to first installed support "+str(index))
 check(Openings.installed_support_error(model.built_walls,model.wall_attachments)=="",label+" complete opening support")
func check_imported_walls(model,data:Dictionary,label:String):
 var expected_count=0
 # These cases originate from the untouched historical shell, with explicit
 # removals only. They never invent a modern wall then relabel it as legacy.
 for root in ["shell:back","shell:west"]:
  for unit in range(Footprint.WIDTH if root=="shell:back" else Footprint.DEPTH):
   var id=root+"#"+str(unit);var receipt=data.get("shell_segment_products",{}).get(id,{"height":"full","material":"original","paid_cost":0,"refund_credit":0})
   var matches=model.built_walls.filter(func(wall):return wall.id==id)
   if receipt.get("removed",false):check(matches.is_empty(),label+" removed wall stays absent "+id);continue
   expected_count+=1;check(matches.size()==1,label+" installed wall identity "+id)
   if matches.size()!=1:continue
   var wall=matches[0]
   check(wall.axis==("x" if root=="shell:back" else "z") and wall.x==(unit if root=="shell:back" else 0) and wall.z==(0 if root=="shell:back" else unit),label+" wall edge preserved "+id)
   check(wall.height==receipt.height and wall.material==receipt.material and wall.paid_cost==receipt.paid_cost and wall.refund_credit==receipt.refund_credit,label+" wall product/value preserved "+id)
 check(model.built_walls.size()==expected_count,label+" no missing or invented walls")
func import_roundtrip(data:Dictionary,label:String):
 var path=OUT+"/"+label+"-legacy.json";write(path,data)
 var source_hash=FileAccess.get_sha256(path);var loaded=Model.new()
 var ok=loaded.load_save(path);check(ok,label+" real legacy-schema load: "+loaded.last_error)
 check(FileAccess.get_sha256(path)==source_hash,label+" legacy source bytes unchanged")
 if not ok:return null
 check_imported_openings(loaded,data,label);check_imported_walls(loaded,data,label)
 check(loaded.coins==data.coins and same(loaded.owned_parcels,data.owned_parcels),label+" imported wallet and plots preserved")
 check(same(loaded.items,data.items) and same(loaded.floor_finishes,data.floor_finishes),label+" imported furniture/floors preserved")
 if int(data.version)>=3:
  check(same(Codec.new().encode(loaded.customers),Codec.new().encode(data.runtime.customers)) and same(Codec.new().encode(loaded.service_snapshot),Codec.new().encode(data.runtime.service)),label+" imported actors/jobs/routes preserved")
  check(loaded._next_customer_id==data.runtime.next_customer_id and loaded._walking_customer_id==data.runtime.walking_customer_id,label+" imported runtime sequences preserved")
 var expected_width=1.5 if int(data.version)<5 else float(data.wall_attachments[0].width)
 var result=current_roundtrip(loaded,label,expected_width,source_hash)
 check(FileAccess.get_sha256(path)==source_hash,label+" original stays unchanged after current saves")
 return result
func staff_snapshot(position:Vector2,route:Array=[],index:int=0)->Dictionary:
 var staff=[]
 for role in ["chef","waiter","cleaner"]:
  staff.append({"role":role,"on_duty":true,"duty_pending":false,"pos":position if role=="chef" else Vector2(2.5,6.5 if role=="waiter" else 7.5),"destination":Vector2i(-100,-100),"path":route if role=="chef" else [],"index":index if role=="chef" else 0,"job_kind":"","job_step":0,"job_elapsed":0.0,"station_id":-1,"job_guest_id":-1,"job_token":-1})
 return {"version":Contract.SERVICE_VERSION,"checkout_format":Contract.CHECKOUT_FORMAT,"serial":0,"records":[],"staff":staff,"animation_time":0.0,"dishwashing":{"format":"little_leaf.dishwashing.v1","next_id":1,"completed":0,"dishes":[]}}
func finish():
 check(FileAccess.get_sha256(fixture_path())==LEGACY_SHA,"immutable pre-unification fixture remains byte exact")
 var report={"checks":checks,"failures":failures};write(OUT+"/REPORT.json",report)
 print("STARTER_DOOR_GRID_RESULT ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
func _init():
 if not "geometry-saveguard" in OS.get_user_data_dir():printerr("SAVEGUARD FAILED");quit(2);return
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
 check(FileAccess.get_sha256(fixture_path())==LEGACY_SHA,"pinned pre-unification fixture bytes")
 if not failures.is_empty():finish();return
 var model=Model.new();var door=model.wall_openings()[0]
 check(door.a==Vector2(0,5) and door.b==Vector2(0,6),"fresh rendered aperture exactly meets grid boundaries 5/6")
 check(door.width==1.0 and (door.a+door.b)*.5==Vector2(0,5.5),"fresh center unchanged and one tile wide")
 check(model.wall_attachments[0].wall_ids==["wall:18"] and model.wall_attachments[0].offset==.5,"fresh door uses its installed grid support")
 check(Model.ENTRANCE==Footprint.ENTRANCE and Model.ENTRY_LANDING==Footprint.ENTRY_LANDING and Model.EXTERIOR_DOOR.y==Footprint.DOOR_CENTER,"landing and arrival share footprint source")
 check(Model.ENTRANCE==Vector2i(0,5) and Model.ENTRY_LANDING==Vector2i(1,5),"arrival cells remain original grid row")
 for z in range(9):
  check(model.edge_blocked(Vector2i(-1,z),Vector2i(0,z))==(z!=5),"grid crossing at row "+str(z))
  check(model.edge_blocked(Vector2i(0,z),Vector2i(-1,z))==(z!=5),"reverse grid crossing at row "+str(z))
 for z in [4.8,4.99,5.01,5.24,5.5,5.76,5.99,6.01,6.2]:
  check(model.segment_blocked(Vector2(-.6,z),Vector2(.6,z))==(z<5.0 or z>6.0),"continuous crossing at "+str(z))
  check(Openings.point_in_door(Vector2(0,z),door.host,model.built_walls,model.wall_attachments,.23)==(z>5.23 and z<5.77),"body clearance at "+str(z))
 check(model._opening_body_error(model.built_walls,model.wall_attachments,[Vector2(-.1,5.5)])=="","saved body fits center lane")
 check(not model.path_between(Vector2i(0,5),Vector2i(2,5)).is_empty(),"arrival path reaches landing")
 check(not model.path_between(Vector2i(2,5),Vector2i(0,5)).is_empty(),"exit path crosses centered door")
 for cell in [Model.ENTRANCE,Model.ENTRY_LANDING]:
  check(model.can_place("plant",cell.x,cell.y),"idle owned landing accepts physical fit "+str(cell))
  check(not model.can_place("plant",cell.x,cell.y,-1,0,[model.cell_center(cell)]),"actual body still protects landing "+str(cell))
 current_roundtrip(model,"fresh",1.0)
 # Grid297 never resizes imported apertures, including clear free 1.5 doors
 # and historical .76 doors. Preserve all former resize/exception scenarios.
 import_roundtrip(legacy(),"old-clear")
 for change in [{"id":9},{"offset":5.6},{"offset":5.50001},{"host_id":"shell:back"},{"paid_cost":40}]:
  var customized=legacy()
  for key in change:customized.wall_attachments[0][key]=change[key]
  if change.get("host_id","")=="shell:back":rear_threshold(customized)
  customized.next_attachment_id=10
  import_roundtrip(customized,"custom-"+str(checks))
 var moved=legacy(.76);moved.wall_attachments[0].paid_cost=40
 import_roundtrip(moved,"paid-standard")
 for change in [{},{"id":9},{"offset":5.6},{"host_id":"shell:back"}]:
  var narrow=legacy(.76);narrow.wall_attachments[0].paid_cost=40
  for key in change:narrow.wall_attachments[0][key]=change[key]
  if change.get("host_id","")=="shell:back":rear_threshold(narrow)
  narrow.next_attachment_id=10
  import_roundtrip(narrow,"narrow-custom-"+str(checks))
 import_roundtrip(legacy(.76),"narrow-free")
 var boundary=legacy(.76);boundary.wall_attachments[0].host_id="shell:back";boundary.wall_attachments[0].offset=.4;rear_threshold(boundary,false)
 import_roundtrip(boundary,"narrow-host-boundary")
 var crowded=legacy(.76)
 crowded.wall_attachments.append({"id":2,"kind":"window","host_id":"shell:west","offset":6.3,"width":.70,"paid_cost":30});crowded.next_attachment_id=3
 import_roundtrip(crowded,"narrow-neighbor-opening")
 var unsupported=legacy(.76);unsupported.wall_attachments[0].offset=5.4
 unsupported.shell_segment_products["shell:west#4"].removed=true
 import_roundtrip(unsupported,"narrow-missing-support")
 moved=legacy(1.0);moved.wall_attachments[0].offset=5.6
 import_roundtrip(moved,"aligned-moved")
 # Generate a real guest record against the imported layout. No old-model
 # substitute or fake runtime API is used to construct legacy building data.
 var guest_model=Model.new();var loaded=guest_model.load_save(fixture_path())
 check(loaded,"runtime factory imports real fixture: "+guest_model.last_error)
 if not loaded:finish();return
 guest_model._spawn_customer();check(not guest_model.customers.is_empty(),"runtime factory spawns a real guest")
 if guest_model.customers.is_empty():finish();return
 guest_template=guest_model.customers[0].duplicate(true)
 for z in [5.05,5.95,5.5]:
  var crossing=guest_fixture();var guest=crossing.runtime.customers[0]
  guest.x=-.12;guest.z=z;guest.route=[Vector2(.5,z),Vector2(.5,5.5)]
  import_roundtrip(crossing,"guest-body-"+str(z))
 for z in [5.05,5.95,5.5]:
  var approaching=guest_fixture();var guest=approaching.runtime.customers[0]
  guest.x=-.8;guest.z=z;guest.route=[Vector2(.5,z),Vector2(.5,5.5)]
  import_roundtrip(approaching,"guest-route-"+str(z))
 var completed=guest_fixture();var completed_guest=completed.runtime.customers[0]
 completed_guest.x=.5;completed_guest.z=5.5;completed_guest.route=[Vector2(.5,5.05),Vector2(.5,5.5)];completed_guest.route_index=1
 import_roundtrip(completed,"completed-prefix")
 for z in [5.05,5.95,5.5]:
  var worker=legacy();worker.runtime.service=staff_snapshot(Vector2(-.12,z))
  var restored=import_roundtrip(worker,"staff-body-"+str(z))
  if restored!=null and z!=5.5:
   restored.service_snapshot.staff[0].pos=Vector2(1.5,5.5)
   current_roundtrip(restored,"staff-clear-later-"+str(z),1.5)
 var worker=legacy();worker.runtime.service=staff_snapshot(Vector2(-.8,5.05),[Vector2i(0,5)])
 import_roundtrip(worker,"staff-diagonal-route")
 var relocating=guest_fixture();var guest=relocating.runtime.customers[0]
 guest.phase="ordering";guest.x=.1;guest.z=5.5;guest.route=[];guest.route_index=0;guest.admitted=true
 var chair=guest_model.get_item(int(guest.chair_id));var seat=Vector2(float(chair.x)+.5,float(chair.z)+.5)
 guest.mobility={"kind":"to_assigned_seat","origin":Vector2(.1,5.5),"route":[Vector2(.1,5.05),Vector2(seat.x,5.05),seat],"route_index":0}
 import_roundtrip(relocating,"mobility-future-jamb")
 guest.mobility.route_index=2;guest.x=seat.x;guest.z=5.05
 import_roundtrip(relocating,"mobility-consumed-jamb")
 var later=guest_fixture();var later_guest=later.runtime.customers[0]
 later_guest.x=-.8;later_guest.z=5.5;later_guest.route=[Vector2(-.8,5.05),Vector2(.5,5.05),Vector2(.5,5.5)]
 import_roundtrip(later,"guest-later-route")
 var worker_later=legacy();worker_later.runtime.service=staff_snapshot(Vector2(-.8,5.5),[Vector2i(-1,4),Vector2i(0,5)])
 import_roundtrip(worker_later,"staff-later-route")
 worker_later.runtime.service.staff[0].pos=Vector2(.5,5.5);worker_later.runtime.service.staff[0].index=2
 import_roundtrip(worker_later,"staff-consumed-route")
 # Earlier headers are variants of real legacy-schema bytes, never a current
 # wall_format=4 payload with only the marker changed. Implicit v1/v3 doors
 # retain 1.5 as well; the original source and its recovery copy stay exact.
 for version in [1,3,5,11,15]:
  var data=legacy();data.version=version;data.erase("starter_geometry_version")
  data.wall_format=1;data.erase("shell_segment_format");data.erase("shell_segment_products")
  if version<15:data.erase("layout_motion_format");data.runtime.erase("layout_motion_format")
  if version<13:data.duty_counts.erase("cashier");data.duty_targets.erase("cashier");data.runtime.erase("checkout_format");data.runtime.erase("next_checkout_ticket")
  import_roundtrip(data,"legacy-v%d"%version)
 finish()
