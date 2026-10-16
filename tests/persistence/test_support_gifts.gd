extends SceneTree
## Synthetic game scene: gifted stock uses the real Decorate planner and Inbox UI.
const Model=preload("res://scripts/core/cafe_model.gd")
const Plan=preload("res://scripts/gameplay/cafe_edit_plan.gd")
const WebSave=preload("res://scripts/persistence/cafe_web_save.gd")
const PROFILE="11111111-1111-4111-8111-111111111111"
const MAIL="aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa"
class TestMain extends "res://scripts/main.gd":
 func _load_startup():
  save_writes_suppressed=true;fresh_start=false;MinimalStart.apply(model)
  web_save=WebSave.new(self)
  web_save.inbox_snapshot={"ok":true,"profileId":PROFILE,"revision":2,"paid":[],"deferred":[]}
 func _save():return true
class DelayedLookup extends "res://scripts/ui/cafe_support_mail.gd":
 var pending:Array=[]
 func _call(name:String,_args:Array,handler:Callable):
  if name=="lookup":pending.append(handler)
var checks=0
var failures=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func run():
 root.size=Vector2i(1360,880)
 var m=Model.new();m.items.clear();m.dining_sets.clear();m.customers.clear();m.gift_stock={"plant":2};m.coins=500
 m.begin_decoration_session()
 var plan=Plan.new();var before=m.coins
 var receipt=plan.prepare(m,"plant",-1,0,Vector2i(5,4),[],true)
 check(bool(receipt.get("ok",false)) and plan.commit(m,receipt),"gift uses the real placement planner")
 check(m.coins==before and int(m.gift_stock.plant)==1 and m.decoration_gifts.size()==1,"staging uses one gift and no coins")
 var id=int(m.items[-1].id)
 check(m.logical_refund(id)==0 and m.remove(id),"staged gift removal grants no coins")
 check(m.coins==before and int(m.gift_stock.plant)==2 and m.decoration_gifts.is_empty(),"staged gift returns to stock")
 check(m.place_gift("plant",5,4),"gift can stage again")
 var gift_baseline=m._decoration_baseline.duplicate(true)
 var staged_count=m.decoration_gifts.size()
 var candidate_saved=m.save_finished_decoration("user://synthetic-gift-finish.json")
 check(candidate_saved and m.decoration_session_active and m._decoration_baseline==gift_baseline and m.decoration_gifts.size()==staged_count,"validated candidate save keeps the live gift draft and Cancel baseline")
 check(m.cancel_decoration_session() and m.decoration_gifts.is_empty() and int(m.gift_stock.plant)==2,"Cancel restores the stock baseline")
 check(not m.place_gift("plant",5,4),"gift cannot place outside Decorate")
 var game=TestMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false)
 game.web_save.profile_id=PROFILE;game.web_save.revision=2;game.web_save.ready=true
 var stock_json=JSON.parse_string('{"profileId":"%s","revision":2.0,"stock":{"schema":1.0,"counts":{"plant":1.0,"stove":0.0}}}'%PROFILE)
 check(game.web_save.accept_gift_stock(stock_json) and game.model.gift_stock.plant is int and game.model.gift_stock.plant==1,"real JSON numeric boundary accepts integral gift counts")
 var future_json=JSON.parse_string('{"profileId":"%s","revision":3.0,"stock":{"schema":1.0,"counts":{"plant":2.0}}}'%PROFILE)
 check(not game.web_save.accept_gift_stock(future_json) and game.web_save.accept_gift_stock(future_json,null,3),"placement ACK accepts its next revision only")
 var fractional_json=JSON.parse_string('{"profileId":"%s","revision":2.0,"stock":{"schema":1.0,"counts":{"plant":1.5}}}'%PROFILE)
 check(not game.web_save.accept_gift_stock(fractional_json),"fractional gift stock is rejected")
 var ui=game.compact_ui;game.model.gift_stock={"plant":2};game.editing=true
 check(not ui.support_mail.entry.visible and not ui.support_mail.panel.visible,"owner compose entry defaults hidden")
 game.model.begin_decoration_session();game._set_catalog_category("Gifts");game._update_ui()
 await process_frame;await process_frame
 var categories=ui.shop_ui.category_scroll.get_global_rect()
 check(categories.encloses(game.category_buttons.Gifts.get_global_rect()) and categories.encloses(game.category_buttons.Build.get_global_rect()),"desktop category rail keeps Gifts and Build inside its clickable viewport")
 var edit_stock=JSON.parse_string('{"profileId":"%s","revision":2.0,"stock":{"schema":1.0,"counts":{"plant":2.0}}}'%PROFILE)
 check(game.web_save.accept_gift_stock(edit_stock) and int(game.model._decoration_baseline.gift_stock.plant)==2,"stock arriving during Decorate updates the cancellation baseline")
 check(ui.shop_ui!=null and game.gift_cards.plant.visible and game.gift_counts.plant.text=="Gift ×2","Gifts shelf shows verified stock")
 game.gift_cards.plant.pressed.emit()
 check(game.selected_gift and game.selected_kind=="plant","Gifts shelf selects gift placement")
 ui.support_mail.mail_snapshot={"ok":true,"profileId":PROFILE,"mail":[{"schema":1,"mailId":MAIL,"title":"A small gift","body":"Thank you for your report.","coins":50,"items":[{"catalogId":"plant","quantity":1}],"issuedAt":1770000000000.0,"status":"unclaimed"}]}
 game.web_save.inbox_snapshot={"ok":false}
 ui.inbox.show();await process_frame;await process_frame
 check(ui.inbox.rows.size()==1 and ui.inbox.has_unread(),"support letter appears without a legacy paid-receipt projection")
 ui.inbox.rows[0].pressed.emit();await process_frame
 check("Thank you for your report." in _text(ui.inbox.letter_body),"support letter opens in Inbox")
 check("Claim attachments" in _text(ui.inbox.footer),"unclaimed gifts keep the real claim action in the fixed footer")
 check(ui.inbox.MailFrame.inner_rect(ui.inbox.panel).encloses(ui.inbox.footer.get_global_rect()) and ui.inbox.MailFrame.inner_rect(ui.inbox.panel).encloses(ui.inbox.heading_box.get_global_rect()),"Inbox heading/actions stay inside the wood face")
 check(ui.inbox.panel.get_theme_stylebox("panel") is StyleBoxTexture and ui.inbox.WIDTH==460,"Inbox restores its original wood frame and width")
 check(ui.inbox.has_unread()==false,"reading does not claim or retain unread dot")
 var tab=InputEventKey.new();tab.keycode=KEY_TAB;tab.pressed=true
 ui.inbox.scroll.grab_focus();ui.inbox.handle_input(tab)
 check(game.get_viewport().gui_get_focus_owner()==ui.inbox.focus_actions[0],"Tab reaches Claim without activating it")
 var older=[]
 for i in range(20):older.append({"schema":1,"mailId":"%08d-aaaa-4aaa-aaaa-aaaaaaaaaaaa"%i,"title":"Older letter %d"%i,"issuedAt":1770000000000.0,"status":"unclaimed"})
 ui.support_mail.mail_snapshot={"ok":true,"profileId":PROFILE,"mail":older,"nextCursor":"another-page"};ui.support_mail.mail_page=4
 ui.inbox.sync()
 check(ui.inbox.rows.size()==20 and "Latest support letters" in _text(ui.inbox.content) and "Load older support letters" in _text(ui.inbox.content),"page beyond 60 letters retains forward and latest navigation with 20-row memory")
 game.save_writes_suppressed=false;game.web_save.pending=true;game.web_save._support_claim_mail_id=MAIL
 game.web_save.request_save()
 check(game.web_save.pending and game.web_save.queued and game.web_save._support_claim_mail_id==MAIL,"pagehide or autosave queues behind an active claim without clearing its identity")
 game.web_save.pending=false;game.web_save.queued=false;game.web_save._support_claim_mail_id="";game.save_writes_suppressed=true
 ui._hide_popups();ui.support_mail.entry.visible=true;ui.support_mail.show()
 check(ui.support_mail.panel.visible and ui.support_mail.gift_catalog.entries.size()==10 and ui.support_mail.result_slots.size()==4 and ui.support_mail.send_button.disabled,"synthetic capability exposes bounded composer with Send gated by preview")
 var composer=ui.support_mail
 # Exercise the actual lookup callback without a Web bridge or live account.
 var delayed=DelayedLookup.new(ui);delayed.setup();delayed.recipient.text="123456789012"
 var lookup_result={"ok":true,"publicUid":"123456789012","profileId":PROFILE,"revision":2,"timeSource":"synthetic","device":"fixture","evidence":"No live data."}
 delayed._lookup();var late_all:Callable=delayed.pending.pop_front();delayed._set_recipient_mode("all")
 var all_summary=delayed.lookup_summary.text
 late_all.call(lookup_result)
 check(delayed.found.is_empty() and delayed.lookup_summary.text==all_summary,"late single-UID lookup success cannot overwrite All players")
 late_all.call({"ok":false,"error":"Late lookup failure"})
 check(delayed.lookup_summary.text==all_summary,"late lookup failure cannot overwrite All players")
 delayed._set_recipient_mode("selected");delayed._lookup();var late_roundtrip:Callable=delayed.pending.pop_front()
 delayed._set_recipient_mode("all");delayed._set_recipient_mode("selected")
 late_roundtrip.call(lookup_result)
 check(delayed.found.is_empty() and delayed.lookup_summary.text=="No player checked yet.","mode round trip with the same UID still invalidates old lookup")
 delayed._lookup();var late_edit:Callable=delayed.pending.pop_front()
 delayed.recipient.text="234567890123";delayed.recipient.text_changed.emit()
 var edited_summary=delayed.lookup_summary.text
 late_edit.call(lookup_result);late_edit.call({"ok":false,"error":"Late lookup failure"})
 check(delayed.found.is_empty() and delayed.lookup_summary.text==edited_summary,"recipient edit fences stale success and failure")
 delayed.recipient.text="123456789012";delayed.recipient.text_changed.emit()
 delayed._lookup();var superseded:Callable=delayed.pending.pop_front()
 delayed._lookup();var latest:Callable=delayed.pending.pop_front();latest.call(lookup_result)
 var latest_summary=delayed.lookup_summary.text
 superseded.call({"ok":false,"error":"Older request failed"})
 check(delayed.found==lookup_result and delayed.lookup_summary.text==latest_summary,"newest single-UID lookup succeeds and older error is ignored")
 delayed._lookup();var during_edit:Callable=delayed.pending.pop_front()
 delayed.subject.text="Continue writing while checking";delayed.subject.text_changed.emit(delayed.subject.text)
 during_edit.call(lookup_result)
 check(delayed.found==lookup_result,"unrelated message editing does not invalidate a recipient lookup")
 delayed.entry.queue_free();delayed.panel.queue_free();delayed=null
 check(composer._utf16_units("🍃") == 2 and composer._utf16_units("Letter 🍃")==9,"client counts emoji as two UTF-16 units like the service")
 composer.recipient.text="123456789012";composer.found={"publicUid":"123456789012","profileId":PROFILE}
 composer.case_id.text="case-20";composer.subject.text="S".repeat(100);composer.letter.text="🍃".repeat(1000);composer.coins.value=1
 composer._refresh_message_feedback()
 check(composer._field_error()=="" and "2000/2000" in composer.message_feedback.text,"exact service subject and letter bounds remain usable")
 composer.subject.text+="S";composer._preview()
 check("Shorten the subject" in composer.note.text and composer.preview_payload.is_empty() and composer.issue_id=="","overlong subject cannot request a preview or allocate an issue")
 composer.subject.text="Thank you";composer.letter.text+="🍃";composer._preview()
 check("Shorten the letter" in composer.note.text and composer.preview_payload.is_empty(),"overlong emoji letter cannot request a preview")
 composer.letter.text="A note";composer.case_id.text="bad/case"
 check("case reference" in composer._field_error(),"client rejects the service's case-reference format")
 composer.case_id.text="case-20";composer.recipient.text="023456789012"
 check("12-digit" in composer._field_error(),"client rejects an invalid public UID")
 composer.recipient.text="123456789012";composer.subject.text="A little thank-you";composer.letter.text="A long letter for our café owner.\n".repeat(30)
 composer.letter.grab_focus();composer.handle_input(tab)
 check(game.get_viewport().gui_get_focus_owner()==composer.preview_button,"Tab leaves multiline editor for review in visual order")
 for i in 22:
  composer.handle_input(tab)
  check(composer.panel.is_ancestor_of(game.get_viewport().gui_get_focus_owner()),"composer keyboard focus remains inside "+str(i))
 composer.recipient.text="123456789012, 234567890123\n123456789012"
 composer._refresh_audience_feedback()
 check("2 unique UIDs" in composer.audience_feedback.text and "1 duplicate removed" in composer.audience_feedback.text,"batch paste reports unique UIDs separately from unconfirmed players")
 check("server audience service" in composer._field_error() and composer._request().is_empty(),"batch mode cannot fall back to issuing one selected UID")
 composer._set_recipient_mode("all")
 check(not composer.recipient_input.visible and "count not confirmed" in composer.audience_feedback.text,"all players hides UID paste and never fabricates a recipient count")
 check(composer._request().is_empty() and composer.send_button.disabled,"unimplemented all-player service fails closed")
 composer._set_recipient_mode("selected")
 composer.recipient.text="123456789012"
 composer._set_gift_quantity("plant",2)
 composer.item_toggle.pressed.emit();composer.item_toggle.pressed.emit()
 check(not composer.item_picker.visible and int(composer.quantities.plant)==2 and "2 items" in composer.selected_title.text,"collapsing item choices retains selected gifts and count")
 composer.item_picker.show()
 var supported_rows=composer.gift_catalog.entries.duplicate(true)
 var large_rows:Array=[]
 for i in 125:large_rows.append({"id":"fixture_%03d"%i,"name":"Fixture item %03d"%i,"category":"Kitchen" if i%2==0 else "Decor"})
 composer.gift_catalog.configure(large_rows);composer.result_page=0;composer._refresh_gift_results()
 check(composer.result_slots.size()==4 and composer.gift_grid.get_child_count()==4 and "125 items" in composer.result_page_label.text,"125 display entries retain four result controls, not 125 widgets")
 check(composer.result_slots.all(func(slot):return slot.add.disabled),"unsupported display fixtures never become grantable items")
 composer.gift_search.text="item 124";composer.gift_search.text_changed.emit(composer.gift_search.text)
 check(composer.result_slots[0].id=="fixture_124" and "1 items" in composer.result_page_label.text,"multi-token search finds the last of 125 entries")
 composer.gift_search.text="no matching item";composer.gift_search.text_changed.emit(composer.gift_search.text)
 check(composer.result_empty.visible and composer.result_slots.all(func(slot):return not slot.card.visible),"empty search hides stale catalogue results")
 composer.gift_catalog.configure(supported_rows);composer.gift_search.text="";composer.gift_search.text_changed.emit("")
 for kind in ["stove","sink","lamp","divider"]:composer._set_gift_quantity(kind,1)
 composer._move_selected_page(1)
 check(composer.selected_slots.size()==3 and composer.selected_page==1 and composer.selected_slots[0].id!="","selected basket is separately paged without another scroller")
 var removed_id=str(composer.selected_slots[0].id);composer._remove_selected(0)
 check(not composer.quantities.has(removed_id),"basket remove clears only its selected item")
 check("Storage" in _text(composer.item_toggle.get_parent()),"mail item destination uses Storage, not a Gifts shelf")
 for viewport in [Vector2i(1360,880),Vector2i(390,844),Vector2i(844,390)]:
  root.size=viewport
  for i in 8:await process_frame
  check(Rect2(Vector2.ZERO,Vector2(viewport)).encloses(composer.panel.get_global_rect()),"composer fits safe viewport "+str(viewport))
  var wood=composer.MailFrame.inner_rect(composer.panel)
  check(wood.encloses(composer.header.get_global_rect()) and wood.encloses(composer.footer.get_global_rect()) and wood.encloses(composer.scroll.get_global_rect()),"header, footer and scroller stay within actual wood face "+str(viewport))
  check(composer.letter.size.y>500 and not composer.letter.get_v_scroll_bar().visible,"long letter expands without an editor scrollbar "+str(viewport))
  check(composer.scroll.get_v_scroll_bar().visible,"form owns long-content scroll "+str(viewport))
  check(composer.send_button.get_global_rect().position.y>=composer.scroll.get_global_rect().end.y,"send stays below scrolling content "+str(viewport))
  composer._move_result_page(99)
  for i in 3:await process_frame
  composer.scroll.ensure_control_visible(composer.result_next)
  for i in 3:await process_frame
  check(composer.scroll.get_global_rect().encloses(composer.result_next.get_global_rect()),"last gift page controls reachable "+str(viewport))
  check(composer.selected_slots.filter(func(slot):return slot.card.visible).all(func(slot):return slot.minus.size.x>=44 and slot.minus.size.y>=44 and slot.plus.size.x>=44 and slot.plus.size.y>=44),"selected quantity tap targets remain 44px "+str(viewport))
  check("1 Leaf Coins" in composer.attachment_summary.text and composer.attachment_summary.get_global_rect().position.y>=composer.scroll.get_global_rect().end.y,"per-player attachment total remains outside the scroller "+str(viewport))
 composer.scroll.scroll_vertical=0;composer.preview_summary.text="Confirm this synthetic letter.";composer.preview_card.show();composer._reveal_review()
 for i in 4:await process_frame
 check(composer.scroll.get_global_rect().intersects(composer.preview_card.get_global_rect()),"review waits for layout and reveals the new card")
 print("SUPPORT_GIFTS_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"synthetic_only":true}))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;await process_frame;quit(0 if failures.is_empty() else 1)
func _text(node:Node)->String:
 var result=str(node.text) if node is Label or node is Button else ""
 for child in node.get_children():result+="\n"+_text(child)
 return result
