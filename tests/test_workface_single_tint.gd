extends SceneTree
## Workface facts remain available without whole-floor placement tint.
class FixtureMain extends "res://scripts/main.gd":
 var saves=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():saves+=1;return true
class PaintRecorder extends RefCounted:
 var fills=[];var lines=[]
 func iso(x,z):return Vector2(x,z)
 func poly(points,color):fills.append({"points":points,"color":color})
 func line(a,b,color,width):lines.append({"a":a,"b":b,"color":color,"width":width})
 func draw_colored_polygon(points,color,uvs=PackedVector2Array(),texture=null):fills.append({"points":points,"color":color,"uvs":uvs,"texture":texture})
 func draw_polyline(points,color,width,_antialiased):lines.append({"points":points,"color":color,"width":width})
var checks=0;var failures=[]
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func run():
 var game=FixtureMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false);game.editing=true;game.paused=true
 var m=game.model;var guide=game.workface_guidance
 # Keep legacy counter paint coverage without offering a new counter purchase.
 m.items.append({"id":m._next_item_id,"kind":"counter","x":5,"z":6,"rot":0});m._next_item_id+=1;m._notify()
 var state=JSON.stringify([m.items,m.coins,m.revision,game.saves])
 for kind in ["stove","sink","beverage","counter","register"]:
  var item={}
  for entry in m.items:
   if str(entry.kind)==kind:item=entry;break
  check(not item.is_empty(),"fixture includes "+kind)
  game.selected_kind="";game.selected_id=int(item.id);game.interaction.preview_active=false;guide._refresh()
  check(not guide.markers.is_empty(),"selected "+kind+" retains work-cell facts")
  var art=PaintRecorder.new()
  var fills=art.fills.size();var lines=art.lines.size();guide.draw_ground(art)
  check(art.fills.size()==fills+guide.markers.size() and art.lines.size()==lines+guide.markers.size(),"selected "+kind+" paints only its specific workface guidance once")
  check(JSON.stringify([m.items,m.coins,m.revision,game.saves])==state,"paint does not mutate "+kind)
 # Preserve the existing directional draft guide where no red ground cell exists.
 game.selected_id=-1;game.selected_kind="stove"
 var interaction=game.interaction;interaction.preview_active=true;interaction.drag_kind="stove";interaction.drag_item_id=-1;interaction.drag_cell=Vector2i(5,6)
 for rot in 4:
  interaction.drag_rotation=rot;guide._refresh();var art=PaintRecorder.new();guide.draw_ground(art)
  var cell=m.workface_cell({"kind":"stove","x":5,"z":6,"rot":rot})
  check(guide.markers.size()==1 and guide.markers[0].cell==cell,"draft keeps correct working cell r"+str(rot))
  check(art.fills.size()==1 and art.lines.size()==1,"draft paints its directional guidance once without a common floor wash r"+str(rot))
 check(JSON.stringify([m.items,m.coins,m.revision,game.saves])==state,"all draft rendering preserves state")
 game.editing=false;var art=PaintRecorder.new();guide.draw_ground(art)
 check(art.fills.is_empty() and art.lines.is_empty(),"play has no ground-guide paint")
 print("WORKFACE_SINGLE_TINT_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;await process_frame;quit(0 if failures.is_empty() else 1)
