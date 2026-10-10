extends RefCounted
const Money=preload("res://scripts/cafe_money.gd")
const Portrait=preload("res://scripts/cafe_staff_portrait.gd")
const ROLE_COLORS={"chef":Color("dce9d5"),"waiter":Color("f0e2cc"),"cleaner":Color("dceae4"),"cashier":Color("e8e3ce")}
const ROLE_PURPOSES={"chef":"Cooks meals","waiter":"Food & drinks","cleaner":"Dishes & floors","cashier":"Checkout service"}
const VISIBLE_ROLES=["chef","waiter","cleaner","cashier"]
const INK=Color("554631")
const MUTED=Color("75644f")
const SAGE=Color("526a4e")
const WARNING=Color("855536")
const PANEL_WIDTH=396.0
const CARD_SCROLL_HEIGHT=500.0
var game
var compact_ref:WeakRef
var compact:
 get:return compact_ref.get_ref()
var panel:PanelContainer
var layout_box:VBoxContainer
var title:Label
var payroll_card:PanelContainer
var summary:Label
var clock_label:Label
var rows={}
var scroll:ScrollContainer
var role_body:VBoxContainer
var footnote:Label
var done_button:Button
var fit_queued=false
var bottom_fade:TextureRect
func _init(owner,ui):game=owner;compact_ref=weakref(ui)
func build():
 panel=compact._panel();layout_box=VBoxContainer.new();layout_box.add_theme_constant_override("separation",8);panel.add_child(layout_box)
 var heading=HBoxContainer.new();heading.add_theme_constant_override("separation",12);layout_box.add_child(heading)
 title=game.label("Staff",22,INK);title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;title.size_flags_vertical=Control.SIZE_SHRINK_CENTER;heading.add_child(title)
 done_button=compact._small_button("Done",func():panel.hide();compact.sync(),70);done_button.custom_minimum_size=Vector2(70,44);done_button.add_theme_font_size_override("font_size",14);done_button.accessibility_name="Close Staff";heading.add_child(done_button)
 payroll_card=PanelContainer.new();layout_box.add_child(payroll_card)
 var payroll=VBoxContainer.new();payroll.add_theme_constant_override("separation",3);payroll_card.add_child(payroll)
 summary=game.label("",15,INK);summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;payroll.add_child(summary)
 clock_label=game.label("",12,MUTED);clock_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;payroll.add_child(clock_label)
 scroll=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.custom_minimum_size=Vector2(0,CARD_SCROLL_HEIGHT);scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;scroll.follow_focus=true;layout_box.add_child(scroll)
 # Integer scroll offsets can leave a subpixel of the final card under the
 # clip edge. Two real content pixels keep its full frame reachable.
 var content_inset=MarginContainer.new();content_inset.add_theme_constant_override("margin_bottom",2);content_inset.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(content_inset)
 role_body=VBoxContainer.new();role_body.add_theme_constant_override("separation",10);role_body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;content_inset.add_child(role_body)
 # Cards use real roster data, but optional model APIs do not silently expose
 # unfinished roles. Extend this presentation list only with an approved role.
 for role_value in game.model.staff_roster():
  var role=str(role_value)
  if role not in VISIBLE_ROLES:continue
  var card=PanelContainer.new();var card_style=game._style(Color("fcf6e7"),Color("d5c9ac"),12)
  card_style.content_margin_left=10;card_style.content_margin_right=10;card_style.content_margin_top=10;card_style.content_margin_bottom=10
  card.add_theme_stylebox_override("panel",card_style);role_body.add_child(card)
  var content=VBoxContainer.new();content.add_theme_constant_override("separation",6);card.add_child(content)
  var identity=HBoxContainer.new();identity.add_theme_constant_override("separation",8);content.add_child(identity)
  var picture=Control.new();picture.custom_minimum_size=Vector2(64,72);picture.size_flags_vertical=Control.SIZE_SHRINK_CENTER;picture.mouse_filter=Control.MOUSE_FILTER_IGNORE;identity.add_child(picture)
  var portrait=Portrait.new();portrait.staff_role=role;portrait.backdrop=ROLE_COLORS.get(role,Color("e2e6d3"));portrait.position=Vector2(32,66);portrait.scale=Vector2.ONE*.92;picture.add_child(portrait)
  var copy=VBoxContainer.new();copy.add_theme_constant_override("separation",2);copy.size_flags_horizontal=Control.SIZE_EXPAND_FILL;copy.size_flags_vertical=Control.SIZE_SHRINK_CENTER;identity.add_child(copy)
  var role_heading=BoxContainer.new();role_heading.add_theme_constant_override("separation",8);copy.add_child(role_heading)
  var name=game.label(role.capitalize(),18,INK);name.size_flags_horizontal=Control.SIZE_EXPAND_FILL;name.size_flags_vertical=Control.SIZE_SHRINK_CENTER;role_heading.add_child(name)
  var status=game.label("",13,SAGE);status.size_flags_vertical=Control.SIZE_SHRINK_CENTER;role_heading.add_child(status)
  var wage=game.label("%s / min each"%Money.amount(int(game.model.WAGE_RATES[role])),13,MUTED);wage.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;copy.add_child(wage)
  var purpose=game.label("",12,MUTED);purpose.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;copy.add_child(purpose)
  var controls=BoxContainer.new();controls.add_theme_constant_override("separation",8);content.add_child(controls)
  var hire:Button=null;var rest:Button=null;var resume:Button=null;var included:Label=null
  if role=="cashier":
   included=game.label("Included · no hiring fee",13,MUTED);included.custom_minimum_size.y=44;included.size_flags_horizontal=Control.SIZE_EXPAND_FILL;included.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;included.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;controls.add_child(included)
  else:
   var key=str(role);hire=_action("Hire · %s"%Money.amount(int(game.model.HIRE_FEES[role])),func():game._hire_staff(key);sync(),true);controls.add_child(hire)
   rest=_action("Off duty",func():game._change_staff_duty(key,-1);sync());controls.add_child(rest)
   resume=_action("Resume",func():game._change_staff_duty(key,1);sync(),true);controls.add_child(resume)
   rest.tooltip_text="An extra worker finishes their job, then rests. No fee or refund."
  rows[role]={"name":name,"heading":role_heading,"purpose":purpose,"wage":wage,"hire":hire,"rest":rest,"resume":resume,"included":included,"status":status,"portrait":portrait,"card":card,"controls":controls}
 footnote=game.label("Game minutes · no offline wages",11,MUTED);footnote.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;layout_box.add_child(footnote)
 game.get_viewport().size_changed.connect(_queue_fit)
 panel.minimum_size_changed.connect(_queue_fit)
 bottom_fade=TextureRect.new();bottom_fade.mouse_filter=Control.MOUSE_FILTER_IGNORE;bottom_fade.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;bottom_fade.z_index=22;game.ui.add_child(bottom_fade);bottom_fade.hide()
 var gradient=Gradient.new();gradient.colors=PackedColorArray([Color(.8314,.7765,.6196,0),Color(.8314,.7765,.6196,.9)])
 var fade_texture=GradientTexture2D.new();fade_texture.gradient=gradient;fade_texture.width=8;fade_texture.height=12;fade_texture.fill_from=Vector2.ZERO;fade_texture.fill_to=Vector2(0,1);bottom_fade.texture=fade_texture
 panel.visibility_changed.connect(_sync_fade);scroll.get_v_scroll_bar().value_changed.connect(func(_value):_sync_fade())
 sync()
func apply_theme(hud):
 # build() runs before HUD setup. The owner applies the shared painted theme
 # afterwards; normal labels retain the game's Noto Sans regular body font.
 hud.theme_panel(panel,true,26)
 hud.theme_panel(payroll_card,false,10)
 hud.theme_scroll(scroll)
 for label in [title,summary]:label.add_theme_font_override("font",hud.font_bold)
 footnote.add_theme_color_override("font_color",hud.INK)
 hud.theme_button(done_button)
 for row in rows.values():
  hud.theme_panel(row.card,false,10)
  for label in [row.name,row.status]:label.add_theme_font_override("font",hud.font_bold)
  for action in [row.hire,row.rest,row.resume]:
   if is_instance_valid(action):hud.theme_button(action,action!=row.rest)
 _queue_fit()
func _action(words:String,callback:Callable,accent=false)->Button:
 var button=game.button(words,callback,accent);button.custom_minimum_size=Vector2(0,44);button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;button.add_theme_font_size_override("font_size",13)
 for style_name in ["normal","hover","pressed","disabled"]:
  var style=button.get_theme_stylebox(style_name).duplicate();style.content_margin_left=8;style.content_margin_right=8;button.add_theme_stylebox_override(style_name,style)
 return button
func _queue_fit():
 if fit_queued:return
 fit_queued=true;call_deferred("_fit")
func _fit():
 fit_queued=false
 if not is_instance_valid(panel):return
 var view=game.get_viewport().get_visible_rect().size
 var insets=compact.hud._safe_insets() if compact.hud!=null else Vector4.ZERO
 var top=compact.hud.popup_top() if compact.hud!=null else 92.0
 var width=minf(PANEL_WIDTH,maxf(0,view.x-insets.x-insets.z-24))
 var available=compact.hud.popup_height_budget() if compact.hud!=null else maxf(0,view.y-top-insets.w-12)
 # Short landscape screens keep wages readable in the scrolling content
 # instead of letting fixed chrome consume the role viewport.
 var short_view=available<320
 if short_view and payroll_card.get_parent()!=role_body:
  payroll_card.reparent(role_body);role_body.move_child(payroll_card,0)
 elif not short_view and payroll_card.get_parent()!=layout_box:
  payroll_card.reparent(layout_box);layout_box.move_child(payroll_card,1)
 footnote.visible=not short_view
 # A vertical action stack on narrow screens keeps every label and 44px
 # target intact. All role cards stay inside the same scroll.
 var panel_style=panel.get_theme_stylebox("panel")
 for row in rows.values():
  var needed=0.0;var count=0
  for action in row.controls.get_children():
   if action.visible:needed+=action.get_combined_minimum_size().x;count+=1
  needed+=maxi(0,count-1)*8
  var inner=width-panel_style.get_minimum_size().x-row.card.get_theme_stylebox("panel").get_minimum_size().x-9
  row.controls.vertical=needed>inner
  row.heading.vertical=row.name.get_combined_minimum_size().x+row.status.get_combined_minimum_size().x+8>inner-72
 var chrome=layout_box.get_combined_minimum_size().y-scroll.get_combined_minimum_size().y+panel_style.get_minimum_size().y
 scroll.custom_minimum_size.y=minf(CARD_SCROLL_HEIGHT,maxf(44,available-chrome))
 if panel.visible:
  panel.size=Vector2(width,0);panel.position=Vector2(compact.hud.popup_left(panel.size.x) if compact.hud!=null else maxf(insets.x+12,view.x-insets.z-panel.size.x-12),compact.hud.popup_y(panel.size.y) if compact.hud!=null else top)
 _sync_fade.call_deferred()
func _sync_fade():
 if not is_instance_valid(panel) or not is_instance_valid(bottom_fade):return
 var bar=scroll.get_v_scroll_bar();bottom_fade.visible=panel.visible and bar.max_value>bar.page and bar.value<bar.max_value-bar.page-.5
 if bottom_fade.visible:
  var rect=scroll.get_global_rect();bottom_fade.position=Vector2(rect.position.x,rect.end.y-12);bottom_fade.size=Vector2(rect.size.x-(bar.size.x if bar.visible else 0),12)
func sync():
 if not is_instance_valid(panel):return
 summary.text="Team wages · %s / min"%Money.amount(game.model.wage_rate())
 if game.model.wages_due>0:clock_label.text="Due %s · paid from income"%Money.amount(game.model.wages_due);clock_label.add_theme_color_override("font_color",Color("934b3d"))
 else:
  clock_label.text="Next pay in %ds"%ceili(60-game.model.payroll_elapsed) if game._staff_on_duty() and not game.paused and not game.editing else "Wages paused"
  clock_label.add_theme_color_override("font_color",MUTED)
 for role in rows:
  var count=game.model.staff_count(role);var active=int(game.model.duty_counts[role]);var desired=int(game.model.duty_targets[role]);var row=rows[role]
  row.status.text="%d/%d on duty"%[active,count];row.status.accessibility_name="%d of %d on duty"%[active,count]
  row.purpose.text=ROLE_PURPOSES.get(role,"")
  if role=="cashier":
   var pending=bool(game.model.included_checkout_pending)
   row.status.text="Included" if pending else "1/1 on duty";row.status.accessibility_name="Included cashier waiting for safe register space" if pending else "1 of 1 cashier on duty"
   row.purpose.text="Waiting for safe register space" if pending else "Checkout service"
   row.purpose.add_theme_color_override("font_color",WARNING if pending else MUTED)
   row.wage.text="No wages until deployed" if pending else "%s / min on duty"%Money.amount(int(game.model.WAGE_RATES[role]))
   row.portrait.modulate.a=.55 if pending else 1.0
   for index in range(game.staff_states.size()):
    if str(game.staff_states[index].role)==role:row.portrait.set_member(index);break
   continue
  var reason=game.model.hire_reason(role)
  row.hire.text="Team full" if reason=="Team full" else "Hire · %s"%Money.amount(int(game.model.HIRE_FEES[role]))
  if active>desired:row.purpose.text="%d finishing, then off duty"%(active-desired)
  elif reason=="Add stove":row.purpose.text="Add stove to hire"
  elif reason=="Resume first":row.purpose.text="%d resting · resume free"%(count-active)
  elif reason=="Wages due":row.purpose.text="Pay wages before hiring"
  elif reason=="Not enough coins":row.purpose.text="Save %s coins to hire"%Money.amount(int(game.model.HIRE_FEES[role]))
  row.purpose.add_theme_color_override("font_color",WARNING if active>desired or reason in ["Add stove","Wages due","Not enough coins"] else MUTED)
  row.hire.disabled=reason!="" or game.save_recovery_blocked;row.hire.tooltip_text=reason if reason!="" else "One-time hire fee: %s coins"%Money.amount(int(game.model.HIRE_FEES[role]))
  row.rest.visible=desired>1;row.rest.disabled=game.save_recovery_blocked
  row.resume.visible=desired<count;row.resume.disabled=game.save_recovery_blocked or (role=="chef" and desired>=game.model.usable_stoves())
  row.resume.tooltip_text="Add a usable stove to resume" if row.resume.disabled and not game.save_recovery_blocked else "Back on duty · no fee"
  row.hire.accessibility_name="Hire "+role;row.rest.accessibility_name="Send one "+role+" off duty";row.resume.accessibility_name="Resume one "+role
  # Match this role's actual first employee, including older roster orders.
  for index in range(game.staff_states.size()):
   if str(game.staff_states[index].role)==role:
    row.portrait.set_member(index);break
func show():
 scroll.scroll_vertical=0
 game.settings.hide();sync();compact._popup_at(panel,PANEL_WIDTH);_fit();_queue_fit()
