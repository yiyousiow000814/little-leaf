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
 check(m.cancel_decoration_session() and m.decoration_gifts.is_empty() and int(m.gift_stock.plant)==2,"Cancel restores the stock baseline")
 check(not m.place_gift("plant",5,4),"gift cannot place outside Decorate")
 var game=TestMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false)
 game.web_save.profile_id=PROFILE
 var ui=game.compact_ui;game.model.gift_stock={"plant":2};game.editing=true
 check(not ui.support_mail.entry.visible and not ui.support_mail.panel.visible,"owner compose entry defaults hidden")
 game.model.begin_decoration_session();game._set_catalog_category("Gifts");game._update_ui()
 check(ui.shop_ui!=null and game.gift_cards.plant.visible and game.gift_counts.plant.text=="Gift ×2","Gifts shelf shows verified stock")
 game.gift_cards.plant.pressed.emit()
 check(game.selected_gift and game.selected_kind=="plant","Gifts shelf selects gift placement")
 ui.support_mail.mail_snapshot={"ok":true,"profileId":PROFILE,"mail":[{"schema":1,"mailId":MAIL,"title":"A small gift","body":"Thank you for your report.","coins":50,"items":[{"catalogId":"plant","quantity":1}],"issuedAt":1770000000000.0,"status":"unclaimed"}]}
 ui.inbox.show();await process_frame;await process_frame
 check(ui.inbox.rows.size()==1 and ui.inbox.has_unread(),"support letter appears and is unread")
 ui.inbox.rows[0].pressed.emit();await process_frame
 check("Thank you for your report." in _text(ui.inbox.letter_body),"support letter opens in Inbox")
 check("Claim gifts" in _text(ui.inbox.letter_body),"unclaimed gifts have a real claim action")
 check(ui.inbox.has_unread()==false,"reading does not claim or retain unread dot")
 ui._hide_popups();ui.support_mail.entry.visible=true;ui.support_mail.show()
 check(ui.support_mail.panel.visible and ui.support_mail.quantities.size()==10 and ui.support_mail.send_button.disabled,"synthetic capability exposes bounded composer with Send gated by preview")
 print("SUPPORT_GIFTS_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"synthetic_only":true}))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;await process_frame;quit(0 if failures.is_empty() else 1)
func _text(node:Node)->String:
 var result=str(node.text) if node is Label or node is Button else ""
 for child in node.get_children():result+="\n"+_text(child)
 return result
