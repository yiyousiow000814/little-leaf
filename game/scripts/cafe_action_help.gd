extends RefCounted
## Transient keyboard/touch explanations for icon-only actions.
## A completed touch hold consumes release, so it cannot toggle the action.
var hud_ref:WeakRef
var hud:
 get:return hud_ref.get_ref()
var game
var panel:PanelContainer
var label:Label
var hint_tween:Tween
var holds={}
var fired={}
var before={}
var points={}
func _init(owner):hud_ref=weakref(owner);game=owner.game
func setup(buttons:Array):
 panel=PanelContainer.new();panel.add_theme_stylebox_override("panel",hud.texture_style("cream_face",12));panel.mouse_filter=Control.MOUSE_FILTER_IGNORE;panel.z_index=30;game.ui.add_child(panel)
 label=hud._label(panel,"",13);panel.hide()
 for button in buttons:_bind(button)
func hide():
 if is_instance_valid(hint_tween):hint_tween.kill()
 if is_instance_valid(panel):panel.hide()
func show(button:Button):
 if hud==null or not is_instance_valid(game) or not is_instance_valid(button):return
 hide();var words=button.accessibility_name if button.accessibility_name!="" else button.tooltip_text;label.text=words
 var view=game.get_viewport().get_visible_rect().size;var insets=hud._safe_insets()
 var w=minf(view.x-insets.x-insets.z-24,maxf(110,hud.font_bold.get_string_size(words,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x+24))
 panel.size=Vector2(w,38);var rect=button.get_global_rect();var y=rect.end.y+6
 if rect.position.y>view.y*.5:y=rect.position.y-44
 panel.position=Vector2(clampf(rect.get_center().x-w/2,insets.x+12,view.x-insets.z-w-12),maxf(insets.y+6,y));panel.show()
 hint_tween=game.create_tween();hint_tween.tween_interval(2.0)
 hint_tween.tween_callback(func():
  if is_instance_valid(panel):panel.hide())
func cancel(button:Button):
 var id=button.get_instance_id()
 if holds.has(id) and is_instance_valid(holds[id]):holds[id].kill()
func begin(button:Button,point:Vector2):
 if (game.get_viewport().get_visible_rect().size.x>=750 and not hud.layout_host.get_meta("mobile_layout",false)) or button.disabled:return
 var id=button.get_instance_id();cancel(button);hide();fired[id]=false;before[id]=button.button_pressed;points[id]=point
 var tween=game.create_tween();holds[id]=tween;tween.tween_interval(.5)
 tween.tween_callback(func():
  if hud==null or not is_instance_valid(button):return
  fired[id]=true;show(button))
func _bind(button:Button):
 button.focus_entered.connect(func():show(button));button.focus_exited.connect(hide);button.button_down.connect(hide)
 button.mouse_exited.connect(func():cancel(button))
 var original=[]
 for connection in button.pressed.get_connections():
  # Preserve special future signal semantics rather than wrapping them.
  if int(connection.flags)!=0:return
  original.append(connection.callable)
 for callback in original:button.pressed.disconnect(callback)
 button.pressed.connect(func():
  var id=button.get_instance_id()
  if bool(fired.get(id,false)):
   fired[id]=false;button.set_pressed_no_signal(bool(before.get(id,false)));hud.sync(game.get_viewport().get_visible_rect().size.x);return
  for callback in original:callback.call())
 button.gui_input.connect(func(event):
  if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
   if event.pressed:begin(button,event.position)
   else:cancel(button)
  elif event is InputEventScreenTouch:
   if event.pressed:begin(button,event.position)
   else:cancel(button)
  elif event is InputEventMouseMotion or event is InputEventScreenDrag:
   var id=button.get_instance_id()
   if points.has(id) and event.position.distance_to(points[id])>10:cancel(button))
