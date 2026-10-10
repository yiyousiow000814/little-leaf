extends SceneTree
const Main=preload("res://scripts/main.gd")
const Contract=preload("res://scripts/cafe_save_contract.gd")
var checks=0
var failures=[]
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);push_error(label)
func _initialize():run.call_deferred()
func run():
 if not "saveguard" in OS.get_user_data_dir():quit(2);return
 var game=Main.new();game.process_mode=Node.PROCESS_MODE_DISABLED;root.add_child(game)
 var expected="--footprint-placement" in OS.get_cmdline_user_args() and "--fresh-review" in OS.get_cmdline_user_args()
 check(game.model.footprint_placement_enabled==expected,"only explicit fresh placement review enables occupied footprint capability")
 check(game.save_writes_suppressed and game.fresh_start,"fresh review preserves original write suppression and fresh initialization")
 check(game._save() and not FileAccess.file_exists(Contract.PRIMARY_FILE) and not FileAccess.file_exists(Contract.FOOTPRINT_PLACEMENT_FILE),"ordinary controller save cannot promote or write either profile during review")
 print("PLACEMENT_REVIEW_ENTRY_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 for tween in get_processed_tweens():tween.kill()
 for player in game.audio_players.values():player.stop();player.stream=null
 game.queue_free();await process_frame;await process_frame
 quit(0 if failures.is_empty() else 1)
