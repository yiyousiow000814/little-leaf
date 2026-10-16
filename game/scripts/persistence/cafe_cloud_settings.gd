extends RefCounted
# Account controls live inside Settings; the bridge never exposes save payloads.
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
var copy_button:Button
var copy_note:Label
var uid_callback
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
	var identity=HBoxContainer.new();uid_box.add_child(identity)
	var uid_title=game.label("Player UID",13);uid_title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;identity.add_child(uid_title)
	copy_button=game.button("Copy",func():api.copyUid();sync());copy_button.custom_minimum_size=Vector2(80,44)
	copy_button.accessibility_name="Copy player UID";identity.add_child(copy_button)
	uid_field=RichTextLabel.new();uid_field.selection_enabled=true;uid_field.fit_content=true;uid_field.scroll_active=false
	uid_field.autowrap_mode=TextServer.AUTOWRAP_ARBITRARY;uid_field.focus_mode=Control.FOCUS_ALL
	uid_field.add_theme_font_override("normal_font",uid_title.get_theme_font("font"));uid_field.add_theme_font_size_override("normal_font_size",13)
	uid_field.add_theme_color_override("default_color",uid_title.get_theme_color("font_color"))
	uid_field.accessibility_name="Player UID";uid_box.add_child(uid_field)
	copy_note=game.label("",12);copy_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;uid_box.add_child(copy_note)
	box.tree_entered.connect(_watch_uid)
	box.tree_exiting.connect(_unwatch_uid)
	sync();return box
func _watch_uid():
	uid_callback=JavaScriptBridge.create_callback(_uid_changed) if OS.has_feature("web") else _uid_changed
	api.watchUid(uid_callback);sync()
func _unwatch_uid():
	api.unwatchUid();uid_callback=null
func _uid_changed(_args):
	sync()
func sync():
	if api==null or not is_instance_valid(box):return
	var value=JSON.parse_string(str(api.snapshot()))
	if not value is Dictionary:return
	var uid=str(value.get("uid",""))
	uid_box.visible=uid!=""
	if uid_field.text!=uid:uid_field.text=uid
	var copy_status=str(value.get("copyStatus","")) if uid!="" else ""
	copy_button.disabled=uid=="" or copy_status=="copying"
	copy_button.text="Copied" if copy_status=="copied" else ("Copying..." if copy_status=="copying" else "Copy")
	var note="Could not copy. Select the UID and copy it manually." if copy_status=="failed" else ""
	if note!=copy_note.text and note!="":uid_field.grab_focus();uid_field.select_all()
	copy_note.text=note;copy_note.visible=note!=""
	var status=str(value.get("status","Not saved"))
	if status not in ["Saved","Saving…","Not saved"]:status="Not saved"
	if game.progress_unsaved and status=="Saved":status="Not saved"
	# Local staging starts before the cloud bridge publishes its pending state.
	if game.web_save!=null and game.web_save.pending:status="Saving…"
	var now=Time.get_ticks_msec()
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
