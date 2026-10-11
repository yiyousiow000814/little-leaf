extends RefCounted
const SaveLog=preload("res://scripts/cafe_save_log.gd")
var compact_ref:WeakRef
var compact:
 get:return compact_ref.get_ref()
var panel:PanelContainer
var log_text:TextEdit
var copy_button:Button
var copy_note:Label
var back_button:Button
var waiting_for_copy=false

func _init(owner):compact_ref=weakref(owner)

func setup():
 var game=compact.game
 panel=compact._panel();panel.name="SaveLogPanel"
 var body=VBoxContainer.new();body.add_theme_constant_override("separation",9);panel.add_child(body)
 body.add_child(game.label("Log",22))
 var notice=game.label("This session only. Copy before refreshing or closing. Submitted saves are still pending.",13)
 notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;body.add_child(notice)
 log_text=TextEdit.new();log_text.name="SaveLogText";log_text.editable=false;log_text.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY
 log_text.custom_minimum_size=Vector2(0,220);log_text.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 log_text.add_theme_font_size_override("font_size",12);log_text.add_theme_font_override("font",game.ArtFont)
 log_text.add_theme_stylebox_override("read_only",game._style(Color("f8f2df"),Color("d9dcc4"),8))
 log_text.add_theme_color_override("font_readonly_color",Color("554631"));log_text.add_theme_color_override("selection_color",Color("c6d3b6"))
 log_text.accessibility_name="Read-only save diagnostic events"
 body.add_child(log_text)
 copy_button=game.button("Copy log",_copy);copy_button.name="CopySaveLog";copy_button.custom_minimum_size.y=44;body.add_child(copy_button)
 copy_note=game.label("",12);copy_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;copy_note.hide();body.add_child(copy_note)
 back_button=game.button("Back to Help",_back);back_button.custom_minimum_size.y=44;body.add_child(back_button)
 compact.hud.theme_panel(panel,true,26);compact.hud.theme_panel_contents(panel);compact._wrap_themed_popup(panel,420)
 var refresh=Timer.new();refresh.wait_time=0.5;refresh.timeout.connect(_refresh);panel.add_child(refresh);refresh.start()
 panel.hide()

func make_menu_entry()->Button:
 var entry=compact.game.button("Log",show);entry.name="SaveLogEntry";entry.custom_minimum_size.y=44;entry.accessibility_name="Log"
 compact.hud.theme_button(entry)
 return entry

func show():
 compact.game.settings.hide();compact._popup_at(panel,420)
 log_text.text=SaveLog.text();copy_note.hide();waiting_for_copy=false
 compact._queue_popup_fit()

func _refresh():
 if not is_instance_valid(panel) or not panel.visible:return
 var value=SaveLog.text()
 if value!=log_text.text:
  var scroll=log_text.scroll_vertical;log_text.text=value;log_text.scroll_vertical=scroll
 if waiting_for_copy:
  var status=SaveLog.copy_status()
  if status!="pending":_show_copy_status(status)

func _copy():
 log_text.text=SaveLog.text()
 _show_copy_status(SaveLog.copy())

func _show_copy_status(status:String):
 waiting_for_copy=status=="pending"
 copy_note.text="Copying…" if waiting_for_copy else "Log copied" if status=="copied" else "Copy unavailable. Select the log text and copy manually."
 if status not in ["pending","copied"]:
  log_text.grab_focus();log_text.select_all()
 copy_note.show();compact._queue_popup_fit()

func _back():
 panel.hide();compact.return_to_help(compact.help_log)
