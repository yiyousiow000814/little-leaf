extends SceneTree
const Model=preload("res://scripts/cafe_model.gd")
const Contract=preload("res://scripts/cafe_save_contract.gd")
const Pause=preload("res://scripts/cafe_placement_pause.gd")
var checks=0
var failures=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func fixture():
 var m=Model.new();m.coins=50000;m._spawn_customer();m.customers.resize(1);m.operating_open=false;m.enable_footprint_placement()
 var g=m.customers[0];var chair=m.get_item(int(g.chair_id))
 g.phase="eating";g.x=float(chair.x)+.5;g.z=float(chair.z)+.5;g.seated=true;g.admitted=true;g.elapsed=2.0;g.duration=30.0;g.route=[];g.route_index=0
 g.erase("street_route_format");g.erase("street_origin_z")
 return m
func write(path:String,data:Dictionary):
 var file=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(data));file.close()
func _init():
 if not "saveguard" in OS.get_user_data_dir():quit(2);return
 var m=fixture();var g=m.customers[0];var identity=g;var before=g.duplicate(true);var wallet=m.coins
 for at in [Vector2i(8,5),Vector2i(10,5),Vector2i(9,6)]:check(m.place("plant",at.x,at.y),"owned physical obstruction purchase")
 check(m.move(int(g.table_id),9,4,0),"occupied logical table moves even when new seat is unreachable: "+m.last_error)
 check(is_same(identity,m.customers[0]) and g.id==before.id and g.table_id==before.table_id and g.chair_id==before.chair_id,"move preserves referenced guest and dining identity")
 check(Pause.blocked(g) and Vector2(g.x,g.z)==Vector2(before.x,before.z),"unreachable moved seat freezes actual body with explicit pending marker")
 var frozen=JSON.stringify(g)
 m.tick(1.0)
 check(JSON.stringify(g)==frozen,"blocked ticks preserve every guest phase/payload/clock/route field")
 check(m.coins==wallet-3*m.price_of("plant"),"occupied move charges nothing and obstruction purchases charge once")
 var path="user://occupied-placement.json"
 check(m.save_placement(path),"explicit v17 paused seat saves: "+m.last_error)
 var digest=FileAccess.get_sha256(path);var data=JSON.parse_string(FileAccess.get_file_as_string(path))
 check(data.version==17 and data.footprint_placement_format==Contract.FOOTPRINT_PLACEMENT_FORMAT,"separate explicit envelope capability")
 var loaded=Model.new()
 check(loaded.load_placement(path),"paused seat restores atomically: "+loaded.last_error)
 var codec=preload("res://scripts/cafe_runtime_codec.gd").new()
 check(FileAccess.get_sha256(path)==digest and loaded.coins==m.coins and JSON.stringify(codec.encode(loaded.customers[0].mobility))==JSON.stringify(codec.encode(g.mobility)),"restore preserves source bytes wallet and pending history")
 var old=Model.new();var old_items=old.items.duplicate(true);var old_wallet=old.coins
 check(not old.load_save(path) and old.items==old_items and old.coins==old_wallet,"normal historical API rejects v17 atomically")
 check(not m.save_placement(Contract.PRIMARY_FILE) and not m.save_placement("user://little_leaf_cafe_navigation_v16.json"),"explicit placement API refuses historical and private navigation paths")
 for variant in ["unknown","recursive","duplicate","position","downgrade","navigation","anchors"]:
  var bad=data.duplicate(true);var pending=bad.runtime.customers[0].mobility
  match variant:
   "unknown":pending["unknown"]=true
   "recursive":pending.previous=pending.duplicate(true)
   "duplicate":pending.anchors[1]=pending.anchors[0].duplicate(true)
   "position":pending.position={"$vector2":[2.5,2.5]}
   "downgrade":bad.version=15;bad.erase("footprint_placement_format")
   "navigation":bad.navigation_format="little_leaf.staff_navigation.v1"
   "anchors":pending.anchors[0].x=11
  var bad_path="user://occupied-bad-"+variant+".json";write(bad_path,bad)
  var bad_digest=FileAccess.get_sha256(bad_path);var state=JSON.stringify(loaded.customers);var money=loaded.coins
  check(not loaded.load_placement(bad_path),"reject "+variant+" capability/history")
  check(JSON.stringify(loaded.customers)==state and loaded.coins==money and FileAccess.get_sha256(bad_path)==bad_digest,"reject "+variant+" preserves state and input")
 check(m.remove(int(m.item_at(8,5).id)),"repair one actual obstruction")
 m.tick(.1)
 check(not Pause.blocked(g) and Vector2(g.x,g.z)==Vector2(before.x,before.z),"retry publishes legal cardinal replacement without stepping or snapping")
 var remaining=200
 while Model.FurnitureMotion.active(g) and remaining>0:m.tick(.1);remaining-=1
 var target=m.get_item(int(g.chair_id))
 check(not Model.FurnitureMotion.active(g) and g.seated and Vector2(g.x,g.z)==Vector2(float(target.x)+.5,float(target.z)+.5),"real movement reaches same owned seat after repair")
 check(g.phase==before.phase and g.elapsed==before.elapsed,"movement preserves meal phase and clock")
 var walking=fixture();var walker=walking.customers[0]
 walker.phase="arriving";walker.seated=false;walker.x=1.5;walker.z=5.5;walker.elapsed=.25;walker.duration=4.0;walker.route=[Vector2(2.5,5.5),Vector2(2.5,4.5),Vector2(3.5,4.5)];walker.route_index=0
 var route=walker.route.duplicate(true);var position=Vector2(walker.x,walker.z)
 for at in [Vector2i(0,5),Vector2i(1,4),Vector2i(1,6),Vector2i(2,5)]:check(walking.place("plant",at.x,at.y),"future route enclosure permits physical purchase")
 walking.tick(.5)
 check(Pause.blocked(walker) and walker.route==route and Vector2(walker.x,walker.z)==position and walker.elapsed==.25,"arriving route/index/body/clock remain historical while blocked")
 check(walking.save_placement("user://occupied-arriving.json"),"paused arriving cardinal history saves: "+walking.last_error)
 check(walking.remove(int(walking.item_at(2,5).id)),"reopen actual arrival corridor")
 walking.tick(.1)
 check(not Pause.blocked(walker) and Vector2(walker.x,walker.z)==position,"arrival resumes only after full route validation")
 walking.tick(.1)
 check(Vector2(walker.x,walker.z)!=position and walker.id==1,"arrival moves from actual coordinates without losing visit")
 checkout_cases()
 cancellation_cases()
 print("OCCUPIED_PLACEMENT_PROTOCOL_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 quit(0 if failures.is_empty() else 1)
func checkout_cases():
 var m=Model.new();m.coins=50000
 check(m.Checkout.ensure(m),"deploy actual included register")
 m._spawn_customer();m.operating_open=false;m.enable_footprint_placement()
 check(m.customers.size()==2,"two independent actual dining reservations")
 var item=m.Checkout.register(m);var front=m.workface_cell(item);var side=m.Checkout._optional_wait(m,item)
 for index in 2:
  var guest=m.customers[index];var cell=front if index==0 else side
  guest.phase="checkout_wait";guest.seated=false;guest.admitted=true;guest.x=float(cell.x)+.5;guest.z=float(cell.y)+.5;guest.route=[];guest.route_index=0;guest.elapsed=.2;guest.duration=0.0
  guest.checkout_register_id=int(item.id);guest.checkout_cell=cell;guest.checkout_ticket=index+1
  guest.erase("street_route_format");guest.erase("street_origin_z")
 m.next_checkout_ticket=3
 var first=m.customers[0];var second=m.customers[1]
 first.phase="paying";first.checkout_token=7
 check(m.place("plant",8,8),"block only future relocated register front")
 check(m.move(int(item.id),8,7,0),"move register with two live checkout identities: "+m.last_error)
 check(Pause.blocked(first) and Pause.blocked(second) and m.checkout_claims().is_empty(),"pending historical cells are dormant for every claim reader")
 check(m.Checkout.busy(m,int(item.id)),"dormant physical claims retain authoritative live cashier token ownership")
 var first_state=JSON.stringify(first);var second_state=JSON.stringify(second)
 m.tick(.5)
 check(JSON.stringify(first)==first_state and JSON.stringify(second)==second_state,"checkout pre-movement readers preserve both pending guests and clocks")
 check(m.save_placement("user://occupied-checkout.json"),"two pending FIFO/register/token histories serialize: "+m.last_error)
 check(m.remove(int(m.item_at(8,8).id)),"reopen new front without releasing tickets or payment token")
 m.tick(.1)
 check(not Pause.blocked(first) and not Pause.blocked(second),"both guests atomically receive legal current routes")
 check(first.checkout_cell!=second.checkout_cell and m.checkout_claims().size()==2,"current standing cells have distinct single owners")
 check(first.checkout_ticket==1 and first.checkout_token==7 and first.phase=="paying" and second.checkout_ticket==2,"reacquisition preserves FIFO token and payment phase")
 # A departing live body may still own the new front; a pending head must wait.
 var original=Model.FurnitureMotion.copy_model(m)
 check(m.place("table_set",3,6,0),"third independent dining identity for live claim competitor")
 var third=m.dining_sets[-1]
 var hold=m.customers[0].duplicate(true);hold.id=m._next_customer_id;m._next_customer_id+=1
 hold.table_id=int(third.table_id);hold.chair_id=int(third.seat_id);m.next_checkout_ticket=4
 var old_claim=first.checkout_cell
 Pause.pause(original,first)
 hold.phase="leaving";hold.paid=true;hold.checkout_ticket=3;hold.checkout_token=9;hold.checkout_cell=old_claim;hold.mobility={};hold.x=float(old_claim.x)+.5;hold.z=float(old_claim.y)+.5
 m.Checkout.depart(m,hold)
 m.customers.append(hold)
 check(m.save_placement("user://occupied-live-competitor.json"),"live competing guest has distinct validated dining/FIFO identity: "+m.last_error)
 m._placement_pause_revision.clear()
 var pending=JSON.stringify(first)
 check(not Pause.retry(m,first) and JSON.stringify(first)==pending,"live competing claim prevents pending head from partially acquiring or moving")
 m.customers.erase(hold)
 check(Pause.retry(m,first) and first.checkout_cell==old_claim,"claim release allows exactly one complete retry without a new layout edit")

func cancellation_cases():
 var m=Model.new();m._spawn_customer();m.enable_footprint_placement()
 var guest=m.customers[0];var actual=Vector2(guest.x,guest.z);var id=guest.id
 Pause.pause(m,guest)
 check(Pause.blocked(guest),"exterior arrival may hold an explicit pending intent")
 check(m.save_placement("user://occupied-exterior.json"),"pending actual public lane serializes: "+m.last_error)
 check(m.set_operating_open(false),"explicit close cancels only unadmitted exterior arrival")
 check(not Pause.blocked(guest) and guest.withdrawn and guest.phase=="leaving" and guest.id==id and Vector2(guest.x,guest.z)==actual,"close replaces exterior intent without teleporting or replacing identity")
 check(m.save_placement("user://occupied-exterior-cancelled.json"),"cancelled exterior route remains readable: "+m.last_error)
 var loaded=Model.new()
 check(loaded.load_placement("user://occupied-exterior-cancelled.json") and loaded.customers[0].withdrawn,"cancelled exterior route reloads without resurrecting reservation")
 var seated=fixture();var path="user://occupied-write-atomic.json"
 check(seated.save_placement(path),"valid existing save for failed-write preservation")
 check(seated.save("user://occupied-copy-v15.json"),"ordinary unblocked fixture remains strictly v15 writable")
 check(not loaded.load_placement("user://occupied-copy-v15.json"),"explicit placement reader refuses silent v15 profile promotion")
 var digest=FileAccess.get_sha256(path);var guest_state=JSON.stringify(seated.customers)
 seated.customers[0].x+=.1
 check(not seated.save_placement(path) and FileAccess.get_sha256(path)==digest,"invalid current seated body cannot overwrite accepted destination")
 seated.customers[0].x-=.1
 check(JSON.stringify(seated.customers)==guest_state,"failed save never normalizes live body/history")
 var bad=JSON.parse_string(FileAccess.get_file_as_string(path));bad.runtime.customers[0].x+=.1
 write("user://occupied-unmarked-body.json",bad)
 check(not loaded.load_placement("user://occupied-unmarked-body.json"),"unmarked v17 body must match current seat rather than historical anchor")

