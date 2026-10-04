extends RefCounted
## Skin the existing status channel; the game still owns wording and lifetime.
var compact_ref:WeakRef
var compact:
 get:return compact_ref.get_ref()
var panel:PanelContainer
var label:Label
var issue_label:Label
var show_button:Button
var row:HBoxContainer
var normal_holder:MarginContainer
func _init(owner):compact_ref=weakref(owner)
func setup():
 panel=PanelContainer.new();panel.mouse_filter=Control.MOUSE_FILTER_IGNORE;compact.game.ui.add_child(panel);compact.hud.theme_panel(panel,false,10)
 row=HBoxContainer.new();row.add_theme_constant_override("separation",8);row.mouse_filter=Control.MOUSE_FILTER_IGNORE;panel.add_child(row)
 normal_holder=MarginContainer.new();normal_holder.mouse_filter=Control.MOUSE_FILTER_IGNORE;normal_holder.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(normal_holder)
 label=compact.game.status_text;label.reparent(normal_holder);label.custom_minimum_size=Vector2.ZERO;label.position=Vector2.ZERO
 label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;label.mouse_filter=Control.MOUSE_FILTER_IGNORE
 label.add_theme_color_override("font_color",compact.hud.INK);label.accessibility_live=DisplayServer.LIVE_POLITE
 issue_label=label.duplicate();issue_label.text="";row.add_child(issue_label);issue_label.hide()
 show_button=compact._small_button("Show",func():compact.game.workface_guidance.show_access_issue(),64);show_button.custom_minimum_size.y=44;show_button.tooltip_text="Show the blocked station and working tile";row.add_child(show_button);show_button.hide();panel.hide()
func sync_position():
 if compact==null or not is_instance_valid(compact.game) or not is_instance_valid(panel):return
 # Modal cards already show outcomes beside their actions. Persistent world
 # warnings remain authoritative and return after dismissal of the dialog.
 var guide=compact.game.workface_guidance
 var unsaved=compact.game._unsaved_progress_message() if compact.game.has_method("_unsaved_progress_message") else ""
 var save_warning=unsaved!=""
 var has_issue=not save_warning and guide!=null and not compact.viewport_too_small and not guide.current_access_issue().is_empty()
 panel.mouse_filter=Control.MOUSE_FILTER_STOP if has_issue or save_warning else Control.MOUSE_FILTER_IGNORE
 issue_label.visible=has_issue or save_warning;show_button.visible=has_issue
 issue_label.text=unsaved if save_warning else (guide.access_message() if has_issue else "")
 if has_issue:
  show_button.text="Next" if guide.access_issues.size()>1 and guide.focused_key!="" else "Show"
  show_button.tooltip_text=str(guide.current_access_issue().reason)
 normal_holder.visible=not has_issue and not save_warning
 # Keep the game-owned status label untouched; the issue row has its own text.
 var active=issue_label if has_issue or save_warning else label
 label.size_flags_horizontal=Control.SIZE_SHRINK_CENTER;issue_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 panel.visible=((save_warning or has_issue or (label.visible and not label.text.strip_edges().is_empty())) and not compact.has_open_popup())
 if not panel.visible:return
 var game=compact.game;var h=compact.hud;var view=game.get_viewport().get_visible_rect().size;var inset=h._safe_insets()
 var font=active.get_theme_font("font");var font_size=active.get_theme_font_size("font_size")
 var natural=font.get_string_size(active.text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
 var action_width=show_button.get_combined_minimum_size().x+8 if has_issue else 0.0
 var width=minf(maxf(120,natural+24+action_width),minf(420,view.x-inset.x-inset.z-32))
 var padding=panel.get_theme_stylebox("panel").get_minimum_size();var text_width=maxf(1,width-padding.x-action_width)
 var measured=font.get_multiline_string_size(active.text,HORIZONTAL_ALIGNMENT_CENTER,text_width,font_size,-1,TextServer.BREAK_MANDATORY|TextServer.BREAK_WORD_BOUND|TextServer.BREAK_ADAPTIVE)
 # Establish the real wrap width before a Container can measure a zero-width
 # label into one line per character. Explicit font metrics bound first paint.
 active.size.x=text_width;active.custom_minimum_size=Vector2(text_width,ceilf(measured.y));active.reset_size()
 var height=maxf(44 if has_issue else 40,ceilf(measured.y)+padding.y)
 panel.custom_minimum_size=Vector2(width,height);panel.reset_size();panel.size=Vector2(width,height)
 height=panel.size.y # Container minima may exceed the font estimate after wrapping.
 var x=inset.x+(view.x-inset.x-inset.z-width)/2;var y=view.y-inset.w-height-16
 if game.tray.visible and compact.tray_reveal>0:
  y=minf(y,game.tray.position.y-height-8)
  # Selection actions sit above the catalogue. A notice must clear their
  # actual animated bounds, including item name and disabled buttons.
  if compact.shop_ui!=null and is_instance_valid(compact.shop_ui.action_background):
   var board=compact.shop_ui.action_background
   if board.is_visible_in_tree():
    var actions=board.get_global_rect()
    if x<actions.end.x and x+width>actions.position.x:y=minf(y,actions.position.y-height-8)
 var top=h.layout_host.get_global_rect().end.y+8
 if y<top:panel.hide();return
 panel.position=Vector2(x,y);panel.modulate.a=1.0 if has_issue or save_warning else (minf(1.0,game.toast_lifetime/.42) if game.toast_lifetime>0 else 1.0)
 panel.accessibility_name=active.text
