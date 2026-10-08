extends SceneTree
const Main=preload("res://scripts/main.gd")
var checks=0
var failures=[]
func _initialize():run.call_deferred()
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func run():
 root.size=Vector2i(1360,880)
 check(OS.get_environment("XDG_DATA_HOME")!="" and OS.get_user_data_dir().begins_with(OS.get_environment("XDG_DATA_HOME")),"isolated generated profile")
 var game=Main.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false)
 check(game.fresh_start and not game.save_recovery_blocked,"actual fresh startup path")
 var initial={"items":game.model.items.duplicate(true),"coins":game.model.coins,"cooks":game.model.cooks,"waiters":game.model.waiters,"cleaners":game.model.cleaners,"cashiers":game.model.cashiers}
 for kind in ["stove","beverage","sink"]:
  var item=game.model.items.filter(func(i):return i.kind==kind)[0]
  check(game.model._workface_open_in(item,game.model.items),"fresh "+kind+" workfront open")
 game.model._spawn_customer()
 check(game.model.customers.size()==1,"fresh table admits one real customer")
 var seconds=0.0
 for frame in range(4000):
  game.model._arrival_elapsed=0.0;game._tick_live_service(.1);game._animate_staff(.1);game.animation_time+=.1;seconds+=.1
  if game.model.served==1:break
 check(game.model.served==1 and game.model.total_earned==game.model.MEAL_PAYMENT,"untouched public fresh layout serves and settles first meal")
 check(not game.model.customers.is_empty() and not game.model.customers[0].meal_abandoned,"fresh diner finishes without meal abandonment")
 print("FRESH_SERVICE_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"initial":initial,"first_payment_seconds":seconds,"player_save_used":false}))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;await process_frame
 quit(0 if failures.is_empty() else 1)
