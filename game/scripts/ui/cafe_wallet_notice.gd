extends RefCounted
## Transient cash events only. The model remains the sole owner of amounts.
const Money=preload("res://scripts/gameplay/cafe_money.gd")
var compact_ref:WeakRef
var compact:
 get:return compact_ref.get_ref()
var panel:PanelContainer
var text:Label
var active={}
var pending=[]
var remaining=0.0
var elapsed=0.0
var natural_width=110.0
var content_width=0.0
const HOLD=2.4
func _init(owner):compact_ref=weakref(owner)
func setup(surface:PanelContainer,label:Label):
 panel=surface;text=label;compact.hud.theme_panel(panel,false,8)
 panel.custom_minimum_size=Vector2(110,44);panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
 var row=HBoxContainer.new();row.alignment=BoxContainer.ALIGNMENT_CENTER;row.add_theme_constant_override("separation",6);row.mouse_filter=Control.MOUSE_FILTER_IGNORE;panel.add_child(row)
 text.reparent(row);text.add_theme_font_override("font",compact.hud.font_bold);text.add_theme_font_size_override("font_size",15);text.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;text.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 text.accessibility_live=DisplayServer.LIVE_POLITE
 var coin=compact.hud._picture(row,compact.hud._texture("coin"));coin.custom_minimum_size=Vector2(22,22);coin.size_flags_vertical=Control.SIZE_SHRINK_CENTER;row.move_child(coin,0)
 content_width=panel.get_theme_stylebox("panel").get_minimum_size().x+row.get_theme_constant("separation")+coin.custom_minimum_size.x
 panel.resized.connect(compact.hud._sync_stats)
 panel.visibility_changed.connect(compact.hud._sync_stats)
 panel.hide()
func show_earned(amount:int):
 if amount>0:_push("earned",amount)
func show_wages(amount:int):
 if amount>0:_push("wages",amount)
func show_due(amount:int):
 if amount>0:_push("due",amount)
func _push(kind:String,amount:int):
 if active.is_empty():_start({"kind":kind,"amount":amount});return
 if str(active.kind)==kind:
  active.amount=amount if kind=="due" else int(active.amount)+amount
  if pending.is_empty():remaining=HOLD
  _copy();return
 # Three event kinds form a bounded queue. Coalesce same-kind events without
 # netting wages against revenue or discarding a charge behind frequent income.
 for notice in pending:
  if str(notice.kind)==kind:
   notice.amount=amount if kind=="due" else int(notice.amount)+amount;return
 pending.append({"kind":kind,"amount":amount})
func _start(notice:Dictionary):
 active=notice;remaining=HOLD;elapsed=0.0;panel.modulate.a=1.0;_copy();sync_position()
func _copy():
 if active.is_empty():return
 var amount=Money.amount(int(active.amount));var kind=str(active.kind)
 text.text=("+"+amount+" earned") if kind=="earned" else (("Wages −"+amount) if kind=="wages" else ("Wages due "+amount))
 text.add_theme_color_override("font_color",Color("45674b") if kind=="earned" else Color("87573c"))
 panel.accessibility_name=text.text;panel.accessibility_description="Recorded income" if kind=="earned" else ("Paid team wages" if kind=="wages" else "Team wages owed; paid from later income")
 natural_width=maxf(110.0,ceilf(text.get_theme_font("font").get_string_size(text.text,HORIZONTAL_ALIGNMENT_LEFT,-1,text.get_theme_font_size("font_size")).x)+content_width)
 panel.size=Vector2.ZERO
 compact.earnings_amount=int(active.amount) if kind=="earned" else 0;compact.earnings_seconds=remaining
func tick(delta:float):
 if compact==null:return
 var can_show=not compact.has_open_popup()
 panel.visible=not active.is_empty() and can_show
 if active.is_empty():return
 # Defer the notice while a panel covers its wallet anchor; never cover Staff
 # or Settings and never lose the entire event while those panels are open.
 if not can_show:return
 elapsed+=maxf(0,delta);remaining=maxf(0,remaining-delta);compact.earnings_seconds=remaining
 if remaining<=0:
  active={};panel.hide();compact.earnings_amount=0
  if not pending.is_empty():_start(pending.pop_front())
  return
 panel.modulate.a=minf(1.0,remaining/.42);sync_position()
func sync_position():
 if compact==null or not is_instance_valid(compact.game) or not is_instance_valid(panel):return
 panel.visible=not active.is_empty() and not compact.has_open_popup()
 var h=compact.hud;var view=compact.game.get_viewport().get_visible_rect().size;var inset=h._safe_insets()
 var anchor=h.wallet.get_global_rect();var width=natural_width
 # Keep the complete amount below its balance, clear of the wrapped action row.
 if h.layout_host.get_meta("unified_wrapped",false):
  var available=compact.game.edit_button.get_global_rect().position.x-(inset.x+8)-6
  width=minf(width,maxf(110.0,available))
 var wrap=TextServer.AUTOWRAP_WORD_SMART if width<natural_width else TextServer.AUTOWRAP_OFF
 if text.autowrap_mode!=wrap or not is_equal_approx(panel.custom_minimum_size.x,width):
  text.autowrap_mode=wrap;panel.custom_minimum_size=Vector2(width,44)
  # Container minimum sizes settle after the label changes its wrapping mode.
  panel.reset_size.call_deferred()
 var lift=0.0 if h._reduced_motion_requested() else 4.0*(1.0-clampf(elapsed/.16,0.0,1.0))
 panel.position=Vector2(clampf(anchor.get_center().x-width/2,inset.x+8,maxf(inset.x+8,view.x-inset.z-width-8)),anchor.end.y+6+lift)
