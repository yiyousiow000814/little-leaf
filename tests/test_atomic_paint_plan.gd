extends SceneTree
const Model=preload("res://scripts/cafe_model.gd")
const Paint=preload("res://scripts/cafe_paint_plan.gd")
const Walls=preload("res://scripts/cafe_walls.gd")
var checks=0
var failures=[]
var notifications=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func fresh():
 var model=Model.new();model.coins=10000;return model
func snapshot(model)->String:
 return var_to_str([model.coins,model.revision,model.floor_finishes,model.built_walls,model.shell_segment_products,model.shell_products,model.wall_attachments,model.items,model.customers,model.dining_sets,model.owned_parcels,model._next_wall_id,model._next_attachment_id,model.decoration_build_purchases,model.decoration_purchases,model.last_event])
func observe(model):
 notifications.append({"coins":model.coins,"revision":model.revision,"walls":model.built_walls.size(),"floor":model.floor_finishes.duplicate(true)})
func _initialize():run.call_deferred()
func run():
 if not "saveguard" in OS.get_user_data_dir():printerr("Use an isolated saveguard profile");quit(2);return
 var model=fresh();var plan=Paint.new();var before=snapshot(model);model.last_error="preserved"
 var a=Vector2i(2,2);var b=Vector2i(3,2)
 var receipt=plan.prepare(model,"floor","cream_tile",[a,b,a,b])
 check(receipt.ok and receipt.count==2 and receipt.changed_count==2,"floor duplicates unique")
 check(receipt.paid==20 and receipt.refund==0 and receipt.net==20,"floor complete preview price")
 check(snapshot(model)==before and model.last_error=="preserved","floor prepare changes no model state or error")
 check(is_same(receipt,plan.prepare(model,"floor","cream_tile",[a,b,a,b])),"unchanged prepare reuses receipt")
 plan.invalidate();check(snapshot(model)==before,"cancel discards entire stroke")
 check(not plan.commit(model,receipt) and snapshot(model)==before,"cancelled receipt cannot commit")
 receipt=plan.prepare(model,"floor","cream_tile",[a,b,a,b])
 model.changed.connect(observe.bind(model));notifications.clear()
 var wallet=model.coins;var revision=model.revision
 check(plan.commit(model,receipt),"floor stroke commits")
 check(model.coins==wallet-20 and model.revision==revision+1 and notifications.size()==1,"floor charges and notifies exactly once")
 check(notifications[0].floor["2,2"].style=="cream_tile" and notifications[0].floor["3,2"].style=="cream_tile" and notifications[0].coins==wallet-20,"listener only sees complete floor stroke")
 before=snapshot(model);check(not plan.commit(model,receipt) and snapshot(model)==before,"receipt cannot be spent twice")
 receipt=plan.prepare(model,"floor","cream_tile",[a,b,Vector2i(4,2)])
 check(receipt.ok and receipt.count==3 and receipt.changed_count==1 and receipt.net==10,"matching floors are free noops")
 check(receipt.targets[0].action=="noop" and receipt.targets[1].action=="noop","noop targets available for drawing")
 receipt=plan.prepare(model,"floor","sage_tile",[a,b])
 check(receipt.ok and receipt.paid==24 and receipt.refund==10 and receipt.net==14,"floor replacement totals use existing half refund")
 wallet=model.coins;check(plan.commit(model,receipt) and model.coins==wallet-14,"floor replacement exact total")
 receipt=plan.prepare(model,"floor","sage_tile",[a,b]);before=snapshot(model);notifications.clear()
 check(receipt.ok and receipt.changed_count==0 and receipt.net==0,"all matching floor stroke is zero charge")
 check(plan.commit(model,receipt) and snapshot(model)==before and notifications.is_empty(),"all noop stroke emits no transaction")

 # No prefix can be installed when any later target is invalid or unaffordable.
 for bad in [Vector2i(-1,2),Vector2i(12,2),Vector2i(2,9),Vector2i(99,99)]:
  model=fresh();before=snapshot(model);receipt=plan.prepare(model,"floor","sage_tile",[a,b,bad])
  check(not receipt.ok and snapshot(model)==before,"unowned/outside floor preview atomic "+str(bad))
  check(not plan.commit(model,receipt) and snapshot(model)==before,"unowned/outside floor commit atomic "+str(bad))
 model=fresh();model.coins=19;before=snapshot(model)
 receipt=plan.prepare(model,"floor","cream_tile",[a,b])
 check(not receipt.ok and receipt.paid==20 and receipt.net==20 and receipt.count==2,"unaffordable floor retains full price")
 check(not plan.commit(model,receipt) and snapshot(model)==before,"unaffordable floor does not partially charge")
 model.coins=20;receipt=plan.prepare(model,"floor","cream_tile",[a,b])
 check(receipt.ok and plan.commit(model,receipt) and model.coins==0,"exact budget accepted")

 # Freshness includes direct changes that bypass revision notifications.
 for mutation in ["wallet","floor","ownership","session","ledger","wall","actor","revision"]:
  model=fresh();var actors=[];receipt=plan.prepare(model,"floor","cream_tile",[a,b],actors)
  match mutation:
   "wallet":model.coins-=1
   "floor":model.floor_finishes["2,2"]={"style":"sage_tile","paid_cost":12}
   "ownership":model.owned_parcels.append("front_0")
   "session":model.decoration_session_active=true
   "ledger":model.decoration_build_purchases["wall:99"]=55
   "wall":model.built_walls.append({"id":99,"axis":"x","x":8,"z":6,"height":"half","material":"leaf_print"})
   "actor":actors.append(Vector2(8.5,6.0))
   "revision":model._notify()
  before=snapshot(model)
  check(not plan.commit(model,receipt,actors) and snapshot(model)==before,"stale receipt rejected for "+mutation)
 model=fresh();receipt=plan.prepare(model,"floor","cream_tile",[a,b]);var copy=receipt.duplicate(true);before=snapshot(model)
 check(not plan.commit(model,copy) and snapshot(model)==before,"foreign receipt copy rejected")
 receipt.net=0;check(not plan.commit(model,receipt) and snapshot(model)==before,"mutated price receipt rejected")
 receipt=plan.prepare(model,"floor","cream_tile",[a,b]);receipt.targets[0].cell=Vector2i(6,6)
 check(not plan.commit(model,receipt) and snapshot(model)==before,"mutated target receipt rejected")
 var input=[a,b];receipt=plan.prepare(model,"floor","cream_tile",input);input.append(Vector2i(4,2))
 check(plan.commit(model,receipt) and model.coins==9980 and model.floor_style_at(Vector2i(4,2))=="warm_oak","caller cannot mutate private target request")

 # New walls and mixed replacements use the same model guards and prices.
 model=fresh();model.begin_decoration_session();before=snapshot(model)
 var first=Walls.make("x",8,6);var second=Walls.make("x",9,6)
 receipt=plan.prepare(model,"full","leaf_print",[first,second,first])
 check(receipt.ok and receipt.count==2 and receipt.changed_count==2 and receipt.paid==110 and receipt.refund==0,"wall duplicate edges priced once")
 check(snapshot(model)==before,"wall prepare is pure")
 wallet=model.coins;revision=model.revision;model.changed.connect(observe.bind(model));notifications.clear()
 check(plan.commit(model,receipt) and model.coins==wallet-110 and model.built_walls.size()==2,"wall stroke commits all edges")
 check(model.revision==revision+1 and notifications.size()==1 and notifications[0].walls==2 and notifications[0].coins==wallet-110,"wall listener sees one complete transaction")
 check(model._next_wall_id==3 and model.decoration_build_purchases=={"wall:1":55,"wall:2":55},"wall IDs and purchase receipts remain exact")
 var retained=model.built_walls[0]
 receipt=plan.prepare(model,"half","sage_panels",[first,second,Walls.make("x",10,6)])
 check(receipt.ok and receipt.paid==105 and receipt.refund==54 and receipt.net==51,"mixed replacements and new wall aggregate exact price")
 wallet=model.coins;check(plan.commit(model,receipt) and model.coins==wallet-51,"mixed wall transaction charged once")
 check(is_same(retained,model.built_walls[0]) and retained.height=="half" and retained.id==1,"existing wall identity and ID preserved")
 check(model._next_wall_id==4 and model.decoration_build_purchases=={"wall:1":35,"wall:2":35,"wall:3":35},"only new edge allocates ID; replacement updates receipts")
 before=snapshot(model);receipt=plan.prepare(model,"half","sage_panels",[first,second]);check(receipt.ok and receipt.net==0 and plan.commit(model,receipt) and snapshot(model)==before,"matching walls produce no charge or notify")

 # Original shell segments and aliases are geometric edges, not whole roots.
 model=fresh();model.begin_decoration_session();before=snapshot(model)
 var back=Walls.make("x",2,0)
 receipt=plan.prepare(model,"full","cream_stripe",[back,{"key":"shell:back#2"},Walls.make("x",3,0),first])
 check(receipt.ok and receipt.count==3 and receipt.paid==165 and receipt.refund==0,"shell and edge aliases deduplicate")
 check(receipt.targets[0].key=="shell:back#2" and receipt.targets[0].action=="replace","shell target resolves one segment")
 var original=model.shell_products.duplicate(true);var openings=model.wall_attachments.duplicate(true)
 check(plan.commit(model,receipt),"mixed original shell and new edge commits")
 check(model.shell_products==original and model.wall_attachments==openings,"shell roots and original opening stay unchanged")
 check(model.shell_segment_products["shell:back#2"].material=="cream_stripe" and model.shell_segment_products["shell:back#3"].material=="cream_stripe" and model.shell_segment_products["shell:back#4"].material=="original","only visited shell tiles changed")
 check(model.decoration_build_purchases=={"shell:back#2":55,"shell:back#3":55,"wall:1":55},"shell and built receipts have independent canonical keys")
 check(model.save("user://atomic-paint.json"),"stroke synthetic save succeeds")
 var loaded=Model.new();check(loaded.load_save("user://atomic-paint.json"),"stroke synthetic save restores")
 check(loaded.coins==model.coins and JSON.parse_string(JSON.stringify(loaded.built_walls))==JSON.parse_string(JSON.stringify(model.built_walls)) and loaded.shell_segment_products==model.shell_segment_products,"stroke payment and geometry roundtrip")
 check(loaded.decoration_build_purchases.is_empty(),"reload does not renew current-session refunds")

 # Removed shell segments are repurchased normally; historical odd credits
 # stay exact rather than being recomputed from a rounded whole-root price.
 model=fresh();check(model.remove_wall("shell:back#2"),"removed shell fixture")
 before=snapshot(model);receipt=plan.prepare(model,"full","leaf_print",[back,{"axis":"x","x":2,"z":0}])
 check(receipt.ok and receipt.count==1 and receipt.net==55 and receipt.targets[0].action=="place","removed shell edge costs one new wall")
 check(snapshot(model)==before and plan.commit(model,receipt),"removed shell repurchase commits atomically")
 check(model.shell_segment_products["shell:back#2"].removed and model.built_walls.size()==1,"repurchase preserves shell tombstone and new wall identity")
 model=fresh();model.shell_products["shell:back"]={"height":"full","material":"sage_panels","paid_cost":660}
 model.shell_segment_products=model.ShellSegments.migrate(model.shell_products,[]).segments
 receipt=plan.prepare(model,"half","leaf_print",[Walls.make("x",2,0),Walls.make("x",3,0)])
 check(receipt.ok and receipt.paid==70 and receipt.refund==55 and receipt.net==15,"historical per-segment odd credits remain exact")
 wallet=model.coins;check(plan.commit(model,receipt) and model.coins==wallet-15,"historical shell replacement credits once")
 model=fresh();check(model.buy_parcel("front_0"),"owned expansion fixture")
 model.coins=100;receipt=plan.prepare(model,"floor","cream_tile",[Vector2i(1,9),Vector2i(1,10)])
 check(receipt.ok and receipt.net==20 and receipt.targets[0].action=="place","unfloored purchased plot accepts stroke")
 check(plan.commit(model,receipt) and model.floor_style_at(Vector2i(1,10))=="cream_tile" and model.coins==80,"new plot floor publishes all tiles")

 # Every model wall constraint is evaluated against the whole growing shadow.
 for suffix in [Walls.make("x",12,12),Walls.make("x",99,99)]:
  model=fresh();before=snapshot(model);receipt=plan.prepare(model,"full","sage_panels",[first,suffix])
  check(not receipt.ok and not plan.commit(model,receipt) and snapshot(model)==before,"invalid later wall rolls back valid prefix "+str(suffix))
 model=fresh();model.coins=109;before=snapshot(model);receipt=plan.prepare(model,"full","leaf_print",[first,second])
 check(not receipt.ok and receipt.net==110 and not plan.commit(model,receipt) and snapshot(model)==before,"wall total budget rejects whole stroke")
 model=fresh();before=snapshot(model);receipt=plan.prepare(model,"full","leaf_print",[first,second],[Vector2(9.5,6.0)])
 check(not receipt.ok and receipt.error.contains("actor") and not plan.commit(model,receipt,[Vector2(9.5,6.0)]) and snapshot(model)==before,"actor crossing later wall rolls back earlier wall")
 model=fresh();check(model.place_wall_attachment("window","shell:back",2.5),"supported window fixture")
 before=snapshot(model);receipt=plan.prepare(model,"half","leaf_print",[first,back])
 check(not receipt.ok and not plan.commit(model,receipt) and snapshot(model)==before,"lowering supported opening rejects whole stroke")
 model=fresh();var box=[Walls.make("x",8,5),Walls.make("z",9,5),Walls.make("x",8,6),Walls.make("z",8,5)]
 before=snapshot(model);receipt=plan.prepare(model,"full","leaf_print",box,[Vector2(8.5,5.5)])
 check(not receipt.ok and receipt.error.contains("seal") and not plan.commit(model,receipt,[Vector2(8.5,5.5)]) and snapshot(model)==before,"combined enclosure fails atomically")
 model=fresh();check(model.place("stove",8,5),"stove fixture");before=snapshot(model)
 receipt=plan.prepare(model,"full","leaf_print",[Walls.make("x",10,6),Walls.make("x",8,6)])
 check(not receipt.ok and receipt.error.contains("Stove") and not plan.commit(model,receipt) and snapshot(model)==before,"stove workface protection retained")

 # Malformed requests stay read-only and never silently target another cell.
 for spec in [["floor","cream_tile",[]],["bad","cream_tile",[a]],["floor","bad",[a]],["floor","cream_tile",[null]],["floor","cream_tile",[{"x":2.5,"z":2}]],["full","leaf_print",[{"axis":"y","x":2,"z":2}]],["full","leaf_print",[{"key":"shell:back"}]]]:
  model=fresh();before=snapshot(model);receipt=plan.prepare(model,spec[0],spec[1],spec[2])
  check(not receipt.ok and not plan.commit(model,receipt) and snapshot(model)==before,"malformed stroke rejected "+str(spec))
 print("ATOMIC_PAINT_PLAN_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"player_save_used":false,"engine_model_only":true}))
 quit(0 if failures.is_empty() else 1)
