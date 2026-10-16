extends SceneTree
const Model=preload("res://scripts/core/cafe_model.gd")
const Start=preload("res://scripts/minimal_start.gd")
const Plan=preload("res://scripts/gameplay/cafe_edit_plan.gd")
var checks=0
var failures=[]
func _initialize():run.call_deferred()
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func prepare(plan,model,kind:String,id:int,rot:int,cell:Vector2i,actors:Array):
 var args=[model,kind,id,rot,cell,actors]
 if plan.has_method("prepare_sell"):args.append(1)
 return plan.callv("prepare",args)
func frozen(model)->String:
 return JSON.stringify([model.customers,model.service_snapshot,model.wall_actor_positions,model.checkout_staff_claims])
func run():
 var m=Model.new();Start.apply(m);m.coins=10000
 # This bounded actor-only fixture does not claim to be a resumable visit.
 # It isolates the model's independent customer and staff footprint readers.
 m.customers.append({"id":99,"phase":"eating","x":4.5,"z":6.5,"table_id":6,"chair_id":7,"elapsed":8.25,"paid":false})
 m.service_snapshot={"records":[{"guest_id":99,"token":23,"plate_owner":"table","plate_target_id":6}],"staff":[{"job_kind":"cook","station_id":1,"job_elapsed":2.75}]}
 m.wall_actor_positions.append(Vector2(5.5,6.5));m.checkout_staff_claims.append(Vector2(6.5,6.5))
 var before=frozen(m);var original=m.items.duplicate(true);var wallet=m.coins
 m.begin_decoration_session()
 var plan=Plan.new()
 var staff=[Vector2(5.5,6.5)]
 check(not m.can_place("plant",4,6),"runtime rejects a present guest")
 check(not m.can_place("plant",5,6,-1,0,staff),"runtime rejects a present worker")
 for cell in [Vector2i(4,6),Vector2i(5,6)]:
  var quote=prepare(plan,m,"plant",-1,0,cell,staff)
  check(quote.ok and quote.physical_ok,"Decorate quote fits across actor "+str(cell))
  check(frozen(m)==before,"preview preserves all authoritative service fields")
  if quote.ok:
   check(plan.commit(m,quote,staff),"commit actor-independent placement")
   check(not plan.commit(m,quote,staff),"spent quote cannot charge twice")
 check(frozen(m)==before,"draft placement retains service and clocks")
 var placed=m.item_at(4,6)
 if not placed.is_empty():
  var quote=prepare(plan,m,"plant",int(placed.id),2,Vector2i(6,6),staff)
  check(quote.ok and plan.commit(m,quote,staff),"move and rotate across a reserved endpoint")
  check(frozen(m)==before,"moving changes no actor, job or custody")
 var quote=prepare(plan,m,"plant",-1,0,Vector2i(8,6),staff)
 check(quote.ok,"valid quote before wallet change")
 m.coins-=1
 check(not plan.commit(m,quote,staff),"stale wallet rejects cached quote")
 quote=prepare(plan,m,"plant",-1,0,Vector2i(50,50),staff)
 check(not quote.ok,"static ownership remains a placement gate")
 m.coins=0;quote=prepare(plan,m,"plant",-1,0,Vector2i(8,6),staff)
 check(not quote.ok and quote.physical_ok,"funds remain a separate transaction gate")
 check(m.cancel_decoration_session(),"Cancel restores baseline once")
 check(m.items==original and m.coins==wallet and frozen(m)==before,"Cancel restores exact layout wallet and paused service")
 check(not m.cancel_decoration_session() and m.coins==wallet,"repeated Cancel gives no credit")
 m.begin_decoration_session();plan=Plan.new()
 var stove=m.items.filter(func(item):return item.kind=="stove")[0]
 var exists=plan.has_method("prepare_sell")
 check(exists,"Sell has the same explicit typed quote boundary")
 if exists:
  quote=plan.prepare_sell(m,int(stove.id),1)
  check(quote.ok and quote.action==2 and quote.context==1,"busy last stove can be sold in the draft")
  var refund=m.logical_refund(int(stove.id));wallet=m.coins
  check(plan.commit(m,quote) and m.coins==wallet+refund and m.get_item(int(stove.id)).is_empty(),"Sell credits its quoted refund once")
  check(frozen(m)==before,"Sell does not refresh or retire service")
  check(not plan.commit(m,quote) and m.coins==wallet+refund,"duplicate Sell does not duplicate credit")
  check(m.cancel_decoration_session() and m.coins==wallet and m.items==original,"Cancel restores sold active host and wallet")
 print("DECORATE_ACTION_QUOTES_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"original_player_save_used":false,"scope":"isolated planner only; no Apply/reconciliation/UI acceptance"}))
 quit(0 if failures.is_empty() else 1)
