extends SceneTree
const WebSave=preload("res://scripts/cafe_web_save.gd")
class Model extends RefCounted:
	var coins=1200
	var last_error=""
	var last_event=""
class Api extends RefCounted:
	var storageKind="crazygames-data"
class Game extends Node:
	var background_elapsed=null
	var model=Model.new()
	var platform_autosave_dirty=true
	var platform_dirty_generation=3
	var progress_unsaved=true
	var progress_save_error=""
	var save_recovery_blocked=false
	var save_writes_suppressed=false
	var paused=false
	var startup_notice=""
	func _update_ui():pass
var checks=0
var failures=[]
func check(condition:bool,label:String):
	checks+=1
	if not condition:failures.append(label)
func _init():call_deferred("run")
func run():
	for variant in ["accepted","newer_dirty","ordinary","cloud_claim","wrong_storage","bad_revision"]:
		var game=Game.new();root.add_child(game)
		var save=WebSave.new(game);save.api=Api.new();save._platform_dirty_snapshot=3;save.ready=true;save.profile_id="synthetic"
		var ack={"ok":true,"profileId":"synthetic","revision":1,"durable":false,"platformAccepted":true,"cloudConfirmed":false,"creditedCoins":0}
		if variant=="newer_dirty":game.platform_dirty_generation=4
		if variant=="ordinary":ack.erase("platformAccepted")
		if variant=="cloud_claim":ack.cloudConfirmed=true
		if variant=="wrong_storage":save.api.storageKind="other"
		if variant=="bad_revision":ack.revision=2
		save._on_commit([JSON.stringify(ack)])
		if variant=="accepted":
			check(save.platform_managed and save.ready and save.revision==1,"explicit platform acceptance advances controller")
			check(not game.progress_unsaved and game.model.last_event=="Progress submitted to CrazyGames","honest platform UI acknowledgement")
		elif variant=="newer_dirty":
			check(save.ready and game.platform_autosave_dirty and game.progress_unsaved,"new dirty generation survives older acceptance")
		else:
			check(not save.ready and game.progress_unsaved and game.save_recovery_blocked,"unsafe acknowledgement blocked: "+variant)
		game.queue_free()
	print("CRAZYGAMES_ACK_RESULT "+JSON.stringify({"checks":checks,"failures":failures,"synthetic_only":true,"cloud_verified":false}))
	quit(0 if failures.is_empty() else 1)
