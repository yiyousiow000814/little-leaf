extends SceneTree
const Fixture=preload("res://tests/role_fixture.gd")
var checks=0
var failures=[]
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func run():
 var game=Fixture.new();root.add_child(game);await process_frame
 game.set_process(false);game.illustration.set_process(false)
 var record=game.setup_dirty(true)
 record.guest.phase="cleaning";record.guest.duration=1.0;record.guest.elapsed=0.0
 var cleaned=game.model.total_cleaned;var served=game.model.served;var earned=game.model.total_earned
 game.worker("cleaner").on_duty=false
 for tick in range(1000):game._tick_live_service(.05);game.advance()
 check(record.table_wiped and record.plate_owner=="clean","real phase loop completes waiter table work")
 check(game.model.customers.size()==1 and game.service_guests.size()==1 and not record.cleanup_done,"cleaning phase retains guest/table while floor unfinished")
 check(game.model.total_cleaned==cleaned,"partial cleanup never increments cleaned count")
 game.worker("cleaner").on_duty=true
 for tick in range(3000):
  game._tick_live_service(.05);game.advance()
  if game.model.customers.is_empty():break
 check(game.model.customers.is_empty() and game.service_guests.is_empty(),"combined completion releases guest/table through live model")
 check(game.model.total_cleaned==cleaned+1,"completed visit counted exactly once")
 for tick in range(100):game._tick_live_service(.05);game.advance()
 check(game.model.total_cleaned==cleaned+1 and game.model.served==served and game.model.total_earned==earned,"repeated ticks never duplicate cleaning or payment")
 var report={"checks":checks,"failures":failures,"normal_saves_suppressed":game.save_writes_suppressed,"test":"actual model cleaning-phase gate and staff simulation"}
 FileAccess.open("res://docs/role-boundaries/release-results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
 print("ROLE_RELEASE_RESULT ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
