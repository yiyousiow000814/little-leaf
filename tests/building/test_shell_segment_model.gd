extends SceneTree
const Model=preload("res://scripts/cafe_model.gd")
const Segments=preload("res://scripts/cafe_shell_segments.gd")
const Geometry=preload("res://scripts/cafe_wall_openings.gd")
var checks=0
var failures=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func same(v)->String:return JSON.stringify(v)
func snapshot(m)->String:return same([m.coins,m.revision,m.shell_products,m.shell_segment_products,m.built_walls,m.wall_attachments,m._next_wall_id,m._next_attachment_id,m.items])
func write(name:String,data:Dictionary)->String:
 var path="user://"+name+".json";var f=FileAccess.open(path,FileAccess.WRITE);f.store_string(JSON.stringify(data));f.close();return path
func _initialize():run.call_deferred()
func run():
 if not "saveguard" in OS.get_user_data_dir():printerr("Use isolated model runner");quit(2);return
 var initial=Model.new();initial.coins=10000
 check(initial.save("user://initial.json"),"new model saves: "+initial.last_error)
 var base=JSON.parse_string(FileAccess.get_file_as_string("user://initial.json"))
 check(base.version==15 and base.wall_format==2 and base.shell_segment_format==Segments.FORMAT,"outer v15 retained and wall format guarded")
 var legacy=base.duplicate(true);legacy.wall_format=1;legacy.erase("shell_segment_format");legacy.erase("shell_segment_products")
 for extension in [false,true]:
  for material in ["original","sage_panels","cream_stripe","leaf_print"]:
   for paid in [0,440,495]:
    var raw=legacy.duplicate(true);raw.shell_products["shell:west"]={"height":"full","material":material,"paid_cost":paid}
    if extension:raw.built_walls=[{"id":41,"axis":"z","x":0,"z":8,"height":"full","material":"leaf_print"}];raw.next_wall_id=42
    raw.wall_attachments=[{"id":77,"kind":"door","host_id":"shell:west","offset":5.5,"width":1.5,"paid_cost":40}];raw.next_attachment_id=78
    var expected_roots=raw.shell_products.duplicate(true)
    for root_id in expected_roots:expected_roots[root_id].paid_cost=int(expected_roots[root_id].paid_cost)
    var path=write("legacy",raw);var hash_before=FileAccess.get_sha256(path);var model=Model.new();var label=str([extension,material,paid])
    check(model.load_save(path),label+" legacy load: "+model.last_error)
    check(FileAccess.get_sha256(path)==hash_before,label+" import bytes unchanged")
    check(model.shell_products==expected_roots,label+" inherited root snapshots retained")
    check(same(model.wall_attachments)==same(raw.wall_attachments),label+" paid wide opening ID/host/offset/width/value unchanged")
    check(model._next_wall_id==raw.next_wall_id and model._next_attachment_id==78,label+" ID counters unchanged")
    var state=Segments.state(model.shell_products,model.shell_segment_products);var totals=Segments.totals(state,"shell:west",model.built_walls)
    check(totals.paid_cost==paid and totals.refund_credit==paid/2,label+" exact paid/refund retained")
    check(model.wall_hosts()[0].host_id=="shell:back" and model.wall_hosts()[1].host_id=="shell:west",label+" geometric root ordering retained")
    check(model.wall_hosts()[1].normal==Vector2(-.26,0),label+" original shell thickness retained")
    check(model.selectable_wall_hosts().size()==21,label+" all exposed grid targets including player extension")
    var before=snapshot(model);var bill=model.wall_replacement_quote("shell:west#2","half","sage_panels")
    check(bill.valid and bill.new_cost==35 and bill.refund==model.shell_segment_products["shell:west#2"].refund_credit,label+" one-unit quote")
    check(snapshot(model)==before,label+" quote/cancel does not mutate")
    check(not model.replace_wall("shell:west","half","sage_panels") and snapshot(model)==before,label+" ambiguous whole-root replacement rejected atomically")
    var neighbors=model.shell_segment_products.duplicate(true);var coins=model.coins
    check(model.replace_wall("shell:west#2","half","sage_panels"),label+" single segment replacement")
    check(model.coins==coins-int(bill.net),label+" charged exact net")
    for key in neighbors:
     if key!="shell:west#2":check(model.shell_segment_products[key]==neighbors[key],label+" unchanged neighbor "+key)
    check(model.shell_products==expected_roots and same(model.wall_attachments)==same(raw.wall_attachments),label+" roots/openings remain stable after edit")
    before=snapshot(model);check(not model.replace_wall("shell:west#2","half","sage_panels") and snapshot(model)==before,label+" same style cannot charge")
    for index in [4,5,6]:
     before=snapshot(model);check(not model.replace_wall("shell:west#"+str(index),"half","sage_panels") and snapshot(model)==before,label+" wide door rejects supporting segment "+str(index))
    check(model.save("user://mixed.json"),label+" mixed save: "+model.last_error)
    var restored=Model.new();check(restored.load_save("user://mixed.json"),label+" mixed reload: "+restored.last_error)
    check(restored.coins==model.coins and restored.shell_segment_products==model.shell_segment_products,label+" mixed ledger/wallet roundtrip")
    check(restored.shell_products==model.shell_products and restored.wall_attachments==model.wall_attachments,label+" root/opening roundtrip")
 var low=Model.new();low.coins=0;var before=snapshot(low)
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
  before=snapshot(low);check(not low.load_save(write("bad-"+damage,malformed)) and snapshot(low)==before,"malformed load leaves live model unchanged "+damage)
 # Root snapshot is half height, while one current segment is full. Opening
 # support must use the current segment rather than that stale base snapshot.
 var raw=legacy.duplicate(true);raw.shell_products["shell:back"].height="half"
 var mixed=Model.new();check(mixed.load_save(write("half-root",raw)),"half root legacy load")
 check(mixed.replace_wall("shell:back#2","full","cream_stripe"),"raise one inherited half segment")
 check(mixed.can_place_wall_attachment("window","shell:back",2.5),"opening accepts full segment over stale half root")
 check(not mixed.can_place_wall_attachment("window","shell:back",3.0),"opening crossing full and half neighbors is rejected")
 check(mixed.place_wall_attachment("window","shell:back",2.5),"place supported window")
 before=snapshot(mixed);check(not mixed.replace_wall("shell:back#2","half","leaf_print") and snapshot(mixed)==before,"window support prevents lowering atomically")
 check(mixed.save("user://half-root-mixed.json"),"mixed heights with supported window save")
 var reread=Model.new();check(reread.load_save("user://half-root-mixed.json"),"mixed heights with supported window reload")
 # Historical allocation remains fixed when a retained extension moves or
 # is removed, including half roots and a previously repurchased neighbor.
 for height in ["full","half"]:
  for edited in [false,true]:
   for action in ["remove","move"]:
    raw=legacy.duplicate(true);raw.shell_products["shell:west"]={"height":height,"material":"cream_stripe","paid_cost":int(Segments.LEGACY_PRICES[height])*9}
    raw.built_walls=[{"id":41,"axis":"z","x":0,"z":8,"height":"full","material":"leaf_print"}];raw.next_wall_id=42
    raw.wall_attachments=[{"id":77,"kind":"door","host_id":"shell:back","offset":5.5,"width":1.5,"paid_cost":40}];raw.next_attachment_id=78
    var transition=Model.new();var label=str([height,edited,action])
    check(transition.load_save(write("extension-transition",raw)),label+" inherited extension load")
    if edited:check(transition.replace_wall("shell:west#2",height,"sage_panels"),label+" prior neighbor purchase")
    var ledger=transition.shell_segment_products.duplicate(true);var roots=transition.shell_products.duplicate(true);var openings=transition.wall_attachments.duplicate(true)
    var old_totals=Segments.totals(Segments.state(roots,ledger),"shell:west",transition.built_walls);var wallet=transition.coins
    var ok=transition.remove_wall("z:0:8") if action=="remove" else transition.move_wall("z:0:8","x",0,9)
    check(ok,label+" extension action: "+transition.last_error)
    check(transition.coins==wallet+(27 if action=="remove" else 0),label+" only existing player-wall refund applies")
    check(transition.shell_segment_products==ledger,label+" every segment payment/style unchanged")
    check(transition.shell_products==roots and transition.wall_attachments==openings,label+" roots and openings unchanged")
    check(Segments.totals(Segments.state(roots,ledger),"shell:west",transition.built_walls)==old_totals,label+" exact aggregate paid/refund survives extent change")
    check(transition.get_wall_host("shell:west#8").paid_cost==0 and transition.get_wall_host("shell:west#8").refund_credit==0,label+" exposed ninth entry remains included")
    check(transition.save("user://extension-transition-result.json"),label+" save after extent change: "+transition.last_error)
    var restored=Model.new();check(restored.load_save("user://extension-transition-result.json"),label+" reload after extent change: "+restored.last_error)
    check(restored.shell_segment_products==ledger and restored.coins==transition.coins,label+" extent-change roundtrip preserves exact ledger/wallet")
    check(restored._next_wall_id==42 and restored._next_attachment_id==78,label+" counters unchanged")
    check(restored.replace_wall("shell:west#8",height,"leaf_print"),label+" newly exposed ninth tile can be purchased")
    check(restored.save("user://extension-transition-purchased.json"),label+" subsequent ninth purchase saves")
    var last=Model.new();check(last.load_save("user://extension-transition-purchased.json"),label+" subsequent ninth purchase reloads")
  var roots=Geometry.initial_shell_products("cream_stripe");roots["shell:west"]={"height":height,"material":"cream_stripe","paid_cost":int(Segments.LEGACY_PRICES[height])*9}
  var nine=Segments.migrate(roots,[]);var eight=Segments.migrate(roots,[{"axis":"z","x":0,"z":8}])
  nine.segments["shell:west#0"]=eight.segments["shell:west#0"].duplicate(true)
  check(Segments.validate(nine,[])!="",height+" incompatible historical bases cannot mix per index")
 var report={"checks":checks,"failures":failures,"player_save_used":false,"browser_verified":false,"native_pixels_verified":false}
 print("SHELL_SEGMENT_MODEL_RESULT ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
