extends SceneTree
const Fixture=preload("res://tests/role_fixture.gd")
const Model=preload("res://scripts/cafe_model.gd")
const Codec=preload("res://scripts/cafe_runtime_codec.gd")
const Contract=preload("res://scripts/cafe_save_contract.gd")
var checks=0
var failures=[]
var game
func _initialize():run.call_deferred()
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func read_json(path):return JSON.parse_string(FileAccess.get_file_as_string(path))
func write_json(path,data):FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(data))
func same_values(a,b)->bool:
 # JSON decodes integral numbers as floats; compare exact numeric values,
 # while retaining array order and every ledger key/value.
 if a is Dictionary and b is Dictionary:
  if a.size()!=b.size():return false
  for key in a:
   if not b.has(key) or not same_values(a[key],b[key]):return false
  return true
 if a is Array and b is Array:
  if a.size()!=b.size():return false
  for i in a.size():
   if not same_values(a[i],b[i]):return false
  return true
 if (a is int or a is float) and (b is int or b is float):return float(a)==float(b)
 return a==b
func run():
 if not "saveguard" in OS.get_user_data_dir():printerr("Use isolated profile");quit(2);return
 game=Fixture.new();root.add_child(game);await process_frame
 game.set_process(false);game.illustration.set_process(false)
 var record=game.setup_dirty();var worker=game.legacy_job(record,5,.35)
 var slot=game.staff_states.find(worker)
 record.trash_owner="staff";record.trash_staff_index=slot;record.trash_target_id=-1
 game.model.service_snapshot=game._service_save_snapshot()
 var baseline=game.model.service_snapshot.duplicate(true)
 var file="user://interrupted-staff-navigation.json"
 var codec=Codec.new()
 check(Contract.VERSION==15 and Contract.PRIMARY_FILE.ends_with("_v15.json"),"default save version/namespace remains15")
 check(not Contract.accepts_version(14,true) and not Contract.accepts_version(16) and Contract.accepts_version(16,true),"navigation requires explicit capability and never admits14")
 for phase in ["follow","replan-leg","replan-center"]:
  var service=baseline.duplicate(true);var row=service.staff[slot]
  row.navigation_phase="follow" if phase=="follow" else "replan"
  row.pos=Vector2(4.72,6.72) if phase!="replan-center" else Vector2(5.5,7.5)
  row.destination=Vector2i(6,7)
  row.path=[Vector2i(4,6),Vector2i(5,7),Vector2i(6,7)] if phase=="follow" else ([Vector2i(4,6),Vector2i(5,7)] if phase=="replan-leg" else [Vector2i(5,7)])
  row.index=1;game.model.service_snapshot=service
  var original=codec.encode(service)
  check(game.model.save(file,true),phase+" saves: "+game.model.last_error)
  var envelope=read_json(file)
  check(envelope.version==16 and envelope.navigation_format==Contract.STAFF_NAVIGATION_FORMAT and envelope.runtime.service.version==5,phase+" uses staff-only capable envelope, service5")
  var loaded=Model.new();var wallet=loaded.coins;var old_items=loaded.items.duplicate(true)
  check(not loaded.load_save(file) and loaded.coins==wallet and loaded.items==old_items,phase+" unsupported default reader refuses atomically")
  check(loaded.load_save(file,false,true),phase+" explicit capable reader loads: "+loaded.last_error)
  var actual=loaded.service_snapshot.staff[slot]
  check(actual.pos==row.pos and actual.path==row.path and actual.index==1 and actual.destination==row.destination and actual.navigation_phase==row.navigation_phase,phase+" reload preserves exact current leg/anchor without snapping")
  check(actual.job_kind==row.job_kind and actual.job_step==5 and actual.job_elapsed==.35 and actual.job_token==row.job_token and actual.job_guest_id==row.job_guest_id,phase+" preserves interrupted job identity and clock")
  var saved_record=loaded.service_snapshot.records[0]
  check(saved_record.trash_owner=="staff" and saved_record.trash_staff_index==slot and loaded.coins==game.model.coins,phase+" preserves payload slot and wallet")
  if not same_values(codec.encode(loaded.service_snapshot),original):print("STAFF_NAVIGATION_COMPARE ",JSON.stringify({"expected":original,"actual":codec.encode(loaded.service_snapshot)}))
  check(same_values(codec.encode(loaded.service_snapshot),original),phase+" preserves all staff order, clocks and claim/payload ledgers")
  check(codec.encode(game.model.service_snapshot)==original,phase+" snapshot validation does not mutate live rows")
  loaded=null
 # Rejected wire mutations are a few representative coherence/capability cases.
 var envelope=read_json(file)
 for bad in ["off-leg","hop","phase","index","unowned-body"]:
  var broken=envelope.duplicate(true);var state=codec.decode(broken.runtime)
  var row=state.service.staff[slot];row.navigation_phase="follow";row.path=[Vector2i(4,6),Vector2i(5,7),Vector2i(6,7)];row.index=1;row.pos=Vector2(4.72,6.72)
  if bad=="off-leg":row.pos.y+=.01
  elif bad=="hop":row.path[1]=Vector2i(6,7)
  elif bad=="phase":row.navigation_phase="pending"
  elif bad=="index":row.index=0
  else:row.navigation_phase="replan";row.path=[Vector2i(14,6)];row.pos=Vector2(14.5,6.5)
  broken.runtime=codec.encode(state);write_json("user://bad-navigation.json",broken)
  var loaded=Model.new();var wallet=loaded.coins
  check(not loaded.load_save("user://bad-navigation.json",false,true) and loaded.coins==wallet and loaded.service_snapshot.is_empty(),bad+" rejected before installation")
  loaded=null
 var disguised=envelope.duplicate(true);disguised.version=15
 check(not Contract.accepts_header(disguised,true),"v15 refuses capable envelope marker")
 disguised.erase("navigation_format")
 check(not Contract.accepts_header(disguised,true),"v15 refuses marked staff even without envelope marker")
 check(not game.model.save(Contract.PRIMARY_FILE,true),"capability cannot overwrite default namespace")
 check(not game.model.save("user://legacy-marked.json"),"default writer cannot silently downgrade marked staff")
 # Historical route permissiveness is deliberately retained, not retrofitted.
 var legacy=baseline.duplicate(true);var old=legacy.staff[slot]
 old.pos=Vector2(4.72,6.91);old.path=[Vector2i(4,6),Vector2i(8,6)];old.index=0;old.destination=Vector2i(8,6)
 game.model.service_snapshot=legacy
 check(game.model.save("user://legacy-staff.json"),"unmarked legacy route remains writable")
 var loaded=Model.new()
 check(loaded.load_save("user://legacy-staff.json") and loaded.service_snapshot.staff[slot].pos==old.pos and loaded.service_snapshot.staff[slot].path==old.path and loaded.service_snapshot.staff[slot].index==0,"v15 preserves old position, path and index semantics")
 loaded=null
 print("STAFF_NAVIGATION_SAVE_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"player_save_used":false,"production_activation":false}))
 quit(0 if failures.is_empty() else 1)
