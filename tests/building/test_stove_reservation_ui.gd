extends SceneTree
const AudioDrain = preload("res://tests/fixtures/audio_mixer_drain.gd")
## Current UI permits physical work-side placement and keeps atomic cancellation.
const NoBottom=preload("res://tests/fixtures/no_bottom_notifications.gd")
const Guide=preload("res://scripts/rendering/cafe_workface_guidance.gd")
class FixtureMain extends "res://scripts/main.gd":
 var saves=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():saves+=1;return true
 func _interaction_over_ui(_screen:Vector2)->bool:return false
var game;var checks=0;var failures=[]
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func state():return JSON.stringify([game.model.items,game.model.customers,game.model.coins,game.model.revision,game.model._next_item_id,game.saves])
func key(code):
 var event=InputEventKey.new();event.keycode=code;event.pressed=true;game.interaction.handle_input(event)
func run():
 root.size=Vector2i(1360,880);game=FixtureMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false);game.paused=true;game.editing=true
 var m=game.model;m.items.clear();m.dining_sets.clear();m.customers.clear();m.coins=100000;m.checkout_staff_claims.clear();m.wall_actor_positions.clear();m._notify()
 for staff in game.staff_states:staff.pos=Vector2(1.5,7.5)
 check(m.place("stove",5,4),"isolated stove fixture places")
 var stove=m.items[-1];game._rebuild_furniture();game._update_ui();await process_frame
 for rot in 4:
  game.interaction.cancel();check(m.move(int(stove.id),5,4,rot),"fixture rotates r"+str(rot));game._rebuild_furniture()
  var front=m.workface_cell(stove);game.interaction._select_item(stove)
  var facts=Guide.describe(game)
  check(facts.size()==1 and facts[0].cell==front and facts[0].clear,"selection retains actual operational side r"+str(rot))
  game.selected_id=-1;game.selected_kind="plant";game.rotation_step=0;var before=state()
  game.interaction.refresh(game.illustration.iso(front.x+.5,front.y+.5))
  check(game.interaction.preview_active and game.interaction.drag_valid and game.interaction.drag_footprint_valid,"empty working tile is a physically valid preview r"+str(rot))
  check(state()==before,"hover never commits r"+str(rot))
  key(KEY_ESCAPE);check(state()==before and not game.interaction.preview_active,"Escape revokes preview without saving r"+str(rot))
  game.selected_kind="plant";game.selected_id=-1;game.interaction.refresh(game.illustration.iso(front.x+.5,front.y+.5))
  var coins=m.coins;var saves=game.saves;var dirty_generation=game.platform_dirty_generation;game.interaction._commit_preview()
  check(m.coins==coins-m.price_of("plant") and game.saves==saves and game.platform_dirty_generation>dirty_generation,"real UI purchase charges once and marks progress dirty r"+str(rot))
  var blocker=m.items[-1];game.interaction.cancel();game.interaction._select_item(stove);facts=Guide.describe(game)
  check(facts.size()==1 and not facts[0].clear,"committed obstruction is still operationally diagnosable r"+str(rot))
  check(m.remove(int(blocker.id),false),"physical blocker can be removed r"+str(rot));game._rebuild_furniture()
  var next_front=m.workface_cell({"kind":"stove","x":5,"z":4,"rot":posmod(rot+1,4)})
  check(m.place("plant",next_front.x,next_front.y),"next work-side obstruction fixture r"+str(rot));blocker=m.items[-1]
  game._rebuild_furniture();game.interaction._select_item(stove);saves=game.saves;dirty_generation=game.platform_dirty_generation;key(KEY_R)
  check(int(stove.rot)==posmod(rot+1,4) and game.saves==saves and game.platform_dirty_generation>dirty_generation,"R rotation marks dirty and depends on the stove body, not empty work space r"+str(rot))
  before=state();key(KEY_ESCAPE);check(state()==before,"post-rotation cancel adds no second save r"+str(rot))
  check(m.remove(int(blocker.id),false),"rotation work-side fixture removed r"+str(rot));game._rebuild_furniture()
 for size in [Vector2i(390,844),Vector2i(1360,880)]:
  root.size=size;await process_frame;game.illustration.update_projection();var before=state()
  NoBottom.verify(game,check,"physical stove UI "+str(size));check(state()==before,"resize preserves transaction state "+str(size))
 game.editing=false;check(Guide.describe(game).is_empty(),"play has no decorate-only diagnostic draft")
 var report={"checks":checks,"failures":failures,"save_calls":game.saves}
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;await process_frame
 var audio_drain = await AudioDrain.wait_for_mixer_cycles(self)
 check(audio_drain.ok, "audio teardown observes two mixer cycles within 1s")
 print("AUDIO_TEARDOWN_RESULT ", JSON.stringify(audio_drain))
 report.checks=checks;report.failures=failures
 print("STOVE_RESERVATION_UI_RESULT ",JSON.stringify(report))
 quit(0 if failures.is_empty() else 1)
