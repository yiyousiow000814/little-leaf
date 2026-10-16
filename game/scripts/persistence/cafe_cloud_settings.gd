extends RefCounted
# Account controls live inside Settings; the bridge never exposes save payloads.
class UidAction extends BaseButton:
	var focus_style:StyleBoxFlat
	func _notification(what):
		if what in [NOTIFICATION_FOCUS_ENTER,NOTIFICATION_FOCUS_EXIT]:queue_redraw()
	func _draw():
		if has_focus() and focus_style!=null:draw_style_box(focus_style,Rect2(Vector2.ZERO,size))
var game
var api
var box:VBoxContainer
var last_status=""
var saved_until_msec=0
const SAVED_CONFIRMATION_MSEC=2000
var reason_label:Label
var save_button:Button
var reload_button:Button
var uid_box:VBoxContainer
var uid_field:RichTextLabel
var uid_action:UidAction
var uid_caption:Label
var uid_feedback:Label
var copy_note:Label
var uid_callback
var last_copy_status=""
var copied_until_msec=0
func _init(owner_game=null):
	game=owner_game
func build(test_api=null)->VBoxContainer:
	if test_api!=null:api=test_api
	elif OS.has_feature("web"):
		# Missing optional interfaces emit an engine error, so probe before lookup.
		if not JavaScriptBridge.eval("typeof window.LittleLeafCloudSettings === 'object' && window.LittleLeafCloudSettings !== null"):return null
		api=JavaScriptBridge.get_interface("LittleLeafCloudSettings")
	if api==null:return null
	box=VBoxContainer.new();box.name="CloudSaveSettings";box.add_theme_constant_override("separation",6)
	var actions=HBoxContainer.new();box.add_child(actions)
	save_button=game.button("Save",func():game._save();sync());actions.add_child(save_button)
	reload_button=game.button("Reload",func():api.reload());actions.add_child(reload_button)
	var sign_out=game.button("Sign out",func():api.signOut());actions.add_child(sign_out)
	for button in [save_button,reload_button,sign_out]:
		button.custom_minimum_size=Vector2(80,44);button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	reason_label=game.label("",12);reason_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;box.add_child(reason_label)
	uid_box=VBoxContainer.new();uid_box.add_theme_constant_override("separation",4);box.add_child(uid_box)
	var identity=MarginContainer.new();uid_box.add_child(identity)
	uid_action=UidAction.new();uid_action.custom_minimum_size=Vector2(44,44);uid_action.focus_mode=Control.FOCUS_ALL
	uid_action.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	uid_action.focus_style=game._style(Color.TRANSPARENT,Color("725237"),4);uid_action.focus_style.set_border_width_all(2)
	uid_action.accessibility_name="Copy player UID";uid_action.pressed.connect(func():api.copyUid();sync());identity.add_child(uid_action)
	var account=HBoxContainer.new();account.mouse_filter=Control.MOUSE_FILTER_IGNORE;account.add_theme_constant_override("separation",5);identity.add_child(account)
	uid_caption=game.label("UID:",11,Color("75644f"));uid_caption.size_flags_vertical=Control.SIZE_SHRINK_CENTER;account.add_child(uid_caption)
	uid_field=RichTextLabel.new();uid_field.selection_enabled=true;uid_field.fit_content=true;uid_field.scroll_active=false
	uid_field.size_flags_horizontal=Control.SIZE_EXPAND_FILL;uid_field.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	uid_field.autowrap_mode=TextServer.AUTOWRAP_ARBITRARY;uid_field.focus_mode=Control.FOCUS_ALL
	uid_field.add_theme_font_override("normal_font",uid_caption.get_theme_font("font"));uid_field.add_theme_font_size_override("normal_font_size",11)
	uid_field.add_theme_color_override("default_color",uid_caption.get_theme_color("font_color"))
	uid_field.accessibility_name="Player UID";account.add_child(uid_field)
	uid_feedback=game.label("",11,Color("75644f"));uid_feedback.size_flags_vertical=Control.SIZE_SHRINK_CENTER;account.add_child(uid_feedback)
	copy_note=game.label("",12);copy_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;uid_box.add_child(copy_note)
	box.tree_entered.connect(_watch_uid)
	box.tree_exiting.connect(_unwatch_uid)
	sync();return box
func attach_footer(parent:VBoxContainer):
	uid_box.reparent(parent)
func _watch_uid():
	uid_callback=JavaScriptBridge.create_callback(_uid_changed) if OS.has_feature("web") else _uid_changed
	api.watchUid(uid_callback);sync()
func _unwatch_uid():
	api.unwatchUid();uid_callback=null
func _uid_changed(_args):
	sync()
func _public_uid(value)->String:
	if not value is String or value.length()!=12:return ""
	if value.unicode_at(0)<49 or value.unicode_at(0)>57:return ""
	for index in range(1,12):
		if value.unicode_at(index)<48 or value.unicode_at(index)>57:return ""
	return value
func sync():
	if api==null or not is_instance_valid(box):return
	var value=JSON.parse_string(str(api.snapshot()))
	if not value is Dictionary:return
	var public_status=str(value.get("publicUidStatus",""))
	var uid=_public_uid(value.get("publicUid")) if public_status=="ready" else ""
	uid_box.visible=public_status in ["loading","ready","unavailable"]
	if uid_field.text!=uid:uid_field.text=uid;last_copy_status="";copied_until_msec=0
	uid_field.visible=uid!=""
	var copy_status=str(value.get("copyStatus","")) if uid!="" else ""
	var now=Time.get_ticks_msec()
	if copy_status!=last_copy_status:
		copied_until_msec=now+SAVED_CONFIRMATION_MSEC if copy_status=="copied" else 0
		last_copy_status=copy_status
	var copied=copy_status=="copied" and now<copied_until_msec
	uid_feedback.text=("Loading..." if public_status=="loading" else "Unavailable") if uid=="" else ("Copied" if copied else ("Copying..." if copy_status=="copying" else ""))
	uid_feedback.visible=uid_feedback.text!=""
	uid_action.disabled=uid=="" or copy_status=="copying"
	uid_action.tooltip_text=("UID loading" if public_status=="loading" else "UID unavailable") if uid=="" else ("Player UID copied" if copied else "Click or tap UID to copy")
	uid_action.accessibility_description=uid_action.tooltip_text
	uid_field.mouse_filter=Control.MOUSE_FILTER_STOP if copy_status=="failed" else Control.MOUSE_FILTER_IGNORE
	var note="Could not copy. Select the UID and copy it manually." if copy_status=="failed" else ""
	if note!=copy_note.text and note!="":uid_field.grab_focus();uid_field.select_all()
	copy_note.text=note;copy_note.visible=note!=""
	var status=str(value.get("status","Not saved"))
	if status not in ["Saved","Saving…","Not saved"]:status="Not saved"
	if game.progress_unsaved and status=="Saved":status="Not saved"
	# Local staging starts before the cloud bridge publishes its pending state.
	if game.web_save!=null and game.web_save.pending:status="Saving…"
	if status!=last_status:
		# Only an authoritative Saved transition starts this confirmation. Time
		# merely restores the action label; it never changes the save state.
		saved_until_msec=now+SAVED_CONFIRMATION_MSEC if status=="Saved" else 0
		last_status=status
	save_button.text="Saving…" if status=="Saving…" else ("Saved" if status=="Saved" and now<saved_until_msec else "Save")
	reason_label.text=str(value.get("reason",""))
	if status=="Not saved" and reason_label.text=="":reason_label.text="Changes have not been saved yet."
	reason_label.visible=reason_label.text!=""
	save_button.accessibility_name="Save progress, "+status
	save_button.accessibility_description=reason_label.text
	reload_button.visible=bool(value.get("reload",false))
	save_button.disabled=status=="Saving…" or not bool(value.get("canSave",false)) or game.save_recovery_blocked
