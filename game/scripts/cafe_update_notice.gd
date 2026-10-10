extends RefCounted
## Optional, nonmodal update banner. Release discovery and reload stay in its bridge.
var ui_ref:WeakRef
var ui:
 get:return ui_ref.get_ref()
var game
var api
var panel:PanelContainer
var message:Label
var reason:Label
var update_button:Button
var later_button:Button
var version=""
var started=false
func _init(owner):
 ui_ref=weakref(owner);game=owner.game
func setup(test_api=null):
 api=test_api
 if api==null and OS.has_feature("web"):
  if JavaScriptBridge.eval("typeof window.LittleLeafUpdate === 'object' && typeof window.LittleLeafUpdate.snapshot === 'function'"):
   api=JavaScriptBridge.get_interface("LittleLeafUpdate")
 panel=PanelContainer.new();panel.name="UpdateAvailableNotice";panel.z_index=40
 panel.add_theme_stylebox_override("panel",game._style(Color("fff8e7"),Color("bcb18b"),10));game.ui.add_child(panel)
 var box=VBoxContainer.new();box.add_theme_constant_override("separation",6);panel.add_child(box)
 message=game.label("Update available",15);message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;box.add_child(message)
 reason=game.label("",12);reason.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;box.add_child(reason);reason.hide()
 var actions=HBoxContainer.new();actions.add_theme_constant_override("separation",8);box.add_child(actions)
 update_button=ui._small_button("Save and update",_update,0);later_button=ui._small_button("Later",_later,0)
 for button in [update_button,later_button]:
  button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;button.add_theme_font_size_override("font_size",14);button.custom_minimum_size=Vector2(0,44);button.clip_text=true;actions.add_child(button)
 panel.get_child(0).minimum_size_changed.connect(func():_fit_notice.call_deferred())
 panel.resized.connect(_position_notice)
 panel.hide()
 if api!=null:
  api.start(str(ProjectSettings.get_setting("application/config/version","")));started=true
func sync():
 if api==null or not is_instance_valid(panel):return
 var snapshot=JSON.parse_string(str(api.snapshot()))
 if not snapshot is Dictionary:return
 version=str(snapshot.get("version",""))
 var busy=bool(snapshot.get("busy",false)) or (game.web_save!=null and game.web_save.update_busy)
 panel.visible=(bool(snapshot.get("available",false)) or busy) and not (game.save_recovery_blocked and ui.help_panel.visible)
 if not panel.visible:return
 message.text="Saving before update…" if busy else "Update available"
 reason.text=str(snapshot.get("reason",""))
 if game.web_save!=null and game.web_save.update_message!="":reason.text=game.web_save.update_message
 reason.visible=reason.text!=""
 update_button.disabled=busy or game.web_save==null or game.save_recovery_blocked or not game.web_save.ready or game.web_save.pending or game.web_save.recovery_busy
 later_button.disabled=busy
 _fit_notice()
func _fit_notice():
 if not is_instance_valid(panel) or ui==null:return
 var view=game.get_viewport().get_visible_rect().size;var inset=ui.hud._safe_insets()
 var width=minf(380,view.x-inset.x-inset.z-24)
 var minimum=update_button.get_theme_font("font").get_string_size(update_button.text,HORIZONTAL_ALIGNMENT_LEFT,-1,update_button.get_theme_font_size("font_size")).x+24
 for button in [update_button,later_button]:button.custom_minimum_size.x=minimum
 var padding=panel.get_theme_stylebox("panel").get_minimum_size()
 var inner=maxf(0,width-padding.x)
 message.size.x=inner;reason.size.x=inner
 panel.get_child(0).size.x=inner
 panel.size=Vector2(width,0)
 _position_notice()
func _position_notice():
 if not is_instance_valid(panel) or ui==null:return
 var view=game.get_viewport().get_visible_rect().size;var inset=ui.hud._safe_insets()
 panel.position=Vector2(view.x-inset.z-panel.size.x-12,minf(ui.hud.layout_host.get_global_rect().end.y+8,view.y-inset.w-panel.size.y-12))
func _later():
 if api==null or later_button.disabled:return
 api.dismiss(version)
 if game.web_save!=null:game.web_save.update_message=""
 sync()
func _update():
 if update_button.disabled or game.web_save==null:return
 game.web_save.save_and_update(version)
 sync()
