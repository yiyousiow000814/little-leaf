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
	sync();return box
func sync():
	if api==null or not is_instance_valid(box):return
	var value=JSON.parse_string(str(api.snapshot()))
	if not value is Dictionary:return
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
