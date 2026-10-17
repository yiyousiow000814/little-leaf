extends SceneTree
## Existing mail UI with canonical Storage claim installation, generated profiles only.
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
class CaptureMail extends "res://scripts/ui/cafe_support_mail.gd":
 # Only transport is synthetic. Production setup, layout and render methods run.
 func _call(name:String,args:Array,handler:Callable):
  if name=="preview":
   var result:Dictionary=args[0].duplicate(true)
   result.ok=true;result.status="ready";result.previewHash="synthetic-capture-review"
   result.recipientCount=72 if result.audience.mode=="all" else result.audience.publicUids.size()
   result.preparedCount=result.recipientCount;result.expiresAt=floor(Time.get_unix_time_from_system()*1000.0)+60000.0
   result.captureStartedAt=1792224000123;result.captureCompletedAt=1792224005456
   result.totals={"coins":int(result.coins)*int(result.recipientCount),"items":[]}
   for item in result.items:result.totals.items.append({"catalogId":item.catalogId,"quantity":int(item.quantity)*int(result.recipientCount)})
   result.scope="Cloud cafés found during this review" if result.audience.mode=="all" else "Selected player UIDs"
   handler.call(result)
  elif name=="list":handler.call(mail_snapshot.duplicate(true))
  else:handler.call({"ok":false,"error":"Synthetic capture never sends or grants."})
var checks=0
var failures=[]
var capture_dir=""
var capture_composer_only=false
var captures:Array=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():
 var args=OS.get_cmdline_user_args()
 for index in args.size():
  if args[index]=="--capture-composer-only":capture_composer_only=true
  if args[index].begins_with("--capture-dir="):capture_dir=args[index].trim_prefix("--capture-dir=")
  elif args[index]=="--capture-dir" and index+1<args.size():capture_dir=args[index+1]
 run.call_deferred()
func run():
 root.size=Vector2i(1360,880)
 var game=TestMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false)
 game.web_save.profile_id=PROFILE;game.web_save.revision=2;game.web_save.ready=true
 var ui=game.compact_ui
 check(not ui.support_mail.entry.visible and not ui.support_mail.panel.visible,"owner compose entry defaults hidden")
 ui.support_mail.mail_snapshot={"ok":true,"profileId":PROFILE,"mail":[{"schema":1,"mailId":MAIL,"title":"A small gift","body":"Thank you for your report.","coins":50,"items":[{"catalogId":"plant","quantity":1}],"issuedAt":1770000000000.0,"status":"unclaimed"}]}
 game.web_save.inbox_snapshot={"ok":false}
 ui.inbox.show();await process_frame;await process_frame
 check(ui.inbox.rows.size()==1 and ui.inbox.has_unread(),"support letter appears without a legacy paid-receipt projection")
 ui.inbox.rows[0].pressed.emit();await process_frame
 check("Thank you for your report." in _text(ui.inbox.letter_body),"support letter opens in Inbox")
 check(ui.inbox.claim_button.text=="Claim","unclaimed letters keep the concise Claim action in the fixed footer")
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
 composer.can_issue_many=true;composer.can_issue_all=true;composer.all_button.disabled=false
 # Exercise the actual lookup callback without a Web bridge or live account.
 var delayed=DelayedLookup.new(ui);delayed.setup();delayed.can_issue_many=true;delayed.can_issue_all=true;delayed.recipient.text="123456789012"
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
 var batch_request=composer._request()
 check(composer._field_error()=="" and batch_request.audience.publicUids==["123456789012","234567890123"] and not batch_request.has("profileId"),"batch review requests both UIDs without client-authoritative profiles")
 composer._set_recipient_mode("all")
 check(not composer.recipient_input.visible and "count confirmed in Review" in composer.audience_feedback.text,"all players hides UID paste and never fabricates a recipient count")
 check(composer._request().audience=={"mode":"all"} and composer.send_button.disabled,"all-player audience can be reviewed but Send stays gated")
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
 check(composer.category_buttons.size()==composer.gift_catalog.categories().size() and _popup_count(composer.item_picker)==0,"category navigation is inline, with no PopupMenu/window")
 composer._set_note("Preparing audience · nothing sent.")
 for viewport in [Vector2i(1360,880),Vector2i(390,844),Vector2i(844,390)]:
  root.size=viewport
  for i in 8:await process_frame
  check(Rect2(Vector2.ZERO,Vector2(viewport)).encloses(composer.panel.get_global_rect()),"composer fits safe viewport "+str(viewport))
  var wood=composer.MailFrame.inner_rect(composer.panel)
  check(wood.encloses(composer.header.get_global_rect()) and wood.encloses(composer.footer.get_global_rect()) and wood.encloses(composer.scroll.get_global_rect()),"header, footer and scroller stay within actual wood face "+str(viewport))
  check(composer.note.visible and composer.note.text=="Preparing audience · nothing sent." and wood.encloses(composer.note.get_global_rect()),"nonempty review progress remains readable in fixed footer "+str(viewport))
  check(composer.letter.size.y>500 and not composer.letter.get_v_scroll_bar().visible,"long letter expands without an editor scrollbar "+str(viewport))
  check(composer.scroll.get_v_scroll_bar().visible,"form owns long-content scroll "+str(viewport))
  check(composer.send_button.get_global_rect().position.y>=composer.scroll.get_global_rect().end.y,"send stays below scrolling content "+str(viewport))
  composer._move_result_page(99)
  for i in 3:await process_frame
  composer.scroll.ensure_control_visible(composer.result_next)
  for i in 3:await process_frame
  check(composer.scroll.get_global_rect().encloses(composer.result_next.get_global_rect()),"last gift page controls reachable "+str(viewport))
  var selected_before=composer.quantities.duplicate(true)
  await _click(composer.category_buttons.Kitchen,composer.scroll)
  check(composer.gift_category=="Kitchen" and composer.category_buttons.Kitchen.button_pressed and not composer.category_buttons.All.button_pressed,"normal category click selects inline Kitchen "+str(viewport))
  check(composer.result_slots.filter(func(slot):return slot.card.visible).all(func(slot):return slot.id in ["stove","sink","counter"]),"category results contain Kitchen entries only "+str(viewport))
  composer.scroll.ensure_control_visible(composer.result_slots[0].card)
  for i in 4:await process_frame
  check(composer.scroll.get_global_rect().encloses(composer.result_slots[0].card.get_global_rect()),"category result card is fully reachable "+str(viewport))
  check(composer.quantities==selected_before,"category click preserves selected quantities "+str(viewport))
  await _click(composer.category_buttons.All,composer.scroll)
  check(composer.gift_category=="All" and _popup_count(composer.item_picker)==0,"normal category return never opens an overlay "+str(viewport))
  check(wood.encloses(composer.send_button.get_global_rect()) and wood.encloses(composer.preview_button.get_global_rect()),"actual fixed actions remain inside wood "+str(viewport))
  if viewport.y<500:check(composer.scroll.size.y>=100,"short landscape retains at least one readable result card")
  check(composer.selected_slots.filter(func(slot):return slot.card.visible).all(func(slot):return slot.minus.size.x>=44 and slot.minus.size.y>=44 and slot.plus.size.x>=44 and slot.plus.size.y>=44),"selected quantity tap targets remain 44px "+str(viewport))
  check("1 Leaf Coins" in composer.attachment_summary.text and composer.attachment_summary.get_global_rect().position.y>=composer.scroll.get_global_rect().end.y,"per-player attachment total remains outside the scroller "+str(viewport))
  composer._set_note("Synthetic review error.")
  for i in 3:await process_frame
  check(composer.note.visible and composer.note.text=="Synthetic review error." and composer.MailFrame.inner_rect(composer.panel).encloses(composer.note.get_global_rect()),"review error remains visible inside painted footer "+str(viewport))
  composer._set_note("")
  for i in 3:await process_frame
  check(not composer.note.visible and is_equal_approx(composer.footer.get_global_rect().end.y,composer.send_button.get_global_rect().end.y),"empty status removes footer line and separation "+str(viewport))
  check(composer.preview_button.size.y>=44 and composer.send_button.size.y>=44 and composer.panel.get_theme_stylebox("panel").get_content_margin(SIDE_BOTTOM)==(30.0 if composer.panel.size.x<480 else 34.0),"collapsed footer preserves themed touch targets and wood bottom inset "+str(viewport))
  composer._set_note("Preparing audience · nothing sent.")
 composer.scroll.scroll_vertical=0;composer.preview_summary.text="Confirm this synthetic letter.";composer.preview_card.show();composer._reveal_review()
 for i in 4:await process_frame
 check(composer.scroll.get_global_rect().intersects(composer.preview_card.get_global_rect()),"review waits for layout and reveals the new card")
 if capture_dir!="":await _capture_mail_surfaces(game,ui)
 ui._hide_popups();game.model.service_snapshot=game._service_save_snapshot()
 var payload=game.model.save_data();var wallet=game.model.coins;var claimed_id=int(payload.next_item_id)
 payload.version=17;payload.storage_format="little_leaf.storage.v1";payload.storage={"items":[{"id":claimed_id,"kind":"plant","x":0,"z":0,"rot":0,"paid_cost":0}],"dining_sets":[]};payload.next_item_id+=1;payload.coins+=50
 game.web_save.pending=true;game.web_save._support_claim_mail_id=MAIL
 var claim_generation=game.web_save._support_claim_generation
 var confirmation=JSON.stringify({"ok":true,"profileId":PROFILE,"revision":3,"payload":JSON.stringify(payload)})
 game.web_save._on_support_claim([confirmation],claim_generation)
 check(game.model.coins==wallet+50 and game.model.stored_ids("plant")==[claimed_id] and game.web_save.revision==3,"native claim installs coins and canonical owned Storage together")
 game.web_save._on_support_claim([confirmation],claim_generation)
 check(game.model.coins==wallet+50 and game.model.stored_ids("plant")==[claimed_id],"duplicate callback cannot credit or duplicate stock")
 var confirmed_model=game.model
 game.web_save.pending=true;game.web_save._support_claim_mail_id=MAIL
 game.web_save._on_support_claim([JSON.stringify({"ok":true,"profileId":PROFILE,"revision":4,"payload":"not json"})],game.web_save._support_claim_generation)
 check(game.model==confirmed_model and game.model.coins==wallet+50 and game.save_recovery_blocked,"invalid confirmed payload preserves model and blocks unsafe continuation")
 print("SUPPORT_MAIL_UI_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"synthetic_only":true}))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;await process_frame;quit(0 if failures.is_empty() else 1)

func _capture_mail_surfaces(game,ui):
 if DisplayServer.get_name()=="headless":
  check(false,"--capture-dir requires a real display renderer, not headless checks");return
 check(DirAccess.make_dir_recursive_absolute(capture_dir)==OK,"capture output directory is writable")
 var original=ui.support_mail;original.panel.hide()
 var composer=CaptureMail.new(ui);ui.support_mail=composer;composer.setup()
 composer.entry.visible=true;composer.can_issue_many=true;composer.can_issue_all=true;composer.all_button.disabled=false
 composer.recipient.text="123456789012, 234567890123"
 composer.case_id.text="case-329-capture";composer.subject.text="A little thank-you";composer.letter.text="Thank you for helping Little Leaf grow."
 composer.coins.value=125;composer._set_gift_quantity("plant",2);composer._set_gift_quantity("beverage",1)
 var record={"schema":1,"mailId":MAIL,"title":composer.subject.text,"body":composer.letter.text,"coins":125,"items":[{"catalogId":"plant","quantity":2},{"catalogId":"beverage","quantity":1}],"issuedAt":1770000000000.0,"status":"unclaimed"}
 composer.mail_snapshot={"ok":true,"profileId":PROFILE,"mail":[record]}
 for viewport in [Vector2i(1360,880),Vector2i(390,844),Vector2i(844,390)]:
  root.size=viewport;ui._hide_popups();composer.show();composer._set_recipient_mode("selected")
  composer.scroll.scroll_vertical=0;await _settle_capture(ui)
  _check_compose_capture(composer,viewport,false)
  check(composer.recipient.editable and composer.recipient.text=="123456789012, 234567890123" and composer.coins.editable and int(composer.coins.value)==125 and int(composer.quantities.plant)==2 and int(composer.quantities.beverage)==1,"editable capture retains selected UIDs and coin/item quantities "+str(viewport))
  await _save_capture("editable-composer",viewport)
  if capture_composer_only:continue
  composer._preview()
  await _settle_capture(ui)
  _check_compose_capture(composer,viewport)
  check("2 recipients" in composer.preview_summary.text and "Leafy plant ×2" in composer.preview_summary.text and "Beverage station ×1" in composer.preview_summary.text,"selected review uses exact real attachment names and quantities "+str(viewport))
  await _save_capture("selected-review",viewport)
  composer.scroll.scroll_vertical=int(composer.preview_card.position.y+composer.preview_card.size.y-composer.scroll.size.y)
  await _settle_capture(ui)
  await _save_capture("selected-attachments",viewport)
  composer._set_recipient_mode("all");composer._preview();await _settle_capture(ui)
  _check_compose_capture(composer,viewport)
  check("72 recipients" in composer.preview_summary.text and "9000 Leaf Coins" in composer.preview_summary.text and "Leafy plant ×144" in composer.preview_summary.text and "Beverage station ×72" in composer.preview_summary.text and "08:00:00.123 UTC" in composer.preview_summary.text and composer.send_button.text=="Send to 72 players" and not composer.send_button.disabled,"All review has prepared count, aggregates, interval and explicit Send gate "+str(viewport))
  await _save_capture("all-review",viewport)
  composer.panel.hide();ui.inbox.show();ui.inbox._show_detail("support-mail/"+MAIL);await _settle_capture(ui)
  var wood=ui.inbox.MailFrame.inner_rect(ui.inbox.panel)
  check(wood.encloses(ui.inbox.heading_box.get_global_rect()) and wood.encloses(ui.inbox.footer.get_global_rect()) and wood.encloses(ui.inbox.scroll.get_global_rect()),"Inbox capture containers stay inside painted wood face "+str(viewport))
  check("Leafy plant ×2" in _text(ui.inbox.letter_body) and "Beverage station ×1" in _text(ui.inbox.letter_body) and "125 Leaf Coins" in _text(ui.inbox.letter_body),"Inbox capture preserves attachment names, amounts and counts "+str(viewport))
  await _save_capture("inbox-letter",viewport)
  ui.inbox.scroll.scroll_vertical=int(ui.inbox.content.size.y-ui.inbox.scroll.size.y);await _settle_capture(ui)
  await _save_capture("inbox-attachments",viewport)
 var receipt={"schema":1,"synthetic_only":true,"player_save_used":false,"actual_ui_methods":true,"rendered_pngs":true,"renderer":RenderingServer.get_current_rendering_method(),"display":DisplayServer.get_name(),"captures":captures,"visual_acceptance":"pending human inspection"}
 var output=FileAccess.open(capture_dir.path_join("capture-receipt.json"),FileAccess.WRITE)
 check(output!=null,"capture receipt is writable")
 if output!=null:output.store_string(JSON.stringify(receipt,"  "));output.close()
 ui._hide_popups();ui.support_mail=original;composer.entry.queue_free();composer.panel.queue_free()

func _settle_capture(ui):
 for i in 10:
  ui._fit_themed_popups();await process_frame

func _check_compose_capture(composer,viewport:Vector2i,expect_review:bool=true):
 var wood=composer.MailFrame.inner_rect(composer.panel)
 check(Rect2(Vector2.ZERO,Vector2(viewport)).encloses(composer.panel.get_global_rect()),"capture composer fits viewport "+str(viewport))
 for part in [composer.header,composer.footer,composer.scroll,composer.preview_button,composer.send_button]:
  check(wood.encloses(part.get_global_rect()),"capture composer fixed controls remain within painted wood face "+part.get_class()+str(viewport))
 check(_scroll_count(composer.panel)==1 and not composer.letter.get_v_scroll_bar().visible and not composer.recipient.get_v_scroll_bar().visible,"capture composer retains one scroll area "+str(viewport))
 check(composer.note.text.is_empty() and not composer.note.visible and is_equal_approx(composer.footer.get_global_rect().end.y,composer.send_button.get_global_rect().end.y),"capture empty footer closes immediately below actions "+str(viewport))
 check(composer.preview_button.size.y>=44 and composer.send_button.size.y>=44,"capture actions retain themed 44px touch height "+str(viewport))
 check("125 Leaf Coins · 3 items" in composer.attachment_summary.text,"capture fixed per-player totals are visible "+str(viewport))
 if expect_review:check(composer.scroll.get_global_rect().intersects(composer.preview_card.get_global_rect()),"capture review card is in the scrolling viewport "+str(viewport))
 else:check(composer.scroll.scroll_vertical==0 and not composer.preview_card.visible and composer.send_button.disabled,"editable top capture has no prepared review or Send authority "+str(viewport))

func _save_capture(surface:String,viewport:Vector2i):
 await RenderingServer.frame_post_draw
 var pixels=root.get_texture().get_image()
 var filename="%s-%dx%d.png"%[surface,viewport.x,viewport.y]
 var path=capture_dir.path_join(filename)
 check(pixels!=null and not pixels.is_empty() and pixels.get_size()==viewport,"actual rendered image matches viewport "+filename)
 if pixels==null or pixels.is_empty():return
 check(pixels.save_png(path)==OK,"actual rendered PNG saved "+filename)
 captures.append({"surface":surface,"viewport":[viewport.x,viewport.y],"file":filename,"sha256":FileAccess.get_sha256(path)})

func _scroll_count(node:Node)->int:
 var count=1 if node is ScrollContainer else 0
 for child in node.get_children():count+=_scroll_count(child)
 return count
func _text(node:Node)->String:
 var result=str(node.text) if node is Label or node is Button else ""
 for child in node.get_children():result+="\n"+_text(child)
 return result

func _click(button:Button,scroller:ScrollContainer):
 scroller.ensure_control_visible(button)
 for i in 4:await process_frame
 var point=button.get_global_rect().get_center()
 var motion=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;root.push_input(motion,true)
 for pressed in [true,false]:
  var event=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=point;event.global_position=point
  root.push_input(event,true);await process_frame
 for i in 4:await process_frame

func _popup_count(node:Node)->int:
 var count=1 if node is PopupMenu else 0
 for child in node.get_children():count+=_popup_count(child)
 return count
