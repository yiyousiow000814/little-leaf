extends SceneTree
const Model=preload("res://scripts/cafe_model.gd")
var failures=[]
var checks=0
var states=[]
const FIRST_RING=["front_0","front_1","front_2","front_3","right_0","right_1","right_2","corner_0"]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func shown(model)->Array:
 var result=[]
 for parcel in model.expansion_parcels():
  if not parcel.owned and parcel.visible:result.append(parcel.id)
 return result
func verify_view(model,label:String):
 for p in model.expansion_parcels():
  if not p.owned:check(p.visible==(p.unlocked or FIRST_RING.has(str(p.id))),label+": first ring and shared-edge frontier for "+str(p.id))
 for id in model.owned_parcels:
  var p=model.parcel_by_id(id)
  check(model.is_floor_owned(Vector2i(p.x,p.z)),label+": owned ground persists for "+str(id))
  check(not shown(model).has(id),label+": owned plot has no sale marker for "+str(id))
  check(model.visible_land_width()>=p.x+p.w and model.visible_land_depth()>=p.z+p.h,label+": camera contains owned plot "+str(id))
 states.append({"state":label,"owned":model.owned_parcels.duplicate(),"visible_unowned":shown(model),"bounds":[model.visible_land_width(),model.visible_land_depth()]})
func _init():
 if not "expansion-saveguard" in OS.get_user_data_dir():printerr("SAVEGUARD FAILED");quit(2);return
 var m=Model.new();var coins=m.coins
 check(shown(m)==FIRST_RING,"fresh scene exposes all eight first geometric ring plots")
 check(shown(m).has("corner_0") and not m.parcel_by_id("corner_0").unlocked,"tree corner remains visible and purchase-locked in the first ring")
 check(not shown(m).has("corner_1"),"only outer second-ring corner is initially hidden")
 var tree_plot=m.parcel_at(Vector2i(14,11))
 check(tree_plot.id=="corner_0" and tree_plot.x==12 and tree_plot.z==9 and tree_plot.visible,"tree coordinate belongs to the preserved first-ring corner")
 check(m.parcel_by_id("corner_1").x==15 and m.parcel_by_id("corner_1").z==9,"outer corner lies in the second geometric band")
 check(m.visible_land_width()==15 and m.visible_land_depth()==12,"fresh preview bounds exclude outer locked column")
 check(coins<10000 and shown(m).has("front_0"),"low balance does not hide unlocked land")
 check(not m.buy_parcel("corner_1") and m.coins==coins and m.owned_parcels.is_empty(),"hidden plot cannot be bought and does not mutate wallet")
 verify_view(m,"fresh")
 m.coins=1000000
 check(m.buy_parcel("front_3"),"buy front neighbor")
 check(shown(m).has("corner_0") and not shown(m).has("corner_1"),"tree corner remains shown while outer corner is still hidden")
 check(m.visible_land_width()==15 and m.visible_land_depth()==15,"bounds include next front plot immediately")
 check(m.parcel_by_id("row2_3").unlocked and shown(m).has("row2_3") and m.parcel_by_id("row2_3").cost==18000,"one 10k plot reveals its adjacent 18k frontier without completing the row")
 verify_view(m,"front neighbor")
 check(m.buy_parcel("corner_0"),"buy first corner")
 check(shown(m).has("corner_1"),"outer corner revealed by owned shared edge")
 check(m.visible_land_width()==18 and m.visible_land_depth()==15,"bounds expand with actual unlocked frontier")
 verify_view(m,"first corner")
 check(m.buy_parcel("corner_1"),"buy outer corner")
 check(shown(m).has("corner2_0") and shown(m).has("corner2_1"),"each next corner plot follows its owned edge")
 verify_view(m,"first corner row complete")
 var alt=Model.new();alt.coins=1000000
 for id in ["right_2","right_0","right_1","right2_0","right2_1","right2_2"]:check(alt.buy_parcel(id),"right route purchase "+id)
 check(shown(alt).has("corner_1"),"outer right neighbor independently reveals corner")
 verify_view(alt,"outer right owned")
 # A winding connected expansion must expose every cardinal neighbor, even
 # above/left of the latest purchase with no original ledger prerequisite.
 var winding=Model.new();winding.coins=1000000
 for id in ["front_3","row2_3","corner2_0","corner2_1"]:check(winding.buy_parcel(id),"connected winding purchase "+id)
 for id in ["corner_1","corner3_1","corner2_0"]:
  var parcel=winding.parcel_by_id(id)
  check(parcel.owned or (parcel.unlocked and parcel.visible),"up/down/left frontier or owned neighbor "+id)
 check(winding.parcel_by_id("corner_1").unlocked and not winding.owned_parcels.has("corner_0"),"upward frontier does not require its ledger predecessor")
 check(winding.buy_parcel("corner3_1"),"buy downward frontier")
 check(winding.parcel_by_id("corner3_0").unlocked and winding.parcel_by_id("corner3_0").visible,"left frontier revealed immediately")
 check(winding.buy_parcel("corner3_0"),"buy lateral frontier without ledger predecessor")
 var winding_path="user://winding-frontier.json"
 check(winding.save(winding_path),"connected lateral ownership saves")
 var winding_hash=FileAccess.get_sha256(winding_path);var winding_reload=Model.new()
 check(winding_reload.load_save(winding_path),"connected lateral ownership reloads")
 check(winding_reload.owned_parcels==winding.owned_parcels and winding_reload.coins==winding.coins,"winding roundtrip preserves IDs and balance")
 check(shown(winding_reload)==shown(winding),"reload reconstructs exact orthogonal frontier")
 check(FileAccess.get_sha256(winding_path)==winding_hash,"reload does not alter source save")
 var low=Model.new();low.coins=10000
 check(low.buy_parcel("front_1"),"first plot spends exact 10k")
 check(low.parcel_by_id("row2_1").visible and low.parcel_by_id("row2_1").unlocked,"zero balance still shows next 18k neighbor")
 check(not low.buy_parcel("row2_1") and low.coins==0 and low.owned_parcels==["front_1"],"unaffordable visible frontier cannot change balance/ownership")
 var low_path="user://first-plot-frontier.json"
 check(low.save(low_path),"save one historical first-ring parcel")
 var low_reload=Model.new();var low_hash=FileAccess.get_sha256(low_path)
 check(low_reload.load_save(low_path),"reload existing first-plot schema")
 check(low_reload.parcel_by_id("row2_1").visible and low_reload.parcel_by_id("row2_1").unlocked,"reload reveals same adjacent 18k frontier")
 check(low_reload.coins==0 and FileAccess.get_sha256(low_path)==low_hash,"reload preserves old wallet and save bytes")
 check(not low._ownership_connected(["corner3_1"]),"disconnected saved island remains invalid")
 var original_ids=Model.PARCEL_IDS.duplicate();var full=Model.new();full.coins=10000000
 var bought=0
 while not full.next_parcel().is_empty() and bought<24:
  var next=full.next_parcel();var before=full.coins
  check(full.buy_parcel(str(next.id)),"all future parcels remain purchasable: "+str(next.id))
  check(full.coins==before-int(next.cost),"price unchanged: "+str(next.id))
  bought+=1
  verify_view(full,"purchase "+str(bought))
 check(bought==24 and full.expanded,"all 24 original parcels retained")
 check(Model.PARCEL_IDS==original_ids,"parcel identifiers unchanged")
 check(shown(full).is_empty(),"fully owned map has no sale markers")
 check(full.visible_land_width()==18 and full.visible_land_depth()==18,"fully owned map keeps complete bounds")
 var path="user://expansion-roundtrip.json"
 check(full.save(path),"owned map save")
 var before_hash=FileAccess.get_sha256(path);var reloaded=Model.new()
 check(reloaded.load_save(path),"owned map reload")
 check(reloaded.owned_parcels==full.owned_parcels and reloaded.coins==full.coins,"save preserves exact ownership and wallet")
 check(FileAccess.get_sha256(path)==before_hash,"loading does not rewrite source bytes")
 verify_view(reloaded,"fully owned reload")
 print("EXPANSION_VISIBILITY_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"states":states}))
 quit(0 if failures.is_empty() else 1)
