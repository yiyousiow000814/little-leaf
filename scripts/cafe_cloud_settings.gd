extends RefCounted
# Account controls live inside Settings; the bridge never exposes save payloads.
var game
var api
var box:VBoxContainer
var status_label:Label
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
	status_label=game.label("Not saved",15);box.add_child(status_label)
	reason_label=game.label("",12);reason_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;box.add_child(reason_label)
	var actions=HBoxContainer.new();box.add_child(actions)
	save_button=game.button("Save",func():game._save();sync());actions.add_child(save_button)
	reload_button=game.button("Reload",func():api.reload());actions.add_child(reload_button)
	var sign_out=game.button("Sign out",func():api.signOut());actions.add_child(sign_out)
	for button in [save_button,reload_button,sign_out]:
		button.custom_minimum_size=Vector2(80,44);button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	sync();return box
func sync():
	if api==null or not is_instance_valid(box):return
	var value=JSON.parse_string(str(api.snapshot()))
	if not value is Dictionary:return
	status_label.text=str(value.get("status","Not saved"))
	if status_label.text not in ["Saved","Saving…","Not saved"]:status_label.text="Not saved"
	if game.progress_unsaved and status_label.text=="Saved":status_label.text="Not saved"
	reason_label.text=str(value.get("reason",""));reason_label.visible=reason_label.text!=""
	reload_button.visible=bool(value.get("reload",false))
	save_button.disabled=not bool(value.get("canSave",false)) or game.save_recovery_blocked
