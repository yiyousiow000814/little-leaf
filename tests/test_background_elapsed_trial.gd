extends SceneTree
const Fixture=preload("res://tests/role_fixture.gd")
const Elapsed=preload("res://scripts/cafe_background_elapsed.gd")
class LocalStaging extends RefCounted:
	const STAGING_FILE="user://elapsed_profit_staging.json"
	func stop():pass
	func _recovery_bridge():return null
	func recovery_snapshot():return {"serverOwnership":true}
var failures=[]
var checks=0
func _initialize():run.call_deferred()
func check(ok,label):
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func run():
	var game=Fixture.new();root.add_child(game);await process_frame
	game.set_process(false);game.illustration.set_process(false)
	game.web_save=LocalStaging.new();game.paused=false;game.setup_dirty()
	game.model.first_guest_pending=false;game.model.operating_open=true
	var original=game.model;var before_coins=original.coins;var payroll=original.payroll_elapsed
	var controller=Elapsed.new(game)
	check(controller.average_profit_rate()==0.0,"old/new profiles have no fabricated earning history")
	for i in range(59):controller.observe_profit(1.0,10.0,2.0)
	check(controller.average_profit_rate()==0.0,"minimum sixty active seconds required")
	controller.observe_profit(1.0,10.0,2.0)
	check(is_equal_approx(controller.average_profit_rate(),8.0),"actual revenue minus incurred wages is net profit")
	controller.frozen_profit_rate=controller.average_profit_rate()
	var payload=controller._trial_payload(1200.0)
	check(payload!="","twenty-minute formula snapshot validates")
	if payload!="":
		var result=JSON.parse_string(payload)
		check(int(result.coins)==before_coins+7200,"20 minutes times 8 net coins per second times .75")
		check(float(result.payroll_elapsed)==payroll and int(result.total_earned)==original.total_earned and int(result.served)==original.served,"no hidden customer/payroll simulation or invented historical meals")
	check(game.model==original and game.model.coins==before_coins,"trial leaves public wallet untouched before confirmation")
	controller.frozen_profit_rate=0.1;original.background_profit_remainder=0.95
	payload=controller._trial_payload(1.0)
	var fractional=JSON.parse_string(payload)
	check(int(fractional.coins)==before_coins+1 and absf(float(fractional.background_profit_remainder)-0.025)<0.000001,"fraction carries deterministically with exact whole snapshot")
	check(controller._trial_payload(INF)=="" and controller._trial_payload(-1.0)=="","nonfinite or negative duration rejected")
	for i in range(1000):controller.observe_profit(1.0,0.0,1.0)
	check(controller.profit_samples.size()<=301 and controller.history_seconds<=301.0,"averaging storage bounded to recent five active minutes")
	check(controller.average_profit_rate()==0.0,"no recent paid meals or non-positive profit grants zero")
	game.model.operating_open=false
	controller.hidden_changed(true)
	check(controller.phase=="idle" and controller._trial_payload(1200.0)=="" and controller.average_profit_rate()==0.0,"closed cafe cannot arm or settle stale profit history")
	game.model.operating_open=true
	controller.frozen_profit_rate=0.0;payload=controller._trial_payload(1200.0)
	check(int(JSON.parse_string(payload).coins)==before_coins,"no valid rate preserves balance during long hidden interval")
	var legacy=JSON.parse_string(payload);legacy.erase("background_profit_remainder")
	var file=FileAccess.open(LocalStaging.STAGING_FILE,FileAccess.WRITE);file.store_string(JSON.stringify(legacy));file.close()
	var old_model=game.Model.new()
	check(old_model.load_save(LocalStaging.STAGING_FILE) and old_model.background_profit_remainder==0.0,"old saves default only remainder, never create profit history")
	legacy.background_profit_remainder=1.1
	file=FileAccess.open(LocalStaging.STAGING_FILE,FileAccess.WRITE);file.store_string(JSON.stringify(legacy));file.close()
	check(not old_model.load_save(LocalStaging.STAGING_FILE),"malformed fractional balance rejected")
	controller.phase="arming";controller.stop()
	check(game.paused and game.save_recovery_blocked and game.save_writes_suppressed,"uncertain account arming cancellation synchronously blocks old foreground model")
	var unavailable=[]
	controller.cancel_for_binding(func(receipt):unavailable.append(receipt))
	check(unavailable.size()==1 and unavailable[0].code=="ELAPSED_UNAVAILABLE","missing native binding bridge never reports terminal clearance")
	controller.cancellation_pending=true;unavailable.clear()
	controller.cancel_for_binding(func(receipt):unavailable.append(receipt))
	check(unavailable.size()==1 and unavailable[0].code=="SAVE_BUSY","duplicate native binding cancellation rejects without replacing pending callback")
	print("BACKGROUND_ELAPSED_TRIAL_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	game.queue_free();await process_frame
	quit(0 if failures.is_empty() else 1)
