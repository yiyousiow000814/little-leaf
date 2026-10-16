extends SceneTree
const Model=preload("res://scripts/core/cafe_model.gd")
const Start=preload("res://scripts/minimal_start.gd")
const Plan=preload("res://scripts/gameplay/cafe_edit_plan.gd")
const Storage=preload("res://scripts/gameplay/cafe_storage.gd")
const Contract=preload("res://scripts/persistence/cafe_save_contract.gd")
const Hold=preload("res://scripts/persistence/cafe_layout_hold.gd")
var checks=0
var failures=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func fresh():
 var m=Model.new();Start.apply(m);m.coins=10000;return m
func store(m,id:int)->bool:
 var p=Plan.new();var q=p.prepare_store(m,id);return q.ok and p.commit(m,q)
func place(m,id:int,cell:Vector2i,rot:int=0)->bool:
 var p=Plan.new();var q=p.prepare(m,Storage.kind_for(m,id),-1,rot,cell,[],Plan.Context.DECORATE,Plan.Source.STORAGE,id)
 return q.ok and p.commit(m,q)
func rejected_hold(raw:Dictionary,label:String):
 check(not Contract.accepts_header(raw),label+" rejected at header")
 FileAccess.open("user://storage-invalid-hold.json",FileAccess.WRITE).store_string(JSON.stringify(raw))
 var m=fresh();var before=m.save_data().duplicate(true)
 check(not m.load_save("user://storage-invalid-hold.json") and not m.last_error.is_empty() and m.save_data()==before,label+" fails with diagnostic and unchanged model")
func hold_marker_cases():
 for version in [16,17]:
  var valid=fresh().save_data();valid.version=version
  if version==17:valid.storage_format=Storage.FORMAT;valid.storage=Storage.empty()
  valid.layout_hold_format=Hold.FORMAT;valid.runtime.layout_hold_format=Hold.FORMAT;valid.runtime.service.layout_hold=Hold.empty()
  check(Contract.accepts_header(valid),str(version)+" accepts coherent hold markers before full runtime validation")
  for field in ["outer","runtime","service"]:
   for mutation in ["missing","wrong"]:
    var raw=valid.duplicate(true)
    if field=="outer":
     if mutation=="missing":raw.erase("layout_hold_format")
     else:raw.layout_hold_format="wrong"
    elif field=="runtime":
     if mutation=="missing":raw.runtime.erase("layout_hold_format")
     else:raw.runtime.layout_hold_format="wrong"
    else:
     if mutation=="missing":raw.runtime.service.erase("layout_hold")
     else:raw.runtime.service.layout_hold.format="wrong"
    rejected_hold(raw,str(version)+" "+mutation+" "+field+" marker")
  var outer_only=valid.duplicate(true);outer_only.runtime.erase("layout_hold_format");outer_only.runtime.service.erase("layout_hold")
  rejected_hold(outer_only,str(version)+" outer-only hold")
  var bad_registry=valid.duplicate(true);bad_registry.runtime.service.layout_hold=[]
  rejected_hold(bad_registry,str(version)+" non-object hold registry")
func _initialize():run.call_deferred()
func run():
 if not "saveguard" in OS.get_user_data_dir():printerr("Use isolated generated profile");quit(2);return
 for kind in ["plant","stove","table_set","table_set_cottage","table_set_retro","table_set_refined"]:
  var m=fresh();var id=m._next_item_id;check(m.place(kind,3,6),kind+" baseline purchase")
  var before=m.items.duplicate(true);var groups=m.dining_sets.duplicate(true);var wallet=m.coins;var next_id=m._next_item_id
  check(not m.store_item(id),"packing requires Decorate")
  m.begin_decoration_session();var p=Plan.new();var q=p.prepare_store(m,id)
  check(q.ok and m.items==before and m.storage.items.is_empty(),kind+" preview does not mutate")
  check(p.commit(m,q) and not p.commit(m,q),kind+" packing commits only once")
  check(m.get_item(id).is_empty() and m.stored_ids(kind)==[id] and m.coins==wallet and m._next_item_id==next_id,kind+" exact identity and coins conserved")
  var stock=m.storage.duplicate(true)
  check(not place(m,id,Vector2i(-1,-1)) and m.storage==stock and m.coins==wallet,kind+" invalid placement consumes nothing")
  check(m.save("user://storage-draft.json"),kind+" draft saves baseline")
  var loaded=Model.new();check(loaded.load_save("user://storage-draft.json") and loaded.items==before and loaded.storage.items.is_empty() and loaded.coins==wallet,kind+" interrupted draft reloads baseline")
  check(place(m,id,Vector2i(3,6)) and m.stored_ids(kind).is_empty() and m.coins==wallet and m._next_item_id==next_id,kind+" unpack is free and reuses IDs")
  check(m.cancel_decoration_session() and m.items==before and m.dining_sets==groups and m.storage.items.is_empty() and m.coins==wallet,kind+" Cancel restores full session")
  m.begin_decoration_session();check(store(m,id),kind+" pack for Apply");m.finish_decoration_session()
  check(m.save("user://storage-applied.json"),kind+" applied stock saves: "+m.last_error)
  check(loaded.load_save("user://storage-applied.json") and loaded.stored_ids(kind)==[id] and loaded.coins==wallet,kind+" applied stock reloads")
  check(loaded.save_data().version==17,kind+" owned storage requires explicit17")
  loaded.begin_decoration_session();check(place(loaded,id,Vector2i(3,6)),kind+" reloaded stock unpacks")
  loaded.finish_decoration_session();check(loaded.items==before and loaded.dining_sets==groups and loaded.coins==wallet,kind+" recorded value and variant survive")
  loaded.begin_decoration_session();check(store(loaded,id) and loaded.cancel_decoration_session() and loaded.items==before,kind+" repeated pack Cancel cannot duplicate")
 var m=fresh();var before=m.items.duplicate(true);m.begin_decoration_session()
 var legacy=m.logical_item_id(6);var legacy_item=m.get_item(legacy).duplicate(true);check(store(m,legacy) and place(m,legacy,Vector2i(legacy_item.x,legacy_item.z),m.logical_rotation(legacy)),"legacy dining variant can be stored and restored")
 check(m.cancel_decoration_session() and m.items==before,"legacy exact coordinates restored on Cancel")
 m=fresh();var historic=m.dining_set_for(6);var old_seat=m.get_item(int(historic.seat_id));old_seat.kind="bench";historic.variant="legacy_bench";historic.paid_cost=175
 var bench_before=m.items.duplicate(true);var bench_group=m.dining_sets.duplicate(true);var bench_table=m.get_item(6).duplicate(true)
 m.begin_decoration_session();check(store(m,6) and m.stored_ids("table_set_legacy_bench")==[6] and m.stored_ids("table_set").is_empty(),"legacy bench set has an honest separate owned display identity")
 check(place(m,6,Vector2i(bench_table.x,bench_table.z),int(historic.rot)) and m.items.size()==bench_before.size() and m.items.all(func(item):return item in bench_before) and m.dining_sets==bench_group,"legacy bench variant and paid basis survive exact re-placement")
 check(m.placement_parts("table_set_legacy_bench",3,6,0)[1].kind=="bench","legacy owned preview keeps its real bench silhouette")
 check(not m.place("table_set_legacy_bench",3,6),"historic display key cannot create a newly purchased entitlement")
 m.cancel_decoration_session();m=fresh()
 var register=m.items.filter(func(item):return item.kind=="register")[0];m.begin_decoration_session();var wallet=m.coins
 check(store(m,int(register.id)) and m.register_unplaced,"register is owned and unplaced")
 check(not m.place("register",3,6) and m.coins==wallet,"Shop cannot duplicate stored register")
 check(place(m,int(register.id),Vector2i(register.x,register.z),int(register.rot)) and not m.register_unplaced and m.coins==wallet,"same register restores without buying or refund")
 m.cancel_decoration_session()
 m=fresh();var id=m._next_item_id;m.storage.items.append({"id":id,"kind":"plant","x":0,"z":0,"rot":0,"paid_cost":0});m._next_item_id+=1;m.storage_used=true
 m.begin_decoration_session();check(place(m,id,Vector2i(3,6)),"zero-basis claimed stock uses ordinary placement");m.finish_decoration_session()
 check(m.logical_refund(id)==0,"claim has no invented resale entitlement")
 m.begin_decoration_session();check(m.remove(id) and m.cancel_decoration_session() and m.get_item(id).paid_cost==0,"Cancel restores zero-basis item without coins")
 m=fresh();m.begin_decoration_session();id=m._next_item_id;wallet=m.coins
 check(m.place("plant",3,6) and store(m,id) and place(m,id,Vector2i(3,6)) and m.logical_refund(id)==45,"same-session purchase receipt survives pack and unpack")
 check(m.remove(id) and m.coins==wallet,"same-session sell after unpack refunds exactly paid amount")
 m.cancel_decoration_session();check(m.coins==wallet and m.get_item(id).is_empty(),"Cancel cannot duplicate purchase refund")
 var raw=fresh().save_data();check(raw.version==15 and not raw.has("storage"),"untouched legacy save remains15")
 raw.version=17;raw.storage_format=Storage.FORMAT;raw.storage=Storage.empty();raw.storage.items.append(raw.items[0].duplicate(true))
 FileAccess.open("user://storage-duplicate.json",FileAccess.WRITE).store_string(JSON.stringify(raw))
 m=fresh();before=m.items.duplicate(true);wallet=m.coins
 check(not m.load_save("user://storage-duplicate.json") and m.items==before and m.coins==wallet,"duplicate owned ID fails closed without publication")
 raw=fresh().save_data();raw.storage_format=Storage.FORMAT;raw.storage=Storage.empty()
 FileAccess.open("user://storage-old-marker.json",FileAccess.WRITE).store_string(JSON.stringify(raw))
 check(not m.load_save("user://storage-old-marker.json"),"old version cannot disguise Storage")
 hold_marker_cases()
 print("STORAGE_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"player_save_used":false}))
 quit(0 if failures.is_empty() else 1)
