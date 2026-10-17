extends SceneTree
## Actual WebSave claim receipt methods, generated café and disposable profile.
## Transport/save submission alone are stubbed; payload validation is real.
const Controller=preload("res://scripts/persistence/cafe_web_save.gd")
class TestController extends "res://scripts/persistence/cafe_web_save.gd":
 var available=true
 func _support_bridge():return self if available else null
 func request_save(_skip_unchanged=false):pending=true;inflight_generation=generation;return false
class Host extends Node:
 const Model=preload("res://scripts/core/cafe_model.gd")
 var model=Model.new()
 var compact_ui=null
 var web_lifecycle=null
 var paused=false
 var editing=false
 var save_recovery_blocked=false
 var save_writes_suppressed=false
 var progress_save_error=""
 var progress_unsaved=false
 var fresh_start=false
 var rebuilds=0
 func _update_ui():pass
 func _connect_model_events():pass
 func _rebuild_room():rebuilds+=1
 func _rebuild_furniture():rebuilds+=1
 func _restore_service_runtime():rebuilds+=1
 func _save():pass
var checks=0
var failures=[]
func check(ok:bool,message:String):
 checks+=1
 if not ok:failures.append(message);printerr("FAIL ",message)
func _initialize():call_deferred("run")
func run():
 var host=Host.new();root.add_child(host);host.model.reset_new()
 var controller=TestController.new(host);controller.ready=true
 controller.profile_id="22222222-2222-4222-8222-222222222222";controller.revision=1
 var initial_money=host.model.coins
 for busy in ["retrying","recovery_busy","update_busy"]:
  controller.set(busy,true)
  check(not controller.claim_support_mail("11111111-1111-4111-8111-111111111111"),busy+" blocks Claim")
  controller.set(busy,false)
 check(controller.claim_support_mail("11111111-1111-4111-8111-111111111111"),"claim begins by preserving current save")
 var old_generation=controller._support_claim_generation
 check(controller.pending and host.paused and root.gui_disable_input,"claim retains input freeze")
 controller.stop()
 controller.ready=true;controller.pending=false;host.save_recovery_blocked=false;host.save_writes_suppressed=false
 check(controller.claim_support_mail("33333333-3333-4333-8333-333333333333"),"new lifecycle can prepare a distinct claim")
 controller._on_support_claim([JSON.stringify({"ok":false,"error":"stale"})],old_generation)
 check(controller.pending and controller._support_claim_mail_id.begins_with("33333333"),"stale callback cannot cancel new claim")
 check(host.progress_save_error=="","stale callback cannot replace current status")
 var generation=controller._support_claim_generation
 controller._on_support_claim([JSON.stringify({"ok":true,"profileId":controller.profile_id,"revision":2.5,"payload":"{}"})],generation)
 check(host.save_recovery_blocked and host.save_writes_suppressed and host.paused,"fractional receipt revision fails closed")
 check(host.model.coins==initial_money and host.rebuilds==0,"invalid claim never changes model or wallet")
 # Validate and install actual current-model v17 payload, including monotonic
 # free-grant IDs. This is a generated fixture, not a player save.
 var candidate=Host.Model.new();candidate.reset_new();candidate.storage_used=true
 var item_id=candidate._next_item_id;candidate._next_item_id+=1
 candidate.storage.items.append({"id":item_id,"kind":"plant","x":0,"z":0,"rot":0,"paid_cost":0})
 candidate.coins+=60
 var filename=OS.get_user_data_dir().path_join("support-claim-generated.json")
 check(candidate.save(filename),"generated Storage payload saves")
 var payload=FileAccess.get_file_as_string(filename)
 host.save_recovery_blocked=false;host.save_writes_suppressed=false;controller.ready=true;controller.pending=false
 check(controller.claim_support_mail("44444444-4444-4444-8444-444444444444"),"valid claim can begin")
 generation=controller._support_claim_generation
 controller._on_support_claim([JSON.stringify({"ok":true,"profileId":controller.profile_id,"revision":2,"payload":payload})],generation)
 check(host.model.storage_used and host.model.storage.items.size()==1,"claimed item is installed in canonical Storage")
 check(host.model.storage.items[0].id==item_id and host.model.storage.items[0].paid_cost==0,"grant identity and acquisition cost remain exact")
 check(host.model.coins==initial_money+60 and controller.revision==2,"receipt wallet/revision installed once")
 check(not controller.pending and not root.gui_disable_input and host.rebuilds==3,"valid receipt releases hold after model rebuild")
 controller._on_support_claim([JSON.stringify({"ok":true,"profileId":controller.profile_id,"revision":2,"payload":payload})],generation)
 check(host.model.coins==initial_money+60 and host.model.storage.items.size()==1 and host.rebuilds==3,"duplicate native callback cannot grant or rebuild twice")
 controller.stop();host.queue_free();await process_frame
 print("SUPPORT_MAIL_CLAIM_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"synthetic_only":true,"player_save_used":false}))
 quit(0 if failures.is_empty() else 1)
