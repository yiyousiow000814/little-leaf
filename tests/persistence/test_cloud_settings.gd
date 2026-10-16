extends SceneTree
const CloudSettings=preload("res://scripts/persistence/cafe_cloud_settings.gd")
class FakeApi extends RefCounted:
	var value={"status":"Not saved","reason":"","canSave":true,"reload":false,"uid":"SyntheticUidAbCdEf0123456789XY","copyStatus":""}
	var observer
	var copies=0
	func snapshot():return JSON.stringify(value)
	func watchUid(callback):observer=callback
	func unwatchUid():observer=null
	func copyUid():copies+=1;value.copyStatus="copying";observer.call([])
	func publish():observer.call([])
	func signOut():pass
	func reload():pass
class PendingWrite extends RefCounted:
	var pending=true
var failures=[]
var checks=0
func check(ok,label):
	checks+=1
	if not ok:failures.append(label);printerr(label)
func _init():call_deferred("run")
func run():
	root.size=Vector2i(390,844)
	var game=load("res://main.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.save_writes_suppressed=true;game.paused=true
	await process_frame;await process_frame
	var api=FakeApi.new();var cloud=CloudSettings.new(game);var box=cloud.build(api)
	var settings_box=game.settings_controls.panel.get_child(0)
	# Compact UI wraps the original Settings VBox inside its themed scroll area.
	settings_box=game.settings_controls.preference_storage_note.get_parent()
	settings_box.add_child(box);settings_box.move_child(box,settings_box.get_child_count()-2)
	cloud.attach_footer(settings_box)
	game.settings_controls.cloud_settings=cloud
	game.settings.hide();check(not box.is_visible_in_tree(),"Cloud controls must not cover gameplay")
	game.settings.show();game._update_ui();await process_frame;await process_frame
	settings_box.remove_child(box);check(api.observer==null,"Settings detaches its UID observer on tree exit")
	settings_box.add_child(box);check(api.observer!=null,"Settings restores its UID observer after compact-scroll reparenting")
	check(box.get_child_count()==2 and cloud.reason_label.get_index()>cloud.save_button.get_parent().get_index(),"No loose status line above the Save action")
	check(cloud.uid_box.get_parent()==settings_box and cloud.uid_box.get_index()>game.compact_ui.settings_help.get_index(),"UID belongs to the footer below primary Settings actions")
	check(not cloud.uid_action is Button and cloud.uid_action.accessibility_name=="Copy player UID" and cloud.uid_action.focus_mode==Control.FOCUS_ALL,"UID text has native keyboard activation without a separate visible button")
	check(cloud.uid_field.text==api.value.uid and cloud.uid_box.visible and cloud.uid_field.selection_enabled,"Full UID is selectable read-only account text")
	cloud.uid_action.pressed.emit()
	check(api.copies==1 and cloud.uid_action.disabled and cloud.uid_caption.text!="Copied","Copy waits for clipboard settlement")
	api.value.copyStatus="failed";api.publish()
	check(cloud.copy_note.visible and cloud.uid_field.get_selected_text()==api.value.uid and cloud.uid_caption.text!="Copied","Denied clipboard retains selected manual fallback without success")
	api.value.copyStatus="copied";api.publish()
	check(cloud.uid_caption.text=="Copied" and cloud.uid_action.accessibility_description=="Player UID copied" and not cloud.copy_note.visible,"Only confirmed clipboard success shows brief accessible feedback")
	cloud.copied_until_msec=0;cloud.sync();check(cloud.uid_caption.text=="Player UID","Copy feedback expires without restarting or changing identity")
	api.value.uid="";api.publish()
	check(not cloud.uid_box.visible and cloud.uid_field.text=="" and cloud.uid_action.disabled,"Account event immediately clears UID and copy action")
	api.value.uid="SyntheticUidAbCdEf0123456789XY";api.value.copyStatus="";api.publish()
	for state in ["Saved","Saving…","Not saved"]:
		api.value.status=state;game._update_ui()
		var expected="Saved" if state=="Saved" else ("Saving…" if state=="Saving…" else "Save")
		check(cloud.save_button.text==expected,"Button reflects authoritative state "+state)
		check(cloud.save_button.accessibility_name=="Save progress, "+state,"Accessible state remains available "+state)
	api.value.status="Saving…";cloud.sync();cloud.saved_until_msec=0;cloud.sync()
	check(cloud.save_button.text=="Saving…" and cloud.save_button.disabled,"Elapsed confirmation cannot turn pending into success or permit duplicate clicks")
	api.value.status="Saved";cloud.sync()
	check(cloud.save_button.text=="Saved" and not cloud.save_button.disabled,"Confirmed save gives brief success feedback")
	cloud.saved_until_msec=0;cloud.sync();cloud.sync()
	check(cloud.save_button.text=="Save" and cloud.last_status=="Saved","Confirmation expires without changing saved state or restarting")
	api.value.status="Saving…";cloud.sync();api.value.status="Saved";cloud.sync()
	check(cloud.save_button.text=="Saved","A later automatic save gets its own confirmed feedback")
	game.progress_unsaved=true;api.value.status="Saved";cloud.sync()
	check(cloud.save_button.text=="Save" and cloud.last_status=="Not saved" and cloud.reason_label.visible,"Unacknowledged local changes cannot say Saved")
	game.web_save=PendingWrite.new();cloud.sync()
	check(cloud.save_button.text=="Saving…" and cloud.save_button.disabled,"Local staging shows busy before the cloud bridge updates")
	game.web_save=null;cloud.sync()
	check(cloud.save_button.text=="Save" and cloud.last_status=="Not saved","Finishing local staging alone cannot claim cloud confirmation")
	game.progress_unsaved=false
	api.value={"status":"Not saved","reason":"Offline. Progress on this device will sync when connected.","canSave":true,"reload":false};cloud.sync();check(cloud.reason_label.visible and not cloud.reload_button.visible,"Offline reason remains visible in Settings")
	check(cloud.save_button.text=="Save" and cloud.reason_label.text==api.value.reason,"Offline does not become false success")
	api.value={"status":"Not saved","reason":"Another save changed. Pending progress preserved.","canSave":false,"reload":true};cloud.sync();check(cloud.save_button.disabled and cloud.reload_button.visible,"Conflict cannot overwrite and offers reload")
	api.value={"status":"Not saved","reason":"Saving is unavailable. Keep this page open and try again.","canSave":true,"reload":false};cloud.sync()
	check(cloud.reason_label.visible and cloud.reason_label.text==api.value.reason,"Failure details remain visible below actions")
	api.value={"status":"Saving…","reason":"","canSave":true,"reload":false};cloud.sync()
	api.value.uid="SyntheticUidAbCdEf0123456789XY";cloud.sync()
	for size in [Vector2i(360,680),Vector2i(390,844),Vector2i(844,390),Vector2i(1360,880)]:
		root.size=size;game._update_ui();await process_frame;await process_frame
		check(Rect2(Vector2.ZERO,Vector2(size)).encloses(game.settings.get_global_rect()),"Settings stays inside viewport "+str(size))
		for button in cloud.save_button.get_parent().get_children():
			check(button.size.y>=44 and button.get_global_rect().position.x>=game.settings.get_global_rect().position.x and button.get_global_rect().end.x<=game.settings.get_global_rect().end.x,"Account action has usable width/touch height "+str(size))
		check(cloud.uid_field.text==api.value.uid and cloud.uid_action.size.y>=44 and cloud.uid_action.get_global_rect().end.x<=game.settings.get_global_rect().end.x,"Full UID and invisible44px copy hit area fit Settings "+str(size))
	api.value.uid="x".repeat(128);api.publish();check(cloud.uid_field.text==api.value.uid,"Long UID is retained in full without ellipsis or substitution")
	api.value.uid="";api.publish();check(not cloud.uid_box.visible,"Guest/signed-out view never invents a UID")
	game.settings.hide();check(not box.is_visible_in_tree(),"Closing Settings hides all account controls")
	game.queue_free();await process_frame;await process_frame
	check(api.observer==null,"Freeing Settings removes its bridge callback")
	print("CLOUD_SETTINGS_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
