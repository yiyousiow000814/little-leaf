extends RefCounted
## A fixed-height horizontal shop: category rail above a scrollable product rail.
## Existing real catalog keys, callbacks, prices and atomic dining products stay intact.
const Illustration=preload("res://scripts/illustrated_cafe.gd")
const ThumbnailAtlas=preload("res://scripts/furniture_static_atlas.gd")
const ViewportLayout=preload("res://scripts/cafe_viewport_layout.gd")
const DECOR_THUMBNAILS=["plant","lamp","bookshelf","rug","divider"]
var owner_ref:WeakRef
var ui:
 get:return owner_ref.get_ref()
var game
var root:Control
var background:NinePatchRect
var action_background:NinePatchRect
var category_scroll:ScrollContainer
var category_row:HBoxContainer
var category_more:Button
var category_back:Button
var category_picker:Button
var category_panel:PanelContainer
var category_panel_buttons={}
var product_back:Button
var product_next:Button
var category_icons={}
var price_icons={}
var scroll_tweens={}
var affordability_labels={}
var build_previews={}
var product_shelf=Rect2()
var product_snap_timers={}
var product_contacts={}
var product_rest_offsets={}
var product_stride=0.0
var product_page_items=1
var product_snap_enabled=false
var product_layout_key=""
var last_product_category=""
var product_restore_index=-1
var rail_fit_queued=false
var footer_hint:Label
var last_category=""
var last_layout_width=-1.0
var category_page_items=6
var header_active=false
var browse_offset=0
func _init(owner):owner_ref=weakref(owner);game=owner.game
func _style(button:Button):
 var h=ui.hud
 button.add_theme_stylebox_override("normal",h.texture_style("cream_face",14))
 button.add_theme_stylebox_override("hover",h.texture_style("cream_face",14,Color(1.08,1.05,1.0)))
 button.add_theme_stylebox_override("pressed",h.texture_style("green_face",14))
 button.add_theme_stylebox_override("hover_pressed",h.texture_style("green_face",14,Color(1.06,1.06,1.02)))
 button.add_theme_stylebox_override("disabled",h.texture_style("cream_face",14,Color(.73,.71,.66)))
 button.add_theme_font_override("font",h.font_bold)
 for state in ["font_color","font_hover_color","font_focus_color"]:button.add_theme_color_override(state,h.INK)
 button.add_theme_color_override("font_pressed_color",h.CREAM);button.add_theme_color_override("font_hover_pressed_color",h.CREAM)
 var focus=h._surface(Color.TRANSPARENT,Color("fff8dd"),10);focus.set_border_width_all(2);button.add_theme_stylebox_override("focus",focus)
 h._soft_button(button)
 h._bind_motion(button)
func _illustration(parent:Control,kind:String)->Node2D:
 var art=Illustration.new();art.icon_kind=kind;parent.add_child(art);return art
func _fit_thumbnail(kind:String,art:Node2D,slot_size:Vector2):
 if kind not in DECOR_THUMBNAILS:
  var ratio=minf(1,minf(slot_size.y/54.0,slot_size.x/77.0))
  art.scale=Vector2.ONE*.78*ratio;art.position=Vector2((slot_size.x-77*ratio)/2,3*ratio);return
 # The established static-art bounds include the original AA fringe. Convert
 # through Illustration's unchanged icon transform, then uniformly fit them.
 var source:Rect2=ThumbnailAtlas.PART_BOUNDS[kind]
 var icon_bounds=Rect2(Vector2(49,57)+source.position*.8,source.size*.8)
 var padded=Rect2(8,4,slot_size.x-16,slot_size.y-8)
 var factor=minf(padded.size.x/icon_bounds.size.x,padded.size.y/icon_bounds.size.y)
 art.scale=Vector2.ONE*factor;art.position=padded.get_center()-icon_bounds.get_center()*factor
 art.set_meta("thumbnail_visual_bounds",Rect2(art.position+icon_bounds.position*factor,icon_bounds.size*factor))
 art.set_meta("thumbnail_padded_slot",padded)

func _scroll_skin(scroll:ScrollContainer):
 var bar=scroll.get_h_scroll_bar();bar.custom_minimum_size.y=9
 var track=game._style(Color("a69678"),Color.TRANSPARENT,4)
 for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:track.set_content_margin(side,0)
 bar.add_theme_stylebox_override("scroll",track)
 for state in ["grabber","grabber_highlight","grabber_pressed"]:
  var style=game._style(Color("f2e8d2"),Color("8e8168"),4)
  for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:style.set_content_margin(side,0)
  bar.add_theme_stylebox_override(state,style)
 bar.value_changed.connect(func(_value):_sync_scroll_buttons())
 bar.changed.connect(_sync_scroll_buttons)

func _nav(label:String,callback:Callable)->Button:
 var button=ui._small_button(label,callback,44);_style(button);button.add_theme_font_size_override("font_size",12);root.add_child(button);return button
func setup():
 root=Control.new();root.mouse_filter=Control.MOUSE_FILTER_IGNORE;ui.column.add_child(root)
 background=NinePatchRect.new();background.texture=ui.hud._texture("shop_frame");background.mouse_filter=Control.MOUSE_FILTER_IGNORE
 background.material=ui.hud._art_material()
 background.patch_margin_left=26;background.patch_margin_right=26;background.patch_margin_top=23;background.patch_margin_bottom=23;root.add_child(background)
 game.tray.add_theme_stylebox_override("panel",StyleBoxEmpty.new());ui.categories.hide()
 category_scroll=ScrollContainer.new();category_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_SHOW_NEVER;category_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;root.add_child(category_scroll)
 category_scroll.follow_focus=true;category_row=HBoxContainer.new();category_row.add_theme_constant_override("separation",6);category_scroll.add_child(category_row);category_row.size_flags_horizontal=Control.SIZE_EXPAND_FILL;category_row.alignment=BoxContainer.ALIGNMENT_CENTER;_scroll_skin(category_scroll)
 var kinds={"Tables":"table_set","Kitchen":"stove","Drinks":"beverage","Cleaning":"sink","Decor":"plant","Build":"counter"}
 for category in game.category_buttons:
  var button:Button=game.category_buttons[category];button.reparent(category_row);_style(button)
  button.alignment=HORIZONTAL_ALIGNMENT_CENTER;button.add_theme_font_size_override("font_size",14)
  button.tooltip_text=category+" furniture" if category!="Build" else "Walls, doors, windows and flooring"
  category_icons[category]=_illustration(button,kinds[category])
 game.catalog_scroll.reparent(root);ui.build_scroll.reparent(root);ui.context.reparent(root);ui.wall_quote_label.reparent(root)
 action_background=background.duplicate();root.add_child(action_background);root.move_child(action_background,0);action_background.mouse_filter=Control.MOUSE_FILTER_STOP;action_background.hide()
 for scroll in [game.catalog_scroll,ui.build_scroll]:
  scroll.follow_focus=true;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_SHOW_NEVER;_scroll_skin(scroll);scroll.minimum_size_changed.connect(_queue_rail_fit)
  var timer=Timer.new();timer.one_shot=true;timer.wait_time=.18;root.add_child(timer)
  product_snap_timers[scroll.get_instance_id()]=timer
  timer.timeout.connect(_snap_products.bind(scroll))
  scroll.get_h_scroll_bar().value_changed.connect(func(_value):_queue_product_snap(scroll))
  scroll.gui_input.connect(_product_input.bind(scroll))
  scroll.scroll_started.connect(_product_scroll_started.bind(scroll))
  scroll.scroll_ended.connect(_product_scroll_ended.bind(scroll))
  var shelf_row=scroll.get_child(0);shelf_row.size_flags_horizontal=Control.SIZE_EXPAND_FILL;shelf_row.alignment=BoxContainer.ALIGNMENT_CENTER;shelf_row.minimum_size_changed.connect(_queue_rail_fit)
 category_back=_nav("‹",func():_scroll_categories(-1));category_back.accessibility_name="Previous categories"
 category_more=_nav("›",func():_scroll_categories(1));category_more.tooltip_text="Next categories · swipe to browse";category_more.accessibility_name="Next categories"
 product_back=_nav("‹",func():_page_products(-1));product_back.accessibility_name="Previous products"
 product_next=_nav("›",func():_page_products(1));product_next.accessibility_name="Next products"
 for arrow in [category_back,category_more,product_back,product_next]:arrow.add_theme_font_size_override("font_size",24)
 ui.help_access.reparent(root);_style(ui.help_access)
 _setup_category_picker()
 for kind in game.catalog_cards:
  var card:Button=game.catalog_cards[kind];_style(card)
  var column:VBoxContainer=card.get_child(0);column.mouse_filter=Control.MOUSE_FILTER_IGNORE;column.add_theme_constant_override("separation",2)
  column.offset_left=8;column.offset_right=-8;column.offset_top=4;column.offset_bottom=-4
  var holder:Control=column.get_child(0);holder.custom_minimum_size=Vector2(132,84)
  var art:Node2D=holder.get_child(0);art.position=Vector2(8,1);art.scale=Vector2(1.08,1.08)
  for index in [1,2]:
   var label:Label=column.get_child(index);label.add_theme_font_override("font",ui.hud.font_bold);label.add_theme_color_override("font_color",ui.hud.INK);label.add_theme_font_size_override("font_size",16 if index==1 else 21)
  card.custom_minimum_size=Vector2(148,140);card.toggle_mode=true
  var price_label:Label=game.catalog_prices[kind]
  var price_row=HBoxContainer.new();price_row.alignment=BoxContainer.ALIGNMENT_CENTER;price_row.add_theme_constant_override("separation",5);price_row.mouse_filter=Control.MOUSE_FILTER_IGNORE
  column.add_child(price_row)
  var coin=ui.hud._picture(price_row,ui.hud._texture("coin"));coin.custom_minimum_size=Vector2(21,21);coin.size_flags_vertical=Control.SIZE_SHRINK_CENTER;price_icons[kind]=coin
  price_label.reparent(price_row);price_label.size_flags_horizontal=Control.SIZE_SHRINK_CENTER;price_label.size_flags_vertical=Control.SIZE_SHRINK_CENTER
  var availability=ui.hud._label(column,"",11,Color("93482e"));availability.custom_minimum_size.y=16;availability.size_flags_horizontal=Control.SIZE_EXPAND_FILL;affordability_labels[kind]=availability
 for key in ["full","door","window"]:
  var card:Button=game.build_tools.tool_buttons[key];_style(card);card.custom_minimum_size=Vector2(148,140)
  var column:VBoxContainer=card.get_child(0);column.add_theme_constant_override("separation",2);column.offset_left=8;column.offset_right=-8;column.offset_top=4;column.offset_bottom=-4
  var image=column.get_child(0);image.custom_minimum_size.y=54
  var holder=Control.new();holder.custom_minimum_size=Vector2(84,54);holder.mouse_filter=Control.MOUSE_FILTER_IGNORE;column.add_child(holder);column.move_child(holder,0);image.reparent(holder)
  build_previews[key]={"holder":holder,"image":image}
  var title:Label=column.get_child(1);title.custom_minimum_size.y=22;title.add_theme_font_override("font",ui.hud.font_bold);title.add_theme_font_size_override("font_size",16)
  var price:Label=column.get_child(2);price.add_theme_font_override("font",ui.hud.font_bold);price.add_theme_font_size_override("font_size",21);price.add_theme_color_override("font_color",ui.hud.INK)
  var price_row=HBoxContainer.new();price_row.custom_minimum_size.y=28;price_row.alignment=BoxContainer.ALIGNMENT_CENTER;price_row.add_theme_constant_override("separation",5);price_row.mouse_filter=Control.MOUSE_FILTER_IGNORE;column.add_child(price_row)
  var coin=ui.hud._picture(price_row,ui.hud._texture("coin"));coin.custom_minimum_size=Vector2(21,21);coin.size_flags_vertical=Control.SIZE_SHRINK_CENTER
  price.reparent(price_row);price.size_flags_vertical=Control.SIZE_SHRINK_CENTER
  var availability=ui.hud._label(column,"",11);availability.custom_minimum_size.y=16
 for button in [ui.rotate_button,ui.move_button,ui.finish_button,ui.remove_button,ui.upgrade_button,ui.cancel_button,ui.floor_access]:_style(button)
 footer_hint=ui.hud._label(root,"",13);footer_hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_LEFT
 ui.floor_access.reparent(root)
 ui.context_label.clip_text=true;ui.context_label.custom_minimum_size.x=0;ui.context_label.size_flags_horizontal=Control.SIZE_SHRINK_CENTER;ui.context_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;ui.context.alignment=BoxContainer.ALIGNMENT_CENTER
 ui.context_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;ui.context_label.add_theme_font_override("font",ui.hud.font_bold);ui.context_label.add_theme_color_override("font_color",ui.hud.INK)
 for button in [ui.rotate_button,ui.move_button,ui.finish_button,ui.remove_button,ui.upgrade_button,ui.cancel_button,ui.floor_access]:button.custom_minimum_size.y=44
 ui.wall_quote_label.autowrap_mode=TextServer.AUTOWRAP_OFF;ui.wall_quote_label.clip_text=true;ui.wall_quote_label.add_theme_font_size_override("font_size",11)
 for card in game.catalog_cards.values():_flatten_card(card)
 for key in ["full","door","window"]:_flatten_card(game.build_tools.tool_buttons[key])
 root.resized.connect(func():background.size=root.size)
 game.get_window().focus_exited.connect(_cancel_product_contacts)
 game.tree_exiting.connect(_dispose_product_scroll)
func _setup_category_picker():
 category_picker=ui._small_button("",_toggle_category_picker,112);_style(category_picker);category_picker.add_theme_font_size_override("font_size",13);category_picker.accessibility_name="Choose furniture category";root.add_child(category_picker);category_picker.hide()
 category_picker.draw.connect(_draw_category_picker_arrow)
 category_panel=ui._panel();category_panel.name="CatalogueCategories";ui.hud.theme_panel(category_panel,false,12)
 var grid=GridContainer.new();grid.columns=2;grid.add_theme_constant_override("h_separation",8);grid.add_theme_constant_override("v_separation",8);category_panel.add_child(grid)
 for category in game.category_buttons:
  var button=ui._small_button(category,_pick_category.bind(category),124);_style(button);button.custom_minimum_size=Vector2(124,44);button.add_theme_font_size_override("font_size",13);button.toggle_mode=true;grid.add_child(button);category_panel_buttons[category]=button
 category_panel.resized.connect(_position_category_panel)
func _draw_category_picker_arrow():
 # Draw the indicator directly: bundled Web fonts need not contain U+25BE.
 var font=category_picker.get_theme_font("font")
 var font_size=category_picker.get_theme_font_size("font_size")
 var text_width=font.get_string_size(category_picker.text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
 var center=Vector2((category_picker.size.x+text_width)*.5-5,category_picker.size.y*.5+1)
 var points=PackedVector2Array([center+Vector2(-3,-2),center+Vector2(3,-2),center+Vector2(0,2)])
 category_picker.draw_colored_polygon(points,ui.hud.CREAM if category_picker.is_pressed() else ui.hud.INK)
func _toggle_category_picker():
 if category_panel.visible:category_panel.hide();ui.sync();return
 ui._popup_at(category_panel,280);_position_category_panel();ui.sync()
func _pick_category(category:String):
 category_panel.hide();game._set_catalog_category(category)
func _position_category_panel():
 if not is_instance_valid(category_panel) or not category_panel.visible:return
 var view=game.get_viewport().get_visible_rect().size;var insets=ui.hud._safe_insets()
 var safe=Rect2(Vector2(insets.x+12,insets.y+12),Vector2(view.x-insets.x-insets.z-24,view.y-insets.y-insets.w-24))
 var anchor=category_picker.get_global_rect()
 category_panel.position=Vector2(clampf(anchor.position.x,safe.position.x,maxf(safe.position.x,safe.end.x-category_panel.size.x)),clampf(anchor.position.y-category_panel.size.y-8,safe.position.y,maxf(safe.position.y,safe.end.y-category_panel.size.y)))

func _flatten_card(card:Button):
 card.mouse_filter=Control.MOUSE_FILTER_PASS
 # Reflow the existing art/name/price/status children side by side. Their
 # callbacks, product IDs, prices, text and purchase logic remain the same.
 var old=card.get_child(0);var body=Control.new();body.mouse_filter=Control.MOUSE_FILTER_IGNORE
 card.add_child(body);card.move_child(body,0)
 body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 body.offset_left=8;body.offset_top=4;body.offset_right=-8;body.offset_bottom=-4
 for child in old.get_children():child.reparent(body)
 old.queue_free()
func _layout_product_card(card:Button,width:float,height:float,short_landscape:bool=false):
 var body=card.get_child(0);var image=body.get_child(0);var tiny=width<180 or short_landscape
 var art_width=44.0 if tiny else 56.0;var text_x=art_width+6;var text_width=width-16.0-text_x
 var title:Label=body.get_child(1);title.horizontal_alignment=HORIZONTAL_ALIGNMENT_LEFT
 title.clip_text=false;title.autowrap_mode=TextServer.AUTOWRAP_OFF if tiny else TextServer.AUTOWRAP_WORD_SMART
 # Narrow and short-landscape cards give the full name the whole top row. The image and
 # price/status sit beside each other below, preserving readable type.
 _put(title,Rect2(0 if tiny else text_x,0 if tiny else 1,width-16 if tiny else text_width,0))
 var title_end=title.position.y+title.get_combined_minimum_size().y
 var price=body.get_child(2);price.alignment=BoxContainer.ALIGNMENT_BEGIN
 var price_y=title_end+2;var price_height=maxf(24,price.get_combined_minimum_size().y)
 _put(price,Rect2(text_x,price_y,text_width,price_height))
 var status=body.get_child(3);status.horizontal_alignment=HORIZONTAL_ALIGNMENT_LEFT
 _put(status,Rect2(text_x,price_y+price_height+2,text_width,maxf(16,status.get_combined_minimum_size().y)))
 var image_height=minf(42,height-8-price_y) if tiny else minf(58,height-16)
 _put(image,Rect2(0,price_y if tiny else (height-8-image_height)*.5,art_width,image_height))
func _active_products()->ScrollContainer:return ui.build_scroll if game.catalog_category=="Build" else game.catalog_scroll
func _scroll_to(scroll:ScrollContainer,target:float):
 var bar=scroll.get_h_scroll_bar();target=clampf(target,0,maxf(0,bar.max_value-bar.page))
 var id=scroll.get_instance_id()
 if scroll_tweens.has(id) and is_instance_valid(scroll_tweens[id]):scroll_tweens[id].kill()
 var tween=game.create_tween();scroll_tweens[id]=tween;tween.set_trans(Tween.TRANS_CUBIC);tween.set_ease(Tween.EASE_OUT)
 scroll.set_meta("shop_scroll_target",int(target))
 tween.tween_property(scroll,"scroll_horizontal",int(target),.18)
 if scroll!=category_scroll:tween.finished.connect(_product_scroll_finished.bind(scroll))
func _scroll_categories(direction:int):
 _scroll_to(category_scroll,category_scroll.scroll_horizontal+direction*(category_scroll.size.x+6))
func _reveal_category():
 if ui==null or not is_instance_valid(game):return
 var names=game.category_buttons.keys();var index=names.find(game.catalog_category)
 if index<0:return
 var button:Button=game.category_buttons[game.catalog_category]
 var start=floori(float(index)/category_page_items)*category_page_items*(button.size.x+6)
 var bar=category_scroll.get_h_scroll_bar();category_scroll.scroll_horizontal=int(clampf(start,0,maxf(0,bar.max_value-bar.page)))
func _restore_browse_offset():
 if ui==null:return
 category_scroll.scroll_horizontal=browse_offset
func sync_quote(original_text=""):
 if ui==null or not ui.wall_quote_label.visible:return
 var b=game.build_tools;var quote={}
 if not b.active() or b.mode not in ["half","full","floor"]:ui.wall_quote_label.hide();return
 if b.mode=="floor":quote=b.floor_quote
 elif b.replacing:quote=b.replacement_quote
 var text=""
 if b.mode=="floor" and not b.floor_preview.is_empty() and game.model.floor_style_at(Vector2i(int(b.floor_preview.x),int(b.floor_preview.z)))==b.floor_material:
  text="Already installed · no charge"
 elif not quote.is_empty():
  text="Pay %s · new %s, refund %s"%[ui.Money.amount(int(quote.net)),ui.Money.amount(int(quote.new_cost)),ui.Money.amount(int(quote.refund))]
  if quote.has("units"):text+=" · %d tiles"%int(quote.units)
 elif b.mode=="floor":text="Floor · %s / tile"%ui.Money.amount(game.model.floor_price(b.floor_material))
 else:text="Wall · %s / tile"%ui.Money.amount(game.model.wall_price(b.mode))
 ui.wall_quote_label.text=text
 ui.context_label.text=("Pay "+ui.Money.amount(int(quote.net))) if not quote.is_empty() else ("No charge" if text.begins_with("Already") else text)
 ui.context_label.tooltip_text=text
 if original_text!="":ui.wall_quote_label.tooltip_text=original_text
 ui.wall_quote_label.custom_minimum_size.x=0
 ui.wall_quote_label.size=Vector2.ZERO;ui.wall_quote_label.hide();_layout_context()

func _layout_context(available_width:float=-1.0):
 if not ui.context.visible:return
 var used=0.0;var count=0
 for child in ui.context.get_children():
  if child!=ui.context_label and child.visible:
   used+=child.get_combined_minimum_size().x;count+=1
 var natural=ui.hud.font_bold.get_string_size(ui.context_label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,ui.context_label.get_theme_font_size("font_size")).x+8
 var budget=available_width if available_width>=0 else float(ui.context.get_meta("available_width",ui.context.size.x))
 ui.context_label.custom_minimum_size.x=minf(natural,maxf(0,budget-used-count*6))

func _layout_action_board(width:float):
 action_background.visible=ui.context.visible
 if not ui.context.visible:return
 var used=0.0;var count=0
 for child in ui.context.get_children():
  if child==ui.context_label or not child.visible:continue
  child.custom_minimum_size=Vector2(44,48)
  used+=child.get_combined_minimum_size().x;count+=1
 var name_width=ui.hud.font_bold.get_string_size(ui.context_label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,ui.context_label.get_theme_font_size("font_size")).x+8
 var board_width=minf(width,maxf(180,used+name_width+count*6+48))
 var short_landscape=root.size.y<ViewportLayout.SHORT_SHOP_HEIGHT
 var board=Rect2((width-board_width)*.5,-60 if short_landscape else -72,board_width,56 if short_landscape else 64)
 action_background.position=board.position;action_background.size=board.size
 var available_width=board_width-48
 # A previous selection label must not inflate this HBox before fitting.
 ui.context_label.custom_minimum_size.x=0
 ui.context.set_meta("available_width",available_width)
 _layout_context(available_width)
 _put(ui.context,Rect2(board.position+Vector2(24,4 if short_landscape else 8),Vector2(available_width,48)))
func _product_scroll_finished(scroll:ScrollContainer):
 product_rest_offsets[scroll.get_instance_id()]=scroll.scroll_horizontal
 _queue_product_snap(scroll)
func _product_tween_running(scroll:ScrollContainer)->bool:
 var tween=scroll_tweens.get(scroll.get_instance_id())
 return is_instance_valid(tween) and tween.is_running()
func _stop_product_scroll(scroll:ScrollContainer):
 var id=scroll.get_instance_id();var tween=scroll_tweens.get(id)
 if is_instance_valid(tween):tween.kill()
 scroll_tweens.erase(id)
 if product_snap_timers.has(id):product_snap_timers[id].stop()
func _product_input(event:InputEvent,scroll:ScrollContainer):
 var id=scroll.get_instance_id()
 if event is InputEventScreenTouch:
  var contacts=product_contacts.get(id,{})
  if event.pressed:contacts[event.index]=true;_stop_product_scroll(scroll)
  else:contacts.erase(event.index)
  if contacts.is_empty():product_contacts.erase(id);_queue_product_snap(scroll)
  else:product_contacts[id]=contacts
 elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
  var contacts=product_contacts.get(id,{})
  if event.pressed:contacts[-1]=true;_stop_product_scroll(scroll)
  else:contacts.erase(-1)
  if contacts.is_empty():product_contacts.erase(id);_queue_product_snap(scroll)
  else:product_contacts[id]=contacts
 elif event is InputEventPanGesture or (event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN,MOUSE_BUTTON_WHEEL_LEFT,MOUSE_BUTTON_WHEEL_RIGHT]):
  _stop_product_scroll(scroll);_queue_product_snap(scroll)
func _product_scroll_started(scroll:ScrollContainer):
 _stop_product_scroll(scroll)
 var contacts=product_contacts.get(scroll.get_instance_id(),{});contacts[-2]=true;product_contacts[scroll.get_instance_id()]=contacts
func _product_scroll_ended(scroll:ScrollContainer):
 product_contacts.erase(scroll.get_instance_id());_queue_product_snap(scroll)
func _dispose_product_scroll():
 var window=game.get_window()
 if window.focus_exited.is_connected(_cancel_product_contacts):window.focus_exited.disconnect(_cancel_product_contacts)
 for scroll in [game.catalog_scroll,ui.build_scroll]:_stop_product_scroll(scroll)
 product_contacts.clear()
func _cancel_product_contacts():
 for scroll in [game.catalog_scroll,ui.build_scroll]:
  product_contacts.erase(scroll.get_instance_id());_stop_product_scroll(scroll);_queue_product_snap(scroll)
func _queue_product_snap(scroll:ScrollContainer):
 if not product_snap_enabled or product_restore_index>=0 or not scroll.is_visible_in_tree() or _product_tween_running(scroll):return
 if not product_contacts.get(scroll.get_instance_id(),{}).is_empty():return
 product_snap_timers[scroll.get_instance_id()].start()
func _snap_products(scroll:ScrollContainer):
 if not product_snap_enabled or product_stride<=0 or not scroll.is_visible_in_tree() or _product_tween_running(scroll):return
 if not product_contacts.get(scroll.get_instance_id(),{}).is_empty():return
 var current=float(scroll.scroll_horizontal);var rest=float(product_rest_offsets.get(scroll.get_instance_id(),0))
 var target=roundf(current/product_stride)*product_stride
 # A single wheel notch must advance, even when it moves less than half a card.
 if absf(current-rest)>1 and absf(target-rest)<1:target+=signf(current-rest)*product_stride
 var end=maxf(0,scroll.get_h_scroll_bar().max_value-scroll.get_h_scroll_bar().page)
 target=clampf(target,0,end)
 if absf(target-scroll.scroll_horizontal)>.5:_scroll_to(scroll,target)
 else:product_rest_offsets[scroll.get_instance_id()]=scroll.scroll_horizontal
func _page_products(direction:int):
 var scroll=_active_products();var current=float(scroll.get_meta("shop_scroll_target",scroll.scroll_horizontal)) if _product_tween_running(scroll) else float(scroll.scroll_horizontal)
 if product_snap_enabled and product_stride>0:
  _scroll_to(scroll,(roundf(current/product_stride)+direction*product_page_items)*product_stride)
 else:_scroll_to(scroll,current+direction*maxf(150,scroll.size.x*.8))
func _sync_scroll_buttons():
 if category_more==null:return
 var category_bar=category_scroll.get_h_scroll_bar();var end=maxf(0,category_bar.max_value-category_bar.page)
 category_back.disabled=category_scroll.scroll_horizontal<=1;category_more.disabled=category_scroll.scroll_horizontal>=end-1
 var scroll=_active_products();var bar=scroll.get_h_scroll_bar();var product_end=maxf(0,bar.max_value-bar.page)
 product_back.disabled=scroll.scroll_horizontal<=1;product_next.disabled=scroll.scroll_horizontal>=product_end-1
func _put(control:Control,rect:Rect2):
 control.custom_minimum_size=Vector2.ZERO;control.position=rect.position;control.size=rect.size
func _queue_rail_fit():
 if rail_fit_queued:return
 rail_fit_queued=true;_fit_product_rails.call_deferred()
func _fit_product_rails():
 rail_fit_queued=false
 if ui==null or not is_instance_valid(game.catalog_scroll) or product_shelf.size==Vector2.ZERO:return
 # Card minima settle after a breakpoint. Hidden rails must also shrink from
 # their old minimum before the new viewport is assessed.
 _put(game.catalog_scroll,product_shelf);_put(ui.build_scroll,product_shelf)
 # Child rows can grow after a category switch without changing the scroll's
 # own minimum. Settle the real range before restoring/paging whole cards.
 game.catalog_scroll.queue_sort();ui.build_scroll.queue_sort()
 _settle_product_rails.call_deferred()
func _settle_product_rails():
 if ui==null or not is_instance_valid(game.catalog_scroll):return
 if product_restore_index>=0:
  var scroll=_active_products();var end=maxf(0,scroll.get_h_scroll_bar().max_value-scroll.get_h_scroll_bar().page)
  scroll.scroll_horizontal=int(clampf(product_restore_index*product_stride,0,end));product_rest_offsets[scroll.get_instance_id()]=scroll.scroll_horizontal;product_restore_index=-1
 _sync_scroll_buttons();ui._sync_viewport_guard()
func browse_rect()->Rect2:
 # Measure the settled product rails, including their real assigned bounds.
 # Reserve the full browser even while selection collapses it or Play hides it,
 # so entering Decorate cannot turn a permitted window into an unusable one.
 var view=game.get_viewport().get_visible_rect().size
 var bottom_pad=8.0 if root.size.y<ViewportLayout.SHORT_SHOP_HEIGHT and view.y<360 else 12.0
 var height=maxf(game.catalog_scroll.position.y+game.catalog_scroll.size.y,ui.build_scroll.position.y+ui.build_scroll.size.y)+bottom_pad
 return Rect2(Vector2(game.tray.position.x,view.y-ui.hud.safe_bottom()-12.0-height),Vector2(root.size.x,height))
func _short_landscape_chip_width()->float:
 var width=104.0
 for category in game.category_buttons:
  var button:Button=game.category_buttons[category]
  width=maxf(width,ceilf(ui.hud.font_bold.get_string_size(button.text,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x)+45.0)
 return width
func _short_landscape_card_width()->float:
 # Fit the actual names and availability text before choosing a whole-card page.
 var width=168.0
 if game.catalog_category=="Build":
  for key in ["full","door","window"]:
   var title:Label=game.build_tools.tool_buttons[key].get_child(0).get_child(1)
   width=maxf(width,ceilf(ui.hud.font_bold.get_string_size(title.text,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x)+16.0)
 else:
  for kind in game.catalog_cards:
   var card:Button=game.catalog_cards[kind]
   if not card.visible:continue
   var title:Label=card.get_child(0).get_child(1)
   width=maxf(width,ceilf(ui.hud.font_bold.get_string_size(title.text,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x)+16.0)
   var shortfall=maxi(0,int(game.model.price_of(kind))-int(game.model.coins))
   var status="Need "+ui.Money.amount(shortfall) if shortfall>0 else ""
   if kind=="register":status="Counter + cashier" if game.model.included_checkout_pending else "Move it in the café"
   width=maxf(width,ceilf(ui.hud.font_bold.get_string_size(status,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x)+66.0)
 return width

func sync(width:float):
 var insets=ui.hud._safe_insets();var available_width=width-insets.x-insets.z;var narrow=available_width<650
 var tray_style=game.tray.get_theme_stylebox("panel");tray_style.content_margin_left=0;tray_style.content_margin_right=0;tray_style.content_margin_top=0;tray_style.content_margin_bottom=0
 var w=minf(940,available_width-20)
 var view=game.get_viewport().get_visible_rect().size;var compact=ViewportLayout.compact_shop(view)
 var selection_only=game.selected_id>=0 and game.selected_kind=="" and not game.build_tools.active()
 var h=ViewportLayout.shop_height(view,available_width)
 var short_landscape=h<ViewportLayout.SHORT_SHOP_HEIGHT
 # A single strip still reserves each real line's font height, including the
 # availability line, rather than making type smaller to meet a fixed box.
 var tight_landscape=short_landscape and view.y<360.0
 var product_vertical_padding=14.0 if tight_landscape else 20.0
 var picker_landscape=short_landscape and available_width<700.0
 if short_landscape:h=maxf(h,ceilf(ui.hud.font_bold.get_height(13)*2+maxf(24,ui.hud.font_bold.get_height(18))+12)+product_vertical_padding)
 var header_y=(h-44.0)*.5 if short_landscape else 8.0
 root.custom_minimum_size=Vector2(w,h);root.size=Vector2(w,h);background.size=root.size
 game.tray.offset_left=insets.x+(available_width-w)/2;game.tray.offset_right=-(insets.z+(available_width-w)/2);ui.tray_base_top=-h-12-insets.w
 var next_active=ui.hud.has_edit_action()
 # Selection keeps the catalogue, category and scroll position intact.
 header_active=next_active
 ui.context.visible=game.editing and header_active
 ui.cancel_button.visible=header_active
 ui.cancel_button.text="Cancel"
 ui.context_label.visible=true
 ui.floor_access.visible=game.catalog_category=="Build" and not header_active or game.build_tools.mode=="floor"
 var floor_header=ui.floor_access.visible
 var tiny=w<440
 var show_help=short_landscape or not (tiny and game.catalog_category=="Build")
 var floor_width=maxf(48,ceilf(ui.hud.font_bold.get_string_size(ui.floor_access.text,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x)+16) if picker_landscape else 66.0
 for state in ["normal","hover","pressed","hover_pressed","disabled"]:
  var style=ui.floor_access.get_theme_stylebox(state);style.content_margin_left=8 if picker_landscape else 6;style.content_margin_right=8 if picker_landscape else 6
 var tail=(52 if show_help else 0)+(floor_width+8 if game.catalog_category=="Build" else 0)
 var category_margin=16 if picker_landscape else (24 if tiny or short_landscape else 32)
 var minimum_chip=100.0 if narrow else 112.0
 var categories_overflow=short_landscape or 6*minimum_chip+30>w-category_margin*2-tail
 category_more.visible=categories_overflow and not picker_landscape;category_back.visible=categories_overflow and not picker_landscape;category_scroll.visible=not picker_landscape
 category_picker.visible=picker_landscape;category_picker.text=game.catalog_category+"   "
 if not picker_landscape or not game.editing:category_panel.hide()
 for category in category_panel_buttons:category_panel_buttons[category].set_pressed_no_signal(category==game.catalog_category)
 ui.help_access.visible=show_help
 var category_width=112.0 if picker_landscape else (_short_landscape_chip_width() if short_landscape else w-category_margin*2-tail-(104 if categories_overflow else 0))
 category_page_items=1 if short_landscape else (maxi(1,mini(5,floori((category_width+6)/(minimum_chip+6)))) if categories_overflow else 6)
 var chip_width=(category_width-6*(category_page_items-1))/category_page_items
 for category in game.category_buttons:
  var button:Button=game.category_buttons[category];button.custom_minimum_size=Vector2(chip_width,44);button.add_theme_font_size_override("font_size",13 if short_landscape else (12 if narrow else 14))
  var art:Node2D=category_icons[category];art.scale=Vector2(.36,.36) if narrow or short_landscape else Vector2(.43,.43);art.position=Vector2(7,7)
  for state in ["normal","hover","pressed","hover_pressed","disabled"]:
   var style=button.get_theme_stylebox(state);style.content_margin_left=36;style.content_margin_right=9
 var category_x=category_margin+(52 if categories_overflow and not picker_landscape else 0)
 _put(category_picker,Rect2(category_margin,header_y,112,44))
 _put(category_scroll,Rect2(category_x,header_y,category_width,44));_put(category_back,Rect2(category_margin,header_y,44,44));_put(category_more,Rect2(category_x+category_width+8,header_y,44,44))
 _put(ui.help_access,Rect2(w-category_margin-44 if short_landscape else w-76,header_y,44,44));ui.help_access.add_theme_font_size_override("font_size",20)
 var floor_parent=ui.context if floor_header and header_active else root
 if ui.floor_access.get_parent()!=floor_parent:ui.floor_access.reparent(floor_parent)
 if floor_header and header_active:ui.floor_access.custom_minimum_size=Vector2(66,44)
 if floor_header and not header_active:_put(ui.floor_access,Rect2(w-category_margin-(52 if show_help else 0)-floor_width if short_landscape else w-(150 if show_help else 98),header_y,floor_width,44))
 if last_category!=game.catalog_category or not is_equal_approx(last_layout_width,category_width):
  last_category=game.catalog_category;last_layout_width=category_width;_reveal_category.call_deferred()
 var count=0
 for card in game.catalog_cards.values():
  if card.visible:count+=1
 if game.catalog_category=="Build":count=3
 var card_w=_short_landscape_card_width() if short_landscape else (168.0 if tiny else 200.0)
 var margin=16 if picker_landscape else (24 if short_landscape else (22 if tiny else 32))
 var product_left=category_x+category_width+(12 if picker_landscape else 64) if short_landscape else float(margin)
 var product_right=w-margin-tail if short_landscape else w-margin
 var product_width=product_right-product_left
 var product_gap=_active_products().get_child(0).get_theme_constant("separation")
 var content_width=count*card_w+maxi(0,count-1)*product_gap
 var arrows=content_width>product_width
 var side=(56 if narrow or short_landscape else 48) if arrows else 0
 var shelf_width=product_width-side*2
 var next_page_items=1
 if (narrow or short_landscape) and arrows:
  # Resting mobile pages contain complete cards. Do not trade readable text
  # or the 44px arrow targets for a sliver of a neighbouring product.
  next_page_items=maxi(1,floori((shelf_width+product_gap)/((card_w if short_landscape else 168.0)+product_gap)))
  card_w=floori((shelf_width-product_gap*(next_page_items-1))/next_page_items)
  shelf_width=card_w*next_page_items+product_gap*(next_page_items-1)
 var next_key=str([game.catalog_category,narrow,short_landscape,card_w,shelf_width])
 if product_layout_key!=next_key:
  var index=roundi(_active_products().scroll_horizontal/product_stride) if product_stride>0 and last_product_category==game.catalog_category else 0
  for scroll in [game.catalog_scroll,ui.build_scroll]:_stop_product_scroll(scroll);product_contacts.erase(scroll.get_instance_id())
  product_restore_index=index;product_layout_key=next_key;last_product_category=game.catalog_category
 product_stride=card_w+product_gap;product_page_items=next_page_items;product_snap_enabled=(narrow or short_landscape) and arrows
 var card_h=h-(product_vertical_padding if short_landscape else 70.0);var image_h=minf(58,card_h-16)
 var name_h=18;var price_h=24
 for key in ["full","door","window"]:
  var card=game.build_tools.tool_buttons[key];card.custom_minimum_size=Vector2(card_w,card_h)
  var column=card.get_child(0);var selected_color=ui.hud.CREAM if card.button_pressed else ui.hud.INK
  column.get_child(1).add_theme_color_override("font_color",selected_color);column.get_child(2).get_child(1).add_theme_color_override("font_color",selected_color)
  var holder=build_previews[key].holder;var preview=build_previews[key].image
  holder.custom_minimum_size=Vector2(56,image_h)
  preview.size=Vector2(84,54);preview.scale=Vector2.ONE*minf(float(image_h)/54.0,56.0/84.0);preview.position=Vector2((56-84*preview.scale.x)/2,(image_h-54*preview.scale.y)/2);preview.queue_redraw()
  column.get_child(1).custom_minimum_size.y=name_h;column.get_child(2).custom_minimum_size.y=price_h
  column.get_child(1).add_theme_font_size_override("font_size",13);column.get_child(2).get_child(1).add_theme_font_size_override("font_size",18)
 product_back.visible=arrows;product_next.visible=arrows
 var shelf_y=(6.0 if tight_landscape else 8.0) if short_landscape else 58.0
 var shelf=Rect2(product_left+(product_width-shelf_width)*.5,shelf_y,shelf_width,card_h)
 product_shelf=shelf;_put(game.catalog_scroll,shelf);_put(ui.build_scroll,shelf)
 game.catalog_scroll.visible=game.catalog_category!="Build";ui.build_scroll.visible=game.catalog_category=="Build"
 _put(product_back,Rect2(product_left,shelf_y+(card_h-44)/2,44,44));_put(product_next,Rect2(product_right-44,shelf_y+(card_h-44)/2,44,44))
 for kind in game.catalog_cards:
  var card:Button=game.catalog_cards[kind];card.custom_minimum_size=Vector2(card_w,card_h)
  var column:Control=card.get_child(0);var holder=column.get_child(0);holder.custom_minimum_size=Vector2(56,image_h);holder.clip_contents=kind in DECOR_THUMBNAILS
  var art:Node2D=holder.get_child(0);_fit_thumbnail(kind,art,Vector2(56,image_h))
  var price_label:Label=game.catalog_prices[kind]
  column.get_child(1).custom_minimum_size.y=name_h;column.get_child(2).custom_minimum_size.y=price_h;column.get_child(3).custom_minimum_size.y=16
  column.get_child(1).add_theme_font_size_override("font_size",13);price_label.add_theme_font_size_override("font_size",18)
  card.set_pressed_no_signal(game.selected_kind==kind)
  for label in [column.get_child(1),price_label]:label.add_theme_color_override("font_color",ui.hud.CREAM if card.button_pressed else ui.hud.INK)
  var shortfall=maxi(0,int(game.model.price_of(kind))-int(game.model.coins))
  affordability_labels[kind].add_theme_font_size_override("font_size",13 if short_landscape else 11)
  affordability_labels[kind].text="Need "+ui.Money.amount(shortfall) if shortfall>0 else ""
  affordability_labels[kind].add_theme_color_override("font_color",ui.hud.CREAM if card.button_pressed else Color("93482e"))
  if shortfall>0:price_label.add_theme_color_override("font_color",ui.hud.CREAM if card.button_pressed else Color("93482e"))
  card.accessibility_description=("Need "+ui.Money.amount(shortfall)+" more coins. Preview available; purchase is blocked.") if shortfall>0 else "Available to place"
  card.tooltip_text=column.get_child(1).text+" · "+ui.Money.amount(game.model.price_of(kind))+" coins"+(" · need "+ui.Money.amount(shortfall)+" more; preview only" if shortfall>0 else "")
  if kind=="register":
   var pending=bool(game.model.included_checkout_pending)
   price_icons[kind].hide();price_label.text="Included" if pending else "Placed"
   price_label.add_theme_font_size_override("font_size",17)
   card.disabled=not pending or game.save_recovery_blocked
   affordability_labels[kind].text="Counter + cashier" if pending else "Move it in the café"
   affordability_labels[kind].add_theme_color_override("font_color",ui.hud.CREAM if card.button_pressed else ui.hud.INK)
   card.accessibility_name="Place included checkout counter" if pending else "Checkout counter already placed"
   card.accessibility_description="One included checkout counter and cashier, no purchase fee" if pending else "Drag the checkout counter in the café to move it"
   card.tooltip_text=card.accessibility_description
 for kind in game.catalog_cards:
  var card=game.catalog_cards[kind];_layout_product_card(card,card_w,card_h,short_landscape)
  var holder=card.get_child(0).get_child(0);_fit_thumbnail(kind,holder.get_child(0),holder.size)
 for key in ["full","door","window"]:
  _layout_product_card(game.build_tools.tool_buttons[key],card_w,card_h,short_landscape)
  var holder=build_previews[key].holder;var preview=build_previews[key].image
  preview.scale=Vector2.ONE*minf(holder.size.x/84.0,holder.size.y/54.0)
  preview.position=(holder.size-Vector2(84,54)*preview.scale)*.5
 for action in [ui.rotate_button,ui.move_button,ui.finish_button,ui.remove_button,ui.upgrade_button]:
  for state in ["normal","hover","pressed","hover_pressed","disabled"]:
   var style=action.get_theme_stylebox(state);style.content_margin_left=8 if narrow else 12;style.content_margin_right=8 if narrow else 12
 _put(ui.context,Rect2(32,header_y,w-64,44));ui.context_label.add_theme_font_size_override("font_size",14 if narrow else 16)
 if game.build_tools.mode in ["door","window"]:
  ui.context_label.text=str(game.build_tools.mode).capitalize()+" · "+ui.Money.amount(game.model.attachment_price(game.build_tools.mode))
 elif game.build_tools.mode=="move_opening":ui.context_label.text="Move opening"
 ui.context_label.tooltip_text=ui.context_label.text
 _layout_action_board(w)
 _position_category_panel()
 footer_hint.hide()
 if ui.wall_quote_label.visible:sync_quote()
 _layout_context()
 _sync_scroll_buttons.call_deferred();_queue_rail_fit();ui._set_tray_reveal(ui.tray_reveal)
