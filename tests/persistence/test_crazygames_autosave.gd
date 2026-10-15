extends SceneTree
const Policy=preload("res://scripts/persistence/cafe_autosave_policy.gd")
class ScheduledMain extends "res://scripts/main.gd":
	var attempts=0
	var fail_next=false
	func _autosave():
		attempts+=1
		if fail_next:
			fail_next=false
			return false
		platform_autosave_dirty=false
		progress_unsaved=false
		return true
class PendingSave extends RefCounted:
	var pending=true
var checks=0
var failures=[]
func check(ok:bool,label:String):
	checks+=1
	if not ok:failures.append(label)
func _init():
	for backend in [false,true]:
		check(not Policy.due(backend,true,4.999,false,false,false),"every backend waits five seconds")
		check(Policy.due(backend,true,5.0,false,false,false),"dirty progress submits at five seconds")
		check(not Policy.due(backend,false,100.0,false,false,false),"clean progress never rewrites idle payload")
		check(not Policy.due(backend,true,10.0,true,false,false),"one in-flight write retains dirty work")
		check(not Policy.due(backend,true,10.0,false,true,false),"recovery/suppressed writes stay blocked")
		check(not Policy.due(backend,true,10.0,false,false,true),"active drag waits")
		check(Policy.due(backend,true,10.0,false,false,false),"release permits dirty progress")
	scheduler_cases()
	print("CRAZYGAMES_AUTOSAVE_RESULT "+JSON.stringify({"checks":checks,"failures":failures,"remote_confirmation":false,"interval_seconds":Policy.INTERVAL_SECONDS}))
	quit(0 if failures.is_empty() else 1)
func scheduler_cases():
	var game=ScheduledMain.new()
	game._mark_platform_dirty();game._tick_autosave(4.9)
	check(game.attempts==0 and game.progress_unsaved,"dirty progress waits for the fixed slot")
	for _i in range(20):game._mark_platform_dirty()
	check(is_equal_approx(game.save_timer,4.9) and game.attempts==0,"repeated changes never reset the clock or save per operation")
	game._tick_autosave(.1)
	check(game.attempts==1 and not game.platform_autosave_dirty,"one slot coalesces all changes")
	game._tick_autosave(20.0)
	check(game.attempts==1,"clean long frames do not save")
	var pending_save=PendingSave.new();game.web_save=pending_save
	game._mark_platform_dirty();game._tick_autosave(5.0)
	check(game.attempts==1 and game.platform_autosave_dirty,"an in-flight write keeps dirty work without starting another")
	pending_save.pending=false;game._tick_autosave(4.9)
	check(game.attempts==1,"a released writer waits for the next fixed slot")
	game._tick_autosave(.1)
	check(game.attempts==2,"pending changes coalesce at the next slot")
	game.save_recovery_blocked=true;game._mark_platform_dirty();game._tick_autosave(5.0)
	check(game.attempts==2 and game.platform_autosave_dirty,"ownership/recovery block cannot consume dirty state")
	game.save_recovery_blocked=false;game._tick_autosave(5.0)
	check(game.attempts==3,"dirty state survives the block")
	game._mark_platform_dirty();game._tick_autosave(16.0)
	check(game.attempts==4,"a long frame starts one write without catch-up bursts")
	game._mark_platform_dirty();game.fail_next=true;game._tick_autosave(5.0)
	check(game.attempts==5 and game.platform_autosave_dirty,"failed persistence keeps dirty state")
	game._tick_autosave(5.0)
	check(game.attempts==6 and not game.platform_autosave_dirty,"the next fixed slot retries dirty work")
	# This fixture never enters Main._ready or opens a player profile.
	game.people.free();game.ui.free();game.free()
