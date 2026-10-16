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
 check("Claim gifts" in _text(ui.inbox.letter_body),"unclaimed gifts have a real claim action")
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
 check(ui.support_mail.panel.visible and ui.support_mail.quantities.size()==10 and ui.support_mail.send_button.disabled,"synthetic capability exposes bounded composer with Send gated by preview")
 var composer=ui.support_mail
 composer.letter.grab_focus();composer.handle_input(tab)
 check(game.get_viewport().gui_get_focus_owner()==composer.coins.get_line_edit(),"Tab leaves multiline editor for attachments")
 for i in 22:
  composer.handle_input(tab)
  check(composer.panel.is_ancestor_of(game.get_viewport().gui_get_focus_owner()),"composer keyboard focus remains inside "+str(i))
 composer.letter.text="A long letter for our café owner.\n".repeat(30)
 for viewport in [Vector2i(1360,880),Vector2i(390,844),Vector2i(844,390)]:
  root.size=viewport
  for i in 8:await process_frame
  check(Rect2(Vector2.ZERO,Vector2(viewport)).encloses(composer.panel.get_global_rect()),"composer fits safe viewport "+str(viewport))
  check(composer.letter.size.y>500 and not composer.letter.get_v_scroll_bar().visible,"long letter expands without an editor scrollbar "+str(viewport))
  check(composer.scroll.get_v_scroll_bar().visible,"form owns long-content scroll "+str(viewport))
  check(composer.send_button.get_global_rect().position.y>=composer.scroll.get_global_rect().end.y,"send stays below scrolling content "+str(viewport))
  composer.scroll.scroll_vertical=int(composer.scroll.get_v_scroll_bar().max_value)
  for i in 3:await process_frame
  check(composer.scroll.get_global_rect().encloses(composer.quantities.divider.get_global_rect()),"last attachment reachable "+str(viewport))
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
