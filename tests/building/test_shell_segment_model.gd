extends SceneTree
## Legacy shell receipts are import evidence, never a second live wall authority.
## Keep the original regression's payment, aperture and rejection matrix while
## exercising only the unified Model after the read-only import boundary.
const Model=preload("res://scripts/core/cafe_model.gd")
const Segments=preload("res://scripts/gameplay/cafe_shell_segments.gd")
const Geometry=preload("res://scripts/gameplay/cafe_wall_openings.gd")
const Walls=preload("res://scripts/gameplay/cafe_walls.gd")
const Codec=preload("res://scripts/persistence/cafe_building_codec.gd")
const BuildingEdges=preload("res://scripts/gameplay/cafe_building_edges.gd")
var checks=0
var failures=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func same(v)->String:return JSON.stringify(v)
func same_json_value(a,b)->bool:
 # JSON has one numeric type and unordered object keys; array order and every
 # field/value remain significant. This never replaces raw text/hash guards.
 if (a is int or a is float) and (b is int or b is float):return float(a)==float(b)
 if typeof(a)!=typeof(b):return false
 if a is Dictionary:
  if a.size()!=b.size():return false
  for key in a:
   if not b.has(key) or not same_json_value(a[key],b[key]):return false
  return true
 if a is Array:
  if a.size()!=b.size():return false
  for index in a.size():
   if not same_json_value(a[index],b[index]):return false
  return true
 return a==b
func snapshot(m)->String:return same([m.coins,m.revision,m.built_walls,m.wall_attachments,m._next_wall_id,m._next_attachment_id,m.items,m.owned_parcels,m._legacy_building_original])
func write(name:String,data:Dictionary)->String:
 var path="user://"+name+".json";var f=FileAccess.open(path,FileAccess.WRITE);f.store_string(JSON.stringify(data));f.close();return path
func records(model)->Dictionary:
 var result={}
 for wall in model.built_walls:result[Walls.identity(wall)]=wall.duplicate(true)
 return result
func retained_totals(model,ids:Array)->Dictionary:
 var paid=0;var refund=0
 for id in ids:
  var wall=model.get_wall(id)
  if not wall.is_empty():paid+=int(wall.paid_cost);refund+=int(wall.refund_credit)
 return {"paid_cost":paid,"refund_credit":refund}
func checked_legacy(raw:Dictionary)->Dictionary:
 # Exercise the production strict legacy reader, not a relabeled modern save.
 return Model.new()._validate_saved_walls(raw,raw.owned_parcels)
func project(checked:Dictionary,attachments:Array)->Dictionary:
 return BuildingEdges.project_validated_legacy(checked.shell_products,checked.shell_segment_products,checked.walls,attachments)
func check_original(model,path:String,original:String,label:String):
 check(FileAccess.get_file_as_string(path)==original and FileAccess.get_sha256(path)==original.sha256_text(),label+" import bytes unchanged")
 check(model._legacy_building_original==original,label+" exact source roots, aliases and receipts retained as provenance")
func check_archive(path:String,original:String,label:String):
 var archive=path+".pre-grid-"+original.sha256_text()+".json"
 check(FileAccess.get_file_as_string(archive)==original and FileAccess.get_sha256(archive)==original.sha256_text(),label+" complete original recovery bytes retained")
func check_modern(path:String,label:String):
 var data=JSON.parse_string(FileAccess.get_file_as_string(path))
 check(data.version==15 and data.building_format==Codec.FORMAT and data.wall_format==Codec.WALL_FORMAT and data.wall_attachment_format==Codec.ATTACHMENT_FORMAT,label+" outer v15 retained and current wall format guarded")
 for field in ["shell_products","shell_segment_products","shell_segment_format","shell_material"]:
  check(not data.has(field),label+" no dormant live/save authority "+field)
func check_projection(raw:Dictionary,model,label:String):
 var before=same(raw);var live_before=snapshot(model)
 var checked=checked_legacy(raw)
 check(checked.ok,label+" strictly validates original legacy building")
 if not checked.ok:return
 var result=project(checked,raw.wall_attachments)
 check(result.ok,label+" projects validated legacy building")
 if not result.ok:return
 var hosts=Segments.selectable_hosts(checked.shell_products,checked.shell_segment_products,checked.walls)
 check(result.edges.size()==hosts.size() and model.built_walls.size()==hosts.size(),label+" one installed record per visible grid edge")
 for host in hosts:
  var key=Walls.key(host.axis,int(host.a.x),int(host.a.y))
  var id=str(host.get("segment_key",host.host_id))
  check(result.edges.has(key),label+" preserves grid edge "+key)
  if not result.edges.has(key):continue
  var edge:Dictionary=result.edges[key];var wall=model.get_wall(id)
  check(edge.id==id and edge.a==host.a and edge.b==host.b,label+" legacy projection preserves stable identity and extent "+key)
  check(edge.height==host.height and edge.material==host.material,label+" legacy projection preserves appearance "+key)
  check(edge.physical_rect==Geometry.segment_rect({"host":host,"a":host.a,"b":host.b}),label+" read-only projection preserves exact original physical rectangle "+key)
  check(not edge.has("shell") and not edge.has("segment_key"),label+" installed projection has no default-only type "+key)
  check(not wall.is_empty(),label+" live installed identity exists "+id)
  if wall.is_empty():continue
  var installed=Geometry.wall_host(wall)
  check(Walls.key_of(wall)==key and installed.a==edge.a and installed.b==edge.b,label+" active edge datum and identity preserved "+key)
  check(wall.height==edge.height and wall.material==edge.material,label+" active appearance preserved "+key)
  check(wall.paid_cost==edge.paid_cost and wall.refund_credit==edge.refund_credit and model.wall_refund(id)==edge.refund_credit,label+" exact active payment/refund retained "+key)
  # Grid v2 deliberately centers every body and visible face. Preserve the old
  # rectangle in the pure projection, not as a second physical shell mechanism.
  var direction=Vector2.RIGHT if wall.axis=="x" else Vector2.DOWN
  var normal=Walls.normal(wall)
  check(Walls.physical_rect(wall).is_equal_approx(Rect2(installed.a-normal*.08,direction+normal*.16).abs()),label+" active body uses common centered .16 profile "+key)
  check(Walls.visual_front(wall).is_equal_approx(normal*.13) and Walls.visual_back(wall).is_equal_approx(normal*-.13),label+" active visible thickness remains .26 "+key)
  check(Walls.pattern_origin(wall)==edge.pattern_origin,label+" imported pattern phase retained "+key)
  check(not wall.has("shell") and not wall.has("segment_key") and not wall.has("origin_shell"),label+" live wall has no dormant shell type/history "+key)
 check(model.wall_attachments.size()==raw.wall_attachments.size(),label+" one active object per original opening")
 for index in raw.wall_attachments.size():
  var old:Dictionary=raw.wall_attachments[index]
  var aperture=Geometry.aperture(old,checked.walls,checked.shell_products)
  var opening:Dictionary=result.openings[index]
  var active=model.get_wall_attachment(int(old.id));var actual=Geometry.aperture(active,model.built_walls)
  check(opening.id==old.id and opening.paid_cost==old.paid_cost and opening.width==old.width,label+" projection preserves opening identity/payment/width")
  check(opening.a==aperture.a and opening.b==aperture.b and opening.bottom==aperture.bottom and opening.top==aperture.top,label+" projection preserves complete aperture")
  check(result.migration_report.opening_aliases[int(old.id)]=={"host_id":old.host_id,"offset":float(old.offset)},label+" original host alias remains import audit data")
  check(not opening.wall_ids.is_empty() and active.wall_ids==opening.wall_ids,label+" complete ordered support resolves to installed identities")
  check(active.id==old.id and active.kind==old.kind and active.paid_cost==old.paid_cost and active.width==old.width,label+" active opening identity/kind/payment/width unchanged")
  check(actual.a==aperture.a and actual.b==aperture.b and actual.bottom==aperture.bottom and actual.top==aperture.top,label+" active opening retains absolute aperture despite new relative host offset")
  check(not active.has("host_id"),label+" original root alias is not a live opening authority")
 check(before==same(raw) and snapshot(model)==live_before,label+" projection never mutates source state or active wallet/model")

func projection_edge_cases(base:Dictionary):
 var initial=Model.new();var path=write("projection-initial",base)
 check(initial.load_save(path),"actual legacy projection fixture loads: "+initial.last_error)
 check_projection(base,initial,"legacy preset")
 var before=snapshot(initial);var source_before=same(base);var checked=checked_legacy(base)
 var projected=project(checked,base.wall_attachments)
 projected.edges["x:0:0"].material="leaf_print";projected.migration_report.opening_aliases[1].offset=2.5
 projected.openings[0].wall_ids.clear()
 check(snapshot(initial)==before and same(base)==source_before,"projected records and metadata are independently mutable")
 var walls=[{"id":42,"axis":"x","x":1,"z":1,"height":"full","material":"sage_panels","paid_cost":55,"refund_credit":27},
  {"id":43,"axis":"x","x":2,"z":1,"height":"full","material":"sage_panels","paid_cost":55,"refund_credit":27}]
 var opening=[{"id":88,"kind":"door","host_id":"span:42,43","offset":1.0,"width":1.5,"paid_cost":40}]
 var result=BuildingEdges.project_validated_legacy(checked.shell_products,checked.shell_segment_products,walls,opening)
 check(result.ok and result.openings[0].wall_ids==["wall:42","wall:43"],"ordinary spanning opening resolves complete ordered support")
 var duplicates=walls.duplicate(true);duplicates[1].x=1
 check(not BuildingEdges.project_validated_legacy(checked.shell_products,checked.shell_segment_products,duplicates,[]).ok,"duplicate edge is rejected instead of overwritten")
 duplicates=walls.duplicate(true);duplicates[1].id=42
 check(not BuildingEdges.project_validated_legacy(checked.shell_products,checked.shell_segment_products,duplicates,[]).ok,"duplicate installed identity is rejected")
 var removed=checked.shell_segment_products.duplicate(true);removed["shell:west#5"]["removed"]=true
 check(not BuildingEdges.project_validated_legacy(checked.shell_products,removed,checked.walls,base.wall_attachments).ok,"missing supporting edge is rejected instead of filled")
 var lowered=checked.shell_segment_products.duplicate(true);lowered["shell:west#5"]={"height":"half","material":"original","paid_cost":35,"refund_credit":17}
 check(not BuildingEdges.project_validated_legacy(checked.shell_products,lowered,checked.walls,base.wall_attachments).ok,"half-height supporting edge is rejected")
 check(snapshot(initial)==before and same(base)==source_before,"failed projections preserve source, model and wallet")
 # A real legacy-format clone expresses the old moved-origin/tombstone pair.
 # The current command instead retains its existing installed ID, tested below.
 var moved_raw=base.duplicate(true);moved_raw.shell_segment_products["shell:west#5"].removed=true
 moved_raw.built_walls=[{"id":1,"axis":"x","x":2,"z":9,"height":"full","material":"original","paid_cost":0,"refund_credit":0,"origin_shell":"shell:west#5"}]
 moved_raw.next_wall_id=2;moved_raw.wall_attachments[0].host_id="wall:1";moved_raw.wall_attachments[0].offset=.5
 var moved=Model.new();path=write("legacy-moved",moved_raw);var moved_original=FileAccess.get_file_as_string(path)
 check(moved.load_save(path),"legacy moved starter wall/door fixture loads: "+moved.last_error)
 check_projection(moved_raw,moved,"legacy moved starter door wall")
 result=project(checked_legacy(moved_raw),moved_raw.wall_attachments)
 check(result.migration_report.moved_origins.get("wall:1")=="shell:west#5" and result.migration_report.removed_ids.has("shell:west#5"),"legacy moved lineage and removed receipt survive in audit without duplicate geometry")
 check(result.openings[0].wall_ids==["wall:1"] and moved.get_wall("shell:west#5").is_empty(),"legacy moved door resolves to the same ordinary installed identity")
 check_original(moved,path,moved_original,"legacy moved source")
 var live=Model.new();check(live.load_save(write("live-move-source",base)),"load legacy source for current move command")
 var identity_before=live.get_wall("shell:west#5").duplicate(true);var opening_before=live.wall_attachments.duplicate(true);var wallet=live.coins;var next_id=live._next_wall_id
 check(live.move_wall("shell:west#5","x",2,9),"current command moves imported starter wall and hosted door")
 check(live.get_wall("z:0:5").is_empty() and live.get_wall("x:2:9").id=="shell:west#5","current move preserves installed identity and leaves old edge empty")
 check(live.coins==wallet and live._next_wall_id==next_id and live.wall_attachments==opening_before,"current move does not charge, allocate an ID or rewrite hosted opening")
 check(live.get_wall("shell:west#5").paid_cost==identity_before.paid_cost and live.get_wall("shell:west#5").refund_credit==identity_before.refund_credit,"current move retains exact receipt")
 var empty_raw=base.duplicate(true);empty_raw.wall_attachments=[]
 for id in empty_raw.shell_segment_products:empty_raw.shell_segment_products[id].removed=true
 result=project(checked_legacy(empty_raw),[])
 check(result.ok and result.edges.is_empty() and result.openings.is_empty(),"empty legacy projection never regenerates the preset")
 check(result.migration_report.removed_ids.size()==21 and result.migration_report.discarded_covered_free_ids.is_empty(),"removed source IDs are audit data, never installed geometry")
 var empty=Model.new();check(empty.load_save(write("legacy-empty",empty_raw)) and empty.built_walls.is_empty(),"legacy removed structure loads with no resurrected walls")
 empty=Model.new();empty.set_operating_open(false)
 check(empty.remove_wall_attachment(1),"remove included door through production command")
 for wall in empty.built_walls.duplicate(true):check(empty.remove_wall(Walls.identity(wall)),"remove real starter edge "+Walls.identity(wall))
 check(empty.built_walls.is_empty() and empty.wall_attachments.is_empty(),"production removal leaves no dormant preset")
 check(empty.save("user://empty-current.json"),"empty current building saves")
 var empty_again=Model.new();check(empty_again.load_save("user://empty-current.json") and empty_again.built_walls.is_empty() and empty_again.wall_attachments.is_empty(),"empty current building stays empty after reload")

func _initialize():run.call_deferred()
func run():
 if not "saveguard" in OS.get_user_data_dir():printerr("Use isolated model runner");quit(2);return
 var fixtures=OS.get_environment("UNIFIED_LEGACY_FIXTURE_DIR")
 if fixtures=="":fixtures="res://tests/fixtures/unified_building"
 var fixture_path=fixtures.path_join("public_closed.json")
 var fixture_original=FileAccess.get_file_as_string(fixture_path);var fixture_hash=FileAccess.get_sha256(fixture_path)
 var base=JSON.parse_string(fixture_original)
 check(base is Dictionary and base.version==15 and base.wall_format==2 and base.wall_attachment_format==1 and base.shell_segment_format==Segments.FORMAT and not base.has("building_format"),"fixture is genuine pre-grid v15/wall2, not relabeled grid-v2 bytes")
 if not base is Dictionary or base.has("building_format"):
  finish();return
 base.coins=10000
 projection_edge_cases(base)
 var initial=Model.new();initial.coins=10000
 check(initial.save("user://initial.json"),"new unified model saves: "+initial.last_error)
 check_modern("user://initial.json","fresh")
 # Wall1 is derived only from this genuine wall2 legacy fixture. No installed
 # grid records, v2 placements, or current writer output are relabeled legacy.
 var legacy=base.duplicate(true);legacy.wall_format=1;legacy.erase("shell_segment_format");legacy.erase("shell_segment_products")
 for extension in [false,true]:
  for material in ["original","sage_panels","cream_stripe","leaf_print"]:
   for paid in [0,440,495]:
    var raw=legacy.duplicate(true);raw.shell_products["shell:west"]={"height":"full","material":material,"paid_cost":paid}
    if extension:raw.built_walls=[{"id":41,"axis":"z","x":0,"z":8,"height":"full","material":"leaf_print"}];raw.next_wall_id=42
    raw.wall_attachments=[{"id":77,"kind":"door","host_id":"shell:west","offset":5.5,"width":1.5,"paid_cost":40}];raw.next_attachment_id=78
    var expected_roots=raw.shell_products.duplicate(true)
    var path=write("legacy",raw);var original=FileAccess.get_file_as_string(path);var model=Model.new();var label=str([extension,material,paid])
    var loaded=model.load_save(path);check(loaded,label+" legacy load: "+model.last_error)
    if not loaded:continue
    check_projection(raw,model,label)
    var checked=checked_legacy(raw);var projection=project(checked,raw.wall_attachments)
    check(projection.openings[0].wall_ids==["shell:west#4","shell:west#5","shell:west#6"] and model.wall_attachments[0].wall_ids==projection.openings[0].wall_ids,label+" wide opening remains one object supported by three unit edges")
    check(projection.migration_report.discarded_covered_free_ids.size()==(1 if extension else 0),label+" only hidden covered free default is discarded")
    if extension:
     check(projection.edges["z:0:8"].id=="wall:41" and projection.migration_report.discarded_covered_free_ids==["shell:west#8"] and model.get_wall("shell:west#8").is_empty(),label+" paid visible extension retained without hidden inventory or coin compensation")
    check_original(model,path,original,label)
    check(model.coins==int(raw.coins),label+" import never compensates or charges coins")
    check(same_json_value(JSON.parse_string(model._legacy_building_original).shell_products,expected_roots),label+" original inherited root snapshots retained outside active state")
    check(same_json_value(JSON.parse_string(model._legacy_building_original).wall_attachments,raw.wall_attachments),label+" original paid wide opening ID/host/offset/width/value unchanged in provenance")
    check(model._next_wall_id==raw.next_wall_id and model._next_attachment_id==78,label+" ID counters unchanged")
    var ids=[]
    for index in (8 if extension else 9):ids.append("shell:west#"+str(index))
    var totals=retained_totals(model,ids)
    check(totals.paid_cost==paid and totals.refund_credit==paid/2,label+" exact aggregate paid/refund retained")
    var roots=Geometry.shell_hosts(checked.shell_products,checked.walls)
    check(roots[0].host_id=="shell:back" and roots[1].host_id=="shell:west" and roots[1].normal==Vector2(-.26,0),label+" original geometric root order and thickness retained in read-only import evidence")
    check(model.wall_hosts()[0].host_id=="shell:back#0" and model.wall_hosts()[11].host_id=="shell:back#11" and model.wall_hosts()[12].host_id=="shell:west#0",label+" deterministic per-edge order replaces live root hosts")
    check(model.get_wall_host("shell:back").is_empty() and model.get_wall_host("shell:west").is_empty(),label+" legacy root aliases are not active hosts")
    check(model.selectable_wall_hosts().size()==21,label+" all exposed grid targets including player extension")
    var before=snapshot(model);var bill=model.wall_replacement_quote("shell:west#2","half","sage_panels")
    check(bill.valid and bill.new_cost==35 and bill.refund==model.get_wall("shell:west#2").refund_credit,label+" one-unit quote")
    check(snapshot(model)==before,label+" quote/cancel does not mutate")
    check(not model.replace_wall("shell:west","half","sage_panels") and snapshot(model)==before,label+" ambiguous whole-root replacement rejected atomically")
    var neighbors=records(model);var coins=model.coins;var openings=model.wall_attachments.duplicate(true)
    check(model.replace_wall("shell:west#2","half","sage_panels"),label+" single segment replacement")
    check(model.coins==coins-int(bill.net),label+" charged exact net")
    for key in neighbors:
     if key!="shell:west#2":check(model.get_wall(key)==neighbors[key],label+" unchanged neighbor "+key)
    check(model._legacy_building_original==original and model.wall_attachments==openings,label+" original roots/provenance and active openings stable after edit")
    before=snapshot(model);check(not model.replace_wall("shell:west#2","half","sage_panels") and snapshot(model)==before,label+" same style cannot charge")
    for index in [4,5,6]:
     before=snapshot(model);check(not model.replace_wall("shell:west#"+str(index),"half","sage_panels") and snapshot(model)==before,label+" wide door rejects lowering supporting segment "+str(index))
     check(not model.move_wall("shell:west#"+str(index),"x",2,9) and snapshot(model)==before,label+" wide door rejects moving one supporting segment atomically "+str(index))
     check(not model.remove_wall("shell:west#"+str(index)) and snapshot(model)==before,label+" wide door rejects selling supporting segment atomically "+str(index))
    check(model.save("user://mixed.json"),label+" mixed save: "+model.last_error)
    check_archive("user://mixed.json",original,label);check_modern("user://mixed.json",label)
    var restored=Model.new();check(restored.load_save("user://mixed.json"),label+" mixed reload: "+restored.last_error)
    check(restored.coins==model.coins and restored.built_walls==model.built_walls,label+" mixed installed ledger/wallet roundtrip")
    check(restored.wall_attachments==model.wall_attachments and restored._next_wall_id==model._next_wall_id and restored._next_attachment_id==model._next_attachment_id,label+" opening and ID counter roundtrip")
    check(restored._legacy_building_original=="",label+" current save has no dormant legacy authority")
 var low=Model.new();check(low.load_save(write("low-source",base)),"low-funds legacy fixture loads");low.coins=0;var before=snapshot(low)
 check(not low.replace_wall("shell:back#2","half","leaf_print") and snapshot(low)==before,"insufficient funds atomic")
 var malformed=base.duplicate(true);malformed.wall_format=1;before=snapshot(low)
 check(not low.load_save(write("masked-format",malformed)) and snapshot(low)==before,"format1 cannot silently ignore segment fields")
 for damage in ["missing","extra","refund","height","format","invented_cost","invented_rounding"]:
  malformed=base.duplicate(true)
  match damage:
   "missing":malformed.shell_segment_products.erase("shell:back#1")
   "extra":malformed.shell_segment_products["shell:back#12"]=malformed.shell_segment_products["shell:back#1"]
   "refund":malformed.shell_segment_products["shell:back#1"].refund_credit=1
   "height":malformed.shell_segment_products["shell:back#1"].height="low"
   "format":malformed.shell_segment_format="unrecognized"
   "invented_cost":malformed.shell_segment_products["shell:back#1"].paid_cost=62;malformed.shell_segment_products["shell:back#1"].refund_credit=31
   "invented_rounding":malformed.shell_segment_products["shell:back#1"].paid_cost=55;malformed.shell_segment_products["shell:back#1"].refund_credit=28
  before=snapshot(low);check(not low.load_save(write("bad-"+damage,malformed)) and snapshot(low)==before,"malformed legacy load leaves live model/wallet/provenance unchanged "+damage)
 # Imported half-height units, not the archived root snapshot, own support.
 var raw=legacy.duplicate(true);raw.shell_products["shell:back"].height="half"
 var mixed=Model.new();check(mixed.load_save(write("half-root",raw)),"half root legacy load")
 check(mixed.replace_wall("shell:back#2","full","cream_stripe"),"raise one inherited half segment")
 check(mixed.can_place_wall_attachment("window","shell:back#2",.5),"opening accepts full installed segment over archived half root")
 before=snapshot(mixed)
 check(not mixed.can_place_wall_attachment("window",Geometry.host_ref(["shell:back#2","shell:back#3"]),1.0) and snapshot(mixed)==before,"opening crossing full and half neighbors rejected without mutation")
 check(mixed.place_wall_attachment("window","shell:back#2",.5),"place supported window")
 var window=mixed.wall_attachments[-1];var aperture=Geometry.aperture(window,mixed.built_walls)
 check(window.wall_ids==["shell:back#2"] and aperture.a.is_equal_approx(Vector2(2.15,0)) and aperture.b.is_equal_approx(Vector2(2.85,0)),"unit-relative host preserves original window aperture")
 before=snapshot(mixed);check(not mixed.replace_wall("shell:back#2","half","leaf_print") and snapshot(mixed)==before,"window support prevents lowering atomically")
 check(mixed.save("user://half-root-mixed.json"),"mixed heights with supported window save")
 check_archive("user://half-root-mixed.json",mixed._legacy_building_original,"mixed heights")
 var reread=Model.new();check(reread.load_save("user://half-root-mixed.json") and reread.built_walls==mixed.built_walls and reread.wall_attachments==mixed.wall_attachments and reread.coins==mixed.coins,"mixed heights with supported window reload exactly")
 extension_transitions(legacy)
 no_dormant_receipts(base)
 check(FileAccess.get_file_as_string(fixture_path)==fixture_original and FileAccess.get_sha256(fixture_path)==fixture_hash,"original repository legacy fixture remains byte-for-byte untouched")
 finish()

func extension_transitions(legacy:Dictionary):
 # Historical allocation stays fixed when the retained paid extension leaves.
 # The covered free ninth record is discarded, never revealed or refunded.
 var corridor_fixture=Model.new();corridor_fixture.coins=20000;corridor_fixture.set_operating_open(false)
 check(corridor_fixture.buy_parcel("front_0") and corridor_fixture.coins==10000,"legacy extension fixture purchases actual corridor-connected side land")
 check(corridor_fixture.save("user://corridor-side-ownership.json"),"generated corridor ownership saves through ordinary writer")
 var corridor_payload=JSON.parse_string(FileAccess.get_file_as_string("user://corridor-side-ownership.json"))
 for height in ["full","half"]:
  for edited in [false,true]:
   for action in ["remove","move"]:
    var raw=legacy.duplicate(true);raw.shell_products["shell:west"]={"height":height,"material":"cream_stripe","paid_cost":int(Segments.LEGACY_PRICES[height])*9}
    raw.owned_parcels=corridor_payload.owned_parcels.duplicate();raw.expanded=corridor_payload.expanded
    raw.built_walls=[{"id":41,"axis":"z","x":0,"z":8,"height":"full","material":"leaf_print"}];raw.next_wall_id=42
    raw.wall_attachments=[{"id":77,"kind":"door","host_id":"shell:back","offset":3.5,"width":1.5,"paid_cost":40}];raw.next_attachment_id=78
    var transition=Model.new();var label=str([height,edited,action]);var path=write("extension-transition",raw);var original=FileAccess.get_file_as_string(path)
    var loaded=transition.load_save(path);check(loaded,label+" inherited extension load: "+transition.last_error)
    if not loaded:continue
    check_projection(raw,transition,label+" initial extension")
    if edited:check(transition.replace_wall("shell:west#2",height,"sage_panels"),label+" prior neighbor purchase")
    var ledger=records(transition);var openings=transition.wall_attachments.duplicate(true);var inherited_ids=[]
    for index in range(8):inherited_ids.append("shell:west#"+str(index))
    var old_totals=retained_totals(transition,inherited_ids);var wallet=transition.coins
    var ok=transition.remove_wall("z:0:8") if action=="remove" else transition.move_wall("z:0:8","x",0,9)
    check(ok,label+" extension action: "+transition.last_error)
    check(transition.coins==wallet+(27 if action=="remove" else 0),label+" only existing player-wall refund applies")
    for id in ledger:
     if id!="wall:41":check(transition.get_wall(id)==ledger[id],label+" every other installed payment/style unchanged "+id)
    check(transition.wall_attachments==openings and transition._legacy_building_original==original,label+" source roots/provenance and openings unchanged")
    check(retained_totals(transition,inherited_ids)==old_totals,label+" exact inherited aggregate paid/refund survives extent change")
    check(transition.get_wall("z:0:8").is_empty() and transition.get_wall("shell:west#8").is_empty(),label+" former covering edge stays empty with no dormant free ninth product")
    if action=="move":check(transition.get_wall("x:0:9").id=="wall:41" and transition.get_wall("wall:41").paid_cost==55 and transition.get_wall("wall:41").refund_credit==27,label+" moved covering wall keeps stable identity/payment")
    check(transition.save("user://extension-transition-result.json"),label+" save after extent change: "+transition.last_error)
    check_archive("user://extension-transition-result.json",original,label);check_original(transition,path,original,label)
    var restored=Model.new();check(restored.load_save("user://extension-transition-result.json"),label+" reload after extent change: "+restored.last_error)
    check(restored.built_walls==transition.built_walls and restored.wall_attachments==openings and restored.coins==transition.coins,label+" extent-change roundtrip preserves exact installed ledger/wallet/openings")
    check(restored._next_wall_id==42 and restored._next_attachment_id==78,label+" counters unchanged")
    check(restored.get_wall("z:0:8").is_empty() and restored.get_wall("shell:west#8").is_empty(),label+" reload cannot resurrect discarded ninth record")
    var before=snapshot(restored)
    check(not restored.replace_wall("shell:west#8",height,"leaf_print") and snapshot(restored)==before,label+" discarded receipt cannot be replaced or grant value")
    wallet=restored.coins
    check(restored.place_wall("z",0,8,height,"leaf_print"),label+" empty ninth edge can be bought through ordinary placement")
    var bought=restored.get_wall("z:0:8");var cost=int(Walls.PRICES[height])
    check(not bought.is_empty() and bought.id=="wall:42" and bought.paid_cost==cost and bought.refund_credit==cost/2 and restored.coins==wallet-cost,label+" ninth edge is a new exact-cost purchase with ordinary ID/receipt")
    check(restored._next_wall_id==43 and restored._next_attachment_id==78 and retained_totals(restored,inherited_ids)==old_totals,label+" new purchase changes only its ordinary wall counter and receipt")
    check(restored.save("user://extension-transition-purchased.json"),label+" subsequent ninth purchase saves")
    var last=Model.new();check(last.load_save("user://extension-transition-purchased.json") and last.built_walls==restored.built_walls and last.wall_attachments==restored.wall_attachments and last.coins==restored.coins and last._next_wall_id==43,label+" subsequent ninth purchase reloads exactly")
  var roots=Geometry.initial_shell_products("cream_stripe");roots["shell:west"]={"height":height,"material":"cream_stripe","paid_cost":int(Segments.LEGACY_PRICES[height])*9}
  var nine=Segments.migrate(roots,[]);var eight=Segments.migrate(roots,[{"axis":"z","x":0,"z":8}])
  nine.segments["shell:west#0"]=eight.segments["shell:west#0"].duplicate(true)
  check(Segments.validate(nine,[])!="",height+" incompatible historical bases cannot mix per index")

func no_dormant_receipts(base:Dictionary):
 # Replaces the deleted preserves_inherited_extension helper assertions with
 # real import/command behavior. No category may reveal a hidden free product.
 for variant in ["inherited","removed","purchased_tombstone","moved_origin"]:
  var raw=base.duplicate(true);raw.built_walls=[{"id":41,"axis":"z","x":0,"z":8,"height":"full","material":"leaf_print"}];raw.next_wall_id=42
  if variant in ["removed","purchased_tombstone"]:raw.shell_segment_products["shell:west#8"].removed=true
  if variant=="purchased_tombstone":raw.shell_segment_products["shell:west#8"]={"height":"full","material":"leaf_print","paid_cost":55,"refund_credit":27,"removed":true}
  if variant=="moved_origin":
   raw.shell_segment_products["shell:back#3"].removed=true
   raw.built_walls[0].origin_shell="shell:back#3";raw.built_walls[0].paid_cost=0;raw.built_walls[0].refund_credit=0
  var path=write("no-dormant-"+variant,raw);var original=FileAccess.get_file_as_string(path);var model=Model.new()
  var loaded=model.load_save(path);check(loaded,variant+" legacy covered-edge fixture loads: "+model.last_error)
  if not loaded:continue
  check_projection(raw,model,variant+" covered edge")
  var wallet=model.coins
  check(model.remove_wall("wall:41") and model.coins==wallet+(0 if variant=="moved_origin" else 27),variant+" covering wall sale returns only its retained receipt")
  check(model.get_wall("z:0:8").is_empty() and model.get_wall("shell:west#8").is_empty(),variant+" sale cannot reveal a free or purchased dormant receipt")
  if variant=="moved_origin":check(model.get_wall("x:3:0").is_empty() and model.get_wall("shell:back#3").is_empty(),"moved origin cannot respawn its source edge")
  check(model.save("user://no-dormant-result.json"),variant+" no-dormant result saves")
  check_archive("user://no-dormant-result.json",original,variant)
  var restored=Model.new();check(restored.load_save("user://no-dormant-result.json") and restored.built_walls==model.built_walls and restored.coins==model.coins,variant+" no-dormant result reloads exactly")
 # Reject paid/refund corruption at the legacy boundary, not by hiding it.
 for field in ["paid_cost","refund_credit"]:
  var raw=base.duplicate(true);raw.built_walls=[{"id":41,"axis":"z","x":0,"z":8,"height":"full","material":"leaf_print"}];raw.next_wall_id=42
  raw.shell_segment_products["shell:west#8"][field]=1
  var model=Model.new();var before=snapshot(model)
  check(not model.load_save(write("covered-invalid-"+field,raw)) and snapshot(model)==before,"covered included receipt cannot invent "+field+" and rejection is atomic")
 var ordinary=Model.new();check(ordinary.load_save(write("ordinary-seventh",base)),"non-ninth legacy fixture loads")
 var wallet=ordinary.coins
 check(ordinary.remove_wall("shell:west#7") and ordinary.coins==wallet and ordinary.get_wall("z:0:7").is_empty(),"non-ninth included wall also has no free-reveal exception")
 check(ordinary.place_wall("z",0,7,"full","leaf_print"),"non-ninth removed edge repurchases normally")
 wallet=ordinary.coins
 check(ordinary.remove_wall("z:0:7") and ordinary.coins==wallet+27 and ordinary.get_wall("z:0:7").is_empty(),"purchased non-ninth wall returns only normal receipt and never resurrects")

func finish():
 var report={"checks":checks,"failures":failures,"player_save_used":false,"browser_verified":false,"native_pixels_verified":false}
 print("SHELL_SEGMENT_MODEL_RESULT ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
