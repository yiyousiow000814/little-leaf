extends SceneTree
const AudioDrain=preload("res://tests/fixtures/audio_mixer_drain.gd")
const OpeningArt=preload("res://scripts/rendering/illustrated_openings.gd")
class Fixture extends "res://scripts/main.gd":
 var saves=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():saves+=1;return true
 func _interaction_over_ui(_screen:Vector2)->bool:return false
class CursorEvidence extends Control:
 var pointer=Vector2.ZERO
 var corners=PackedVector2Array()
 func _draw():
  if corners.size()>0:draw_polyline(corners,Color("376ca0"),2.0,true)
  draw_circle(pointer,7,Color("fff8df"),false,2.0,true)
  draw_line(pointer-Vector2(10,0),pointer+Vector2(10,0),Color("b35b38"),1.7,true)
  draw_line(pointer-Vector2(0,10),pointer+Vector2(0,10),Color("b35b38"),1.7,true)
var game
var checks=0
var failures=[]
var observations=[]
var capture_dir=OS.get_environment("LL_CAPTURE_OUTPUT")
var marker
var caption
var evidence_layer
func _initialize():run.call_deferred()
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func state():return JSON.stringify([game.model.items,game.model.dining_sets,game.model.coins,game.model.revision,game.saves])
func fixture(specs:Array):
 game._cancel_selection();game._set_catalog_category("Decor")
 var m=game.model;m.items.clear();m.dining_sets.clear();m.customers.clear();m.coins=100000;m.checkout_staff_claims.clear();m.wall_actor_positions.clear();m._notify()
 for spec in specs:check(m.place(spec[0],spec[1],spec[2]),"synthetic fixture "+str(spec))
 game._rebuild_furniture();game._update_ui()
func click(point:Vector2):
 var motion=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;root.push_input(motion,true)
 for pressed in [true,false]:
  var event=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
func selected_description()->String:
 var item=game.model.get_item(game.selected_id)
 if not item.is_empty():return str(item.kind)+" cell (%d,%d) id %d"%[item.x,item.z,item.id]
 if game.build_tools.opening_source_id>=0:return "opening id "+str(game.build_tools.opening_source_id)
 if game.compact_ui._selected_wall_key()!="":return "wall "+game.compact_ui._selected_wall_key()
 return "none"
func capture(label:String,point:Vector2,expected:int):
 var cell=game._floor_cell(point)
 observations.append({"scene":label,"pointer":[point.x,point.y],"floor_cell":[cell.x,cell.y],"selected_id":game.selected_id,"selected":selected_description(),"expected_id":expected,"opening_id":game.build_tools.opening_source_id,"wall":game.compact_ui._selected_wall_key(),"saves":game.saves})
 if capture_dir=="":return
 marker.pointer=point;marker.corners=PackedVector2Array([game.illustration.iso(cell.x,cell.y),game.illustration.iso(cell.x+1,cell.y),game.illustration.iso(cell.x+1,cell.y+1),game.illustration.iso(cell.x,cell.y+1),game.illustration.iso(cell.x,cell.y)]);marker.queue_redraw()
 caption.text="Synthetic cursor: cell (%d,%d)\nSelected: %s"%[cell.x,cell.y,selected_description()]
 game.illustration.queue_redraw()
 for frame in 5:await process_frame
 await RenderingServer.frame_post_draw
 check(root.get_texture().get_image().save_png(capture_dir.path_join(label+".png"))==OK,"capture "+label)
func floor_case(label:String,point:Vector2,expected:int,capture_frame=true):
 var before=state()
 game.interaction._begin_left(point);game.interaction._release_left(point)
 check(game.selected_id==expected,label+" interaction selects clicked cell's logical item")
 game._cancel_selection()
 if label=="01-neighbor-table":game._set_catalog_category("Build")
 click(point)
 check(game.selected_id==expected,label+" compact/full-input path agrees with interaction")
 check(state()==before,label+" clicking preserves layout, wallet, revision and saves")
 if capture_frame:await capture(label,point,expected)
func run():
 root.size=Vector2i(1360,880);game=Fixture.new();root.add_child(game);game.set_process(false);game.paused=true
 await process_frame
 game._toggle_edit();game.compact_ui.set_tray_open(true)
 for staff in game.staff_states:staff.pos=Vector2(1.5,7.5)
 game.illustration.zoom=1.0;game.illustration.pan_offset=Vector2.ZERO;game.illustration.update_projection()
 if capture_dir!="":
  evidence_layer=CanvasLayer.new();evidence_layer.layer=100;root.add_child(evidence_layer)
  marker=CursorEvidence.new();marker.mouse_filter=Control.MOUSE_FILTER_IGNORE;evidence_layer.add_child(marker)
  caption=Label.new();caption.position=Vector2(12,112);caption.add_theme_color_override("font_color",Color("203c34"));caption.add_theme_color_override("font_outline_color",Color("fff8df"));caption.add_theme_constant_override("outline_size",5);caption.mouse_filter=Control.MOUSE_FILTER_IGNORE;evidence_layer.add_child(caption)
 fixture([["table_set",4,4],["table_set",5,5]])
 var rear=game.model.item_at(4,4);var point=game.illustration.iso(4.5,4.5)
 check(game.illustration.hit_item(point)!=int(rear.id),"legacy rectangle reproduces neighboring-table mispick")
 await floor_case("01-neighbor-table",point,int(rear.id))
 fixture([["plant",4,4],["table_set",5,5]])
 await floor_case("02-occupied-cell",game.illustration.iso(4.5,4.5),int(game.model.item_at(4,4).id))
 fixture([["lamp",5,5]])
 point=game.illustration.iso(4.65,4.35)
 check(game.model.item_at(4,4).is_empty() and game.illustration.hit_item(point)>=0,"empty cell lies inside the lamp's coarse rectangle")
 await floor_case("03-empty-under-lamp",point,-1)
 fixture([["table_set",4,4]])
 var table=game.model.item_at(4,4);var group=game.model.dining_set_for(int(table.id));var seat=game.model.get_item(int(group.seat_id))
 await floor_case("04-dining-seat",game.illustration.iso(seat.x+.5,seat.z+.5),int(table.id))
 fixture([["rug",4,4]])
 await floor_case("05-rug-only",game.illustration.iso(4.5,4.5),int(game.model.item_at(4,4).id))
 fixture([]);point=game.illustration.iso(2.5,0,70);click(point)
 check(game.compact_ui.selected_wall=="x:2:0" and game.selected_id<0,"existing wall remains in its wall selection domain")
 await capture("06-wall",point,-1)
 game._cancel_selection()
 var opening=game.model.wall_openings()[0];var center=(opening.a+opening.b)*.5+OpeningArt.front(opening.host)
 point=game.illustration.iso(center.x,center.y,(opening.bottom+opening.top)*.5);click(point)
 check(game.build_tools.opening_source_id==int(opening.id) and game.selected_id<0,"opening remains in its hosted selection domain")
 await capture("07-opening",point,-1)
 fixture([["plant",4,4]]);point=game.illustration.iso(4.5,4.5)
 var plant_id=int(game.model.item_at(4,4).id);var shop=game.compact_ui.shop_ui
 for full_input in [false,true]:
  game._cancel_selection();game._set_catalog_category("Build");shop.show_tiles()
  if not shop.objects_hidden():shop.toggle_objects()
  var path="full input" if full_input else "interaction"
  check(game.build_tools.mode=="" and game.illustration.objects_hidden(),path+" uses Tiles browse with hidden objects and no floor tool")
  var hidden_before=state()
  if full_input:click(point)
  else:game.interaction._begin_left(point);game.interaction._release_left(point)
  check(game.selected_id<0,path+" cannot select hidden furniture")
  check(not game.compact_ui.has_item_action(),path+" does not open hidden furniture actions")
  check(state()==hidden_before,path+" hidden click preserves layout, wallet, revision and saves")
 game._cancel_selection();game._set_catalog_category("Build");shop.show_tiles()
 if shop.objects_hidden():shop.toggle_objects()
 check(not game.illustration.objects_hidden() and game.build_tools.mode=="","Show objects restores visible Tiles browse without choosing a tool")
 await floor_case("shown-tiles-control",point,plant_id,false)
 game._cancel_selection();game.editing=false;var before=state();click(game.illustration.iso(4.5,4.5))
 check(game.selected_id<0 and state()==before,"non-Decorate click does not select or mutate furniture")
 check(game.saves==0,"all examples avoid original and synthetic saves")
 var report={"checks":checks,"failures":failures,"observations":observations,"original_player_save_used":false,"save_calls":game.saves,"viewport":[1360,880],"zoom":1.0,"overlay":"test-only blue clicked-cell outline and crosshair at the dispatched pointer; caption names actual selected target"}
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free()
 if evidence_layer!=null:evidence_layer.queue_free()
 await process_frame;await process_frame
 report.audio_teardown=await AudioDrain.wait_for_mixer_cycles(self)
 if capture_dir!="":FileAccess.open(capture_dir.path_join("picking-observations.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
 print("DECORATE_FURNITURE_PICKING_RESULT ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
