extends SceneTree
const Model=preload("res://scripts/cafe_model.gd")
const Start=preload("res://scripts/minimal_start.gd")
const Plan=preload("res://scripts/cafe_edit_plan.gd")
class TestMain extends "res://scripts/main.gd":
 var saves=0
 var save_success=true
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():saves+=1;return save_success
var checks=0
var failures=[]
var observations=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func fresh():
 var m=Model.new();Start.apply(m);m.coins=10000;return m
func _initialize():run.call_deferred()
func run():
 if not "saveguard" in OS.get_user_data_dir():printerr("Use isolated generated profile");quit(2);return
 var baseline="--refund-baseline" in OS.get_cmdline_user_args()
 for spec in [["table_set",280,140],["table_set_cottage",420,210],["table_set_retro",1200,600],["table_set_refined",3600,1800],["plant",45,22]]:
  for seat in [false,true] if str(spec[0]).begins_with("table_set") else [false]:
   var m=fresh();var wallet=m.coins;var id=m._next_item_id
   if not baseline:m.begin_decoration_session()
   check(m.place(spec[0],3,6),"purchase "+str(spec)+": "+m.last_error)
   var selected=id+1 if seat else id;var paid=wallet-m.coins
   var expected=int(spec[2]) if baseline else paid
   check(m.logical_refund(selected)==expected,"current-session quote for "+str(spec[0]))
   check(m.move(selected,5,6,1),"move and rotate: "+m.last_error)
   for i in 3:m.rebuild_dining_sets()
   check(m.logical_refund(selected)==expected and m.coins==wallet-paid,"move/rotate/rebuild preserve receipt")
   check(m.remove(selected),"sell succeeds")
   observations.append({"kind":spec[0],"purchase":paid,"refund_before_done":m.coins-wallet+paid,"wallet_loss":wallet-m.coins})
   check(m.coins==wallet-paid+expected,"exact refund once")
   var after=m.coins;check(not m.remove(selected) and m.coins==after,"second sale cannot credit")
 if baseline:
  print("DECORATION_REFUND_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"observations":observations,"baseline":true}));quit(0 if failures.is_empty() else 1);return
 var m=fresh();m.begin_decoration_session();var wallet=m.coins
 check(m.logical_refund(6)==70,"old starter retains140 basis and70 quote")
 var id=m._next_item_id;check(m.place("table_set",3,6),"new set")
 m.begin_decoration_session();check(m.logical_refund(id)==280,"idempotent entry keeps receipts")
 var planner=Plan.new();var receipt=planner.prepare(m,"plant",-1,0,Vector2i(8,6));var pending_id=m._next_item_id
 check(receipt.ok,"plant preview")
 check(m.get_item(pending_id).is_empty() and not m.decoration_purchases.has(pending_id),"preview does not purchase")
 planner.invalidate();check(m.coins==wallet-280 and m.logical_refund(id)==280,"cancel preview preserves receipt")
 receipt=planner.prepare(m,"plant",-1,0,Vector2i(8,6));check(planner.commit(m,receipt),"planner commits once")
 check(m.logical_refund(pending_id)==m.price_of("plant"),"planner publishes receipt")
 check(not planner.commit(m,receipt),"duplicate receipt rejected")
 wallet=m.coins;check(not m.place("plant",8,6) and m.coins==wallet,"overlap does not charge")
 check(not m.remove(int(m.items.filter(func(i):return i.kind=="stove")[0].id)) and m.coins==wallet and m.logical_refund(id)==280,"essential sale failure preserves eligibility")
 check(m.save("user://interrupted-decoration.json"),"autosave")
 check(m.logical_refund(id)==280,"saving retains live session")
 var loaded=Model.new();check(loaded.load_save("user://interrupted-decoration.json"),"interrupted save loads")
 check(not loaded.decoration_session_active and loaded.decoration_purchases.is_empty(),"reload finalizes session")
 check(loaded.coins==m.coins and loaded.logical_refund(id)==140 and loaded.logical_refund(6)==70,"reload preserves wallet and historical bases")
 check(not m.load_save("user://missing-decoration.json") and m.logical_refund(id)==280,"failed load keeps receipt")
 check(m.load_save("user://interrupted-decoration.json") and m.logical_refund(id)==140,"same-object load clears receipt")
 loaded.begin_decoration_session();check(loaded.logical_refund(id)==140,"reentry cannot renew old purchase")
 var stale=Plan.new();receipt=stale.prepare(loaded,"plant",-1,0,Vector2i(9,6));loaded.finish_decoration_session();wallet=loaded.coins
 check(not stale.commit(loaded,receipt) and loaded.coins==wallet,"Done rejects stale preview")
 m=fresh();m.begin_decoration_session();id=m._next_item_id;wallet=m.coins
 check(m.place("table_set",3,6),"Done purchase");m.finish_decoration_session();m.finish_decoration_session()
 check(m.logical_refund(id)==140 and m.dining_set_for(id).paid_cost==280,"Done keeps paid basis")
 m.begin_decoration_session();check(m.remove(id+1) and m.coins==wallet-140,"later sale refunds50 percent")
 m=fresh();m.begin_decoration_session();id=m._next_item_id;wallet=m.coins
 check(m.place("plant",3,6) and m.remove(id,false) and m.coins==wallet-m.price_of("plant"),"no-refund removal consumes receipt")
 check(not m.decoration_purchases.has(id) and m.logical_refund(id)==0,"removed item no entitlement")
 m=fresh();id=m._next_item_id;check(m.place("table",2,1),"old loose table")
 m.begin_decoration_session();check(m.place("chair",2,2),"new chair joins old table")
 check(m.logical_refund(id)==90,"mixed group old table50 plus new chair40")
 wallet=m.coins;check(m.remove(id+1) and m.coins==wallet+90 and m.decoration_purchases.is_empty(),"mixed group credits once")
 m=fresh();m.begin_decoration_session();m.included_bin_pending=true;id=m._next_item_id;wallet=m.coins
 check(m.place("bin",3,6) and m.logical_refund(id)==0,"free included bin has zero session refund")
 check(m.remove(id) and m.coins==wallet,"free item cannot produce current-session money")
 m.reset_new();check(not m.decoration_session_active and m.decoration_purchases.is_empty(),"new profile clears session")
 # Reset a nonempty receipt ledger, then reuse the exact physical ID.
 m=fresh();m.begin_decoration_session();id=m._next_item_id;check(m.place("plant",3,6),"reset case eligible odd-priced plant")
 check(m.logical_refund(id)==45 and not m.decoration_purchases.is_empty(),"reset starts with nonempty receipt")
 Start.apply(m);check(not m.decoration_session_active and m.decoration_purchases.is_empty() and m._next_item_id==id,"fresh profile clears nonempty receipt and reuses counter")
 check(m.place("plant",3,6) and m.logical_refund(id)==22,"reused ID outside session cannot inherit45 refund")
 # Included free bin retains explicitly approved existing resale after Done.
 m=fresh();m.begin_decoration_session();m.included_bin_pending=true;id=m._next_item_id;check(m.place("bin",3,6),"free bin Done fixture")
 check(m.logical_refund(id)==0,"included bin0 before Done");m.finish_decoration_session();check(m.logical_refund(id)==32,"included bin existing32 after Done")
 # New stove purchases have no upgrade level; base furnishing receipts are unchanged.
 m=fresh();m.begin_decoration_session();id=m._next_item_id;wallet=m.coins
 check(m.place("stove",3,6) and not m.get_item(id).has("level") and m.coins==wallet-220,"stove220 purchase has no upgrade level")
 check(m.logical_refund(id)==220 and m.remove(id) and m.coins==wallet,"sale refunds new stove base220 once")
 # Failed removal of the eligible NEW item retains its receipt until unblocked.
 m=fresh();m.begin_decoration_session();id=m._next_item_id;wallet=m.coins;check(m.place("stove",3,6),"eligible new stove")
 var old_stove=int(m.items.filter(func(i):return i.kind=="stove" and int(i.id)!=id)[0].id)
 check(m.remove(old_stove),"remove old stove with new usable replacement")
 wallet=m.coins;check(not m.remove(id) and m.coins==wallet and m.logical_refund(id)==220,"essential guard rejects eligible new item atomically")
 check(m.place("stove",8,6),"unblock essential guard")
 wallet=m.coins;check(m.remove(id) and m.coins==wallet+220,"unblocked eligible sale credits once")
 m=fresh();m.begin_decoration_session();id=m._next_item_id;check(m.place("table_set",3,6),"eligible in-use group")
 m.customers.append({"table_id":id,"chair_id":id+1});wallet=m.coins
 check(not m.remove(id+1) and m.coins==wallet and m.logical_refund(id)==280,"in-use guard retains eligible receipt")
 m.customers.clear();check(m.remove(id+1) and m.coins==wallet+280,"unblocked group sale credits once")
 m=fresh();m.begin_decoration_session();id=m._next_item_id;check(m.place("plant",3,6),"malformed load receipt")
 var malformed=FileAccess.open("user://malformed-decoration.json",FileAccess.WRITE);malformed.store_string("not json");malformed.close();wallet=m.coins
 check(not m.load_save("user://malformed-decoration.json") and m.coins==wallet and m.logical_refund(id)==45,"malformed load retains current receipt")
 m.coins=44;var next_id=m._next_item_id;var ledger=m.decoration_purchases.duplicate(true)
 check(not m.place("plant",8,6) and m.coins==44 and m._next_item_id==next_id and m.decoration_purchases==ledger,"insufficient funds no receipt charge or ID")
 m.coins=10000;var stale_sale=Plan.new();var stale_receipt=stale_sale.prepare(m,"plant",-1,0,Vector2i(8,6))
 check(stale_receipt.ok and m.remove(id),"sale between preview and commit")
 wallet=m.coins;check(not stale_sale.commit(m,stale_receipt) and m.coins==wallet and m.decoration_purchases.is_empty(),"stale planner after sale cannot republish spent receipt")
 var game=TestMain.new();root.add_child(game);game.set_process(false);game.paused=true;await process_frame
 game._toggle_edit();check(game.editing and game.model.decoration_session_active,"controller Decorate enters session")
 id=game.model._next_item_id;game.model.coins=10000;check(game.model.place("table_set",3,6),"controller purchase")
 game._cancel_selection();check(game.model.logical_refund(id)==280,"selection cancel keeps receipt")
 var before=game.saves;game.save_success=false;game._toggle_edit()
 check(not game.editing and not game.model.decoration_session_active and game.model.logical_refund(id)==140 and game.saves==before+1,"Done finalizes even when requested save fails")
 game._toggle_edit();check(game.model.logical_refund(id)==140,"controller reentry normal resale")
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 game.queue_free();await process_frame
 print("DECORATION_REFUND_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"observations":observations,"player_save_used":false,"interrupted_session":"finalized on successful reload"}))
 quit(0 if failures.is_empty() else 1)
