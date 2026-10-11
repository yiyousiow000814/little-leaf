extends SceneTree
## Generated cafe only; compare the exact frozen baseline guard on real controls.
const Shop=preload("res://scripts/cafe_shop_ui.gd")
class TestMain extends "res://scripts/main.gd":
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():return true
 func _setup_music():pass
class LegacyShop extends Shop:
 var legacy_action_layout_key=""
 func _layout_action_board(width:float):
  action_background.visible=ui.context.visible
  if not ui.context.visible:return
  var actions=[];var used=0.0;var gap=6.0
  for child in ui.context.get_children():
   if child==action_copy or not child.visible:continue
   if child.custom_minimum_size!=Vector2(44,44):child.custom_minimum_size=Vector2(44,44)
   for state in ["normal","hover","pressed","hover_pressed","disabled"]:
    var style=child.get_theme_stylebox(state)
    if style.content_margin_left!=10:style.content_margin_left=10
    if style.content_margin_right!=10:style.content_margin_right=10
    if style.content_margin_top!=4:style.content_margin_top=4
    if style.content_margin_bottom!=4:style.content_margin_bottom=4
   var face=child.get_node_or_null("PaintedSurface")
   if face!=null:face.offset_top=4;face.offset_bottom=-4
   actions.append(child);used+=child.get_combined_minimum_size().x
  var signature=str([width,ui.context_label.text,price_label.text,ui.context_label.get_theme_font_size("font_size"),actions.map(func(button):return [button.get_instance_id(),button.text,button.get_combined_minimum_size()])])
  if signature==legacy_action_layout_key:return
  legacy_action_layout_key=signature
  var font=ui.hud.font_bold;var title_width=ceilf(font.get_string_size(ui.context_label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,ui.context_label.get_theme_font_size("font_size")).x)
  var cost_width=ceilf(font.get_string_size(price_label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,price_label.get_theme_font_size("font_size")).x) if price_label.visible else 0.0
  var text_width=title_width+(cost_width+8 if price_label.visible else 0)+2
  var pad=36.0;var text_gap=12.0;var row_width=used+maxi(0,actions.size()-1)*gap
  var inner_limit=maxf(44,width-pad*2);var stacked=text_width+text_gap+row_width>inner_limit
  var board_width=minf(width,maxf(180,(maxf(text_width,row_width) if stacked else text_width+text_gap+row_width)+pad*2))
  var inner_width=board_width-pad*2
  var copy_width=inner_width if stacked else text_width
  # Exact glyph measurements happen before placing children. No stale-price budget.
  ui.context_label.custom_minimum_size=Vector2(minf(title_width,maxf(0,copy_width-(cost_width+8 if price_label.visible else 0))),0);price_label.custom_minimum_size=Vector2(cost_width,0)
  action_copy.custom_minimum_size=Vector2.ZERO
  var copy_height=maxf(22,maxf(ui.context_label.get_theme_font("font").get_height(ui.context_label.get_theme_font_size("font_size")),price_label.get_theme_font("font").get_height(price_label.get_theme_font_size("font_size")) if price_label.visible else 0))
  var x=0.0 if stacked else copy_width+text_gap
  var y=copy_height+4 if stacked else 0.0
  var last_y=y
  for action in actions:
   var action_width=maxf(44,action.get_combined_minimum_size().x)
   if stacked and x>0 and x+action_width>inner_width:x=0;y+=44+gap
   action.position=Vector2(x,y);action.size=Vector2(action_width,44);x+=action_width+gap;last_y=y
  var content_height=maxf(copy_height,last_y+44)
  _put(action_copy,Rect2(0,0 if stacked else (content_height-copy_height)*.5,copy_width,copy_height))
  var vertical_pad=22.0 if stacked else 10.0
  var board_height=content_height+vertical_pad*2
  var board=Rect2((width-board_width)*.5,-board_height-8,board_width,board_height)
  action_background.position=board.position;action_background.size=board.size
  _put(ui.context,Rect2(board.position+Vector2(pad,vertical_pad),Vector2(inner_width,content_height)))
  ui.context.set_meta("available_width",inner_width)


var checks=0
var failures=[]
var samples=[]
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func snapshot(shop):
 var result=[shop.action_background.get_rect(),shop.ui.context.get_rect(),shop.action_copy.get_rect(),shop.price_label.custom_minimum_size,shop.ui.context_label.custom_minimum_size]
 for child in shop.ui.context.get_children():
  if child.visible:result.append([child.get_instance_id(),child.get_rect()])
 return result
func compare(shop,legacy,label):
 shop._layout_action_board(shop.root.size.x)
 var actual=snapshot(shop)
 legacy.legacy_action_layout_key="";legacy._layout_action_board(shop.root.size.x)
 check(actual==snapshot(shop),label)
func measure(shop,iterations):
 var start=Time.get_ticks_usec()
 for i in iterations:shop._layout_action_board(shop.root.size.x)
 return Time.get_ticks_usec()-start
func run():
 var game=TestMain.new();root.add_child(game);await process_frame
 game.set_process(false);game.paused=true;game.editing=true
 var ui=game.compact_ui;var shop=ui.shop_ui;var legacy=LegacyShop.new(ui)
 for field in ["root","action_background","action_copy","price_label"]:legacy.set(field,shop.get(field))
 for width in [960,390]:
  root.size=Vector2i(width,844)
  game.selected_kind="plant";game._update_ui()
  for i in 4:await process_frame
  shop.sync_action_details();compare(shop,legacy,"initial layout %s"%width)
  shop.action_layout_key=[]
  shop._layout_action_board(shop.root.size.x);legacy._layout_action_board(shop.root.size.x)
  var before=[];var after=[]
  for repeat in 7:
   if repeat%2==0:before.append(measure(legacy,3000));after.append(measure(shop,3000))
   else:after.append(measure(shop,3000));before.append(measure(legacy,3000))
  before.sort();after.sort()
  samples.append({"width":width,"calls_per_sample":3000,"samples":7,"baseline_median_us":before[3],"candidate_median_us":after[3]})
  ui.context_label.text="A changed selection title";compare(shop,legacy,"same-frame title change %s"%width)
  shop.price_label.text="Pay 123";shop.price_label.show();compare(shop,legacy,"same-frame price change %s"%width)
  ui.rotate_button.visible=not ui.rotate_button.visible;compare(shop,legacy,"same-frame action visibility %s"%width)
  ui.cancel_button.text="Long cancel label";compare(shop,legacy,"same-frame action text %s"%width)
  ui.cancel_button.add_theme_font_size_override("font_size",20);compare(shop,legacy,"same-frame action minimum size %s"%width)
  shop.root.size.x-=15;compare(shop,legacy,"same-frame width change %s"%width)
 game.editing=false;shop.sync_action_details();check(not shop.action_background.visible,"play mode hides board immediately")
 game.editing=true;shop.sync_action_details();check(shop.action_background.visible,"return to selection shows board immediately")
 print("UI_GUARD_PERFORMANCE_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"timings":samples,"scope":"headless unchanged action-board CPU calls; no FPS, heat or GPU claim"}))
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
