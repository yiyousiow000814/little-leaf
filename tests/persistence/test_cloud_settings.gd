extends SceneTree
const CloudSettings=preload("res://scripts/persistence/cafe_cloud_settings.gd")
class FakeApi extends RefCounted:
	var value={"status":"Not saved","reason":"","canSave":true,"reload":false}
	func snapshot():return JSON.stringify(value)
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
	game.settings_controls.cloud_settings=cloud
	game.settings.hide();check(not box.is_visible_in_tree(),"Cloud controls must not cover gameplay")
	game.settings.show();game._update_ui();await process_frame;await process_frame
	check(box.get_child_count()==2 and cloud.reason_label.get_index()>cloud.save_button.get_parent().get_index(),"No loose status line above the Save action")
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
	for size in [Vector2i(360,680),Vector2i(390,844),Vector2i(844,390),Vector2i(1360,880)]:
		root.size=size;game._update_ui();await process_frame;await process_frame
		check(Rect2(Vector2.ZERO,Vector2(size)).encloses(game.settings.get_global_rect()),"Settings stays inside viewport "+str(size))
		for button in cloud.save_button.get_parent().get_children():
			check(button.size.y>=44 and button.get_global_rect().position.x>=game.settings.get_global_rect().position.x and button.get_global_rect().end.x<=game.settings.get_global_rect().end.x,"Account action has usable width/touch height "+str(size))
	game.settings.hide();check(not box.is_visible_in_tree(),"Closing Settings hides all account controls")
	print("CLOUD_SETTINGS_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	game.queue_free();await process_frame;await process_frame
	quit(0 if failures.is_empty() else 1)
