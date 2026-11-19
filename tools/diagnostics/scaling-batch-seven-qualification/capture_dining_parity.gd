extends Node
# Disposable scene fixture. Native writes RGBA PNG; Web publishes the same real
# viewport readback through JavaScriptBridge. Never run a player profile.
class TestMain extends "res://scripts/main.gd":
 var saves=0
 func _load_startup():save_writes_suppressed=true;fresh_start=false;model.reset_new();paused=true
 func _save():saves+=1;return true

var game:Node
var records=[]
var semantic_only:=OS.get_environment("DINING_SEMANTIC_ONLY")=="1"
var ids=[]
const A="cottage_single"
const B="refined_single"
const C="retro_single"

func _ready():
 run.call_deferred()

func visible_cafe()->bool:
 return game.cafe_intro!=null and not game.cafe_intro.active and not game.cafe_intro.preparing and not game.cafe_intro.cover.is_visible_in_tree()

func state(first:String):
 return [first,B]

func expected_style(variant:String)->String:
 return {A:"cottage",B:"refined",C:"retro"}[variant]

func receipt(variants:Array)->Dictionary:
 var rows={}
 for node in game.illustration.native_object_nodes.values():
  var key:Array=node.appearance
  if key.is_empty() or not key[0] is Array:continue
  var shape:Array=key[0]
  if shape.size()<6 or shape[0]!="furniture" or not shape[2] is Dictionary:continue
  var id:int=shape[2].id
  if not id in ids:continue
  var role:String=shape[1]
  var index:int=ids.find(id)/2
  assert(shape[4]==expected_style(variants[index]),"Retained appearance variant differs")
  assert(node.paint_revision==node.painted_revision and node.draw_count>0,"Native object did not complete a painter callback")
  rows["%s:%s"%[id,role]]={"style":shape[4],"revision":node.paint_revision,"draws":node.draw_count,"slot":node.draw_order}
 assert(rows.size()==6,"Expected two visible table, seat and seat-back triplets")
 return rows

func publish_frame(label:String,image:Image,record:Dictionary):
 assert(image!=null and image.get_size()==Vector2i(1360,880))
 if OS.has_feature("web"):
  var payload=JSON.stringify({"label":label,"receipt":record,"png":Marshalls.raw_to_base64(image.save_png_to_buffer())})
  JavaScriptBridge.eval("window.__littleLeafDiningParity ??= {}; window.__littleLeafDiningParity["+JSON.stringify(label)+"]="+payload+";",true)
 else:
  assert(image.save_png(OS.get_environment("OUTPUT")+"/"+label+".png")==OK)

func capture(label:String,variants:Array):
 game.illustration.queue_redraw()
 for i in range(4):await get_tree().process_frame
 await RenderingServer.frame_post_draw
 assert(visible_cafe() and game.saves==0)
 var row={"label":label,"variants":variants,"objects":receipt(variants),"save_attempts":game.saves}
 records.append(row)
 publish_frame(label,get_viewport().get_texture().get_image(),row)

func run():
 seed(320037);get_tree().root.size=Vector2i(1360,880)
 game=TestMain.new();add_child(game);game.set_process(false);game.illustration.set_process(false)
 if not semantic_only:
  for i in range(900):
   if not is_instance_valid(game.startup_readiness) or game.startup_readiness.completed:break
   await get_tree().process_frame
  assert(not game.startup_preparation_report.is_empty() and not game.startup_preparation_report.timed_out and game.startup_preparation_report.ready==3)
  game.cafe_intro.finish()
  assert(visible_cafe())
 for tween in get_tree().get_processed_tweens():tween.kill()
 game.paused=true;game.animation_time=1.0;game.editing=false;game.model.operating_open=false
 game.model.customers.clear();game.service_guests.clear()
 game.model.items.assign(game.model.items.filter(func(row):return row.kind not in ["table","chair","bench"]))
 game.model.dining_sets.clear();game.model.coins=20000
 assert(game.model.place("table_set_cottage",3,3,0))
 assert(game.model.place("table_set_refined",6,5,0))
 for group in game.model.dining_sets:
  ids.append(int(group.table_id));ids.append(int(group.seat_id))
 assert(ids.size()==4 and game.model.dining_sets[0].variant==A and game.model.dining_sets[1].variant==B)
 for id in ids:assert(not game.model.get_item(id).has("dining_variant"))
 for staff in game.staff_states:staff.pos=Vector2(100,100);staff.path=[];staff.job_kind="";staff.art_action="idle"
 game._rebuild_furniture();game.illustration.update_projection(false)
 if not semantic_only:
  await capture("initial",state(A));await capture("warm",state(A))
  assert(records[0].objects==records[1].objects,"Warm retains all six painter callbacks")
 # Fixture-only authored mutation to challenge incremental visible invalidation.
 game.model.dining_sets[0].variant=C;game.model.revision+=1
 if not semantic_only:
  await capture("changed",state(C));await capture("changed-warm",state(C))
  for key in records[1].objects:
   var before:Dictionary=records[1].objects[key];var after:Dictionary=records[2].objects[key]
   assert(after.slot==before.slot and after.revision==before.revision+int(before.style=="cottage"))
   assert(after.draws==before.draws+int(before.style=="cottage"))
  assert(records[2].objects==records[3].objects)
 var output={"semantic_only":semantic_only,"player_save_used":false,"records":records,"installed_ids":ids,"save_attempts":game.saves}
 if OS.has_feature("web"):
  JavaScriptBridge.eval("window.__littleLeafDiningParityReceipt="+JSON.stringify(output)+";",true)
 else:
  FileAccess.open(OS.get_environment("OUTPUT")+"/runtime.json",FileAccess.WRITE).store_string(JSON.stringify(output))
 print("DINING_APPEARANCE_PARITY_RESULT ",JSON.stringify(output))
 if not OS.has_feature("web"):get_tree().quit()
