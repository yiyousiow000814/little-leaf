extends SceneTree
const Model=preload("res://scripts/cafe_model.gd")
const Money=preload("res://scripts/cafe_money.gd")
const RING_IDS=[
 ["front_0","front_1","front_2","front_3","right_0","right_1","right_2","corner_0"],
 ["row2_0","row2_1","row2_2","row2_3","right2_0","right2_1","right2_2","corner_1","corner2_0","corner2_1"],
 ["row3_0","row3_1","row3_2","row3_3","corner3_0","corner3_1"]
]
const PRICES=[10000,18000,30000]
var checks=0
var failures=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _init():
 if not "expansion-saveguard" in OS.get_user_data_dir():printerr("SAVEGUARD FAILED");quit(2);return
 var m=Model.new();var ids=[]
 for ring_index in RING_IDS.size():
  for id in RING_IDS[ring_index]:
   ids.append(id)
   var p=m.parcel_by_id(id)
   check(m._parcel_geometric_ring(p)==ring_index+1,"geometric ring for "+id)
   check(p.cost==PRICES[ring_index],"ring price for "+id)
 check(ids.size()==24 and Model.PARCEL_IDS.size()==24,"all original 24 plots accounted for")
 for id in Model.PARCEL_IDS:check(ids.has(id),"original identity retained: "+id)
 check(m.parcel_by_id("corner_1").row==0 and m._parcel_geometric_ring(m.parcel_by_id("corner_1"))==2,"outer corner remains ledger row zero but geometric ring two")
 check(not m.parcel_by_id("corner_0").unlocked and m.parcel_by_id("corner_0").visible,"first-ring visibility and purchase lock remain distinct")
 m.coins=10000000;var starting=m.coins;var count=0
 while not m.next_parcel().is_empty() and count<24:
  var p=m.next_parcel();var quoted=int(p.cost);var shown=Money.amount(quoted);var before=m.coins
  check(m.buy_parcel(str(p.id)),"existing progression buys "+str(p.id))
  check(before-m.coins==quoted,"shown price equals actual charge: "+str(p.id))
  check(shown==Money.amount(before-m.coins),"sign amount agrees with wallet delta: "+str(p.id))
  count+=1
 check(count==24 and starting-m.coins==440000,"complete map costs eight 10k, ten 18k and six 30k plots")
 var historic=Model.new();historic.coins=50000
 for id in ["front_3","corner_0","corner_1"]:check(historic.buy_parcel(id),"prepare historical ownership "+id)
 # The old release charged 10k for all three. Its saved wallet was 20k.
 # Loading that authoritative balance must never recompute historical prices.
 historic.coins=20000
 var path="user://historical-land-wallet.json"
 check(historic.save(path),"save synthetic historical ownership and exact balance")
 var bytes=FileAccess.get_sha256(path);var reloaded=Model.new()
 check(reloaded.load_save(path),"historical save loads")
 check(reloaded.coins==20000 and reloaded.owned_parcels==historic.owned_parcels,"no retroactive charge or ownership mutation")
 check(FileAccess.get_sha256(path)==bytes,"historical source bytes unchanged")
 check(not reloaded.buy_parcel("corner_1") and reloaded.coins==20000,"already-owned parcel cannot be charged again")
 print("EXPANSION_RING_PRICES_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"ring_counts":[8,10,6],"prices":PRICES,"all_plots_total":440000}))
 quit(0 if failures.is_empty() else 1)
