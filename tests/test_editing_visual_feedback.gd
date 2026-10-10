extends "res://tests/test_render_visibility.gd"
const Floor=preload("res://scripts/cafe_floor_availability.gd")
class TestMain extends "res://scripts/main.gd":
 var saves=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():saves+=1;return true
 func _interaction_over_ui(_screen:Vector2)->bool:return false
class FloorRecorder extends RefCounted:
 var fills=[]
 func iso(x,z):return Vector2(x,z)
 func poly(points,color):fills.append([Vector2i(points[0]),color])
 func line(_a,_b,_c,_width):pass
func _initialize():run.call_deferred()
func run():
 root.size=Vector2i(1360,880)
 var game=TestMain.new();root.add_child(game);game.set_process(false);game.editing=true;game.model.coins=100000
 await process_frame
 var model=game.model;var floor=game.interaction.floor_availability
 var original=model.items.duplicate(true);var baseline=floor.refresh(model).duplicate(true)
 var stove={};var table={}
 for item in model.items:
  if item.kind=="stove":stove=item
  if item.kind=="table":table=item
 var lifted=floor.refresh(model,int(stove.id)).duplicate(true)
 check(not lifted[Vector2i(stove.x,stove.z)].blocked,"lifted stove old footprint released")
 check(not lifted[model.workface_cell(stove)].blocked,"lifted stove old workface released")
 check(lifted[model.ENTRANCE].blocked and lifted[model.ENTRY_LANDING].blocked,"entrance restrictions retained")
 for item in model.items:
  if item.id!=stove.id:check(lifted[Vector2i(item.x,item.z)].blocked,"other occupancy retained")
 var builds=floor.builds;floor.refresh(model,int(stove.id));check(floor.builds==builds,"unchanged drag reuses background cache")
 lifted=floor.refresh(model,int(table.id)).duplicate(true)
 var members=model.logical_members(int(table.id));check(members.size()>1,"fixture covers logical table and chair")
 for id in members:
  var item=model.get_item(id);check(not lifted[Vector2i(item.x,item.z)].blocked,"all logical members lifted")
 check(floor.refresh(model,int(members[-1]))==lifted,"lifting seat uses the same complete logical footprint")
 check(model.items==original and game.saves==0,"floor preview never mutates or saves model")
 game.interaction.drag_active=true;game.interaction.preview_active=true;game.interaction.drag_item_id=int(stove.id)
 floor.refresh(model,int(stove.id))
 check(not floor.cells[Vector2i(stove.x,stove.z)].blocked,"lifted preview geometry releases its own footprint")
 check(not game.interaction.has_method("draw_floor_feedback"),"placement feedback does not expose whole-floor tint drawing")
 game.interaction.cancel();floor.refresh(model)
 check(floor.cells==baseline and model.items==original,"cancel restores original geometry facts without model writes")
 var shop=game.compact_ui.shop_ui;shop.sync(1360)
 for kind in game.catalog_cards:
  if kind!="register":
   check(game.catalog_cards[kind].tooltip_text=="","affordable catalog has no duplicate tooltip: "+kind)
   check(game.catalog_cards[kind].accessibility_name.ends_with(" coins"),"catalog price remains accessible: "+kind)
 check(game.catalog_cards.register.tooltip_text!="","functional checkout guidance retained")
 model.coins=0;shop.sync(1360)
 for kind in game.catalog_cards:
  if kind!="register":
   check(game.catalog_cards[kind].tooltip_text.begins_with("Need "),"insufficient funds tooltip retained: "+kind)
   check(game.catalog_cards[kind].accessibility_description.contains("purchase is blocked"),"affordability accessibility retained")
 var props=Recorder.new();props.culling=false
 Neighborhood.draw_props(props);var with_bus=props.commands.duplicate(true)
 props.commands=[];Neighborhood.draw_bus(props,Neighborhood.BUS_POSITION)
 check(not props.commands.is_empty() and with_bus.slice(with_bus.size()-props.commands.size())==props.commands,"existing neighborhood API retains original bus painter commands")
 props.commands=[];Neighborhood.draw_props(props)
 check(props.commands==with_bus,"bus presentation restores without state changes")
 var opening=game.illustration.OpeningGeometry.aperture(model.wall_attachments[0],model.built_walls,model.shell_products)
 props.commands=[];game.illustration.OpeningArt.selection_outline(props,opening)
 check(props.commands.size()==8,"selected opening draws four high-contrast double-stroke edges")
 check(model.wall_attachments[0].width==1.0,"selection outline does not normalize starter width")
 print("EDITING_VISUAL_FEEDBACK_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
