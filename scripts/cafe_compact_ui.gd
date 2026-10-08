extends RefCounted
## Presentation only: compact catalog, selection actions, optional details.
const WorkfaceGuidance=preload("res://scripts/cafe_workface_guidance.gd")
const Money=preload("res://scripts/cafe_money.gd")
const StaffPanel=preload("res://scripts/cafe_staff_panel.gd")
const Hud=preload("res://scripts/cafe_hud.gd")
const ShopUI=preload("res://scripts/cafe_shop_ui.gd")
const WalletNotice=preload("res://scripts/cafe_wallet_notice.gd")
const Inbox=preload("res://scripts/cafe_inbox.gd")
const SaveLogPanel=preload("res://scripts/cafe_save_log_panel.gd")
var save_log_panel
const UpdateNotes=preload("res://scripts/cafe_update_notes.gd")
const ViewportLayout=preload("res://scripts/cafe_viewport_layout.gd")
var viewport_too_small=false
var viewport_guard:ColorRect
var viewport_message:PanelContainer
var viewport_title:Label
var viewport_copy:Label
var shop_ui
var shop_layout_view=Vector2(-1,-1)
var shop_layout_insets=Vector4(INF,INF,INF,INF)
var hud
var wallet_notice
var update_notes
var inbox
var settings_inbox:Button
var update_badges=[]
var staff_panel
var blockage_button
var staff_access
var mobile_staff_access
const SHORT_NAMES={"table_set":"Table set","table":"Table","chair":"Chair","stove":"Stove","beverage":"Drinks","sink":"Wash sink","counter":"Serving counter","register":"Checkout counter","bin":"Bin","plant":"Plant","lamp":"Lamp","bookshelf":"Shelf","rug":"Rug","bench":"Bench","divider":"Screen"}
var game
var column
var categories
var context:Control
var context_label:Label
var rotate_button:Button
var move_button:Button
var remove_button:Button
var finish_button:Button
var cancel_button:Button
var build_scroll:ScrollContainer
var finishes:PanelContainer
var management:PanelContainer
var help_panel:PanelContainer
var help_text:Label
var help_box:VBoxContainer
var help_scroll:ScrollContainer
var help_footer:VBoxContainer
var help_heading:Label
var help_overview:Button
var help_notes:Button
var help_scrim:ColorRect
var help_modal=false
var help_done:Button
var help_retry:Button
var settings_help:Button
var help_returns_to_settings=false
var hire_button:Button
var upgrade_button:Button
var plot_button:Button
var hint:PanelContainer
var hint_text:Label
var selected_wall=""
var selected_shell=""
var last_detail=""
var top_row
var title
var business_state:Label
var business_action:Label
var settings_button
var wall_papers:OptionButton
var wall_heights:OptionButton
var wall_preview:Control
var wall_price_label:Label
var wall_use_button:Button
var floor_repair_button:Button
var floor_repair_review:PanelContainer
var floor_repair_text:Label
var floor_repair_confirm:Button
var product_target=""
var wall_review:PanelContainer
var wall_review_text:Label
var wall_confirm_button:Button
var pending_wall={}
var manage_access:Button
var help_access:Button
var earnings:PanelContainer
var earnings_text:Label
var earnings_seconds=0.0
var earnings_amount=0
var play_panel:PanelContainer
var play_panel_box:VBoxContainer
var play_controls:HBoxContainer
var business_menu_action:Button
var compact_play=false
var themed_popups=[]
var popup_action_rows=[]
var popup_fit_queued=false
var tray_tween:Tween
var tray_reveal=0.0
var tray_base_top=-162.0
func _init(owner):game=owner
func _small_button(text:String,callback:Callable,width=66.0)->Button:
 var b=game.button(text,callback);b.custom_minimum_size=Vector2(width,42);b.add_theme_font_size_override("font_size",13);return b
func _panel()->PanelContainer:
 var p=PanelContainer.new();p.z_index=50;p.add_theme_stylebox_override("panel",game._style(Color("f8f4e7"),Color("d4d9bf"),14));game.ui.add_child(p);p.hide();return p
var dismissed_mouse_buttons={}
var dismissed_touches={}
func held_modal_touch_ids()->Array:return dismissed_touches.keys()
func cancel_modal_pointer():
 dismissed_mouse_buttons.clear();dismissed_touches.clear()
 # Lifecycle cancellation disables GUI before synthetic releases; clear the
 # catalogue hold explicitly so resize/touchcancel cannot suppress snapping.
 if shop_ui!=null:shop_ui._cancel_product_contacts()
func consume_modal_dismissal(event:InputEvent)->bool:
 if dismissed_mouse_buttons.is_empty() and dismissed_touches.is_empty():return false
 if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]:
  if event.pressed and not event.canceled:dismissed_mouse_buttons[event.button_index]=true
  else:dismissed_mouse_buttons.erase(event.button_index)
 elif event is InputEventScreenTouch:
  if event.pressed and not event.canceled:dismissed_touches[event.index]=true
  else:dismissed_touches.erase(event.index)
 return event is InputEventMouse or event is InputEventScreenTouch or event is InputEventScreenDrag
func _dismiss_from_pointer(event:InputEvent):
 if event is InputEventMouseButton:dismissed_mouse_buttons[event.button_index]=true
 elif event is InputEventScreenTouch:dismissed_touches[event.index]=true
 if game.camera_gestures!=null:game.camera_gestures.on_focus_lost()
 if game.interaction!=null:game.interaction.on_focus_lost()
 if game.build_tools!=null:game.build_tools.on_focus_lost()
 game.settings.hide();pending_wall={};_hide_popups();sync()
func _popup_at(p:Control,width=320.0):
 if game.camera_gestures!=null:game.camera_gestures.on_focus_lost()
 if game.interaction!=null:game.interaction.on_focus_lost()
 if game.build_tools!=null:game.build_tools.on_focus_lost()
 _hide_popups();var size=game.get_viewport().get_visible_rect().size
 p.set_meta("popup_width",width)
 p.size=Vector2(minf(width,size.x-24),0);p.position=Vector2(hud.popup_left(p.size.x) if hud!=null else maxf(12,size.x-p.size.x-12),hud.popup_top() if hud!=null else 92);p.show()
 game.ui.move_child(p,game.ui.get_child_count()-1)
 if shop_ui!=null:shop_ui.root.hide()
 if is_instance_valid(mobile_staff_access):mobile_staff_access.hide()
func _hide_popups():
 for p in _popup_panels():
  if is_instance_valid(p):p.hide()
func _popup_panels()->Array:
 var panels=[finishes,floor_repair_review,wall_review,management,help_panel,play_panel]
 if save_log_panel!=null and is_instance_valid(save_log_panel.panel):panels.append(save_log_panel.panel)
 if shop_ui!=null and is_instance_valid(shop_ui.category_panel):panels.append(shop_ui.category_panel)
 if shop_ui!=null and is_instance_valid(shop_ui.parking_review):panels.append(shop_ui.parking_review)
 if staff_panel!=null and is_instance_valid(staff_panel.panel):panels.append(staff_panel.panel)
 if update_notes!=null and is_instance_valid(update_notes.panel):panels.append(update_notes.panel)
 if inbox!=null and is_instance_valid(inbox.panel):panels.append(inbox.panel)
 return panels

func has_open_popup()->bool:
 if is_instance_valid(game.settings) and game.settings.visible:return true
 for popup in _popup_panels():
  if is_instance_valid(popup) and popup.visible:return true
 return false

func setup():
 column=game.tray.get_child(0);var old_tools=column.get_child(0);old_tools.hide();game.tool_text.hide()
 categories=column.get_child(1);categories.add_theme_constant_override("h_separation",4);categories.add_theme_constant_override("v_separation",4)
 for b in game.category_buttons.values():b.custom_minimum_size=Vector2(61,40);b.add_theme_font_size_override("font_size",13)
 var stretch=Control.new();stretch.size_flags_horizontal=Control.SIZE_EXPAND_FILL;categories.add_child(stretch)
 manage_access=_small_button("Manage",show_management,74);categories.add_child(manage_access)
 help_access=_small_button("?",show_help,44);categories.add_child(help_access)
 context=Control.new();context.mouse_filter=Control.MOUSE_FILTER_IGNORE;column.add_child(context);column.move_child(context,2)
 context_label=game.label("",13);context_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;context.add_child(context_label)
 rotate_button=_small_button("Rotate",_rotate_selected);context.add_child(rotate_button)
 move_button=_small_button("Move",_move_opening);context.add_child(move_button)
 finish_button=_small_button("Replace",show_finishes);context.add_child(finish_button)
 remove_button=_small_button("Remove",_remove_selected,92);context.add_child(remove_button)
 cancel_button=_small_button("×",func():game._cancel_selection();sync(),42);context.add_child(cancel_button)
 context.hide()
 # A wall is one product: height and wallpaper are chosen together.
 for key in ["half","paint","remove","move_opening","remove_opening"]:game.build_tools.tool_buttons[key].hide()
 for key in ["full","door","window"]:
  var card=game.build_tools.tool_buttons[key];card.custom_minimum_size=Vector2(98,98)
  var labels=card.get_child(0).get_children()
  labels[-1].text=Money.amount(game.model.wall_price("half"))+"–"+Money.amount(game.model.wall_price("full")) if key=="full" else Money.amount(game.model.attachment_price(key))
  labels[-2].text="Wall" if key=="full" else str(key).capitalize()
  card.tooltip_text="Choose height and style, then place or replace one wall tile" if key=="full" else labels[-2].text+" · "+labels[-1].text+" coins · requires a full wall"
 var wall_card=game.build_tools.tool_buttons["full"]
 for signal_link in wall_card.pressed.get_connections():wall_card.pressed.disconnect(signal_link.callable)
 wall_card.pressed.connect(func():product_target="";show_wall_product())
 finishes=_panel();var finish_box=VBoxContainer.new();finish_box.add_theme_constant_override("separation",9);finishes.add_child(finish_box)
 finish_box.add_child(game.label("Wall",20))
 wall_preview=game.build_tools.WallIcon.new();wall_preview.custom_minimum_size=Vector2(84,62);wall_preview.mouse_filter=Control.MOUSE_FILTER_IGNORE;finish_box.add_child(wall_preview)
 wall_heights=game.build_tools._option(["Half wall","Full wall"]);finish_box.add_child(wall_heights)
 finish_box.add_child(game.label("Wall style · included",12))
 wall_papers=game.build_tools.paper_option;wall_papers.reparent(finish_box)
 for signal_link in wall_papers.item_selected.get_connections():wall_papers.item_selected.disconnect(signal_link.callable)
 game.build_tools.wall_options.hide();game.build_tools.surface_options.hide()
 wall_heights.item_selected.connect(func(_index):_sync_wall_product())
 wall_papers.item_selected.connect(_paper_selected)
 wall_price_label=game.label("",13);wall_price_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;wall_price_label.custom_minimum_size=Vector2(250,0);finish_box.add_child(wall_price_label)
 var actions=BoxContainer.new();finish_box.add_child(actions);popup_action_rows.append(actions)
 wall_use_button=_small_button("Use wall",_use_wall_product,144);actions.add_child(wall_use_button)
 actions.add_child(_small_button("Cancel",func():finishes.hide(),78))
 floor_repair_button=_small_button("Finish floor",_review_starter_floor_repair,100);categories.add_child(floor_repair_button)
 floor_repair_review=_panel();var repair_box=VBoxContainer.new();repair_box.add_theme_constant_override("separation",12);floor_repair_review.add_child(repair_box)
 repair_box.add_child(game.label("Finish starter floor",18))
 floor_repair_text=game.label("",15);floor_repair_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;floor_repair_text.custom_minimum_size=Vector2(250,0);repair_box.add_child(floor_repair_text)
 var repair_actions=BoxContainer.new();repair_box.add_child(repair_actions);popup_action_rows.append(repair_actions)
 floor_repair_confirm=_small_button("Finish floor",_confirm_starter_floor_repair,140);repair_actions.add_child(floor_repair_confirm)
 repair_actions.add_child(_small_button("Cancel",func():floor_repair_review.hide(),80))
 wall_review=_panel();var review_box=VBoxContainer.new();review_box.add_theme_constant_override("separation",12);wall_review.add_child(review_box)
 review_box.add_child(game.label("Replace wall",20))
 wall_review_text=game.label("",15);wall_review_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;wall_review_text.custom_minimum_size=Vector2(250,0);review_box.add_child(wall_review_text)
 var review_actions=BoxContainer.new();review_box.add_child(review_actions);popup_action_rows.append(review_actions)
 wall_confirm_button=_small_button("Replace",_confirm_wall_replacement,140);review_actions.add_child(wall_confirm_button)
 review_actions.add_child(_small_button("Cancel",func():wall_review.hide();pending_wall={},80))

 build_scroll=ScrollContainer.new();build_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO;build_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
 column.add_child(build_scroll);game.build_panel.reparent(build_scroll);build_scroll.hide()
 for kind in game.catalog_cards:
  var card=game.catalog_cards[kind];var labels=card.get_child(0).get_children();labels[-2].text=game.model.name_of(kind) if game.model.has_method("is_dining_product") and game.model.is_dining_product(kind) else SHORT_NAMES.get(kind,kind.capitalize());card.custom_minimum_size.y=98
  card.tooltip_text=labels[-2].text+" · "+Money.amount(game.model.price_of(kind))+" coins"
 management=_panel();var manage_box=VBoxContainer.new();manage_box.add_theme_constant_override("separation",8);management.add_child(manage_box)
 manage_box.add_child(game.label("Manage",18))
 hire_button=_small_button("Staff",func():staff_panel.show());manage_box.add_child(hire_button)
 upgrade_button=_small_button("",func():game._upgrade();sync());manage_box.add_child(upgrade_button)
 upgrade_button.reparent(context);context.move_child(upgrade_button,context.get_child_count()-1)
 plot_button=_small_button("",func():game._expand();sync());manage_box.add_child(plot_button)
 manage_box.add_child(_small_button("Done",func():management.hide()))
 help_panel=_panel();help_panel.name="QuickHelpPanel"
 help_box=VBoxContainer.new();help_box.add_theme_constant_override("separation",8);help_panel.add_child(help_box)
 help_heading=game.label("Quick help",18);help_box.add_child(help_heading)
 help_scroll=ScrollContainer.new();help_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;help_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO;help_scroll.follow_focus=true;help_scroll.focus_mode=Control.FOCUS_ALL;help_scroll.accessibility_name="Quick help instructions";help_box.add_child(help_scroll)
 var help_content=VBoxContainer.new();help_content.size_flags_horizontal=Control.SIZE_EXPAND_FILL;help_content.add_theme_constant_override("separation",8);help_scroll.add_child(help_content)
 help_text=game.label("",14);help_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;help_content.add_child(help_text)
 help_retry=_small_button("Try loading again",func():game.web_save.retry_startup());help_content.add_child(help_retry);help_retry.hide()
 help_footer=VBoxContainer.new();help_footer.add_theme_constant_override("separation",8);help_box.add_child(help_footer)
 help_overview=_small_button("Show whole café",func():_camera_action(0));help_footer.add_child(help_overview)
 help_done=_small_button("Done",_close_help);help_footer.add_child(help_done)
 help_scrim=ColorRect.new();help_scrim.name="QuickHelpModalBackdrop";help_scrim.color=Color(0.12,0.16,0.10,0.28);help_scrim.z_index=49;game.ui.add_child(help_scrim);help_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);help_scrim.hide()
 help_panel.visibility_changed.connect(func():
  if not help_panel.visible:_set_help_modal(false))
 hint=PanelContainer.new();hint.mouse_filter=Control.MOUSE_FILTER_IGNORE;hint.add_theme_stylebox_override("panel",game._style(Color("fbefdc"),Color("d4bd95"),9));game.ui.add_child(hint)
 hint_text=game.label("",13,Color("735b3e"));hint_text.mouse_filter=Control.MOUSE_FILTER_IGNORE;hint.add_child(hint_text);hint.hide()
 top_row=game.ui.get_child(0).get_child(0);title=top_row.get_child(0);settings_button=top_row.get_child(top_row.get_child_count()-1)
 var business_content=VBoxContainer.new();business_content.mouse_filter=Control.MOUSE_FILTER_IGNORE;business_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);business_content.offset_top=3;business_content.offset_bottom=-3;business_content.add_theme_constant_override("separation",0);game.business_button.add_child(business_content)
 business_state=game.label("Open",13);business_state.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;business_state.mouse_filter=Control.MOUSE_FILTER_IGNORE;business_content.add_child(business_state)
 business_action=game.label("Close cafe",9);business_action.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;business_action.mouse_filter=Control.MOUSE_FILTER_IGNORE;business_content.add_child(business_action)
 staff_panel=StaffPanel.new(game,self);staff_panel.build()
 staff_access=_small_button("Staff",func():staff_panel.show(),66);top_row.add_child(staff_access);top_row.move_child(staff_access,top_row.get_child_count()-2)
 mobile_staff_access=_small_button("Staff",func():staff_panel.show(),76);mobile_staff_access.custom_minimum_size.y=36;mobile_staff_access.position=Vector2(18,88);game.ui.add_child(mobile_staff_access)
 play_panel=_panel();play_panel_box=VBoxContainer.new();play_panel_box.add_theme_constant_override("separation",10);play_panel.add_child(play_panel_box)
 play_panel_box.add_child(game.label("Café controls",19))
 business_menu_action=_small_button("Close café",func():game._toggle_business();sync());play_panel_box.add_child(business_menu_action)
 play_controls=game.settings_controls.build_play_controls();play_panel_box.add_child(play_controls)
 play_panel_box.add_child(_small_button("Done",func():play_panel.hide();sync()))
 game.business_button.pressed.disconnect(game._toggle_business);game.business_button.pressed.connect(_business_pressed)
 earnings=PanelContainer.new();earnings.mouse_filter=Control.MOUSE_FILTER_IGNORE
 earnings.add_theme_stylebox_override("panel",game._style(Color("f0f5de"),Color("c8d6b2"),9));game.ui.add_child(earnings)
 earnings_text=game.label("",14,Color("3e6b43"));earnings_text.mouse_filter=Control.MOUSE_FILTER_IGNORE;earnings.add_child(earnings_text);earnings.hide()
 blockage_button=_small_button("Show",_show_work_blockage,68);blockage_button.custom_minimum_size.y=34;blockage_button.tooltip_text="Show blocked work tiles in Decorate";game.ui.add_child(blockage_button);blockage_button.hide()
 settings_button.pressed.connect(sync)
 game.business_button.toggle_mode=true;game.business_button.add_theme_stylebox_override("pressed",game._style(Color("547961"),Color.TRANSPARENT,9));game.business_button.add_theme_color_override("font_pressed_color",Color("fff3d8"))
 var settings_box=game.settings.get_child(0)
 settings_inbox=_small_button("Inbox",func():inbox.show());settings_box.add_child(settings_inbox);settings_box.move_child(settings_inbox,settings_box.get_child_count()-2)
 settings_help=_small_button("Help & updates",_show_help_from_settings);settings_help.accessibility_name="Help and update notes";settings_box.add_child(settings_help);settings_box.move_child(settings_help,settings_box.get_child_count()-2)
 for c in settings_box.get_children():
  if c is Label:
   if c.text=="Changes are saved automatically":c.hide()
 hud=Hud.new(self);hud.setup()
 shop_ui=ShopUI.new(self);shop_ui.setup()
 for popup in [finishes,floor_repair_review,wall_review,management,help_panel,play_panel,game.settings,shop_ui.parking_review]:
  hud.theme_panel(popup,true,20 if popup==help_panel else 26);hud.theme_panel_contents(popup)
  _wrap_themed_popup(popup,340 if popup==help_panel else (330 if popup==game.settings else 320))
 save_log_panel=SaveLogPanel.new(self);save_log_panel.setup()
 var log_entry=save_log_panel.make_menu_entry();settings_box.add_child(log_entry);settings_box.move_child(log_entry,settings_box.get_child_count()-2)
 update_notes=UpdateNotes.new(self);update_notes.setup()
 help_notes=update_notes.make_menu_entry();help_footer.add_child(help_notes);help_footer.move_child(help_notes,1)
 for button in [help_overview,help_notes,help_done,help_retry]:button.add_theme_font_size_override("font_size",14)
 inbox=Inbox.new(self);inbox.setup();inbox.unread_changed.connect(_on_notes_unread_changed)
 _add_update_badge(help_access);_add_update_badge(settings_help);_add_update_badge(settings_button);_add_update_badge(settings_inbox)
 update_notes.unread_changed.connect(_on_notes_unread_changed);_sync_update_badges()
 staff_panel.apply_theme(hud)
 for audio in game.settings_controls.audio_rows.values():audio.slider.custom_minimum_size.x=120;audio.slider.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 wallet_notice=WalletNotice.new(self);wallet_notice.setup(earnings,earnings_text)
 _build_viewport_guard()
 for control in [hud.layout_host,game.catalog_scroll,build_scroll]:control.resized.connect(_sync_viewport_guard.call_deferred)
 sync()
func _build_viewport_guard():
 viewport_guard=ColorRect.new();viewport_guard.name="ViewportSizeGuard";viewport_guard.color=Color("e6ecd9");viewport_guard.z_index=1000;game.ui.add_child(viewport_guard);viewport_guard.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 viewport_message=PanelContainer.new();viewport_guard.add_child(viewport_message);hud.theme_panel(viewport_message,false,18)
 viewport_message.resized.connect(_position_viewport_guard)
 var body=VBoxContainer.new();body.add_theme_constant_override("separation",10);viewport_message.add_child(body)
 viewport_title=game.label("Please open in full screen",20);viewport_title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;viewport_title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;body.add_child(viewport_title)
 viewport_copy=game.label("Or make the game window bigger.\nYour café is paused.",14);viewport_copy.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;viewport_copy.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;body.add_child(viewport_copy)
 viewport_guard.hide()
func _sync_viewport_guard():
 if not is_instance_valid(viewport_guard):return
 var view=game.get_viewport().get_visible_rect().size;var insets=hud._safe_insets()
 viewport_too_small=not ViewportLayout.supports(view,hud.layout_host.get_global_rect().end.y,insets,shop_ui.browse_rect().position.y)
 viewport_guard.visible=viewport_too_small
 if shop_ui!=null:shop_ui.root.visible=not has_open_popup() and not viewport_too_small
 if is_instance_valid(game.illustration):game.illustration.visible=not viewport_too_small
 if viewport_too_small:
  var width=minf(360,maxf(100,view.x-insets.x-insets.z-32));var inner=width-36
  for label in [viewport_title,viewport_copy]:label.custom_minimum_size.x=inner;label.size.x=inner
  viewport_message.size=Vector2(width,0)
  _position_viewport_guard()
func _position_viewport_guard():
 if not is_instance_valid(viewport_message):return
 var view=game.get_viewport().get_visible_rect().size;var insets=hud._safe_insets()
 viewport_message.position=Vector2(insets.x+(view.x-insets.x-insets.z-viewport_message.size.x)/2,insets.y+(view.y-insets.y-insets.w-viewport_message.size.y)/2)
func _add_update_badge(button:Button):
 var badge=Panel.new();badge.name="UpdateUnreadDot";badge.mouse_filter=Control.MOUSE_FILTER_IGNORE
 badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT);badge.offset_left=-13;badge.offset_right=-6;badge.offset_top=6;badge.offset_bottom=13
 var dot=StyleBoxFlat.new();dot.bg_color=hud.GREEN;dot.set_corner_radius_all(4);badge.add_theme_stylebox_override("panel",dot);button.add_child(badge)
 update_badges.append({"button":button,"badge":badge})
func _on_notes_unread_changed(_unread:bool):
 _sync_update_badges()
func _sync_update_badges():
 var unread=update_notes!=null and update_notes.has_unread()
 var inbox_unread=inbox!=null and inbox.has_unread()
 for record in update_badges:
  var button=record.button
  if button==settings_button:
   record.badge.visible=unread or inbox_unread
   button.accessibility_name="Settings"+(", unread Inbox messages" if inbox_unread else "")+(", unread update notes" if unread else "")
  elif button==settings_inbox:
   record.badge.visible=inbox_unread;button.accessibility_name="Inbox, unread messages" if inbox_unread else "Inbox"
  else:
   record.badge.visible=unread
   button.accessibility_name="Help and updates, unread update notes" if unread else "Help and updates"
func clear_selection():
 selected_wall="";selected_shell=""
 if is_instance_valid(context):context.hide()
func _selected_opening()->Dictionary:
 return game.model.get_wall_attachment(int(game.build_tools.opening_source_id)) if game.build_tools!=null else {}
func sync():
 if inbox!=null:inbox.sync()
 if update_notes!=null:update_notes.sync();_sync_update_badges()
 if not is_instance_valid(context):return
 var b=game.build_tools;var item=game.model.get_item(game.selected_id);var opening=_selected_opening();var wall=game.model.get_wall(selected_wall)
 var placing=game.selected_kind!="";var edge=b.mode in ["half","full"];var flooring=b.mode=="floor"
 var selected=not item.is_empty() or not opening.is_empty() or not wall.is_empty() or selected_shell!="" or placing or edge or flooring
 context.visible=game.editing and (selected or game.catalog_category=="Build")
 var selected_kind=game.model.logical_kind(int(item.id)) if not item.is_empty() else game.selected_kind
 context_label.text=game.model.name_of(selected_kind) if game.model.has_method("is_dining_product") and game.model.is_dining_product(selected_kind) else SHORT_NAMES.get(selected_kind,selected_kind.capitalize())
 if not opening.is_empty():context_label.text=str(opening.kind).capitalize()
 elif not wall.is_empty() or selected_shell!="":context_label.text="Wall"
 elif edge:context_label.text="Half wall" if b.mode=="half" else "Full wall"
 elif flooring:context_label.text=b.floor_name()
 rotate_button.visible=(not item.is_empty() or placing or edge or not wall.is_empty()) and opening.is_empty() and selected_shell==""
 move_button.visible=not opening.is_empty() and b.mode!="move_opening"
 finish_button.visible=not wall.is_empty() or selected_shell!="" or edge
 finish_button.text="Style" if edge else "Replace"
 remove_button.visible=not item.is_empty() or not opening.is_empty() or not wall.is_empty()
 remove_button.disabled=false
 var refund=0
 if not opening.is_empty():refund=game.model.wall_attachment_refund(int(opening.id))
 elif not wall.is_empty():
  refund=game.model.wall_refund(selected_wall)
  remove_button.disabled=not game.model.can_remove_wall(selected_wall)
  if remove_button.disabled:context_label.text="Move opening first"
 elif not item.is_empty():refund=game.model.logical_refund(int(item.id))
 remove_button.text="Sell +"+Money.amount(refund)
 for kind in game.catalog_prices:game.catalog_prices[kind].text=Money.amount(game.model.price_of(kind))
 build_scroll.visible=game.editing and game.catalog_category=="Build"
 tray_base_top=(-210 if context.visible else -162)-(44 if game.get_viewport().get_visible_rect().size.x<650 else 0)
 _set_tray_reveal(tray_reveal)
 game.state_badge.hide()
 game.business_button.text="";business_state.text="Recovery" if game.save_recovery_blocked else game.model.operating_status();business_action.text="Close cafe" if game.model.operating_open else "Reopen";business_state.add_theme_color_override("font_color",Color("fff3d8") if game.model.operating_open else Color("29473c"));business_action.add_theme_color_override("font_color",Color("e1e8cf") if game.model.operating_open else Color("63775e"));game.business_button.set_pressed_no_signal(game.model.operating_open);game.business_button.disabled=game.save_recovery_blocked
 game.business_button.tooltip_text="Tap to close admissions; current guests finish" if game.model.operating_open else "Tap to reopen"
 game.edit_button.text="Done" if game.editing else "Decorate"
 hire_button.text="Staff";hire_button.disabled=game.save_recovery_blocked
 # Staff.show() refreshes before opening. Closed cards must not repeatedly
 # query hiring/workface eligibility (including stove pathfinding).
 if staff_panel.panel.visible:staff_panel.sync()
 if help_panel.visible:_sync_help_content()
 var upgrade=game.model.stove_upgrade_cost(game.selected_id)
 upgrade_button.text="Stove upgrade · %s"%Money.amount(upgrade) if upgrade>=0 else ("Max level" if item.get("kind","")=="stove" else "Select a stove")
 upgrade_button.disabled=upgrade<0 or game.save_recovery_blocked
 upgrade_button.visible=not item.is_empty() and str(item.kind)=="stove"
 var next_plot=game.model.next_parcel()
 plot_button.text="Next plot · %s"%Money.amount(int(next_plot.cost)) if not next_plot.is_empty() else "All plots owned";plot_button.disabled=next_plot.is_empty() or game.save_recovery_blocked
 var width=game.get_viewport().get_visible_rect().size.x
 for picker in [wall_heights,wall_papers]:picker.custom_minimum_size.y=42 if width<650 else 29
 compact_play=false # Pause and speed stay visible; Open has one action at every width.
 var controls_parent=play_panel_box if compact_play else (hud.layout_host if hud!=null else top_row)
 if play_controls.get_parent()!=controls_parent:
  play_controls.reparent(controls_parent)
  controls_parent.move_child(play_controls,2 if compact_play else mini(game.business_button.get_index()+1,controls_parent.get_child_count()-1))
 if not compact_play:play_panel.hide()
 if compact_play:
  business_state.text="Controls";business_action.text="Paused" if game.paused else game.model.operating_status()
  game.business_button.tooltip_text="Café controls · open, close, pause and speed"
 business_menu_action.text="Close café" if game.model.operating_open else "Reopen café"
 business_menu_action.disabled=game.save_recovery_blocked
 var world_visible=not has_open_popup()
 var narrow=width<650
 earnings.position=Vector2(width-132,164) if narrow else Vector2(maxf(32,game.top_text.get_global_rect().end.x-122),88)
 staff_access.visible=not narrow
 mobile_staff_access.visible=narrow and world_visible
 if is_instance_valid(blockage_button):
  blockage_button.position=Vector2(18,155) if narrow else Vector2(32,116)
  blockage_button.visible=not game.editing and world_visible and not WorkfaceGuidance.blocked_station(game).is_empty()
 for k in game.category_buttons:
  var tab=game.category_buttons[k];tab.custom_minimum_size.x=44 if width<650 else 68
  tab.text=k
  tab.add_theme_font_size_override("font_size",12 if width<650 else 13)
 manage_access.hide();help_access.show();management.hide()
 manage_access.text="Manage";manage_access.custom_minimum_size.x=74;manage_access.tooltip_text="Upgrades and plots"
 # Secondary game actions stay with Decorate, including on narrow screens.
 categories.add_theme_constant_override("h_separation",3 if width<650 else 4)
 context_label.visible=width>=650
 if width<650 and upgrade>=0:upgrade_button.text="Upgrade\n%s"%Money.amount(upgrade)
 # StyleBox setters emit changed even when the numeric margin is identical.
 # Those signals invalidate every subscribed control's minimum-size cache.
 # Preserve exact breakpoint styling without repeatedly invalidating it.
 var action_font_size=12 if width<650 else 13
 var action_margin=8.0 if width<650 else 16.0
 for action_button in [rotate_button,move_button,finish_button,remove_button,upgrade_button,cancel_button]:
  if not action_button.has_theme_font_size_override("font_size") or action_button.get_theme_font_size("font_size")!=action_font_size:
   action_button.add_theme_font_size_override("font_size",action_font_size)
  for state in ["normal","hover","pressed","disabled"]:
   var button_style=action_button.get_theme_stylebox(state)
   if button_style.content_margin_left!=action_margin:button_style.content_margin_left=action_margin
   if button_style.content_margin_right!=action_margin:button_style.content_margin_right=action_margin
 var style=game.tray.get_theme_stylebox("panel");var tray_margin=10.0 if width<650 else 16.0
 if style.content_margin_left!=tray_margin:style.content_margin_left=tray_margin
 if style.content_margin_right!=tray_margin:style.content_margin_right=tray_margin
 # Keep the closing animation and first/resize layout current. Catalog data
 # is refreshed synchronously by every Decorate opening/category change.
 var shop_view=game.get_viewport().get_visible_rect().size
 var shop_insets=hud._safe_insets() if hud!=null else Vector4.ZERO
 if shop_ui!=null and (game.editing or game.tray.visible or shop_view!=shop_layout_view or shop_insets!=shop_layout_insets):
  shop_ui.sync(width);shop_layout_view=shop_view;shop_layout_insets=shop_insets
 if hud!=null:hud.sync(width)
 _fit_themed_popups()
 _sync_viewport_guard()
 _sync_starter_floor_repair()
 if shop_ui!=null:shop_ui.root.visible=not has_open_popup() and not viewport_too_small
func _wrap_themed_popup(panel:PanelContainer,width:float):
 if panel==help_panel:
  panel.set_meta("popup_width",width);hud.theme_scroll(help_scroll)
  for control in [help_scroll.get_child(0),help_footer,help_heading]:control.minimum_size_changed.connect(_queue_popup_fit)
  panel.visibility_changed.connect(_queue_popup_fit);panel.resized.connect(_queue_popup_fit)
  return
 panel.z_index=50
 var body=panel.get_child(0);var scroll=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO;scroll.follow_focus=true
 panel.add_child(scroll);body.reparent(scroll);body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;panel.custom_minimum_size=Vector2.ZERO;panel.set_anchors_preset(Control.PRESET_TOP_LEFT);panel.set_meta("popup_width",width)
 hud.theme_scroll(scroll);themed_popups.append({"panel":panel,"scroll":scroll,"body":body})
 body.minimum_size_changed.connect(_queue_popup_fit);panel.visibility_changed.connect(_queue_popup_fit);panel.resized.connect(_queue_popup_fit)
func _queue_popup_fit():
 if not is_instance_valid(game):return
 if popup_fit_queued:return
 popup_fit_queued=true;_fit_themed_popups.call_deferred()
func _fit_themed_popups():
 popup_fit_queued=false
 if hud==null or not is_instance_valid(game):return
 if shop_ui!=null:shop_ui.root.visible=not has_open_popup() and not viewport_too_small
 _fit_help_panel()
 if inbox!=null:inbox.fit_popup()
 var view=game.get_viewport().get_visible_rect().size;var insets=hud._safe_insets()
 for record in themed_popups:
  var panel:PanelContainer=record.panel
  if not panel.visible:continue
  if panel.get_index()!=game.ui.get_child_count()-1:game.ui.move_child(panel,game.ui.get_child_count()-1)
  var width=minf(float(panel.get_meta("popup_width",320)),maxf(0,view.x-insets.x-insets.z-24))
  var padding=panel.get_theme_stylebox("panel").get_minimum_size()
  var body:Control=record.body;var bar:VScrollBar=record.scroll.get_v_scroll_bar()
  var gutter=bar.get_minimum_size().x+record.scroll.get_theme_constant("scrollbar_h_separation") if bar.visible else 0.0
  for actions in popup_action_rows:
   if not panel.is_ancestor_of(actions):continue
   var needed=float(actions.get_theme_constant("separation"))*maxi(0,actions.get_child_count()-1)
   for action in actions.get_children():needed+=action.get_combined_minimum_size().x
   actions.vertical=needed>width-padding.x-gutter
  body.size.x=maxf(0,width-padding.x-gutter)
  var available=maxf(44,hud.popup_height_budget()-padding.y)
  record.scroll.custom_minimum_size=Vector2(0,minf(available,body.get_combined_minimum_size().y))
  panel.size=Vector2(width,0);panel.position=Vector2(hud.popup_left(panel.size.x),hud.popup_y(panel.size.y))
func _fit_help_panel():
 if not is_instance_valid(help_panel) or not help_panel.visible:return
 var view=game.get_viewport().get_visible_rect().size;var insets=hud._safe_insets()
 var width=minf(340,maxf(0,view.x-insets.x-insets.z-24))
 var padding=help_panel.get_theme_stylebox("panel").get_minimum_size()
 var top=hud.layout_host.get_global_rect().end.y+10
 var footer_height=help_footer.get_combined_minimum_size().y
 var fixed_height=padding.y+help_heading.get_combined_minimum_size().y+footer_height+16
 # Prefer a docked panel with at least 100px of readable instructions. Only
 # genuinely short viewports use a scrim and disable the obscured toolbar.
 var modal=view.y-insets.w-top-12<fixed_height+100
 _set_help_modal(modal)
 if modal:top=insets.y+12
 var available=maxf(0,view.y-insets.w-top-12-fixed_height)
 var body:Control=help_scroll.get_child(0)
 var bar=help_scroll.get_v_scroll_bar()
 var gutter=bar.get_minimum_size().x+help_scroll.get_theme_constant("scrollbar_h_separation") if bar.visible else 0.0
 body.size.x=maxf(0,width-padding.x-gutter)
 help_scroll.custom_minimum_size=Vector2(0,minf(available,body.get_combined_minimum_size().y))
 help_panel.size=Vector2(width,0)
 help_panel.position=Vector2(hud.popup_left(help_panel.size.x),top)
 if help_panel.get_index()!=game.ui.get_child_count()-1:game.ui.move_child(help_panel,game.ui.get_child_count()-1)
func _set_help_modal(enabled:bool):
 help_modal=enabled
 if is_instance_valid(help_scrim):help_scrim.visible=enabled
 if hud==null or not is_instance_valid(hud.layout_host):return
 hud.layout_host.mouse_behavior_recursive=Control.MOUSE_BEHAVIOR_DISABLED if enabled else Control.MOUSE_BEHAVIOR_INHERITED
 hud.layout_host.focus_behavior_recursive=Control.FOCUS_BEHAVIOR_DISABLED if enabled else Control.FOCUS_BEHAVIOR_INHERITED
 if enabled:
  var focused=game.get_viewport().gui_get_focus_owner()
  if focused==null or not help_panel.is_ancestor_of(focused):help_scroll.grab_focus()
func _help_tab(event:InputEventKey)->bool:
 if not help_panel.visible or event.keycode!=KEY_TAB:return false
 var controls=[help_scroll]
 if help_retry.visible and not help_retry.disabled:controls.append(help_retry)
 controls.append_array([help_overview,help_notes,help_done])
 var focused=game.get_viewport().gui_get_focus_owner();var index=controls.find(focused)
 index=posmod(index+(-1 if event.shift_pressed else 1),controls.size())
 controls[index].grab_focus();return true
func _business_pressed():
 if compact_play:
  game.settings.hide();_popup_at(play_panel,320);sync()
 else:game._toggle_business()
func set_tray_open(opened:bool):
 if is_instance_valid(tray_tween):tray_tween.kill()
 var target=1.0 if opened else 0.0
 game.tray.show()
 column.mouse_behavior_recursive=Control.MOUSE_BEHAVIOR_DISABLED
 column.focus_behavior_recursive=Control.FOCUS_BEHAVIOR_DISABLED
 if not opened:
  var focused=game.get_viewport().gui_get_focus_owner()
  if is_instance_valid(focused) and game.tray.is_ancestor_of(focused):game.edit_button.grab_focus()
 tray_tween=game.create_tween();tray_tween.set_trans(Tween.TRANS_CUBIC);tray_tween.set_ease(Tween.EASE_OUT if opened else Tween.EASE_IN)
 tray_tween.tween_method(_set_tray_reveal,tray_reveal,target,maxf(.06,.20*absf(target-tray_reveal)))
 tray_tween.tween_callback(func():
  _set_tray_reveal(target)
  game.tray.visible=opened
  column.mouse_behavior_recursive=Control.MOUSE_BEHAVIOR_INHERITED if opened else Control.MOUSE_BEHAVIOR_DISABLED
  column.focus_behavior_recursive=Control.FOCUS_BEHAVIOR_INHERITED if opened else Control.FOCUS_BEHAVIOR_DISABLED)
func _set_tray_reveal(value:float):
 tray_reveal=clampf(value,0,1)
 var minimum_height=game.tray.get_combined_minimum_size().y
 var bottom_gap=12.0+(hud.safe_bottom() if hud!=null else 0.0)
 var top=minf(tray_base_top,-minimum_height-bottom_gap)
 # Move the tray continuously from below the safe viewport edge.
 var travel=(bottom_gap-top)*(1.0-tray_reveal)
 game.tray.offset_top=top+travel;game.tray.offset_bottom=-bottom_gap+travel
 game.tray.modulate.a=tray_reveal
func show_earnings(amount:int):
 if amount<=0:return
 wallet_notice.show_earned(amount)
func show_wage_payment(amount:int):wallet_notice.show_wages(amount)
func show_wages_due(amount:int):wallet_notice.show_due(amount)
func tick_earnings(delta:float):
 if wallet_notice!=null:wallet_notice.tick(delta)
func _show_work_blockage():
 var target=WorkfaceGuidance.blocked_station(game)
 if target.is_empty():return
 game.settings.hide();_hide_popups()
 if not game.editing:game._toggle_edit()
 game._set_catalog_category(game._catalog_group(str(target.kind)))
 game.interaction._select_item(target)
 game.illustration.queue_redraw();sync()

func _camera_action(amount:float):
 if game.interaction==null:return
 if game.interaction.drag_active:game.interaction.cancel(false)
 if is_zero_approx(amount):
  game.illustration.fit_overview();game.interaction.pan_offset=game.illustration.pan_offset
 else:
  var size=game.get_viewport().get_visible_rect().size
  game.interaction._zoom_step_at(Vector2(size.x*.5,(hud.layout_host.get_global_rect().end.y+shop_ui.browse_rect().position.y)*.5),signf(amount))
 sync()

func _sync_starter_floor_repair():
 if not is_instance_valid(floor_repair_button):return
 var gaps=game.model.starter_floor_gap_cells()
 floor_repair_button.visible=not gaps.is_empty() and game.editing and game.catalog_category=="Build" and shop_ui!=null and shop_ui.build_page=="tiles"
 var blocked=game.save_recovery_blocked or viewport_too_small or not game.editing or game.catalog_category!="Build"
 floor_repair_button.disabled=blocked
 floor_repair_confirm.disabled=blocked or gaps.is_empty()
 if gaps.is_empty():floor_repair_review.hide()
func _review_starter_floor_repair():
 if not floor_repair_button.is_visible_in_tree() or game.save_recovery_blocked or viewport_too_small or not game.editing or game.catalog_category!="Build":return
 var gaps=game.model.starter_floor_gap_cells()
 if gaps.is_empty():_sync_starter_floor_repair();return
 floor_repair_text.text="Complete %d missing starter-row tiles with warm oak for free.\n\nExisting flooring stays as it is."%gaps.size()
 _popup_at(floor_repair_review,320);_sync_starter_floor_repair()
func _confirm_starter_floor_repair():
 # A dismissed or blocked review cannot become a late repair/save.
 if not floor_repair_review.visible or game.save_recovery_blocked or viewport_too_small or not game.editing or game.catalog_category!="Build":return
 floor_repair_review.hide()
 if game.model.repair_starter_floor_gap()>0:game.build_tools._changed()
 _sync_starter_floor_repair();sync()
func _paper_selected(_index:int):
 _sync_wall_product()
func show_finishes():
 product_target=selected_shell if selected_shell!="" else selected_wall
 show_wall_product()
func show_wall_product():
 game.settings.hide()
 wall_papers.clear()
 for name in game.build_tools.MATERIAL_NAMES:wall_papers.add_item(name)
 if not game.model.ShellSegments.parse_key(product_target).is_empty():wall_papers.add_item("Original room")
 var product=game.model.get_wall_host(product_target) if not game.model.ShellSegments.parse_key(product_target).is_empty() else game.model.get_wall(product_target)
 var height=str(product.get("height",game.build_tools.mode if game.build_tools.mode in ["half","full"] else "full"))
 var paper=str(product.get("material",game.build_tools.material))
 wall_heights.select(0 if height=="half" else 1)
 wall_papers.select(3 if paper=="original" and wall_papers.item_count==4 else maxi(0,game.model.WallGeometry.MATERIALS.find(paper)))
 _sync_wall_product();_popup_at(finishes,320)
func _sync_wall_product():
 if not is_instance_valid(wall_heights):return
 var height="half" if wall_heights.selected==0 else "full"
 var paper="original" if wall_papers.selected==3 else game.model.WallGeometry.MATERIALS[maxi(0,wall_papers.selected)]
 wall_preview.height=height;wall_preview.wall_material="sage_panels" if paper=="original" else paper;wall_preview.queue_redraw()
 var price=Money.amount(game.model.wall_price(height))
 wall_price_label.text="New wall · "+price+" coins per tile\nClick an empty edge to build, or an existing wall to replace it."
 if product_target!="":
  var quote=game.model.wall_replacement_quote(product_target,height,paper,game.build_tools.actor_positions())
  wall_price_label.text="New %s · refund %s · pay %s"%[Money.amount(int(quote.new_cost)),Money.amount(int(quote.refund)),Money.amount(int(quote.net))]
  if not quote.valid:wall_price_label.text+="\n"+str(quote.reason)
 wall_use_button.text="Choose target"
func _use_wall_product():
 var height="half" if wall_heights.selected==0 else "full"
 game.build_tools.material="original" if wall_papers.selected==3 else game.model.WallGeometry.MATERIALS[maxi(0,wall_papers.selected)]
 finishes.hide();game.build_tools.choose(height);sync()
func review_wall_replacement(key:String,height:String,paper:String):
 pending_wall={"key":key,"height":height,"material":paper}
 var quote=game.model.wall_replacement_quote(key,height,paper,game.build_tools.actor_positions())
 var scope="Selected one-tile wall"
 wall_review_text.text=scope+"\n"+("Half wall" if height=="half" else "Full wall")+" · "+("Original room" if paper=="original" else game.build_tools.MATERIAL_NAMES[game.model.WallGeometry.MATERIALS.find(paper)])
 wall_review_text.text+="\n\nNew wall: %s coins\nOld wall refund: %s coins\nYou pay: %s coins"%[Money.amount(int(quote.new_cost)),Money.amount(int(quote.refund)),Money.amount(int(quote.net))]
 if not quote.valid:wall_review_text.text+="\n\n"+str(quote.reason)
 wall_confirm_button.disabled=not quote.valid
 _popup_at(wall_review,320)
func _confirm_wall_replacement():
 if not wall_review.visible or not game.editing or game.save_recovery_blocked or viewport_too_small or pending_wall.is_empty():return
 var chosen=pending_wall.duplicate(true)
 if not game.model.replace_wall(chosen.key,chosen.height,chosen.material,game.build_tools.actor_positions()):
  review_wall_replacement(chosen.key,chosen.height,chosen.material);return
 pending_wall={};wall_review.hide();game.build_tools.cancel()
 selected_shell=chosen.key if not game.model.ShellSegments.parse_key(chosen.key).is_empty() else ""
 selected_wall=chosen.key if selected_shell=="" else ""
 game.build_tools._changed();sync()
func _rotate_selected():
 var wall=game.model.get_wall(selected_wall)
 if wall.is_empty():game._rotate();return
 var key=selected_wall;var axis="z" if wall.axis=="x" else "x"
 if game.model.move_wall(key,axis,int(wall.x),int(wall.z),game.build_tools.actor_positions()):
  selected_wall=game.model.WallGeometry.key(axis,int(wall.x),int(wall.z));game.build_tools._changed()
 sync()
func show_management():
 game.settings.hide();sync();_popup_at(management)
func show_help():
 help_returns_to_settings=false;help_done.text="Done"
 game.settings.hide()
 _sync_help_content()
 _popup_at(help_panel,340);help_scroll.scroll_vertical=0;_fit_help_panel();help_scroll.grab_focus()
 if help_retry.visible and not help_retry.disabled:help_retry.grab_focus()
func _sync_help_content():
 help_retry.visible=game.web_save!=null and game.web_save.startup_error!=""
 help_retry.disabled=help_retry.visible and game.web_save.retrying
 help_retry.text="Loading saved café…" if help_retry.disabled else "Try loading again"
 var save_detail=""
 if game.web_save!=null and game.web_save.platform_managed:save_detail="Progress submitted to CrazyGames. Guest saves stay on this device; signed-in progress syncs through the platform and may take up to 30 seconds. Cloud sync is not confirmed here.\n\n"
 if game.save_recovery_blocked:
  save_detail="Your saved café could not be opened. Your original progress is unchanged. Try loading again. If it still fails, keep this page open and share the details below.\n\nDetails: "+game._recovery_notice()+"\n\n" if help_retry.visible else "Saving is paused to protect your progress. Keep this page open and share these details: "+game._recovery_notice()+"\n\n"
 elif game.progress_unsaved:
  save_detail=game._unsaved_progress_message()+"\n\n"
 elif game.paused and game.startup_notice!="":
  save_detail=game.startup_notice+"\n\n"
 help_text.text=save_detail+(last_detail+"\n\n" if not game.save_recovery_blocked and game.editing and last_detail!="" else "")+"View: drag empty ground. Use the mouse wheel or pinch with two fingers to zoom.\n\nIn Decorate, drag furniture to move it. A two-finger camera gesture cancels the current unplaced preview.\n\nSelect a wall, door or window for its actions. Doors and windows need full walls.\n\nBuild > Tiles: choose a style, then click one tile. Replacements refund half the old tile’s paid cost.\n\n+ / − zoom · 0 or Home shows the whole café\nF1 help · R rotates · Esc cancels"
 if game.save_recovery_blocked:help_text.text=save_detail+"You can still use View, Settings and Help while loading is paused."
func _show_help_from_settings():
 show_help();help_returns_to_settings=true;help_done.text="Back to Settings"
func return_to_help():
 _popup_at(help_panel,340);_fit_help_panel();help_notes.grab_focus()
func _close_help():
 help_panel.hide()
 if help_returns_to_settings:game.settings.show();_fit_themed_popups()
 sync()
func _move_opening():
 if _selected_opening().is_empty():return
 game.build_tools.mode="move_opening";game.build_tools._cache_key="";game.build_tools.refresh(game.get_viewport().get_mouse_position());sync()
func _remove_selected():
 var opening=_selected_opening();var ok=false
 if not opening.is_empty():ok=game.model.remove_wall_attachment(int(opening.id),game.build_tools.actor_positions())
 elif selected_wall!="":ok=game.model.remove_wall(selected_wall)
 else:game._sell();sync();return
 if ok:game._cancel_selection();game._save();game._update_ui();game.illustration.queue_redraw()
 sync()
func handle_input(event:InputEvent)->bool:
 if consume_modal_dismissal(event):return true
 if inbox!=null and inbox.handle_input(event):return true
 var panels=_popup_panels()
 if is_instance_valid(game.settings):panels.append(game.settings)
 var any_open=false
 for popup in panels:
  if is_instance_valid(popup) and popup.visible:any_open=true;break
 if not any_open:return false
 if event is InputEventKey and event.pressed and _help_tab(event):return true
 if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
  game.settings.hide();pending_wall={};_hide_popups();sync();return true
 var pointer_press=(event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed)
 if pointer_press:
  for panel in panels:
   if is_instance_valid(panel) and panel.visible and panel.get_global_rect().has_point(event.position):return false
  _dismiss_from_pointer(event);return true
 return false
func handle_unhandled_input(event:InputEvent)->bool:
 if not game.editing or game.catalog_category!="Build" or game.build_tools.mode not in ["","select_opening"]:return false
 if not event is InputEventMouseButton or not event.pressed or event.button_index!=MOUSE_BUTTON_LEFT:return false
 if game.interaction==null or game.interaction._over_ui(event.position):return false
 var opening=game.illustration.hit_wall_attachment(event.position)
 if opening>=0:
  game.build_tools.choose("select_opening");return false
 var wall=game.illustration.hit_wall(event.position)
 if not wall.is_empty():
  game._cancel_selection();selected_wall=game.model.WallGeometry.key_of(wall);sync();return true
 var host=game.illustration.hit_wall_host(event.position)
 if not host.is_empty() and host.shell:
  game._cancel_selection();selected_shell=str(host.segment_key);sync();return true
 clear_selection()
 if game.build_tools.mode=="select_opening":game.build_tools.cancel();sync()
 return false
func short_reason(text:String)->String:
 var t=text.to_lower()
 if t.begins_with("the original cafe shell is already here"):return "Wall already here"
 if t.contains("already occupies"):return "Opening already here"
 if t.contains("empty floor") or t.contains("not a host"):return "Place a wall first"
 if t.contains("full-height") or t.contains("half wall"):return "Needs a full wall"
 if t.contains("attached door/window"):return "Move opening first"
 if t.contains("not enough"):return "Not enough coins"
 if t.contains("crossing"):return "Someone is passing"
 if t.contains("occupied"):return "Spot already used"
 if t.contains("saved café needs") or t.contains("recovery"):return "Save needs recovery"
 if t.contains("current row"):return "Finish this row first"
 if t.contains("plot in front"):return "Buy the front plot first"
 if t.contains("buy") and t.contains("plot"):return "Buy this plot first"
 if t.contains("outside"):return "Outside your café"
 if t.contains("counter back blocked"):return "Chef side blocked"
 if t.contains("counter front blocked"):return "Serve side blocked"
 if t.contains("front blocked"):return "Front blocked"
 if t.contains("seal") or t.contains("reachable") or t.contains("walking route"):return "Keep a path open"
 if t.contains("in use") or t.contains("using") or t.contains("finish using"):return "In use"

 var short=text.split(" · ")[0]
 return short if short.length()<=44 else short.left(41)+"…"
func update_pointer():
 if not is_instance_valid(hint):return
 var reason="";var b=game.build_tools
 if shop_ui!=null:shop_ui.sync_action_details()
 if game.editing and b.active() and b.mode!="select_opening" and not b.preview_valid and b.preview_reason!="":reason=b.preview_reason
 elif game.editing and game.interaction!=null and game.interaction.preview_active:
  if not game.interaction.drag_valid:reason=game.interaction.drag_reason
  elif game.interaction.drag_warning!="":reason=game.interaction.drag_warning
 var pointer=game.get_viewport().get_mouse_position()
 if reason=="" or (game.interaction!=null and game.interaction._over_ui(pointer)):hint.hide();return
 last_detail=reason;hint_text.text=short_reason(reason);hint.size=Vector2.ZERO
 var view=game.get_viewport().get_visible_rect().size
 hint.position=Vector2(clampf(pointer.x+18,12,maxf(12,view.x-hint.size.x-12)),clampf(pointer.y-58,82,maxf(82,game.tray.position.y-48)))
 hint.show()
