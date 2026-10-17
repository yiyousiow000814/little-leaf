extends SceneTree
## Actual mail control-building and response methods, real Array-shaped Model.
## Synthetic transport/theme host only. Headless control checks are NOT PNG evidence.
const Model=preload("res://scripts/core/cafe_model.gd")
const Inbox=preload("res://scripts/ui/cafe_inbox.gd")
class FixtureGame extends Control:
 var model=Model.new()
 var settings=PanelContainer.new()
 var web_save=null
 func _init():
  add_child(settings);settings.add_child(VBoxContainer.new())
 func label(words:String,font_size:int,color:Color)->Label:
  var result=Label.new();result.text=words;result.add_theme_font_size_override("font_size",font_size);result.add_theme_color_override("font_color",color);return result
 func button(words:String,callback:Callable)->Button:
  var result=Button.new();result.text=words;result.pressed.connect(callback);return result
 func _style(fill:Color,border:Color,radius:int)->StyleBoxFlat:
  var result=StyleBoxFlat.new();result.bg_color=fill;result.border_color=border;result.set_border_width_all(1);result.set_corner_radius_all(radius);return result
 func _catalog_group(kind:String)->String:return "Kitchen" if kind in ["stove","sink","counter"] else "Decor"
class FixtureHud extends RefCounted:
 var font_bold=ThemeDB.fallback_font
 func theme_button(_button:Button,_primary=false):pass
 func theme_scroll(_scroll:ScrollContainer):pass
 func theme_panel(panel:PanelContainer,_wood:bool,_padding:int):panel.add_theme_stylebox_override("panel",StyleBoxFlat.new())
 func _texture(_name:String):return null
 func _picture(parent:Control,texture)->TextureRect:
  var result=TextureRect.new();result.texture=texture;parent.add_child(result);return result
 func _safe_insets()->Vector4:return Vector4.ZERO
 func popup_height_budget()->float:return 760.0
class FixtureCompact extends RefCounted:
 var game
 var hud=FixtureHud.new()
 var shop_ui=null
 var inbox=null
 var support_mail=null
 func _init(host):game=host
 func _panel()->PanelContainer:
  var result=PanelContainer.new();game.add_child(result);return result
 func _queue_popup_fit():pass
 func _popup_at(panel:Control,_width:float):panel.show()
class Transport extends "res://scripts/ui/cafe_support_mail.gd":
 var pending:Array=[]
 func _call(name:String,args:Array,handler:Callable):pending.append({"name":name,"args":args.duplicate(true),"handler":handler})
class ClaimTransport extends RefCounted:
 var ready=true
 var pending=false
 var _support_claim_mail_id=""
 var profile_id="synthetic-profile"
 var inbox_snapshot={"ok":true,"profileId":"synthetic-profile","paid":[],"deferred":[]}
 var attempts=0
 func claim_support_mail(id:String)->bool:
  attempts+=1;pending=true;_support_claim_mail_id=id;return true
var checks=0
var failures:Array=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func run():
 var game=FixtureGame.new();root.add_child(game)
 var compact=FixtureCompact.new(game)
 var composer=Transport.new(compact);compact.support_mail=composer;composer.setup()
 composer.recipient.text="123456789012, 234567890123"
 check(composer.all_button.disabled and "not enabled" in composer._recipient_error(),"batch and All are gated by explicit capabilities")
 composer._set_recipient_mode("all")
 check(composer.recipient_mode=="selected","missing All capability cannot select All programmatically")
 composer.entry.visible=true;composer.can_issue_many=true;composer.can_issue_all=true;composer.all_button.disabled=false
 composer.recipient.text="234567890123, 123456789012, 123456789012"
 composer.case_id.text="case-329";composer.subject.text=" A little thank-you ";composer.letter.text="\nThank you for your report.\n";composer.coins.value=125
 composer._set_gift_quantity("plant",2);composer._set_gift_quantity("sink",1)
 check(game.model.catalog is Array,"fixture uses actual Array-shaped gameplay catalogue")
 check(composer.gift_catalog.entries.any(func(row):return row.id=="plant" and row.name=="Leafy plant"),"picker resolves real catalogue names")
 var request=composer._request()
 print("SUPPORT_MAIL_REQUEST ",JSON.stringify(request))
 check(request.subject=="A little thank-you" and request.body=="Thank you for your report." and request.items==[{"catalogId":"plant","quantity":2,"catalogRevision":1},{"catalogId":"sink","quantity":1,"catalogRevision":1}],"request matches server letter trimming, sorted items and catalogue revision")
 check(request.audience=={"mode":"selected","publicUids":["123456789012","234567890123"]},"request has sorted deduplicated UIDs")
 check(not request.has("profileId") and not request.has("recipientPublicUid") and not request.has("recipientCount"),"client supplies no authoritative profiles or count")
 check(composer.found.is_empty() and composer._field_error()=="","informational lookup is not required for Review")
 composer._preview();composer._preview()
 check(composer.pending.size()==1 and composer.preview_button.disabled and composer.send_button.disabled,"double Review launches one request and gates Send")
 var initial=composer.pending.pop_front();initial.handler.call(_review(initial.args[0],"ready",2))
 check(not composer.send_button.disabled and composer.preview_payload.previewHash=="synthetic-review-hash","ready snapshot enables Send only with hash")
 check("Total for this audience:\n250 Leaf Coins\nLeafy plant ×4\nDishwashing sink ×2" in composer.preview_summary.text and composer.send_button.text=="Send letter","selected review shows exact server aggregates without changing selected Send")
 check("Captured 2026-10-17 08:00:00.123 UTC to 2026-10-17 08:00:05.456 UTC" in composer.preview_summary.text,"review renders exact millisecond-accurate server capture interval")
 var wrong_totals=_review(initial.args[0],"ready",2);wrong_totals.totals.coins=251
 check(not composer._matching_review(wrong_totals,initial.args[0]),"mismatched aggregate coins fail closed")
 wrong_totals=_review(initial.args[0],"ready",2);wrong_totals.totals.items[0].quantity=5
 check(not composer._matching_review(wrong_totals,initial.args[0]),"mismatched aggregate item units fail closed")
 var backwards=_review(initial.args[0],"ready",2);backwards.captureCompletedAt=backwards.captureStartedAt-1
 check(not composer._matching_review(backwards,initial.args[0]),"backwards capture interval fails closed")
 check("2 recipients" in composer.preview_summary.text and "Leafy plant ×2" in composer.preview_summary.text and "Dishwashing sink ×1" in composer.preview_summary.text and "125 Leaf Coins" in composer.preview_summary.text,"actual review renderer retains exact names, quantity and wallet amount")
 var old_id=composer.issue_id
 composer.subject.text="Updated note";composer.subject.text_changed.emit(composer.subject.text)
 check(composer.preview_payload.is_empty() and composer.send_button.disabled and composer.issue_id=="","editing invalidates ready review and old issue")
 composer._preview();var stale=composer.pending.pop_front()
 composer.subject.text="Newest note";composer.subject.text_changed.emit(composer.subject.text)
 stale.handler.call(_review(stale.args[0],"ready",2))
 check(composer.preview_payload.is_empty() and composer.send_button.disabled,"stale review cannot approve newer text")
 composer._set_recipient_mode("all");composer._preview();var first=composer.pending.pop_front()
 first.handler.call(_review(first.args[0],"preparing",50))
 var all_id=composer.issue_id
 check(composer.preview_button.text=="Continue review" and composer.send_button.disabled and composer.preview_payload.is_empty(),"preparing audience never enables Send")
 check("50 cloud cafés prepared" in composer.preview_summary.text and not "50 recipients" in composer.preview_summary.text,"preparing progress never fabricates final count")
 composer.panel.hide();composer.show()
 check(composer.issue_id==all_id and composer.preview_button.text=="Continue review","Close/reopen preserves audience preparation")
 composer._preview();var continuation=composer.pending.pop_front()
 check(continuation.args[0].issueId==all_id and continuation.args[0].audience=={"mode":"all"},"Continue Review reuses same bounded all-audience request")
 continuation.handler.call(_review(continuation.args[0],"ready",72))
 check(not composer.send_button.disabled and "72 recipients" in composer.preview_summary.text,"finished audience shows server-confirmed count")
 check(composer.send_button.text=="Send to 72 players" and composer.send_button.autowrap_mode==TextServer.AUTOWRAP_WORD_SMART and "Total for this audience:\n9000 Leaf Coins\nLeafy plant ×144\nDishwashing sink ×72" in composer.preview_summary.text,"All confirmation names exact player count and server-confirmed aggregate units")
 for viewport in [Vector2i(1360,880),Vector2i(390,844),Vector2i(844,390)]:
  root.size=viewport;composer.show()
  for i in 8:composer.fit_popup();await process_frame
  check(composer.MailFrame.inner_rect(composer.panel).encloses(composer.send_button.get_global_rect()) and Rect2(Vector2.ZERO,Vector2(viewport)).encloses(composer.panel.get_global_rect()),"wrapped All confirmation retains synthetic-theme viewport fit "+str(viewport))
 composer._send();composer._send();var sending=composer.pending.pop_front()
 check(composer.pending.is_empty() and composer.send_pending and not composer.subject.editable and composer.all_button.disabled,"double Send is guarded and composition frozen")
 var frozen_quantities=composer.quantities.duplicate(true);composer._set_gift_quantity("plant",8);composer._set_recipient_mode("selected")
 check(composer.quantities==frozen_quantities and composer.recipient_mode=="all","frozen dispatch cannot change attachment quantities or audience")
 check(sending.args[0].issueId==all_id and sending.args[0].previewHash=="synthetic-review-hash","Send uses reviewed issue and hash")
 sending.handler.call({"ok":false,"error":"Synthetic timeout"})
 check(not composer.send_button.disabled and composer.send_button.text=="Resume send" and composer.delivery_started,"uncertain send retains resumable frozen identity")
 composer.panel.hide();composer.show()
 check(composer.issue_id==all_id and composer.preview_payload==sending.args[0] and not composer.subject.editable,"Close/reopen cannot create a duplicate issue after uncertain send")
 composer._send();var resumed=composer.pending.pop_front()
 check(resumed.args[0]==sending.args[0],"retry submits exact frozen audience and letter")
 resumed.handler.call(_delivery(all_id,"sending",72,50,1,21))
 check("50 / 72 sent · 1 failed · 21 pending"==composer.note.text and composer.send_button.text=="Continue send","partial delivery reports all counts, not success")
 check(not composer._matching_delivery(_delivery(all_id,"sent",72,70,1,1),sending.args[0]) and not composer._matching_delivery(_delivery(all_id,"sent",73,73,0,0),sending.args[0]),"malformed terminal state or changed recipient total fails closed")
 composer._send();var last=composer.pending.pop_front();last.handler.call(_delivery(all_id,"completed_with_failures",72,71,1,0))
 check(composer.delivery_terminal and composer.send_button.disabled and composer.preview_button.text=="New letter" and "1 failed" in composer.note.text,"terminal partial failures remain truthful and cannot resend")
 composer._send();check(composer.pending.is_empty(),"repeated terminal Send cannot create another issue")
 composer._preview();check(not composer.delivery_started and composer.issue_id=="" and composer.subject.editable,"explicit New letter resets frozen state")
 composer._preview();var expiring=composer.pending.pop_front();var expired=_review(expiring.args[0],"ready",72);expired.captureStartedAt=0;expired.captureCompletedAt=0;expired.expiresAt=1;expiring.handler.call(expired)
 composer._send();check(composer.pending.is_empty() and composer.send_button.disabled and "expired" in composer.note.text,"expired preview cannot send")
 composer._preview();var expiry_review=composer.pending.pop_front();expiry_review.handler.call(_review(expiry_review.args[0],"ready",72))
 composer._send();var server_expiry=composer.pending.pop_front();server_expiry.handler.call({"ok":false,"code":"PREVIEW_EXPIRED","error":"Review expired before sending."})
 check(not composer.delivery_started and composer.issue_id=="" and composer.subject.editable and "nothing was sent" in composer.note.text,"server-proven zero-delivery expiry permits fresh review")
 composer._preview();var required_review=composer.pending.pop_front();required_review.handler.call(_review(required_review.args[0],"ready",72))
 composer._send();var required=composer.pending.pop_front();required.handler.call({"ok":false,"code":"PREVIEW_REQUIRED","error":"Review state unavailable."})
 check(composer.delivery_started and composer.issue_id==required.args[0].issueId and not composer.subject.editable,"missing server review cannot unlock an uncertain send")
 composer._reset_delivery()
 composer._preview();var mismatch=composer.pending.pop_front();var changed=_review(mismatch.args[0],"ready",72);changed.body="Unexpected server body";mismatch.handler.call(changed)
 check(composer.preview_payload.is_empty() and composer.send_button.disabled and "did not match" in composer.note.text,"mismatching exact letter fails closed")
 composer._preview();var resetting=composer.pending.pop_front();composer.reset();resetting.handler.call(_review(resetting.args[0],"ready",72))
 check(composer.preview_payload.is_empty() and composer.issue_id=="" and not composer.panel.visible,"reset fences previous response")
 # Exercise the actual render methods with known, unknown and absent item names.
 var inbox=Inbox.new(compact);inbox.content=VBoxContainer.new();game.add_child(inbox.content);inbox.footer=VBoxContainer.new();game.add_child(inbox.footer)
 var records=[{"catalogId":"plant","quantity":2},{"catalogId":"sink","quantity":1},{"catalogId":"future_lantern","quantity":3},{"quantity":4}]
 var record={"mailId":"synthetic","title":"A little thank-you","body":"A short note.","issuedAt":1770000000000.0,"coins":125,"items":records,"status":"claimed"}
 inbox._support_detail(record)
 var actual=_text(inbox.letter_body)
 for expected in ["Leafy plant ×2","Dishwashing sink ×1","Future Lantern ×3","Unknown item ×4","125 Leaf Coins","Items → Storage","Claimed"]:
  check(expected in actual,"actual Inbox controls show "+expected)
 check(not "Dear café owner" in actual and not "Warmly" in actual,"support letter does not wrap supplied body in redundant greeting")
 var rendering=_review(request,"ready",2);rendering.items=records;composer._render_review(rendering)
 for expected in ["Leafy plant ×2","Future Lantern ×3","Unknown item ×4"]:check(expected in composer.preview_summary.text,"actual Review label shows "+expected)
 record.items=[];record.coins=0;inbox._support_detail(record)
 check(not "Leaf Coins" in _text(inbox.letter_body),"missing attachments do not fabricate coins or an inventory")
 record.erase("items");inbox._support_detail(record)
 check("A short note." in _text(inbox.letter_body),"absent items field still renders exact body")
 # A failed claim must update detail feedback even when mailbox bytes are unchanged.
 inbox.panel=PanelContainer.new();game.add_child(inbox.panel);inbox.panel.hide();compact.inbox=inbox;game.web_save=ClaimTransport.new()
 record.status="unclaimed";inbox._support_detail(record);inbox.sync()
 inbox.claim_button.pressed.emit();inbox.claim_button.pressed.emit()
 check(game.web_save.attempts==1 and inbox.claim_button.disabled and inbox.claim_status.text=="Claiming attachments…","Claim double-click is guarded and pending detail feedback remains visible")
 game.web_save.pending=false;game.web_save._support_claim_mail_id="";composer.claim_result(false,"Synthetic known failure")
 check(not inbox.claim_button.disabled and inbox.claim_status.text=="Synthetic known failure","known failure re-enables Claim and shows exact reason without mailbox rebuild")
 game.web_save.ready=false;composer.claim_result(false,"Reload to recover an uncertain claim.")
 check(inbox.claim_button.disabled and "Reload" in inbox.claim_status.text,"uncertain claim blocks retry while preserving recovery reason")
 for viewport in [Vector2i(1360,880),Vector2i(390,844),Vector2i(844,390)]:
  root.size=viewport;composer.entry.visible=true;composer.show()
  for i in 8:composer.fit_popup();await process_frame
  check(Rect2(Vector2.ZERO,Vector2(viewport)).encloses(composer.panel.get_global_rect()),"synthetic-theme composer controls fit "+str(viewport))
  check(composer.scroll.get_global_rect().end.y<=composer.send_button.get_global_rect().position.y,"fixed Send remains outside single scrolling form "+str(viewport))
 print("SUPPORT_MAIL_RENDER_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"synthetic_only":true,"actual_ui_methods":true,"rendered_pngs":false}))
 compact.support_mail=null;compact.inbox=null;composer=null;inbox=null;game.queue_free();await process_frame;await process_frame
 quit(0 if failures.is_empty() else 1)
func _review(request:Dictionary,status:String,count:int)->Dictionary:
 var result=request.duplicate(true);result.ok=true;result.status=status;result.preparedCount=count
 result.recipientCount=count if status=="ready" else null;result.previewHash="synthetic-review-hash" if status=="ready" else null
 result.expiresAt=floor(Time.get_unix_time_from_system()*1000.0)+60000.0;result.scope="Cloud cafés found during this review"
 result.captureStartedAt=1792224000123;result.captureCompletedAt=1792224005456 if status=="ready" else null
 result.totals={"coins":int(request.coins)*count,"items":[]} if status=="ready" else null
 if status=="ready":
  for item in request.items:result.totals.items.append({"catalogId":item.catalogId,"quantity":int(item.quantity)*count})
 return result
func _delivery(id:String,status:String,total:int,sent:int,failed:int,pending:int)->Dictionary:
 return {"ok":true,"issueId":id,"status":status,"total":total,"sentCount":sent,"failedCount":failed,"pendingCount":pending}
func _text(node:Node)->String:
 var result=str(node.text) if node is Label or node is Button else ""
 for child in node.get_children():result+="\n"+_text(child)
 return result
