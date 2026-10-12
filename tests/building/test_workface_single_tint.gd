extends SceneTree
## Retired ground painters/cache/node are absent; operational facts remain usable.
const Guide=preload("res://scripts/rendering/cafe_workface_guidance.gd")
class FixtureMain extends "res://scripts/main.gd":
 var saves=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():saves+=1;return true
var checks=0;var failures=[]
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func run():
 var game=FixtureMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false);game.editing=true;game.paused=true
 var methods=[]
 for value in Guide.get_script_method_list():methods.append(str(value.name))
 for name in ["draw_ground","marker_color","_process","_refresh"]:check(not methods.has(name),"retired guide function is deleted: "+name)
 check(not game.interaction.has_method("draw_floor_feedback"),"whole-floor painter is deleted")
 var nodes=[]
 for node in game.get_children():
  if node.get_script()==Guide:nodes.append(node)
 check(nodes.is_empty(),"no empty guidance node or process callback is retained")
 var m=game.model;var state=JSON.stringify([m.items,m.customers,m.coins,m.revision,game.saves])
 for kind in ["stove","sink","beverage","counter","register"]:
  var item={}
  for entry in m.items:
   if str(entry.kind)==kind:item=entry;break
  check(not item.is_empty(),"fixture includes "+kind)
  game.selected_kind="";game.selected_id=int(item.id);game.interaction.preview_active=false
  check(not Guide.describe(game).is_empty(),"selected "+kind+" retains operational workface facts")
  check(JSON.stringify([m.items,m.customers,m.coins,m.revision,game.saves])==state,"read-only diagnosis preserves "+kind)
 game.selected_id=-1;game.selected_kind="stove"
 var interaction=game.interaction;interaction.preview_active=true;interaction.drag_kind="stove";interaction.drag_item_id=-1;interaction.drag_cell=Vector2i(5,6)
 for rot in 4:
  interaction.drag_rotation=rot
  var facts=Guide.describe(game);var cell=m.workface_cell({"kind":"stove","x":5,"z":6,"rot":rot})
  check(facts.size()==1 and facts[0].cell==cell,"diagnostic draft workface follows rotation r"+str(rot))
 check(JSON.stringify([m.items,m.customers,m.coins,m.revision,game.saves])==state,"all draft diagnosis is nonmutating")
 game.editing=false;check(Guide.describe(game).is_empty(),"play does not create decorate workface facts")
 print("WORKFACE_SINGLE_TINT_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;await process_frame;quit(0 if failures.is_empty() else 1)
