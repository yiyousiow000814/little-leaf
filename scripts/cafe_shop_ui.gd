extends RefCounted
## A fixed-height horizontal shop: category rail above a scrollable product rail.
## Existing real catalog keys, callbacks, prices and atomic dining products stay intact.
const Illustration=preload("res://scripts/illustrated_cafe.gd")
const ThumbnailAtlas=preload("res://scripts/furniture_static_atlas.gd")
const ViewportLayout=preload("res://scripts/cafe_viewport_layout.gd")
const GroundArt=preload("res://scripts/illustrated_ground.gd")
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
var build_cards={}
var tile_cards={}
var wall_cards={}
var wall_styles={}
var wall_target=""
var tiles_heading_icon:Control
var walls_heading_icon:Control
var tiles_card:Button
var tiles_back:Button
var tiles_title:Label
var tiles_heading:Control
var build_page="products"
# Presentation only. No model, service, ownership or save state is changed.
var hide_objects=false
var hide_objects_button:Button
var action_copy:HBoxContainer
var price_label:Label
var action_layout_key:Array=[]

var parking_card:Button
var parking_price:Label
var parking_status:Label
var parking_coin:TextureRect
var parking_preview:Control
var parking_review:PanelContainer
var parking_review_text:Label
var parking_sell:Button
var parking_cancel:Button

class ParkingIcon extends Control:
 func _draw():
  # Four marked bays, using the same compact 84 x 54 art slot as Build.
  var a=Vector2(5,18);var b=Vector2(58,4);var c=Vector2(79,35);var d=Vector2(26,49)
  draw_colored_polygon(PackedVector2Array([a+Vector2(0,3),b+Vector2(0,3),c+Vector2(0,3),d+Vector2(0,3)]),Color("65736a"))
  draw_colored_polygon(PackedVector2Array([a,b,c,d]),Color("98a395"))
  draw_polyline(PackedVector2Array([a,b,c,d,a]),Color("5f7164"),1.3,true)
  var left=a.lerp(d,.2);var right=b.lerp(c,.2)
  var bottom_left=a.lerp(d,.84);var bottom_right=b.lerp(c,.84)
  draw_line(left,right,Color("f5eed8"),1.8,true)
  for bay in 5:
   var t=float(bay)/4
   draw_line(left.lerp(right,t),bottom_left.lerp(bottom_right,t),Color("f5eed8"),1.8,true)

class TileIcon extends Control:
 var style="warm_oak"
 var collection=false
 func _draw():
  var styles=["warm_oak","cream_tile","sage_tile"] if collection else [style]
  for index in styles.size():
   var shift=Vector2((index-1)*15,abs(index-1)*5) if collection else Vector2.ZERO
   var center=Vector2(42,26)+shift
   var span=Vector2(19,9.5) if collection else Vector2(31,15.5)
   var corners=PackedVector2Array([center-Vector2(0,span.y),center+Vector2(span.x,0),center+Vector2(0,span.y),center-Vector2(span.x,0)])
   draw_colored_polygon(corners,GroundArt.floor_palette(styles[index])[0])
   var outline=corners.duplicate();outline.append(corners[0]);draw_polyline(outline,GroundArt.floor_line(styles[index]),1.2,true)
   if styles[index]=="warm_oak":
    draw_line(center+Vector2(-span.x*.5,0),center+Vector2(0,span.y*.5),GroundArt.floor_line(styles[index]),1,true)

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
 game.catalog_scroll.reparent(root);ui.build_scroll.reparent(root);ui.context.reparent(root)
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
  var card:Button=game.build_tools.tool_buttons[key];build_cards[key]=card;_style(card);card.custom_minimum_size=Vector2(148,140)
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
 for button in [ui.rotate_button,ui.move_button,ui.finish_button,ui.remove_button,ui.upgrade_button,ui.cancel_button]:_style(button)
 footer_hint=ui.hud._label(root,"",13);footer_hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_LEFT
 ui.context_label.clip_text=true;ui.context_label.custom_minimum_size.x=0;ui.context_label.size_flags_horizontal=Control.SIZE_SHRINK_CENTER;ui.context_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_LEFT
 ui.context_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;ui.context_label.add_theme_font_override("font",ui.hud.font_bold);ui.context_label.add_theme_color_override("font_color",ui.hud.INK)
 for button in [ui.rotate_button,ui.move_button,ui.finish_button,ui.remove_button,ui.upgrade_button,ui.cancel_button]:button.custom_minimum_size.y=44
 for card in game.catalog_cards.values():_flatten_card(card)
 for key in ["full","door","window"]:_flatten_card(game.build_tools.tool_buttons[key])
 _setup_tiles()
 _setup_walls()
 _setup_parking()
 action_copy=HBoxContainer.new();action_copy.mouse_filter=Control.MOUSE_FILTER_IGNORE;action_copy.add_theme_constant_override("separation",8);ui.context.add_child(action_copy)
 ui.context_label.reparent(action_copy);ui.context_label.clip_text=false;ui.context_label.autowrap_mode=TextServer.AUTOWRAP_OFF;ui.context_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 price_label=ui.hud._label(action_copy,"",12);price_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_LEFT;price_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;price_label.clip_text=false;price_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
 ui.floor_repair_button.reparent(root);_style(ui.floor_repair_button)

 root.resized.connect(func():background.size=root.size)
 game.get_window().focus_exited.connect(_cancel_product_contacts)
 game.tree_exiting.connect(_dispose_product_scroll)
func _setup_parking():
 # This fixed exterior upgrade deliberately stays outside the furniture
 # catalog: it can never start a placement preview or become a movable item.
 parking_card=ui._small_button("",_choose_parking);parking_card.name="ParkingUpgradeCard";_style(parking_card)
 parking_card.mouse_filter=Control.MOUSE_FILTER_PASS;game.catalog_scroll.get_child(0).add_child(parking_card)
 var body=Control.new();body.mouse_filter=Control.MOUSE_FILTER_IGNORE;parking_card.add_child(body);parking_card.move_child(body,0)
 body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);body.offset_left=8;body.offset_top=4;body.offset_right=-8;body.offset_bottom=-4
 var holder=Control.new();holder.mouse_filter=Control.MOUSE_FILTER_IGNORE;body.add_child(holder)
 parking_preview=ParkingIcon.new();parking_preview.mouse_filter=Control.MOUSE_FILTER_IGNORE;parking_preview.size=Vector2(84,54);holder.add_child(parking_preview)
 var title=ui.hud._label(body,"Parking · 4 bays",13);title.add_theme_font_override("font",ui.hud.font_bold)
 var price_row=HBoxContainer.new();price_row.alignment=BoxContainer.ALIGNMENT_CENTER;price_row.add_theme_constant_override("separation",5);price_row.mouse_filter=Control.MOUSE_FILTER_IGNORE;body.add_child(price_row)
 parking_coin=ui.hud._picture(price_row,ui.hud._texture("coin"));parking_coin.custom_minimum_size=Vector2(21,21);parking_coin.size_flags_vertical=Control.SIZE_SHRINK_CENTER
 parking_price=ui.hud._label(price_row,"",18);parking_price.clip_text=false;parking_price.size_flags_vertical=Control.SIZE_SHRINK_CENTER;parking_price.add_theme_font_override("font",ui.hud.font_bold)
 parking_status=ui.hud._label(body,"",11);parking_status.custom_minimum_size.y=16
 parking_review=ui._panel();parking_review.name="ParkingSaleReview"
 var box=VBoxContainer.new();box.add_theme_constant_override("separation",12);parking_review.add_child(box)
 box.add_child(game.label("Parking · 4 bays",20))
 parking_review_text=game.label("",15);parking_review_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;parking_review_text.custom_minimum_size=Vector2(250,0);box.add_child(parking_review_text)
 var actions=BoxContainer.new();box.add_child(actions);ui.popup_action_rows.append(actions)
 parking_sell=ui._small_button("Sell parking",_sell_parking,140);actions.add_child(parking_sell)
 parking_cancel=ui._small_button("Cancel",func():parking_review.hide();ui.sync(),80);actions.add_child(parking_cancel)
func _parking_action_allowed()->bool:
 return game.editing and game.catalog_category=="Decor" and not game.save_recovery_blocked and not ui.viewport_too_small
func _choose_parking():
 if not _parking_action_allowed() or ui.has_open_popup():return
 game._cancel_selection()
 if game.model.parking_owned:
  ui._popup_at(parking_review,320);_sync_parking_review();ui.sync();return
 if game.model.buy_parking():game._update_ui();game._save()
 else:ui.sync()
func _sell_parking():
 if not parking_review.visible or not _parking_action_allowed() or not game.model.parking_owned or not game.model.parking_visits.is_empty():return
 if game.model.sell_parking():
  parking_review.hide();game._cancel_selection();game._update_ui();game._save()
 else:_sync_parking_review();ui.sync()
func _sync_parking_review():
 if not parking_review.visible:return
 if not game.editing or game.catalog_category!="Decor" or not game.model.parking_owned:parking_review.hide();return
 var occupied=game.model.parking_visits.size();var refund=int(game.model.parking_refund())
 var reason="Wait until all cars have left before selling." if occupied>0 else "Sell this fixed upgrade for %s coins."%ui.Money.amount(refund)
 if game.save_recovery_blocked:reason="Resolve save recovery before selling."
 parking_review_text.text="Owned · 4 bays\n%d of 4 bays reserved or occupied.\n\n%s"%[occupied,reason]
 if occupied==0 and not game.save_recovery_blocked:
  parking_review_text.text+="\nFull purchase refund this Decorate session." if refund==int(game.model.parking_paid_cost) else "\nHalf of the amount originally paid."
 parking_sell.text="Sell +"+ui.Money.amount(refund)
 parking_sell.disabled=occupied>0 or game.save_recovery_blocked or ui.viewport_too_small
 parking_sell.tooltip_text=reason;parking_sell.accessibility_description=reason
func _sync_parking_card():
 parking_card.visible=game.catalog_category=="Decor"
 var owned=bool(game.model.parking_owned);var occupied=game.model.parking_visits.size()
 var shortfall=maxi(0,int(game.model.parking_price())-int(game.model.coins))
 parking_price.text="Owned" if owned else ui.Money.amount(game.model.parking_price());parking_coin.visible=not owned
 parking_status.text="%d/4 in use"%occupied if owned else ("Need "+ui.Money.amount(shortfall) if shortfall>0 else "Fixed upgrade")
 parking_card.disabled=game.save_recovery_blocked or (not owned and shortfall>0)
 if game.save_recovery_blocked:parking_status.text="Save recovery"
 parking_price.add_theme_color_override("font_color",Color("93482e") if shortfall>0 and not owned else ui.hud.INK)
 parking_status.add_theme_color_override("font_color",Color("93482e") if parking_card.disabled else ui.hud.INK)
 var detail="Owned parking, four fixed bays. %d bays reserved or occupied. "%occupied if owned else "Buy four fixed parking bays for %s coins. No placement needed. "%ui.Money.amount(game.model.parking_price())
 detail+=("Wait until all cars have left before selling." if occupied>0 else "Click to review selling for %s coins."%ui.Money.amount(game.model.parking_refund())) if owned else ("Need %s more coins."%ui.Money.amount(shortfall) if shortfall>0 else "Click to buy.")
 if game.save_recovery_blocked:detail="Resolve save recovery before changing parking."
 parking_card.accessibility_name="Owned parking, four bays" if owned else "Buy parking, four bays"
 parking_card.accessibility_description=detail;parking_card.tooltip_text=detail
 _sync_parking_review()
func _layout_parking_card(width:float,height:float,short_landscape:bool):
 parking_card.custom_minimum_size=Vector2(width,height);parking_status.add_theme_font_size_override("font_size",13 if short_landscape else 11)
 _layout_product_card(parking_card,width,height,short_landscape)
 var holder=parking_preview.get_parent();parking_preview.scale=Vector2.ONE*minf(holder.size.x/84.0,holder.size.y/54.0)
 parking_preview.position=(holder.size-Vector2(84,54)*parking_preview.scale)*.5
func _setup_tiles():
 tiles_card=_make_tile_card("tiles","Tiles",str(game.build_tools.FLOOR_STYLES.size())+" styles","warm_oak",show_tiles,true)
 for index in game.build_tools.FLOOR_STYLES.size():
  var style=game.build_tools.FLOOR_STYLES[index]
  tile_cards[style]=_make_tile_card(style,game.build_tools.FLOOR_NAMES[index],ui.Money.amount(game.model.floor_price(style)),style,choose_floor_style.bind(style))
 tiles_back=_nav("Build",show_build_products);tiles_back.accessibility_name="Back to Build from Tiles";tiles_back.add_theme_font_size_override("font_size",14);tiles_back.draw.connect(_draw_tiles_back);tiles_back.hide()
 tiles_heading=Control.new();tiles_heading.mouse_filter=Control.MOUSE_FILTER_IGNORE;root.add_child(tiles_heading);tiles_heading.hide()
 var face=Panel.new();face.mouse_filter=Control.MOUSE_FILTER_IGNORE;face.add_theme_stylebox_override("panel",ui.hud.texture_style("green_face",14));face.material=ui.hud._art_material(2);tiles_heading.add_child(face);face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 var tile=TileIcon.new();tile.style="cream_tile";tile.mouse_filter=Control.MOUSE_FILTER_IGNORE;tile.size=Vector2(84,54);tile.scale=Vector2.ONE*.38;tile.position=Vector2(5,12);tiles_heading.add_child(tile);tiles_heading_icon=tile
 walls_heading_icon=game.build_tools.WallIcon.new();walls_heading_icon.mouse_filter=Control.MOUSE_FILTER_IGNORE;walls_heading_icon.size=Vector2(84,54);walls_heading_icon.scale=Vector2.ONE*.38;walls_heading_icon.position=Vector2(5,10);tiles_heading.add_child(walls_heading_icon);walls_heading_icon.hide()
 tiles_title=ui.hud._label(tiles_heading,"Tiles",16,ui.hud.CREAM);tiles_title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;tiles_title.clip_text=false
 hide_objects_button=_nav("Hide objects",toggle_objects);hide_objects_button.name="HideObjects";hide_objects_button.toggle_mode=true;hide_objects_button.hide()
 hide_objects_button.accessibility_description="Temporarily hide café furniture, rugs, walls, doors and windows to inspect the floor. Ground, outdoor scenery and plot boundaries stay visible. Hidden objects cannot be selected."
 hide_objects_button.tooltip_text=hide_objects_button.accessibility_description
 _sync_build_page()
func _draw_tiles_back():
 # Pair the chevron with the native 14px caption. Raster bounds place their
 # combined ink on the button center; the caption ink sits 1px above mid-height.
 var center=Vector2(tiles_back.size.x*.5-23,tiles_back.size.y*.5-1)
 var ink=ui.hud.CREAM if tiles_back.is_pressed() else ui.hud.INK
 tiles_back.draw_polyline(PackedVector2Array([center+Vector2(3,-5),center-Vector2(2,0),center+Vector2(3,5)]),ink,1.8,true)
func _make_tile_card(key:String,title:String,price:String,style:String,callback:Callable,collection=false)->Button:
 var card=ui._small_button("",callback);_style(card);card.toggle_mode=not collection;game.build_panel.add_child(card);build_cards[key]=card
 var body=Control.new();body.mouse_filter=Control.MOUSE_FILTER_IGNORE;card.add_child(body);card.move_child(body,0);body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 body.offset_left=8;body.offset_top=4;body.offset_right=-8;body.offset_bottom=-4
 var holder=Control.new();holder.mouse_filter=Control.MOUSE_FILTER_IGNORE;body.add_child(holder)
 var preview=TileIcon.new();preview.style=style;preview.collection=collection;preview.mouse_filter=Control.MOUSE_FILTER_IGNORE;holder.add_child(preview);build_previews[key]={"holder":holder,"image":preview}
 var name_label=ui.hud._label(body,title,13);name_label.add_theme_font_override("font",ui.hud.font_bold)
 var price_row=HBoxContainer.new();price_row.alignment=BoxContainer.ALIGNMENT_BEGIN;price_row.add_theme_constant_override("separation",5);price_row.mouse_filter=Control.MOUSE_FILTER_IGNORE;body.add_child(price_row)
 var coin=ui.hud._picture(price_row,ui.hud._texture("coin"));coin.custom_minimum_size=Vector2(21,21);coin.size_flags_vertical=Control.SIZE_SHRINK_CENTER;coin.visible=not collection
 var cost=ui.hud._label(price_row,price,18);cost.clip_text=false;cost.size_flags_vertical=Control.SIZE_SHRINK_CENTER
 var status=ui.hud._label(body,"Choose a style" if collection else "per tile",11);status.horizontal_alignment=HORIZONTAL_ALIGNMENT_LEFT
 card.tooltip_text="Browse tile styles" if collection else title+" · "+price+" coins per tile"
 card.accessibility_name="Browse Tiles" if collection else title+", "+price+" coins per tile"
 return card
func _setup_walls():
 # Walls browse in the same bottom rail as Tiles. Every card is a complete
 # height/finish product; picking it starts placement without a modal form.
 for height in ["full","half"]:
  for index in range(game.build_tools.MATERIAL_NAMES.size()+1):
   var material=game.build_tools.Geometry.MATERIALS[index] if index<game.build_tools.MATERIAL_NAMES.size() else "original"
   var title=game.build_tools.MATERIAL_NAMES[index] if material!="original" else "Original room"
   var key="wall:"+height+":"+material
   var card=_make_tile_card(key,title,ui.Money.amount(game.model.wall_price(height)),"cream_tile",choose_wall_style.bind(height,material))
   var holder=build_previews[key].holder;var old=build_previews[key].image;holder.remove_child(old);old.queue_free()
   var preview=game.build_tools.WallIcon.new();preview.height=height;preview.wall_material=material if material!="original" else "sage_panels";preview.mouse_filter=Control.MOUSE_FILTER_IGNORE;holder.add_child(preview)
   build_previews[key].image=preview;wall_cards[key]=card;wall_styles[key]={"height":height,"material":material}
   var height_name="Full wall" if height=="full" else "Half wall"
   card.get_child(0).get_child(3).text=height_name
   card.tooltip_text=title+" · "+height_name+" · "+ui.Money.amount(game.model.wall_price(height))+" coins per tile"
   card.accessibility_name=card.tooltip_text
 _sync_build_page()
func _sync_build_page():
 for key in build_cards:
  if build_page=="tiles":build_cards[key].visible=key in tile_cards
  elif build_page=="walls":build_cards[key].visible=key in wall_cards and (wall_styles[key].material!="original" or not game.model.ShellSegments.parse_key(wall_target).is_empty())
  else:build_cards[key].visible=key not in tile_cards and key not in wall_cards
 if is_instance_valid(tiles_title):tiles_title.text="Wall" if build_page=="walls" else "Tiles"
 if is_instance_valid(tiles_heading_icon):tiles_heading_icon.visible=build_page!="walls"
 if is_instance_valid(walls_heading_icon):walls_heading_icon.visible=build_page=="walls"
 if is_instance_valid(tiles_back):tiles_back.accessibility_name="Back to Build from "+("Wall" if build_page=="walls" else "Tiles")
func show_walls(target:String=""):
 if not game.editing or game.catalog_category!="Build" or game.save_recovery_blocked or ui.viewport_too_small:return
 game.settings.hide();game._cancel_selection();ui._hide_popups();wall_target=target;build_page="walls";product_layout_key="";_sync_build_page();ui.build_scroll.scroll_horizontal=0;ui.sync()
func choose_wall_style(height:String,material:String):
 var key="wall:"+height+":"+material
 if not game.editing or game.catalog_category!="Build" or build_page!="walls" or game.save_recovery_blocked or ui.viewport_too_small or not wall_cards.has(key) or not wall_cards[key].visible:return
 game.build_tools.material=material;game.build_tools.choose(height);ui.sync();ui.update_pointer()
func tiles_active()->bool:
 return game.editing and game.catalog_category=="Build" and build_page=="tiles"
func objects_hidden()->bool:
 return tiles_active() and hide_objects
func reset_inspection():
 if not hide_objects:return
 hide_objects=false
 if is_instance_valid(hide_objects_button):hide_objects_button.set_pressed_no_signal(false)
 if is_instance_valid(game.illustration):game.illustration.queue_redraw()
func toggle_objects():
 if not tiles_active() or game.save_recovery_blocked or ui.viewport_too_small:return
 var next=not hide_objects
 # Clear any selected furnishing/wall or in-flight click, but retain the chosen
 # floor tool so the player can compare and place flooring with objects hidden.
 if game.build_tools.mode!="floor":game._cancel_selection()
 else:
  game.build_tools.on_focus_lost()
  game.interaction.cancel(false)
 hide_objects=next;ui.sync();game.illustration.queue_redraw()
func show_tiles():
 if not game.editing or game.catalog_category!="Build" or game.save_recovery_blocked or ui.viewport_too_small:return
 game._cancel_selection();ui._hide_popups();build_page="tiles";product_layout_key="";_sync_build_page();ui.build_scroll.scroll_horizontal=0;ui.sync()
func show_build_products():
 game._cancel_selection();wall_target="";build_page="products";product_layout_key="";_sync_build_page();ui.build_scroll.scroll_horizontal=0;ui.sync()
func choose_floor_style(style:String):
 if not game.editing or game.catalog_category!="Build" or build_page!="tiles" or game.save_recovery_blocked or ui.viewport_too_small or style not in tile_cards:return
 var keep_hidden=objects_hidden()
 game.build_tools.floor_material=style;game.build_tools.choose("floor");hide_objects=keep_hidden;ui.sync();ui.update_pointer()
func _visible_build_keys()->Array:
 var keys=[]
 for key in build_cards:
  if build_cards[key].visible:keys.append(key)
 return keys

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
 var body_width=width-16.0;var body_height=height-8.0
 var art_width=44.0 if tiny else 56.0;var text_x=art_width+6;var text_width=body_width-text_x
 var title:Label=body.get_child(1);title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;title.clip_text=false
 title.autowrap_mode=TextServer.AUTOWRAP_OFF if tiny else TextServer.AUTOWRAP_WORD_SMART
 var title_width=body_width if tiny else text_width
 _put(title,Rect2(0 if tiny else text_x,0,title_width,0))
 var title_height=title.get_combined_minimum_size().y
 var price=body.get_child(2);price.alignment=BoxContainer.ALIGNMENT_CENTER
 var price_height=maxf(24,price.get_combined_minimum_size().y)
 var status:Label=body.get_child(3);status.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
 var has_status=status.text!="";status.visible=has_status;var status_height=maxf(16,status.get_combined_minimum_size().y) if has_status else 0.0
 var copy_height=title_height+2+price_height+(2+status_height if has_status else 0)
 if tiny:
  var row_height=maxf(42,price_height+(2+status_height if has_status else 0))
  var block_height=title_height+4+row_height
  var top=maxf(0,(body_height-block_height)*.5)
  _put(title,Rect2(0,top,body_width,title_height))
  var row_y=top+title_height+4;var price_block=price_height+(2+status_height if has_status else 0)
  var price_y=row_y+(row_height-price_block)*.5
  _put(price,Rect2(text_x,price_y,text_width,price_height))
  _put(status,Rect2(text_x,price_y+price_height+2,text_width,status_height))
  _put(image,Rect2(0,row_y,art_width,row_height))
 else:
  var top=maxf(0,(body_height-copy_height)*.5)
  _put(title,Rect2(text_x,top,text_width,title_height))
  _put(price,Rect2(text_x,top+title_height+2,text_width,price_height))
  _put(status,Rect2(text_x,top+title_height+price_height+4,text_width,status_height))
  var image_height=minf(58,body_height)
  _put(image,Rect2(0,(body_height-image_height)*.5,art_width,image_height))
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
func sync_action_details():
 if ui==null or not is_instance_valid(price_label):return
 ui.context.visible=game.editing and ui.hud.has_edit_action();ui.cancel_button.visible=ui.context.visible
 var b=game.build_tools;var price="";var detail=""
 # Both periodic UI sync and pointer refresh consume this same presentation.
 # Price never replaces the product title, and label visibility is not state.
 if b.active():
  if b.mode in ["half","full","floor"]:
   ui.context_label.text=b.floor_name() if b.mode=="floor" else ("Half wall" if b.mode=="half" else "Full wall")
   var quote=b.floor_quote if b.mode=="floor" else (b.replacement_quote if b.replacing else {})
   var unit_cost=game.model.floor_price(b.floor_material) if b.mode=="floor" else game.model.wall_price(b.mode)
   price=ui.Money.amount(unit_cost)+" / tile"
   if not quote.is_empty():
    if int(quote.get("new_cost",-1))==0 and int(quote.get("net",-1))==0:price="No charge"
    elif bool(quote.get("valid",false)):price="Pay "+ui.Money.amount(int(quote.net))
    elif str(quote.get("reason","")).begins_with("Not enough coins"):price="Need "+ui.Money.amount(maxi(0,int(quote.net)-game.model.coins))
    detail="New %s · refund %s · pay %s"%[ui.Money.amount(int(quote.new_cost)),ui.Money.amount(int(quote.refund)),ui.Money.amount(int(quote.net))]
    if quote.has("units"):detail+=" · %d tiles"%int(quote.units)
   if b.preview_reason!="":detail+=("\n" if detail!="" else "")+b.preview_reason
  elif b.mode in ["door","window"]:
   ui.context_label.text=b.mode.capitalize();price=ui.Money.amount(game.model.attachment_price(b.mode))+" coins"
  elif b.mode=="move_wall":
   ui.context_label.text="Moving wall · choose an edge";price="No charge";detail=b.preview_reason
  elif b.mode=="move_opening":
   var opening=ui._selected_opening()
   ui.context_label.text="Moving "+str(opening.get("kind","opening"))+" · choose a wall"
 price_label.text=price;price_label.visible=price!="";price_label.tooltip_text=detail
 ui.context_label.tooltip_text=ui.context_label.text+(" · "+price if price!="" else "")+("\n"+detail if detail!="" else "")
 action_background.tooltip_text=ui.context_label.tooltip_text
 _layout_action_board(root.size.x)

func _layout_action_board(width:float):
 action_background.visible=ui.context.visible
 if not ui.context.visible:return
 var actions=[];var used=0.0;var gap=6.0
 # Keep the per-pointer guard typed: stringifying nested button state did
 # allocations and numeric formatting on every unchanged decorating frame.
 var signature=[width,ui.context_label.text,price_label.text,ui.context_label.get_theme_font_size("font_size"),price_label.get_theme_font_size("font_size")]
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
  var minimum=child.get_combined_minimum_size()
  actions.append(child);used+=minimum.x
  signature.append(child.get_instance_id());signature.append(child.text);signature.append(minimum)
 if signature==action_layout_key:return
 action_layout_key=signature
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
  for key in _visible_build_keys():
   var title:Label=build_cards[key].get_child(0).get_child(1)
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
  if parking_card.visible:
   width=maxf(width,ceilf(ui.hud.font_bold.get_string_size("Parking · 4 bays",HORIZONTAL_ALIGNMENT_LEFT,-1,13).x)+16.0)
   width=maxf(width,ceilf(ui.hud.font_bold.get_string_size(parking_status.text,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x)+66.0)
 return width

func sync(width:float):
 if not tiles_active():reset_inspection()
 if game.catalog_category!="Build" and build_page!="products":build_page="products";_sync_build_page()
 _sync_parking_card()
 ui._sync_starter_floor_repair()
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
 var nested=game.catalog_category=="Build" and build_page in ["tiles","walls"]
 var tiny=w<440
 var repair_width=(100.0 if tiny else 110.0) if ui.floor_repair_button.visible else 0.0
 var tail=repair_width+8 if repair_width>0 else 0.0
 var category_margin=16 if picker_landscape else (24 if tiny or short_landscape else 32)
 var minimum_chip=100.0 if narrow else 112.0
 var categories_overflow=short_landscape or 6*minimum_chip+30>w-category_margin*2-tail
 category_more.visible=categories_overflow and not picker_landscape;category_back.visible=categories_overflow and not picker_landscape;category_scroll.visible=not picker_landscape
 category_picker.visible=picker_landscape;category_picker.text=game.catalog_category+"   "
 if not picker_landscape or not game.editing:category_panel.hide()
 for category in category_panel_buttons:category_panel_buttons[category].set_pressed_no_signal(category==game.catalog_category)
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
 tiles_back.visible=nested;tiles_heading.visible=nested
 if nested:
  category_scroll.hide();category_back.hide();category_more.hide();category_picker.hide();category_panel.hide()
 for state in ["normal","hover","pressed","hover_pressed","disabled"]:
  var style=tiles_back.get_theme_stylebox(state);style.content_margin_left=30;style.content_margin_right=10
 var back_width=80.0 if tiny and tiles_active() and repair_width>0 else 104.0
 _put(tiles_back,Rect2(category_margin,header_y,back_width,44))
 var heading_x=category_margin+back_width+8;var heading_width=76.0 if tiny and repair_width>0 else 112.0
 tiles_heading.visible=nested and (w-category_margin-tail-(heading_x+heading_width+12)>=210 if short_landscape else heading_x+heading_width+8<=w-category_margin-tail)
 var stacked_inspection=tiles_active() and short_landscape and not tiles_heading.visible
 _put(tiles_heading,Rect2(heading_x,header_y,heading_width,44));_put(tiles_title,Rect2(35,0,heading_width-43,44))
 hide_objects_button.visible=tiles_active()
 hide_objects_button.text=("Show\nobjects" if hide_objects else "Hide\nobjects") if heading_width<100 else ("Show objects" if hide_objects else "Hide objects")
 hide_objects_button.accessibility_name="Show café objects" if hide_objects else "Hide café objects"
 hide_objects_button.set_pressed_no_signal(hide_objects)
 hide_objects_button.disabled=game.save_recovery_blocked or ui.viewport_too_small
 _put(hide_objects_button,Rect2(heading_x,header_y,heading_width,44))
 if stacked_inspection:
  _put(tiles_back,Rect2(category_margin,(h-88)*.5,back_width,44))
  _put(hide_objects_button,Rect2(category_margin,h*.5,back_width,44))
 if tiles_active():tiles_heading.hide()
 _put(ui.floor_repair_button,Rect2(w-category_margin-repair_width,header_y,repair_width,44))
 if last_category!=game.catalog_category or not is_equal_approx(last_layout_width,category_width):
  last_category=game.catalog_category;last_layout_width=category_width;_reveal_category.call_deferred()
 var count=0
 for card in game.catalog_cards.values():
  if card.visible:count+=1
 if parking_card.visible:count+=1
 if game.catalog_category=="Build":count=_visible_build_keys().size()
 var card_w=_short_landscape_card_width() if short_landscape else (168.0 if tiny else 200.0)
 var margin=16 if picker_landscape else (24 if short_landscape else (22 if tiny else 32))
 var product_left=category_x+category_width+(12 if picker_landscape else 64) if short_landscape else float(margin)
 if nested and short_landscape:product_left=heading_x+heading_width+12 if tiles_heading.visible or (hide_objects_button.visible and not stacked_inspection) else category_margin+back_width+12
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
 var next_key=str([game.catalog_category,build_page,narrow,short_landscape,card_w,shelf_width])
 if product_layout_key!=next_key:
  var index=roundi(_active_products().scroll_horizontal/product_stride) if product_stride>0 and last_product_category==game.catalog_category else 0
  for scroll in [game.catalog_scroll,ui.build_scroll]:_stop_product_scroll(scroll);product_contacts.erase(scroll.get_instance_id())
  product_restore_index=index;product_layout_key=next_key;last_product_category=game.catalog_category
 product_stride=card_w+product_gap;product_page_items=next_page_items;product_snap_enabled=(narrow or short_landscape) and arrows
 var card_h=h-(product_vertical_padding if short_landscape else 70.0);var image_h=minf(58,card_h-16)
 var name_h=18;var price_h=24
 for key in _visible_build_keys():
  var card=build_cards[key];card.custom_minimum_size=Vector2(card_w,card_h)
  if key in tile_cards:card.set_pressed_no_signal(game.build_tools.mode=="floor" and game.build_tools.floor_material==key)
  elif key in wall_cards:card.set_pressed_no_signal(game.build_tools.mode==wall_styles[key].height and game.build_tools.material==wall_styles[key].material)
  var column=card.get_child(0);var selected_color=ui.hud.CREAM if card.button_pressed else ui.hud.INK
  column.get_child(1).add_theme_color_override("font_color",selected_color);column.get_child(2).get_child(1).add_theme_color_override("font_color",selected_color);column.get_child(3).add_theme_color_override("font_color",selected_color)
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
  card.accessibility_name=column.get_child(1).text+", "+ui.Money.amount(game.model.price_of(kind))+" coins"
  card.accessibility_description=("Need "+ui.Money.amount(shortfall)+" more coins. Preview available; purchase is blocked.") if shortfall>0 else "Available to place"
  card.tooltip_text=("Need "+ui.Money.amount(shortfall)+" more coins; preview only") if shortfall>0 else ""
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
 _layout_parking_card(card_w,card_h,short_landscape)
 for key in _visible_build_keys():
  _layout_product_card(build_cards[key],card_w,card_h,short_landscape)
  var holder=build_previews[key].holder;var preview=build_previews[key].image
  preview.scale=Vector2.ONE*minf(holder.size.x/84.0,holder.size.y/54.0)
  preview.position=(holder.size-Vector2(84,54)*preview.scale)*.5
 ui.context_label.add_theme_font_size_override("font_size",14 if narrow else 16)
 sync_action_details()
 _position_category_panel()
 footer_hint.hide()
 _sync_scroll_buttons.call_deferred();_queue_rail_fit();ui._set_tray_reveal(ui.tray_reveal)
