extends SceneTree
const Fixture=preload("res://tests/role_fixture.gd")
const Elapsed=preload("res://scripts/cafe_background_elapsed.gd")
class LocalStaging extends RefCounted:
	const STAGING_FILE="user://elapsed_trial_staging.json"
	func stop():pass
var failures=[]
var checks=0
func _initialize():run.call_deferred()
func check(ok,label):
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func run():
	var game=Fixture.new();root.add_child(game);await process_frame
	game.set_process(false);game.illustration.set_process(false)
	game.web_save=LocalStaging.new()
	game.paused=false
	game.setup_dirty()
	game.model.first_guest_pending=false
	# Keep an existing service job, without spawning new random diners.
	game.model.operating_open=false
	var before_model=game.model
	var coins=game.model.coins;var payroll=game.model.payroll_elapsed
	var earned=game.model.total_earned;var wages=game.model.total_wages_paid;var served=game.model.served
	var controller=Elapsed.new(game)
	var payload=controller._trial_payload(2.2)
	check(payload!="","private candidate passes existing complete save validation: "+str(game.model.last_error))
	check(game.model==before_model,"original model restored before the network commit")
	check(game.model.payroll_elapsed==payroll and game.model.coins==coins and game.model.total_earned==earned and game.model.total_wages_paid==wages and game.model.served==served,"private trial awards no visible original economy")
	if payload!="":
		var result=JSON.parse_string(payload)
		check(absf(float(result.payroll_elapsed)-payroll-2.2)<0.000001,"existing payroll advances by exactly the accepted elapsed time")
		check(int(result.coins)==coins and int(result.total_earned)==earned and int(result.total_wages_paid)==wages,"short cleanup fixture adds no invented payment or wage charge")
	check(controller._trial_payload(INF)=="" and controller._trial_payload(-1.0)=="" and controller._trial_payload(60.0001)=="","invalid/unbounded elapsed budget rejected")
	game.model.payroll_elapsed=58.0
	game.model.payroll_accrued=float(game.model.wage_rate())*58.0/60.0
	var first_chunk=controller._trial_payload(1.0)
	var second_chunk=controller._trial_payload(1.2,first_chunk)
	check(first_chunk!="" and second_chunk!="","long guest interval retains every bounded replay chunk")
	if second_chunk!="":
		var result=JSON.parse_string(second_chunk)
		check(absf(float(result.payroll_elapsed)-0.2)<0.000001,"split 2.2 seconds cross exactly one existing payroll cycle")
		check(int(result.total_wages_paid)-wages==game.model.wage_rate() and coins-int(result.coins)==game.model.wage_rate(),"existing wage rate settles once across chunk boundary")
		check(game.model.coins==coins and game.model.total_wages_paid==wages,"chunked private settlement leaves original wallet unchanged")
	print("BACKGROUND_ELAPSED_TRIAL_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	game.queue_free();await process_frame
	quit(0 if failures.is_empty() else 1)
