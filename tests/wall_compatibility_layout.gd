extends SceneTree
## CI-only coordinate/codec preflight, copied into disposable export projects.
## This script is excluded from the shipped pack. Browser assertions still run
## the untouched exported main scene and real Web save controller.
class LayoutMain extends "res://scripts/main.gd":
 var fixture=""
 var save_calls=0
 func _load_startup():
  save_writes_suppressed=true;fresh_start=false
  assert(model.load_save(fixture),model.last_error)
  if model.included_bin_pending:model.ensure_basic_bin()
 func _save():save_calls+=1;return true
var game
var result={"checks":0,"failures":[],"viewport":[1360,880],"points":{},"regions":{}}
var output=""
var fixture=""
var newer=false
func _initialize():
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--fixture="):fixture=arg.trim_prefix("--fixture=")
  if arg.begins_with("--layout-output="):output=arg.trim_prefix("--layout-output=")
  if arg=="--new-layout":newer=true
 run.call_deferred()
func check(ok:bool,label:String):
 result.checks+=1
 if not ok:result.failures.append(label);printerr("FAIL ",label)
func settle():
 game._update_ui()
 for i in 24:await process_frame
func point(control:Control)->Array:
 check(control.is_visible_in_tree(),"visible target "+str(control.name))
 var rect=control.get_global_rect()
 check(Rect2(Vector2.ZERO,Vector2(1360,880)).encloses(rect),"bounded target "+str(control.name))
 var center=rect.get_center();return [center.x,center.y]
func region(control:Control)->Dictionary:
 var rect=control.get_global_rect()
 check(control.is_visible_in_tree() and Rect2(Vector2.ZERO,Vector2(1360,880)).encloses(rect),"bounded visible OCR region "+str(control.name))
 return {"x":floor(rect.position.x),"y":floor(rect.position.y),"width":ceil(rect.size.x),"height":ceil(rect.size.y)}
func text_region(control:Control)->Dictionary:
 var bounds=control.get_global_rect()
 if control is Button:
  var button=control as Button
  var font=button.get_theme_font("font");var size=button.get_theme_font_size("font_size")
  var measured=font.get_string_size(button.text,HORIZONTAL_ALIGNMENT_LEFT,-1,size)
  var at=bounds.get_center()-measured*.5
  var style=button.get_theme_stylebox("normal")
  if button.alignment==HORIZONTAL_ALIGNMENT_LEFT:at.x=bounds.position.x+style.get_margin(SIDE_LEFT)
  elif button.alignment==HORIZONTAL_ALIGNMENT_RIGHT:at.x=bounds.end.x-style.get_margin(SIDE_RIGHT)-measured.x
  bounds=Rect2(at,measured).grow(2)
 check(control.is_visible_in_tree() and Rect2(Vector2.ZERO,Vector2(1360,880)).encloses(bounds),"bounded visible text OCR region "+str(control.name))
 return {"x":floor(bounds.position.x),"y":floor(bounds.position.y),"width":ceil(bounds.size.x),"height":ceil(bounds.size.y),"psm":7 if control is Button else 6,"scale":3}
func find_label(node:Node,words:String)->Label:
 if node is Label and (node as Label).text==words:return node as Label
 for child in node.get_children():
  var found=find_label(child,words)
  if found!=null:return found
 return null
func label_region(node:Node,words:String)->Dictionary:
 var label=find_label(node,words)
 check(label!=null,"required rendered label exists: "+words)
 return text_region(label) if label!=null else {}
func click(name:String,control:Control):
 result.points[name]=point(control)
 var event=InputEventMouseButton.new();event.position=control.get_global_rect().get_center();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true
 Input.parse_input_event(event);await process_frame
 event=event.duplicate();event.pressed=false;Input.parse_input_event(event);await settle()
func run():
 if not "saveguard" in OS.get_user_data_dir():printerr("Use disposable saveguard profile");quit(2);return
 root.size=Vector2i(1360,880)
 game=LayoutMain.new();game.fixture=fixture;root.add_child(game)
 game.set_process(false);game.illustration.set_process(false);game.paused=true
 await settle()
 check(game.model.last_error=="","fixture loads through exact model codec")
 result.points.business=point(game.business_button)
 result.points.decorate=point(game.edit_button)
 result.points.settings=point(game.compact_ui.settings_button)
 if newer:
  # Validate both preserved inputs with the candidate's exact model.
  var model=game.Model.new()
  check(model.load_save("res://tests/wall-fixture-new.json"),"new fixture loads through exact candidate codec")
  await click("decorate",game.edit_button)
  check(game.editing,"real native Decorate pointer enters edit mode")
  # At desktop size the category rail is visible; no guessed screen locations.
  await click("build",game.category_buttons["Build"])
  check(game.catalog_category=="Build","real native Build pointer selects category")
  result.regions.catalog=region(game.tray)
  await click("wall",game.build_tools.tool_buttons["full"])
  var ui=game.compact_ui
  check(ui.finishes.visible,"real native wall card opens product picker")
  result.points.height=point(ui.wall_heights)
  # A mouse-opened OptionButton focuses no item; Down/Enter selects its first item.
  ui.wall_heights.select(0);ui.wall_heights.item_selected.emit(0)
  ui.wall_papers.select(0);ui.wall_papers.item_selected.emit(0)
  await settle()
  result.points.paper=point(ui.wall_papers)
  result.regions.product=region(ui.finishes)
  result.regions.product_label=label_region(ui.finishes,"Wall style · included")
  result.regions.product_target=text_region(ui.wall_use_button)
  result.regions.height=text_region(ui.wall_heights)
  result.regions.paper=text_region(ui.wall_papers)
  result.regions.price=text_region(ui.wall_price_label)
  await click("choose_target",ui.wall_use_button)
  var target=game.illustration.iso(2.5,0,70)
  var hit=game.illustration.hit_wall_host(target)
  check(hit.get("segment_key","")=="shell:back#2","derived world point hits exact back segment")
  result.points.segment=[target.x,target.y]
  game.build_tools.refresh(target);game.build_tools._commit();await settle()
  check(ui.wall_review.visible and ui.pending_wall.get("key","")=="shell:back#2","exact segment opens replacement review")
  check(not ui.wall_confirm_button.disabled,"replacement is valid with restored actors")
  result.regions.review=region(ui.wall_review)
  result.regions.review_heading=label_region(ui.wall_review,"Replace wall")
  result.regions.review_text=text_region(ui.wall_review_text)
  var before=game.model.coins
  await click("confirm",ui.wall_confirm_button)
  check(game.save_calls==1 and game.model.coins==before-35,"normal confirm invokes one save and one 35 coin charge")
  check(game.model.shell_segment_products["shell:back#2"].height=="half","new model has requested half segment")
  result.expected_segment=game.model.shell_segment_products["shell:back#2"].duplicate(true)
  result.expected_cost=35
  game.compact_ui._hide_popups()
 # Only derive recovery Help bounds and retry button; this is not browser proof.
 game.web_save=preload("res://scripts/cafe_web_save.gd").new(game)
 game.web_save._block_startup("Invalid saved wall or finish data")
 game.compact_ui.show_help();await settle()
 result.points.retry=point(game.compact_ui.help_retry)
 var rect=game.compact_ui.help_panel.get_global_rect()
 result.help_rect={"x":floor(rect.position.x),"y":floor(rect.position.y),"width":ceil(rect.size.x),"height":ceil(rect.size.y)}
 var file=FileAccess.open(output,FileAccess.WRITE)
 if file==null:printerr("Cannot write layout receipt");quit(2);return
 file.store_string(JSON.stringify(result,"  "));file.close()
 print("WALL_COMPATIBILITY_LAYOUT_RESULT ",JSON.stringify(result))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame
 quit(0 if result.failures.is_empty() else 1)
