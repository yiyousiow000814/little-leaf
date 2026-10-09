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
var result={"checks":0,"failures":[],"viewport":[1360,880],"points":{},"regions":{},"ui_route":"historical-recovery"}
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
func click_at(name:String,position:Vector2):
 result.points[name]=[position.x,position.y]
 var motion=InputEventMouseMotion.new();motion.position=position;motion.global_position=position;root.push_input(motion,true)
 for pressed in [true,false]:
  var event=InputEventMouseButton.new();event.position=position;event.global_position=position;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
 await settle()
func click(name:String,control:Control):
 point(control)
 await click_at(name,control.get_global_rect().get_center())
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
  var before_selection=game.model.coins
  var attachments=game.model.wall_attachments.duplicate(true)
  # Validate both preserved inputs with the candidate's exact model.
  var model=game.Model.new()
  check(model.load_save("res://tests/wall-fixture-new.json"),"new fixture loads through exact candidate codec")
  await click("decorate",game.edit_button)
  check(game.editing,"real native Decorate pointer enters edit mode")
  # At desktop size the category rail is visible; no guessed screen locations.
  await click("build",game.category_buttons["Build"])
  check(game.catalog_category=="Build","real native Build pointer selects category")
  result.regions.catalog=region(game.tray)
  # Retain the complete tray; enlarge only the separate OCR input losslessly.
  result.regions.catalog.scale=3
  await click("wall",game.build_tools.tool_buttons["full"])
  var ui=game.compact_ui
  var shop=ui.shop_ui
  result.ui_route="wall-bottom-tray"
  check(shop.build_page=="walls" and not ui.has_open_popup(),"real native Wall card opens bottom tray without a popup")
  check(shop._visible_build_keys().size()==6,"Wall tray exposes six complete height and finish products")
  result.regions.wall_heading=text_region(shop.tiles_title)
  # The back button has asymmetric icon padding. Its full native bounds keep
  # the complete label; a font-centered text estimate clips the final letter.
  result.regions.wall_back=region(shop.tiles_back)
  result.regions.wall_back.psm=7
  result.regions.wall_back.scale=3
  # The desired half-wall card starts partly clipped. Page via the real arrow,
  # just as the browser does; do not derive a point from a hidden/clipped card.
  await click("wall_next",shop.product_next)
  var card=shop.wall_cards["wall:half:sage_panels"]
  check(ui.build_scroll.get_global_rect().encloses(card.get_global_rect()),"half Sage panels card is fully inside the visible product rail")
  result.regions.style_name=label_region(card,"Sage panels")
  result.regions.style_height=label_region(card,"Half wall")
  result.regions.style_price=label_region(card,"35")
  await click("wall_style",card)
  check(game.build_tools.mode=="half" and game.build_tools.material=="sage_panels" and card.button_pressed,"real native card selects the half Sage panels product")
  check(shop.build_page=="walls" and not ui.has_open_popup(),"selected product keeps the Wall tray and world available")
  check(game.save_calls==0 and game.model.coins==before_selection,"browsing and selecting a Wall product never saves or charges")
  result.regions.selected_height=text_region(ui.context_label)
  result.regions.selected_price=text_region(shop.price_label)
  var target=game.illustration.iso(2.5,0,70)
  var hit=game.illustration.hit_wall_host(target)
  check(hit.get("segment_key","")=="shell:back#2","derived world point hits exact back segment")
  check(root.get_visible_rect().has_point(target) and not game.interaction._over_ui(target),"derived segment is a visible unobstructed world target")
  await click_at("segment",target)
  check(ui.wall_review.visible and ui.pending_wall.get("key","")=="shell:back#2","exact segment opens replacement review")
  check(not ui.wall_confirm_button.disabled,"replacement is valid with restored actors")
  result.regions.review=region(ui.wall_review)
  result.regions.review_heading=label_region(ui.wall_review,"Replace wall")
  result.regions.review_text=text_region(ui.wall_review_text)
  check(game.save_calls==0 and game.model.coins==before_selection,"target and replacement review never save or charge before confirmation")
  var before=game.model.coins
  await click("confirm",ui.wall_confirm_button)
  check(game.save_calls==1 and game.model.coins==before-35,"normal confirm invokes one save and one 35 coin charge")
  check(game.model.shell_segment_products["shell:back#2"].height=="half" and game.model.shell_segment_products["shell:back#2"].material=="sage_panels","new model has requested half Sage panels segment")
  check(game.model.wall_attachments==attachments,"wall replacement preserves paid opening geometry and ownership")
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
