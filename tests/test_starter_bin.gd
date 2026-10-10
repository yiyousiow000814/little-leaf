extends SceneTree
const Model=preload("res://scripts/cafe_model.gd")
const Minimal=preload("res://scripts/minimal_start.gd")
const Main=preload("res://scripts/main.gd")
var checks=0
var failures=[]
func _initialize():run.call_deferred()
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func same(a,b)->bool:
 if (a is int or a is float) and (b is int or b is float):return absf(float(a)-float(b))<1e-10
 if a is Dictionary and b is Dictionary:
  if a.size()!=b.size():return false
  for key in a:
   if not b.has(key) or not same(a[key],b[key]):return false
  return true
 if a is Array and b is Array:
  if a.size()!=b.size():return false
  for i in a.size():
   if not same(a[i],b[i]):return false
  return true
 return a==b
func roundtrip(model,path:String):
 check(model.save(path),"save synthetic "+path)
 var hash_before=FileAccess.get_sha256(path);var loaded=Model.new()
 check(loaded.load_save(path),"load synthetic "+path)
 check(FileAccess.get_sha256(path)==hash_before,"load never rewrites "+path)
 return loaded
func run():
 check(OS.get_environment("XDG_DATA_HOME")!="" and OS.get_user_data_dir().begins_with(OS.get_environment("XDG_DATA_HOME")),"isolated synthetic profile")
 var model=Model.new()
 Minimal.apply(model)
 check(not model.included_bin_pending and model.count_kind("bin")==0,"public minimal start has no free bin")
 model.included_bin_pending=true;Minimal.apply(model)
 check(not model.included_bin_pending and model.count_kind("bin")==0,"repeated public fresh reset clears old entitlement")
 check(model.price_of("bin")==65 and model.catalog.any(func(entry):return entry.kind=="bin" and entry.price==65),"original purchasable bin and price retained")
 var wallet=model.coins;var items=model.items.duplicate(true);var next_id=model._next_item_id
 check(not model.ensure_basic_bin(),"fresh profile cannot invoke free supplement helper")
 check(model.coins==wallet and model.items==items and model._next_item_id==next_id and not model.included_bin_pending,"refused free supplement preserves fresh state")
 model.coins=64
 check(not model.place("bin",3,6) and model.coins==64 and model.count_kind("bin")==0,"unfunded fresh purchase is atomic")
 model.coins=wallet;model.begin_decoration_session()
 check(model.place("bin",3,6) and model.coins==wallet-65,"optional bin purchase charges65")
 var bought=model.get_item(next_id).duplicate(true)
 check(model.logical_refund(next_id)==65,"same-session paid value retained")
 model.finish_decoration_session();var resale=model.logical_refund(next_id)
 check(resale==32,"existing completed-purchase resale retained")
 var loaded=roundtrip(model,"user://paid-bin.json")
 check(same(loaded.get_item(next_id),bought) and loaded.coins==model.coins and loaded.logical_refund(next_id)==resale,"paid owned bin ID/geometry/value/wallet survive reload")
 # Generate an old unclaimed record rather than accessing any player's save.
 var legacy=Model.new();legacy.included_bin_pending=true
 legacy=roundtrip(legacy,"user://historical-unclaimed-bin.json")
 check(legacy.included_bin_pending and legacy.price_of("bin")==0,"historical pending flag retains its preexisting semantics")
 wallet=legacy.coins;next_id=legacy._next_item_id
 check(legacy.ensure_basic_bin() and legacy.count_kind("bin")==1 and legacy.coins==wallet,"historical supplement remains compatible")
 var historical_bin=legacy.get_item(next_id).duplicate(true);var historical_value=legacy.logical_refund(next_id)
 loaded=roundtrip(legacy,"user://historical-owned-bin.json")
 check(same(loaded.get_item(next_id),historical_bin) and loaded.logical_refund(next_id)==historical_value and loaded.coins==wallet,"historical owned bin and saved value retained")
 check(loaded.ensure_basic_bin() and loaded.count_kind("bin")==1 and loaded.coins==wallet,"existing owned bin never duplicates or charges")
 var new_profile=Model.new();Minimal.apply(new_profile)
 var fresh_loaded=roundtrip(new_profile,"user://new-bin-free-profile.json")
 check(not fresh_loaded.included_bin_pending and fresh_loaded.price_of("bin")==65,"new profile reload cannot regain free entitlement")
 var game=Main.new();game.process_mode=Node.PROCESS_MODE_DISABLED;root.add_child(game)
 check(game.save_writes_suppressed and game.fresh_start,"actual Main fresh-review caller suppresses original-save writes")
 check(game.model.count_kind("bin")==0 and not game.model.included_bin_pending and game.model.price_of("bin")==65,"actual Main startup uses bin-free paid-purchase policy")
 game._toggle_edit();game._set_catalog_category("Cleaning");game._update_ui()
 check(game.catalog_cards.has("bin") and "65" in game.catalog_cards.bin.tooltip_text,"actual shop exposes optional bin65")
 check(game.model.price_of("register")==0,"existing included checkout remains unchanged")
 for player in game.audio_players.values():player.stop();player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame
 print("STARTER_BIN_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"player_save_used":false}))
 quit(0 if failures.is_empty() else 1)
