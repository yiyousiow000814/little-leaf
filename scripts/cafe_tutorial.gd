extends Node
## A non-modal guide to real controls and real service. This script never
## creates guests, completes jobs, pays coins, edits a layout or moves camera.
const State=preload("res://scripts/cafe_tutorial_state.gd")
var game
var panel:PanelContainer
var box:VBoxContainer
var progress:Label
var heading:Label
var copy:Label
var actions:HBoxContainer
var skip_button:Button
var finish_button:Button
var next_button:Button
var pointer:Control
var target_rect=Rect2()
var target_control:Control
var help_entry:Button
var restart_entry:Button
var _last_text=""
var _tick=0.0
func setup(owner):
 game=owner;game.add_child(self)
 panel=PanelContainer.new();panel.name="FirstDayTutorial";panel.z_index=80;game.ui.add_child(panel)
 # A real opaque surface with explicit content margins. No stretched picture
 # frame whose visible paper begins inside its nominal Control rectangle.
 var surface=StyleBoxFlat.new();surface.bg_color=Color("faf7ec");surface.border_color=Color("bdc9af");surface.set_border_width_all(1);surface.set_corner_radius_all(14)
 surface.content_margin_left=14;surface.content_margin_right=14;surface.content_margin_top=10;surface.content_margin_bottom=10
 surface.shadow_color=Color(0.20,0.25,0.15,.12);surface.shadow_size=6;surface.shadow_offset=Vector2(0,3)
 panel.add_theme_stylebox_override("panel",surface)
 var row=HBoxContainer.new();row.add_theme_constant_override("separation",12);panel.add_child(row)
 box=VBoxContainer.new();box.add_theme_constant_override("separation",2);box.size_flags_vertical=Control.SIZE_SHRINK_CENTER;row.add_child(box)
 heading=game.label("",16);heading.hide();box.add_child(heading)
 copy=game.label("",16,Color("4e6045"));copy.add_theme_font_override("font",game.compact_ui.hud.font_bold);copy.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;copy.mouse_filter=Control.MOUSE_FILTER_IGNORE;box.add_child(copy)
 progress=game.label("",11,Color("65745b"));progress.mouse_filter=Control.MOUSE_FILTER_IGNORE;box.add_child(progress)
 actions=HBoxContainer.new();actions.add_theme_constant_override("separation",0);actions.size_flags_vertical=Control.SIZE_SHRINK_CENTER;row.add_child(actions)
 skip_button=_quiet_button("Skip",skip);actions.add_child(skip_button)
 next_button=_quiet_button("Next",next);actions.add_child(next_button)
 finish_button=_quiet_button("Done",finish);actions.add_child(finish_button)
 pointer=Control.new();pointer.name="TutorialControlHighlight";pointer.mouse_filter=Control.MOUSE_FILTER_IGNORE;pointer.z_index=79;game.ui.add_child(pointer);pointer.draw.connect(_draw_pointer)
 var content=game.compact_ui.help_scroll.get_child(0)
 help_entry=game.compact_ui._small_button("Play tutorial",resume,160);content.add_child(help_entry);content.move_child(help_entry,0);game.compact_ui.hud.theme_button(help_entry,true)
 restart_entry=game.compact_ui._small_button("Restart tutorial",restart,160);content.add_child(restart_entry);content.move_child(restart_entry,1);game.compact_ui.hud.theme_button(restart_entry)
 if game.fresh_start and not game.save_recovery_blocked and not "--skip-tutorial" in OS.get_cmdline_user_args():
  game.model.tutorial_state=State.begin(game.model.served)
  game.model.set_operating_open(false)
  game._update_ui()
 sync()
func _quiet_button(text:String,callback:Callable)->Button:
 var button=Button.new();button.text=text;button.pressed.connect(callback);button.custom_minimum_size=Vector2(44,44)
 button.add_theme_font_override("font",game.compact_ui.hud.font_bold);button.add_theme_font_size_override("font_size",12)
 for state in ["normal","hover","pressed","hover_pressed","focus"]:
  var style=StyleBoxFlat.new();style.set_corner_radius_all(9);style.bg_color=Color(0,0,0,0) if state=="normal" else Color("e7eddd");style.content_margin_left=6;style.content_margin_right=6
  if state=="focus":style.bg_color=Color(0,0,0,0);style.border_color=Color("839974");style.set_border_width_all(2)
  button.add_theme_stylebox_override(state,style)
 for state in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color"]:button.add_theme_color_override(state,Color("5d7051"))
 return button
func owns_pointer(event:InputEvent)->bool:
 return panel.visible and (event is InputEventMouseButton or event is InputEventScreenTouch) and panel.get_global_rect().has_point(event.position)
func active()->bool:return game.model.tutorial_state.get("status","")=="active"
func step()->int:return int(game.model.tutorial_state.get("step",State.OPEN))
func _process(delta):
 # Event conditions are cheap; layout work is bounded and no idle draw pulse.
 _tick+=delta
 if _tick<.1:return
 _tick=0.0;sync()
func _commit():
 game.model.changed.emit()
 if game.cafe_intro==null or not game.cafe_intro.active:game._save()
func _advance(next:int):
 game.model.tutorial_state.step=next;_commit()
func resume():
 if game.save_recovery_blocked:return
 if game.model.tutorial_state.is_empty() or game.model.tutorial_state.get("status")=="completed":
  game.model.tutorial_state=State.begin(game.model.served)
 else:game.model.tutorial_state.status="active"
 _open_guide()
func restart():
 if game.save_recovery_blocked:return
 game.model.tutorial_state=State.begin(game.model.served);_open_guide()
func _open_guide():
 game.settings.hide();game.compact_ui._hide_popups();game.compact_ui.sync()
 if game.cafe_intro!=null:game.cafe_intro.finish()
 _commit();sync()
func skip():
 if not active() or game.save_recovery_blocked:return
 # The action label explicitly says Open when the cafe is closed. Skipping
 # the very first step must not leave an unexplained empty, closed cafe.
 game.model.tutorial_state.status="skipped"
 if not game.model.operating_open:game._toggle_business()
 else:_commit()
 sync()
func finish():
 if not active() or step()!=State.COMPLETE or game.save_recovery_blocked:return
 game.model.tutorial_state.status="completed";_commit();sync()
func next():
 if not active() or game.save_recovery_blocked:return
 # Explanation advances metadata only, even while service is paused/closed.
 # Saved ORDER/PAYMENT step IDs keep their format-1 continuation meaning.
 if step()==State.ORDER:_advance(State.PAYMENT)
 elif step()==State.PAYMENT:_advance(State.COMPLETE)
 sync()
func _advance_from_reality():
 match step():
  State.OPEN:
   if game.model.operating_open:_advance(State.STAFF)
  State.STAFF:
   if game.compact_ui.staff_panel.panel.visible:_advance(State.STAFF_DONE)
  State.STAFF_DONE:
   if not game.compact_ui.staff_panel.panel.visible:_advance(State.DECORATE)
  State.DECORATE:
   if game.editing:_advance(State.DONE)
  State.DONE:
   if not game.editing:_advance(State.ORDER)
func sync():
 if not is_instance_valid(panel):return
 var state=game.model.tutorial_state
 help_entry.text="Resume tutorial" if state.get("status","") in ["active","skipped"] else ("Replay tutorial" if state.get("status","")=="completed" else "Play tutorial")
 var help_restricted=game.save_recovery_blocked
 if not help_restricted and game.compact_ui.help_panel.visible and game.web_save!=null and game.web_save.has_method("recovery_snapshot"):
  var recovery=game.web_save.recovery_snapshot()
  help_restricted=bool(recovery.get("available",false)) or bool(recovery.get("busy",false)) or bool(recovery.get("ownershipPaused",false))
 help_entry.visible=not help_restricted
 restart_entry.visible=not help_restricted and state.get("status","") in ["active","skipped"]
 help_entry.disabled=help_restricted;restart_entry.disabled=help_restricted
 var intro=game.cafe_intro!=null and game.cafe_intro.active
 var visible=active() and not intro and not game.save_recovery_blocked and not game.compact_ui.viewport_too_small
 if visible:_advance_from_reality()
 # Other menus remain fully usable. The guide reappears after they close.
 var staff_open=game.compact_ui.staff_panel.panel.visible
 visible=visible and (not game.compact_ui.has_open_popup() or (staff_open and step()==State.STAFF_DONE))
 panel.visible=visible;pointer.visible=visible
 target_control=null;target_rect=Rect2()
 if not visible:return
 var title="";var words="";var number=1
 match step():
  State.OPEN:
   number=1;words="Tap to open";target_control=game.business_button
  State.STAFF:
   number=2;words="Meet your team";target_control=game.compact_ui.staff_access
  State.STAFF_DONE:
   number=2;words="Ready? Tap Done";target_control=game.compact_ui.staff_panel.done_button
  State.DECORATE:
   number=3;words="Try Decorate";target_control=game.edit_button
  State.DONE:
   number=3;words="Back to café";target_control=game.edit_button
  State.ORDER:
   number=4;words="Your team cooks and serves meals."
  State.PAYMENT:
   number=5;words="Guests pay at checkout."
  State.COMPLETE:
   number=6;words="You're ready to run your café!"
 if step() in [State.OPEN,State.STAFF,State.DECORATE] and game.editing:
  words="Tap Done to continue";target_control=game.edit_button
 title=words
 if target_control!=null:target_rect=target_control.get_global_rect().grow(3)
 var text_key=title+"\n"+words+str(number)+str(step())+str(game.model.operating_open)
 if text_key!=_last_text:
  panel.accessibility_name=title;panel.accessibility_description=words
  _last_text=text_key;progress.text="%d / 6"%number;heading.text=title;copy.text=words
  skip_button.text="Skip" if game.model.operating_open else "Skip & open"
  skip_button.visible=step()!=State.COMPLETE;finish_button.visible=step()==State.COMPLETE
  next_button.visible=step() in [State.ORDER,State.PAYMENT]
 _layout();pointer.queue_redraw()
func content_rect()->Rect2:
 var style=panel.get_theme_stylebox("panel")
 return Rect2(panel.position+Vector2(style.content_margin_left,style.content_margin_top),panel.size-style.get_minimum_size())
func _layout():
 var view=game.get_viewport().get_visible_rect().size;var inset=game.compact_ui.hud._safe_insets()
 var top=game.compact_ui.hud.layout_host.get_global_rect().end.y+10
 var bottom=view.y-inset.w-12
 if game.editing:bottom=minf(bottom,game.compact_ui.shop_ui.browse_rect().position.y-10)
 var safe=Rect2(inset.x+12,top,view.x-inset.x-inset.z-24,maxf(0,bottom-top))
 var padding=panel.get_theme_stylebox("panel").get_minimum_size()
 var text_width=ceilf(copy.get_theme_font("font").get_string_size(copy.text,HORIZONTAL_ALIGNMENT_LEFT,-1,16).x)
 var action_width=maxf(44,actions.get_combined_minimum_size().x)
 var width=minf(safe.size.x,text_width+action_width+12+padding.x)
 var inner=maxf(80,width-action_width-12-padding.x)
 copy.custom_minimum_size.x=inner;copy.size.x=inner;box.custom_minimum_size.x=inner
 panel.size=Vector2(width,0)
 var origin=Vector2(safe.get_center().x-panel.size.x*.5,safe.position.y)
 if target_rect.size!=Vector2.ZERO and Rect2(Vector2.ZERO,view).intersects(target_rect):
  origin=Vector2(target_rect.get_center().x-panel.size.x*.5,maxf(safe.position.y,target_rect.end.y+12))
  if origin.y+panel.size.y>safe.end.y:origin.y=target_rect.position.y-panel.size.y-12
 origin.x=clampf(origin.x,safe.position.x,maxf(safe.position.x,safe.end.x-panel.size.x))
 origin.y=clampf(origin.y,safe.position.y,maxf(safe.position.y,safe.end.y-panel.size.y))
 panel.position=origin;pointer.size=view
func _draw_pointer():
 if target_rect.size==Vector2.ZERO:return
 var view=game.get_viewport().get_visible_rect()
 if not view.intersects(target_rect) or panel.get_global_rect().intersects(target_rect):return
 var outline=StyleBoxFlat.new();outline.bg_color=Color(.48,.61,.39,.035);outline.border_color=Color("839974");outline.set_border_width_all(2);outline.set_corner_radius_all(12)
 pointer.draw_style_box(outline,target_rect)
 var rect=panel.get_global_rect();var x=clampf(target_rect.get_center().x,rect.position.x+20,rect.end.x-20)
 var below=rect.position.y>=target_rect.end.y
 var y=rect.position.y if below else rect.end.y
 var direction=-1 if below else 1
 var tip=Vector2(x,y+7*direction)
 var target=Vector2(target_rect.get_center().x,target_rect.end.y+3 if below else target_rect.position.y-3)
 if tip.distance_to(target)>3:pointer.draw_line(tip,target,Color("bdc9af"),1.5,true)
 var points=PackedVector2Array([Vector2(x-7,y),tip,Vector2(x+7,y)])
 pointer.draw_colored_polygon(points,Color("faf7ec"));pointer.draw_polyline(points,Color("bdc9af"),1.0,true)
