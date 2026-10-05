extends SceneTree
## Focused design contract, not a production migration or full game test suite.
const Segments=preload("res://qa/prototypes/shell_segment_contract.gd")
const Model=preload("res://scripts/cafe_model.gd")
const Geometry=preload("res://scripts/cafe_wall_openings.gd")
var checks=0
var failures=[]
var cases=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func same(value)->String:return JSON.stringify(value)
func _initialize():run.call_deferred()
func run():
 if not "saveguard" in OS.get_user_data_dir():printerr("Use the isolated prototype runner");quit(2);return
 for extension in [false,true]:
  var walls=[{"id":41,"axis":"z","x":0,"z":8,"height":"full","material":"leaf_print"}] if extension else []
  for height in ["half","full"]:
   for material in ["original","sage_panels","cream_stripe","leaf_print"]:
    for multiplier in [0,8,9]:
     var price=int(Segments.Walls.PRICES[height]);var products=Geometry.initial_shell_products(material)
     products["shell:back"]={"height":height,"material":material,"paid_cost":0 if multiplier==0 else price*12}
     products["shell:west"]={"height":height,"material":material,"paid_cost":price*multiplier}
     var before=same([products,walls]);var state=Segments.migrate(products,walls)
     var label=str([extension,height,material,multiplier])
     check(Segments.validate(state,walls)=="",label+" migrated state validates")
     check(same([products,walls])==before,label+" input roots and player walls unchanged")
     check(state.segments.size()==21,label+" canonical 12+9 segment identities")
     for root_id in Geometry.SHELL_HOSTS:
      var totals=Segments.totals(state,root_id,walls)
      check(totals.paid_cost==products[root_id].paid_cost,label+" exact paid value "+root_id)
      check(totals.refund_credit==int(products[root_id].paid_cost)/2,label+" exact legacy refund "+root_id)
      check(Segments.uses_original_renderer(state,walls,root_id),label+" homogeneous rendering delegates unchanged original path")
      var root_host=Geometry.resolve_host(root_id,walls,products)
      var cursor=root_host.a
      for index in Segments.active_count(root_id,walls):
       var cell=Segments.segment_host(state,walls,root_id,index)
       check(cell.a==cursor and is_equal_approx(cell.a.distance_to(cell.b),1),label+" contiguous one-grid geometry")
       check(cell.normal==root_host.normal and cell.shell and cell.host_id==root_id,label+" root identity and .26 thickness preserved")
       cursor=cell.b
       var snapshot=same(state)
       var replacement=Segments.replace(state,walls,[],root_id,index,"full","cream_stripe" if material!="cream_stripe" else "sage_panels",10000)
       check(replacement.ok,label+" single-cell style edit succeeds")
       check(same(state)==snapshot,label+" prototype returns copy, no input mutation")
       for other in state.segments:
        if other!=cell.segment_key:check(replacement.state.segments[other]==state.segments[other],label+" neighbor appearance/payment unchanged "+other)
       check(replacement.state.roots==state.roots,label+" original root snapshots unchanged")
       check(replacement.coins==10000-int(replacement.quote.net),label+" exact one-cell bill")
       check(Segments.validate(replacement.state,walls)=="",label+" post-edit ledger validates")
      check(cursor==root_host.b,label+" exact root extent, no gaps or overlaps")
     if not extension and multiplier==8:check(state.segments["shell:west#8"].paid_cost==0 and state.segments["shell:west#8"].refund_credit==0,label+" added ninth tile stays included")
     if extension:check(Segments.segment_host(state,walls,"shell:west",8).is_empty(),label+" retained player extension remains authoritative")
 var products=Geometry.initial_shell_products("cream_stripe");products["shell:west"].paid_cost=495
 var state=Segments.migrate(products,[])
 check(Segments.totals(state,"shell:west",[]).refund_credit==247,"495 paid retains247 refund, not243")
 cases.append({"paid":495,"refund":247,"credits":range(9).map(func(i):return state.segments[Segments.key("shell:west",i)].refund_credit)})
 var original=state.duplicate(true);var first=Segments.replace(state,[],[],"shell:west",4,"half","sage_panels",1000)
 check(first.ok and Segments.render_runs(first.state,[],"shell:west").size()==3,"one edited middle segment produces at most three root-aligned render runs")
 check(Segments.replace(first.state,[],[],"shell:west",4,"half","sage_panels",first.coins).coins==first.coins,"same-style repeat cannot charge")
 var denied=Segments.replace(original,[],[],"shell:west",4,"full","leaf_print",0)
 check(not denied.ok and denied.state==original and denied.coins==0,"insufficient funds are atomic and nonmutating")
 # Aperture boundaries are half-open: a one-cell opening supports only its cell;
 # legacy wide/moved openings can span two or three cells without ID rewrites.
 for spec in [["door",5.5,1.0,[5]],["door",5.5,1.5,[4,5,6]],["door",5.0,.76,[4,5]],["window",4.0,.70,[3,4]]]:
  var opening={"id":77,"kind":spec[0],"host_id":"shell:west","offset":spec[1],"width":spec[2],"paid_cost":0}
  var before=same(opening);var aperture=Geometry.aperture(opening,[],products)
  check(Segments.support_error(state,[],[opening])=="","full support accepts "+str(spec))
  for index in 9:
   var candidate=Segments.replace(state,[],[opening],"shell:west",index,"half","leaf_print",1000)
   check(candidate.ok==(index not in spec[3]),"exact covered segments enforce full height "+str(spec)+" index"+str(index))
   check(same(opening)==before and Geometry.aperture(opening,[],products)==aperture,"attachment identity/geometry unchanged")
 # A current v15 fixture stays byte-identical, and the old loader must reject
 # wall_format2 rather than silently flattening mixed segment state.
 var model=Model.new();model.coins=12345
 check(model.save("user://baseline-v15.json"),"synthetic v15 baseline saves")
 var path="user://baseline-v15.json";var source_hash=FileAccess.get_sha256(path)
 var raw=JSON.parse_string(FileAccess.get_file_as_string(path));var load=Model.new()
 check(load.load_save(path),"current loader accepts original v15")
 var before=same([load.coins,load.built_walls,load.wall_attachments,load.shell_products])
 var candidate=raw.duplicate(true);candidate.wall_format=2;candidate.shell_segment_format=Segments.FORMAT;candidate.shell_segment_products=Segments.migrate(load.shell_products,load.built_walls).segments
 var file=FileAccess.open("user://candidate-format2.json",FileAccess.WRITE);file.store_string(JSON.stringify(candidate));file.close()
 check(not load.load_save("user://candidate-format2.json"),"shipped loader explicitly rejects wall_format2")
 check(same([load.coins,load.built_walls,load.wall_attachments,load.shell_products])==before,"older-reader rejection leaves model unchanged")
 check(FileAccess.get_sha256(path)==source_hash,"baseline source bytes unchanged")
 var encoded=JSON.stringify(state);var decoded=Segments.decode(JSON.parse_string(encoded),[])
 check(decoded.ok and same(decoded.state)==encoded,"segment JSON round-trip preserves numeric ledger and identities")
 for damage in ["missing","extra","negative","refund","dormant"]:
  var damaged=state.duplicate(true);var walls=[]
  match damage:
   "missing":damaged.segments.erase("shell:west#3")
   "extra":damaged.segments["shell:west#9"]=damaged.segments["shell:west#0"].duplicate()
   "negative":damaged.segments["shell:west#0"].paid_cost=-1
   "refund":damaged.segments["shell:west#0"].refund_credit=99
   "dormant":walls=[{"id":41,"axis":"z","x":0,"z":8,"height":"full","material":"leaf_print"}]
  check(Segments.validate(damaged,walls)!="","malformed state rejected "+damage)
 var report={"checks":checks,"failures":failures,"cases":cases,"prototype_only":true,"production_code_modified":false,"player_save_used":false,"pixel_equivalence_verified":false,"browser_storage_verified":false}
 print("SHELL_SEGMENT_CONTRACT_RESULT ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
