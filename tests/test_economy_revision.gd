extends SceneTree
const Model=preload("res://scripts/cafe_model.gd")
const MinimalStart=preload("res://scripts/minimal_start.gd")
const Sets=preload("res://scripts/cafe_dining_sets.gd")
const Checkout=preload("res://scripts/cafe_checkout.gd")
var checks=0
var failures=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func fresh(coins:int=10000):
 var model=Model.new();MinimalStart.apply(model);model.coins=coins;return model
func state(model)->String:
 return JSON.stringify([model.coins,model.served,model.total_earned,model.items,model.dining_sets,model._next_item_id,model.revision,model.payroll_elapsed,model.payroll_accrued,model.wages_due,model.total_wages_paid,model.customers,model.service_snapshot])
func normalized_items(raw:Array)->Array:
 # JSON reads numbers as floats; the loader validates and stores integer fields.
 var result=[]
 for entry in raw:
  var item=entry.duplicate(true)
  if item.get("kind","")=="stove":item.erase("level")
  for key in ["id","x","z","rot","level"]:
   if item.has(key):item[key]=int(item[key])
  result.append(item)
 return result
func write(name:String,data:Dictionary)->String:
 var path="user://"+name+".json";var file=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(data));file.close();return path
func _initialize():run.call_deferred()
func run():
 if not "saveguard" in OS.get_user_data_dir():printerr("Use an isolated generated profile");quit(2);return
 var model=fresh();var before=state(model)
 check(model.price_of("table_set")==280 and Sets.VARIANTS.oak_single.price==280,"storefront and dining product both quote approved280")
 check(model.wage_rate()==50 and model.WAGE_RATES=={"chef":18,"waiter":11,"cleaner":10,"cashier":11},"included four-role roster costs50 per future game minute")
 check(model.MEAL_PAYMENT==200,"new settlement rate is200")
 check(model.HIRE_FEES=={"chef":2800,"waiter":2200,"cleaner":1800},"hire fees retain their existing prices")
 check(model.dining_sets[0].paid_cost==140 and model.logical_refund(6)==70,"included starter retains its existing140 basis and70 refund")
 check(model.price_of("table")==100 and model.price_of("chair")==40 and model.price_of("bench")==75,"legacy individual furniture prices are unchanged")
 check(state(model)==before,"price and refund quotes never mutate progress")
 # Buying either side of a logical set is one purchase; either side sells both.
 for spec in [["table_set",280,140],["table_set_cottage",420,210],["table_set_retro",1200,600],["table_set_refined",3600,1800]]:
  for sell_seat in [false,true]:
   var m=fresh();var wallet=m.coins;var next_id=m._next_item_id;var label=str(spec[0])+" seat="+str(sell_seat)
   check(m.place(str(spec[0]),3,6),label+" purchase succeeds: "+m.last_error)
   var group=m.dining_set_for(next_id).duplicate(true)
   check(m.coins==wallet-int(spec[1]) and group.paid_cost==spec[1],label+" one exact charge and immutable paid basis")
   check(m._next_item_id==next_id+2 and m.logical_members(next_id)==[next_id,next_id+1],label+" two stable members form one group")
   check(m.logical_refund(next_id)==spec[2] and m.logical_refund(next_id+1)==spec[2],label+" either selection quotes the same historical refund")
   check(m.move(next_id+1,5,6,0),label+" moving by seat preserves logical group")
   for repeat in 3:m.rebuild_dining_sets()
   check(m.coins==wallet-int(spec[1]) and m.dining_set_for(next_id).paid_cost==spec[1],label+" move/rebuild never reprice or recharge")
   var path="user://new-set.json";check(m.save(path),label+" saved: "+m.last_error)
   var hash_before=FileAccess.get_sha256(path);var loaded=Model.new();check(loaded.load_save(path),label+" reload: "+loaded.last_error)
   check(FileAccess.get_sha256(path)==hash_before and loaded.coins==m.coins and loaded.dining_sets==m.dining_sets,label+" roundtrip keeps wallet, source bytes and paid bases")
   check(loaded.remove(next_id+1 if sell_seat else next_id),label+" sale succeeds")
   check(loaded.coins==wallet-int(spec[1])+int(spec[2]) and loaded.get_item(next_id).is_empty() and loaded.get_item(next_id+1).is_empty(),label+" sale removes both members and credits exactly once")
   before=state(loaded);check(not loaded.remove(next_id) and state(loaded)==before,label+" repeated sale cannot create a second refund")
 # Insufficient funds, occupied tiles, and removal of the last table are atomic.
 var poor=fresh(279);before=state(poor)
 check(not poor.place("table_set",3,6) and state(poor)==before,"279 coins cannot buy280 and failed purchase consumes no IDs or money")
 model=fresh();before=state(model)
 check(not model.place("table_set",3,3) and state(model)==before,"overlapping group placement does not charge")
 check(not model.remove(7) and state(model)==before,"last usable table sale fails without refund or losing either member")
 # Hidden legacy individual purchases keep their old component basis when paired.
 var wallet=0
 for seat_spec in [["chair",140,70],["bench",175,87]]:
  var loose=fresh();wallet=loose.coins;var tid=loose._next_item_id
  check(loose.place("table",2,1) and loose.coins==wallet-100,"legacy individual table still costs100")
  check(loose.place(str(seat_spec[0]),2,2) and loose.coins==wallet-int(seat_spec[1]),"legacy individual seat keeps its price: "+str(seat_spec[0]))
  check(loose.dining_set_for(tid).paid_cost==seat_spec[1] and loose.logical_refund(tid)==seat_spec[2],"automatic old-component pairing retains historical basis: "+str(seat_spec[0]))
  check(loose.save("user://legacy-components.json"),"legacy component pair saves")
  var paired=Model.new();check(paired.load_save("user://legacy-components.json"),"legacy component pair reloads")
  check(paired.remove(tid+1) and paired.coins==wallet-int(seat_spec[1])+int(seat_spec[2]),"paired component sale preserves half-cost rounding once")
 for spec in [["table",10,6,100,50],["chair",1,7,40,20]]:
  var m=fresh();var id=m._next_item_id;wallet=m.coins
  check(m.place(spec[0],spec[1],spec[2]),"standalone "+str(spec[0])+" places")
  check(m.dining_set_for(id).is_empty() and m.logical_refund(id)==spec[4],"standalone component quote remains unchanged")
  check(m.remove(id) and m.coins==wallet-int(spec[3])+int(spec[4]),"standalone component sale retains original refund")
 # Use the existing synthetic pre-change v15 snapshot, including real payroll.
 var legacy_path="res://tests/fixtures/startup-retry-v15.json";var legacy_hash=FileAccess.get_sha256(legacy_path)
 var original=JSON.parse_string(FileAccess.get_file_as_string(legacy_path))
 for omitted_cost in [false,true]:
  var raw=original.duplicate(true)
  if omitted_cost:raw.dining_sets[0].erase("paid_cost")
  raw.total_earned=2500;raw.served=10;raw.payroll_elapsed=30.0;raw.payroll_accrued=35.25;raw.wages_due=17;raw.total_wages_paid=145
  var path=write("legacy-economy",raw);var input_hash=FileAccess.get_sha256(path);var m=Model.new()
  check(m.load_save(path),"historical v15 loads with omitted_cost="+str(omitted_cost)+": "+m.last_error)
  check(m.coins==raw.coins and m.total_earned==2500 and m.served==10,"loading never reprices old meals or credits/debits wallet")
  check(m.items==normalized_items(raw.items) and m._next_item_id==int(raw.next_item_id),"old furniture identities/positions and next ID survive")
  check(m.dining_sets[0].paid_cost==140 and m.logical_refund(7)==70,"recorded and missing legacy group bases remain140")
  check(m.payroll_elapsed==30.0 and m.payroll_accrued==35.25 and m.wages_due==17 and m.total_wages_paid==145,"old accrued payroll, debt and historical paid wages load exactly")
  check(FileAccess.get_sha256(path)==input_hash,"legacy input bytes remain unchanged")
  before=state(m);m.advance_payroll(60.0,false);check(state(m)==before,"paused/off-duty time never accrues or collects debt")
  wallet=m.coins;var payroll=m.advance_payroll(30.0,true)
  check(payroll.charged==60 and payroll.paid==77 and m.coins==wallet-77,"old35.25 accrual plus new25 costs60, then pays existing17 debt once")
  check(m.payroll_elapsed==0.0 and is_equal_approx(m.payroll_accrued,.25) and m.wages_due==0 and m.total_wages_paid==222,"partial historical cycle retains fractional carry and exact paid ledger")
  check(m.save("user://mixed-payroll.json"),"mixed-rate payroll saves")
  var reloaded=Model.new();check(reloaded.load_save("user://mixed-payroll.json"),"mixed-rate payroll reloads")
  wallet=reloaded.coins;payroll=reloaded.advance_payroll(60.0,true)
  check(payroll.charged==50 and payroll.paid==50 and reloaded.coins==wallet-50 and is_equal_approx(reloaded.payroll_accrued,.25),"next full game minute uses50 and keeps prior fractional carry")
  wallet=reloaded.coins;check(reloaded.place("table_set",3,6),"new280 purchase coexists with old140 table")
  var new_id=reloaded._next_item_id-2
  check(reloaded.dining_set_for(new_id).paid_cost==280 and reloaded.dining_set_for(6).paid_cost==140,"mixed-age group bases stay independent")
  check(reloaded.remove(7) and reloaded.coins==wallet-280+70,"old group sale after new purchase refunds historical70")
 check(FileAccess.get_sha256(legacy_path)==legacy_hash,"tracked legacy fixture is untouched")
 # Reject invented bases before mutating a live model; zero is not a historic oak price.
 for invalid in [-1,0,139,141,279,281,420,140.5,"280"]:
  var raw=original.duplicate(true);raw.dining_sets[0].paid_cost=invalid;var live=fresh(7777);before=state(live)
  check(not live.load_save(write("bad-basis",raw)) and state(live)==before,"invalid paid basis rejects atomically: "+str(invalid))
 # The lower wage rate applies to newly worked time, including partial debt repayment.
 var debt=fresh(5);debt.wages_due=17;debt.total_wages_paid=100
 var paid=debt.advance_payroll(30,true)
 check(paid.paid==5 and paid.charged==0 and debt.coins==0 and debt.wages_due==12 and debt.payroll_accrued==25 and debt.total_wages_paid==105,"insufficient cash pays only available funds without rewriting debt")
 debt.coins=100;paid=debt.advance_payroll(30,true)
 check(paid.charged==50 and paid.paid==62 and debt.coins==38 and debt.wages_due==0 and debt.total_wages_paid==167,"later cash pays old debt and new50 wage bill exactly once")
 model=fresh();wallet=model.coins
 check(model.place("stove",7,1) and model.hire_staff("chef"),"existing stove and chef hiring path remains available")
 check(model.coins==wallet-220-2800 and model.wage_rate()==68,"unchanged hire charge adds only18 per future minute")
 model=fresh();wallet=model.coins
 check(not model.has_method("upgrade_stove") and not model.has_method("stove_upgrade_cost") and model.coins==wallet and not model.get_item(1).has("level"),"no new stove upgrade purchase; starter has no upgrade level")
 # User rejected retained upgrade effects: load old copies at base speed without
 # touching their file, wallet, furniture identity or unrelated progress.
 for level in [1,2,3]:
  var historical=fresh(777);var path="user://stove-base-fixture.json"
  check(historical.save(path),"base fixture saves: "+str(level))
  var raw=JSON.parse_string(FileAccess.get_file_as_string(path))
  for entry in raw.items:
   if entry.kind=="stove":entry.level=level
  path=write("historical-stove-level-%d"%level,raw)
  var identity=historical.get_item(1).duplicate(true)
  var saved_hash=FileAccess.get_sha256(path);var restored=Model.new()
  check(restored.load_save(path) and restored.coins==777 and restored.get_item(1)==identity,"legacy level normalizes without balance/identity change: "+str(level))
  check(is_equal_approx(Model.stove_speed_multiplier(restored.get_item(1)),1.0) and is_equal_approx(Model.cooking_seconds(Model.stove_speed_multiplier({"level":level})),45.0),"legacy level has base cooking behavior: "+str(level))
  check(FileAccess.get_sha256(path)==saved_hash,"loading never rewrites historical input: "+str(level))
  check(restored.save("user://normalized-stove-%d.json"%level),"normalized stove saves: "+str(level))
  var normalized=JSON.parse_string(FileAccess.get_file_as_string("user://normalized-stove-%d.json"%level))
  check(normalized.items.all(func(entry):return entry.kind!="stove" or not entry.has("level")),"new save omits every stove level: "+str(level))
  var roundtrip=Model.new()
  check(roundtrip.load_save("user://normalized-stove-%d.json"%level) and roundtrip.coins==777 and roundtrip.get_item(1)==identity,"normalized identity/balance survives second reload: "+str(level))
 # A stale live object cannot serialize a bonus or mutate itself through save.
 model=fresh(777);model.get_item(1).level=3;before=state(model)
 check(model.save("user://stale-live-stove.json") and state(model)==before,"save normalizes a copy without mutating live state")
 var cleaned=Model.new()
 check(cleaned.load_save("user://stale-live-stove.json") and not cleaned.get_item(1).has("level") and cleaned.coins==777,"stale live upgrade never survives save/reload")
 for invalid in [0,4,-1,1.5,"2"]:
  var raw=JSON.parse_string(FileAccess.get_file_as_string("user://stove-base-fixture.json"))
  for entry in raw.items:
   if entry.kind=="stove":entry.level=invalid
  var live=fresh(777);before=state(live)
  check(not live.load_save(write("invalid-stove-level",raw)) and state(live)==before,"invalid historical level rejects atomically: "+str(invalid))
 # Exercise the actual atomic register settlement, including historical earnings.
 model=fresh();model.total_earned=2500;model.served=10;model._spawn_customer()
 var guest=model.customers[0];var register=model.checkout_register();var front=model.workface_cell(register)
 guest.phase="checkout_wait";guest.seated=false;guest.paid=false;guest.checkout_ticket=1;guest.checkout_token=-1
 guest.checkout_register_id=int(register.id);guest.checkout_cell=front;guest.route=[];guest.route_index=0;guest.x=front.x+.5;guest.z=front.y+.5
 wallet=model.coins
 check(Checkout.begin(model,int(guest.id),1,int(register.id),19),"real register checkout begins")
 before=state(model);check(not Checkout.commit(model,int(guest.id),1,int(register.id),20) and state(model)==before,"wrong checkout token cannot award money")
 check(Checkout.commit(model,int(guest.id),1,int(register.id),19),"real register checkout settles")
 check(model.coins==wallet+200 and model.total_earned==2700 and model.served==11,"new payment adds200 while preserving historical2500")
 before=state(model);check(not Checkout.commit(model,int(guest.id),1,int(register.id),19) and state(model)==before,"duplicate checkout has no extra payment")
 # Legacy in-flight guests without a deployed register use the same new payout.
 var legacy=Model.new();legacy._spawn_customer();guest=legacy.customers[0]
 guest.phase="eating";guest.duration=6.0;guest.elapsed=5.95;guest.settlement_mode="legacy";guest.seated=true;guest.admitted=true
 wallet=legacy.coins;legacy.tick(.05)
 check(legacy.coins==wallet+200 and legacy.total_earned==200 and legacy.served==1,"legacy settlement awards exactly200 for future completion")
 print("ECONOMY_REVISION_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"meal_payment":200,"wages":[18,11,10,11],"table_price":280,"historical_oak_bases":[140,280]}))
 quit(0 if failures.is_empty() else 1)
