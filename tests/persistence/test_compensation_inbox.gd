extends SceneTree
const WebSave=preload("res://scripts/cafe_web_save.gd")
const CAMPAIGN="little-leaf-0.1.5-existing-profile-compensation"
const PROFILE="11111111-1111-4111-8111-111111111111"
const TEST_NOW=1770086400000.0
class DeniedMarkers extends RefCounted:
 var notice="Read status may return after reload because browser storage is unavailable."
 var persisted=false
 func visibleSnapshotJson(raw,_persist):return raw
 func isRead(_profile,_campaign,_revision):return false
 func markRead(_profile,_campaign,_revision,persist):persisted=persist;return true
class TestMain extends "res://scripts/main.gd":
 var save_calls=0
 func _load_startup():
  save_writes_suppressed=true;fresh_start=false;MinimalStart.apply(model);model.coins=43000
  web_save=WebSave.new(self)
  web_save.inbox_snapshot={"ok":true,"profileId":"11111111-1111-4111-8111-111111111111","revision":2,"paid":[],"deferred":[]}
 func _save():save_calls+=1;return true
var game
var checks=0
var failures=[]
var capture_dir=""
var web_points={}
var web_regions={}
func _initialize():
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--capture-dir="):capture_dir=arg.trim_prefix("--capture-dir=")
 call_deferred("run")
func check(ok:bool,message:String):
 checks+=1
 if not ok:failures.append(message);printerr("FAIL ",message)
func settle():
 game._update_ui();await process_frame;await process_frame;await process_frame
func capture(label:String):
 if capture_dir=="":return
 await settle();await RenderingServer.frame_post_draw
 check(root.get_texture().get_image().save_png(capture_dir.path_join(label+".png"))==OK,"capture "+label)
func point(control:Control)->Array:
 var center=control.get_global_rect().get_center();return [center.x,center.y]
func region(control:Control)->Array:
 var bounds=control.get_global_rect();return [bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y]
func button_text_region(button:Button)->Array:
 var font=button.get_theme_font("font");var font_size=button.get_theme_font_size("font_size")
 var measured=font.get_string_size(button.text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size)
 var bounds=Rect2(button.get_global_rect().get_center()-measured*.5,measured).grow(6)
 return [bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y]
func paid(id=CAMPAIGN,revision=1,coins=1000)->Dictionary:
 return {"id":id,"revision":revision,"coins":coins,"grantedAt":1770000000000+revision,"status":"granted"}
func text(node:Node)->String:
 var result=str(node.text) if node is Label or node is Button else ""
 for child in node.get_children():result+="\n"+text(child)
 return result
func run():
 root.size=Vector2i(1360,880)
 game=TestMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false);game.paused=true
 await settle()
 var ui=game.compact_ui;var inbox=ui.inbox
 inbox.clock=func():return TEST_NOW
 inbox.native_high_water=TEST_NOW
 check(not inbox.panel.visible and not ui.has_open_popup(),"Inbox never opens automatically")
 check(ui.settings_inbox.get_index()<ui.settings_help.get_index(),"Settings places Inbox above Help")
 web_points.settings=point(ui.settings_button)
 game.settings.show();await settle()
 web_points.inbox=point(ui.settings_inbox)
 web_regions.settings=button_text_region(ui.settings_inbox)
 game.settings.hide()
 var money=game.model.coins;var snapshot=JSON.stringify(game.web_save.inbox_snapshot)
 inbox.show();await settle()
 check("No letters for now" in text(inbox.body),"empty state is English and visible")
 check(not inbox.has_unread(),"empty Inbox has no unread message")
 await capture("01-empty-desktop")
 game.web_save.inbox_snapshot.paid=[paid("retired-other-compensation",2,200),paid()]
 inbox.show();await settle()
 web_points.first_message=point(inbox.rows[0])
 web_points.back_to_settings=point(inbox.back_button)
 check(inbox.rows.size()==2 and "Café compensation" in text(inbox.rows[0]) and "2 Feb 2026" in text(inbox.rows[0]),"receipt order, envelope title and delivery date are shown")
 check(inbox.has_unread(),"retained paid history starts unread")
 check(inbox.rows[0].unread and inbox.rows[1].unread,"opening list consumes no messages")
 check(game.save_calls==0 and game.model.coins==money,"opening history never credits or saves")
 check(ui.settings_button.get_node("UpdateUnreadDot").visible,"existing Settings button uses a single combined badge")
 await capture("02-history-desktop")
 inbox.rows[1].pressed.emit();await settle()
 web_points.back_to_inbox=point(inbox.back_button)
 web_regions.detail=region(inbox.letter_body)
 check("Paid · Added to your wallet" in text(inbox.body) and "1,000 Leaf Coins" in text(inbox.body) and "Dear café owner," in text(inbox.body) and "0.1.5 update" in text(inbox.body) and "Warmly,\nLittle Leaf" in text(inbox.body),"paid letter has a reason, exact amount, salutation and sign-off")
 check(inbox.has_unread(),"only chosen detail becomes read")
 await capture("03-paid-detail-desktop")
 inbox.back_button.pressed.emit();await settle()
 check(inbox.rows[0].unread and not inbox.rows[1].unread,"reopen preserves one-message read state")
 inbox.rows[0].pressed.emit();inbox.back_button.pressed.emit();await settle()
 check(not inbox.has_unread(),"all paid details can be acknowledged independently")
 inbox.back_button.pressed.emit();await settle()
 check(game.settings.visible and not inbox.panel.visible,"Back returns to Settings")
 game.web_save.inbox_snapshot.revision=3;ui.sync();inbox.show();await settle()
 check(not inbox.has_unread(),"autosave revision does not re-mark existing grant unread")
 game.web_save.inbox_snapshot.profileId="22222222-2222-4222-8222-222222222222";ui.sync();inbox.show();await settle()
 check(inbox.has_unread(),"read status is separated by profile")
 game.web_save.inbox_snapshot={"ok":true,"profileId":PROFILE,"revision":5,"paid":[],"deferred":[{"id":CAMPAIGN,"coins":1000,"reason":"wallet_cap"}]}
 inbox.show();await settle()
 check(inbox.rows.is_empty() and "Compensation pending" in text(inbox.body) and not "Paid ·" in text(inbox.body),"pending eligibility is a status, never a dated delivered letter")
 check(not inbox.has_unread(),"pending eligibility is not a paid unread receipt")
 await capture("04-deferred-desktop")
 game.web_save.inbox_snapshot={"ok":true,"profileId":PROFILE,"revision":6,"paid":[paid(CAMPAIGN,6)],"deferred":[]}
 inbox.show();await settle()
 check(inbox.has_unread(),"pending eligibility cannot suppress later paid receipt")
 web_points.first_message=point(inbox.rows[0])
 await capture("05-one-letter-desktop")
 web_regions.list=region(inbox.heading_box)
 for size in [Vector2i(800,600),Vector2i(390,844),Vector2i(844,390)]:
  root.size=size;await settle();inbox.show();await settle()
  check(inbox.panel.get_global_rect().end.x<=size.x+.5 and inbox.panel.position.x>=0,"horizontal bounds at "+str(size))
  check(inbox.panel.get_global_rect().end.y<=size.y+.5,"vertical bounds at "+str(size))
  await capture("05-history-"+str(size.x)+"x"+str(size.y))
  inbox.rows[0].pressed.emit();await settle()
  check(inbox.letter_body.get_global_rect().position.x-inbox.letter_paper.get_global_rect().position.x>=21.5 and inbox.letter_paper.get_global_rect().end.x-inbox.letter_body.get_global_rect().end.x>=21.5,"real paper margins at "+str(size))
  check(not inbox.scroll.get_h_scroll_bar().visible,"letter never scrolls horizontally at "+str(size))
  await capture("06-detail-"+str(size.x)+"x"+str(size.y))
 root.size=Vector2i(390,844);game.set_meta("hud_safe_insets",Vector4(14,30,14,28));await settle();inbox.show();await settle()
 check(inbox.panel.position.x>=14 and inbox.panel.position.y>=30 and inbox.panel.get_global_rect().end.x<=376 and inbox.panel.get_global_rect().end.y<=816,"Inbox respects safe insets")
 await capture("07-safe-insets")
 game.remove_meta("hud_safe_insets");await settle()
 var history=[]
 for i in 30:history.append(paid("archived-campaign-%03d"%i,i+1,999999999))
 game.web_save.inbox_snapshot={"ok":true,"profileId":PROFILE,"revision":30,"paid":history,"deferred":[]}
 inbox.show();await settle()
 check(inbox.rows.size()==30 and inbox.scroll.get_v_scroll_bar().visible,"long retained history scrolls")
 check(inbox.rows[0].get_node("EnvelopePadding").get_theme_constant("margin_left")==64 and inbox.rows[0].get_node("EnvelopePadding").get_theme_constant("margin_right")==28,"envelope content has real internal margins")
 var tab=InputEventKey.new();tab.keycode=KEY_TAB;tab.pressed=true
 for i in 35:
  check(ui.handle_input(tab),"Inbox captures keyboard focus step "+str(i))
  check(inbox.panel.is_ancestor_of(game.get_viewport().gui_get_focus_owner()),"keyboard stays inside Inbox "+str(i))
 inbox.scroll.scroll_vertical=0;await settle();await capture("07-long-list-portrait")
 check(inbox.back_button.get_global_rect().end.y<=inbox.panel.get_global_rect().end.y and inbox.back_button.get_global_rect().position.y>=inbox.scroll.get_global_rect().end.y,"long lists retain a visible Back button outside scrolling letters")
 root.size=Vector2i(1360,880);inbox.show();await settle();await capture("07-long-list-desktop")
 root.size=Vector2i(390,844);inbox.show();await settle()
 inbox.scroll.scroll_vertical=0;await settle()
 var pointer=InputEventMouseButton.new();pointer.button_index=MOUSE_BUTTON_LEFT;pointer.position=inbox.rows[0].get_global_rect().get_center();pointer.pressed=true;pointer.button_mask=MOUSE_BUTTON_MASK_LEFT
 Input.parse_input_event(pointer);await process_frame
 pointer=pointer.duplicate();pointer.pressed=false;pointer.button_mask=0;Input.parse_input_event(pointer);await settle()
 check(inbox.detail_id=="archived-campaign-000","real GUI pointer activates the intended message")
 inbox.show();await settle()
 var esc=InputEventKey.new();esc.keycode=KEY_ESCAPE;esc.pressed=true
 check(ui.handle_input(esc) and not ui.has_open_popup(),"Escape dismisses Inbox through shared modal route")
 inbox.show();await settle();ui.show_help();await settle()
 check(ui.help_panel.visible and not inbox.panel.visible,"Help and Inbox are mutually exclusive")
 inbox.show();await settle()
 var press=InputEventScreenTouch.new();press.index=0;press.position=Vector2(2,root.size.y-2);press.pressed=true
 check(ui.handle_input(press) and not ui.has_open_popup(),"outside touch dismisses Inbox")
 press.pressed=false;check(ui.consume_modal_dismissal(press),"dismissing touch release cannot click through world")
 inbox.api=DeniedMarkers.new();inbox.show();await settle();inbox.rows[0].pressed.emit();await settle()
 check(inbox.storage_note.visible and "after reload" in inbox.storage_note.text,"denied read-status storage has inline explanation")
 check(not inbox.api.persisted,"review and write-suppression modes never request persistence")
 await capture("08-storage-denied-portrait")
 inbox.api=null
 # Real elapsed time drives retention, independently from simulation time.
 game.web_save.inbox_snapshot={"ok":true,"profileId":PROFILE,"revision":2,"paid":[paid()],"deferred":[]}
 var expiry=float(paid().grantedAt)+inbox.RETENTION_MSEC
 inbox.native_high_water=TEST_NOW;inbox.clock=func():return expiry-1
 inbox.show();await settle();check(inbox.rows.size()==1,"letter remains for the full 14 real days")
 inbox.rows[0].pressed.emit();await settle()
 inbox.clock=func():return expiry
 inbox.last_refresh_second=-1;inbox.sync();await settle()
 check(inbox.detail_id=="" and inbox.rows.is_empty() and not inbox.has_unread(),"exact 14-day boundary removes an open letter and its unread state")
 for size in [Vector2i(1360,880),Vector2i(390,844)]:
  root.size=size;inbox.show();await settle();await capture("09-expired-"+str(size.x)+"x"+str(size.y))
 inbox.clock=func():return TEST_NOW
 inbox.show();await settle()
 check(inbox.rows.is_empty(),"backward wall clock does not resurrect expired native presentation")
 check(game.web_save.inbox_snapshot.paid.size()==1,"expiry retains the original authoritative receipt projection")
 game.web_save.inbox_snapshot={"ok":true,"profileId":PROFILE,"revision":0,"paid":[],"deferred":[]}
 inbox.show();await settle();await capture("10-empty-portrait")
 game.web_save.inbox_snapshot={"ok":false};inbox.show();await settle()
 check("letters are unavailable" in text(inbox.body),"unavailable authority has honest history state")
 await capture("08-unavailable-portrait")
 check(game.model.coins==money and game.save_calls==0,"all Inbox interactions leave wallet and saves unchanged")
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 # Let the audio thread release the synthetic click playback before shutdown.
 await create_timer(.12).timeout
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;await process_frame
 var result={"checks":checks,"failures":failures,"native_synthetic_only":true,"web_input_points":web_points,"web_visible_regions":web_regions}
 if OS.get_environment("LL_UI_RESULT")!="":
  var file=FileAccess.open(OS.get_environment("LL_UI_RESULT"),FileAccess.WRITE);file.store_string(JSON.stringify(result))
 print("COMPENSATION_INBOX_RESULT ",JSON.stringify(result))
 quit(0 if failures.is_empty() else 1)
