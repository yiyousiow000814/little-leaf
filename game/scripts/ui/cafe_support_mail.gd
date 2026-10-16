extends RefCounted
## Owner compose surface and bounded player mail/stock projection. Authority lives in Functions.
const CATALOG=["stove","beverage","sink","counter","bin","plant","lamp","bookshelf","rug","divider"]
var compact_ref:WeakRef
var compact:
 get:return compact_ref.get_ref()
var game
var bridge
var panel:PanelContainer
var entry:Button
var note:Label
var recipient:LineEdit
var case_id:LineEdit
var subject:LineEdit
var letter:TextEdit
var coins:SpinBox
var quantities:Dictionary={}
var lookup_summary:Label
var preview_summary:Label
var send_button:Button
var mail_snapshot:Dictionary={"ok":false,"profileId":"","mail":[]}
var mail_error=""
var found:Dictionary={}
var preview_payload:Dictionary={}
var issue_id=""
var request_generation=0
var form_generation=0
var _callbacks:Array=[]

func _init(owner):compact_ref=weakref(owner);game=owner.game

func setup():
 entry=game.button("Support Mail",show);entry.name="OpenSupportMail";entry.visible=false
 game.settings.get_child(0).add_child(entry)
 compact.hud.theme_button(entry)
 panel=compact._panel();panel.name="SupportMailCompose"
 compact.hud.theme_panel(panel,true,24)
 var frame=VBoxContainer.new();frame.add_theme_constant_override("separation",9);panel.add_child(frame)
 var heading=game.label("Support Mail",22);frame.add_child(heading)
 var scroller=ScrollContainer.new();scroller.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
 scroller.custom_minimum_size=Vector2(0,420);frame.add_child(scroller)
 var form=VBoxContainer.new();form.add_theme_constant_override("separation",8);scroller.add_child(form)
 form.add_child(game.label("Exact player UID",14));recipient=LineEdit.new();recipient.placeholder_text="Paste full player UID";form.add_child(recipient)
 var find=game.button("Find player",_lookup);form.add_child(find)
 lookup_summary=game.label("Find a player before composing.",14);lookup_summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;form.add_child(lookup_summary)
 form.add_child(game.label("Support case reference",14));case_id=LineEdit.new();case_id.placeholder_text="For example: case-123";form.add_child(case_id)
 form.add_child(game.label("Subject",14));subject=LineEdit.new();form.add_child(subject)
 form.add_child(game.label("Letter",14));letter=TextEdit.new();letter.custom_minimum_size.y=110;letter.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;form.add_child(letter)
 form.add_child(game.label("Leaf Coins · maximum 100,000 per letter",14));coins=SpinBox.new();coins.min_value=0;coins.max_value=100000;coins.step=1;form.add_child(coins)
 form.add_child(game.label("Unplaced gifts",15))
 for kind in CATALOG:
  var line=HBoxContainer.new();form.add_child(line)
  var title=game.label(kind.capitalize(),14);title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;line.add_child(title)
  var amount=SpinBox.new();amount.min_value=0;amount.max_value=10;amount.step=1;amount.custom_minimum_size.x=95;line.add_child(amount);quantities[kind]=amount
  amount.value_changed.connect(func(_value):_invalidate_preview())
 var preview_button=game.button("Preview exact letter and gifts",_preview);form.add_child(preview_button)
 preview_summary=game.label("",14);preview_summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;form.add_child(preview_summary)
 send_button=game.button("Send this letter",_send);send_button.disabled=true;form.add_child(send_button)
 note=game.label("",14);note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;frame.add_child(note)
 var back=game.button("Back to Settings",func():panel.hide();game.settings.show());frame.add_child(back)
 for field in [recipient,case_id,subject]:field.text_changed.connect(func(_value):_invalidate_preview())
 letter.text_changed.connect(_invalidate_preview);coins.value_changed.connect(func(_value):_invalidate_preview())
 compact.hud.theme_panel_contents(panel)
 compact._wrap_themed_popup(panel,450)
 panel.hide()

func _call(name:String,args:Array,handler:Callable):
 bridge=JavaScriptBridge.get_interface("LittleLeafSupportMail") if OS.has_feature("web") else null
 if bridge==null:return
 if _callbacks.size()>=12:
  note.text="Support is busy. Wait for the current request.";return
 var generation=request_generation
 var callback
 callback=JavaScriptBridge.create_callback(func(values):
  _callbacks.erase(callback)
  if generation!=request_generation or game==null or not game.is_inside_tree():return
  var value=JSON.parse_string(str(values[0])) if values.size()>0 else null
  handler.call(value if value is Dictionary else {"ok":false,"error":"Invalid support response."})
 )
 _callbacks.append(callback)
 match name:
  "capabilities":bridge.capabilities(callback)
  "lookup":bridge.lookup(args[0],callback)
  "preview":bridge.preview(JSON.stringify(args[0]),callback)
  "issue":bridge.issue(JSON.stringify(args[0]),callback)
  "list":bridge.list(args[0],callback)
  "stock":bridge.stock(callback)

func refresh():
 request_generation+=1;found={};preview_payload={};issue_id=""
 mail_snapshot={"ok":false,"profileId":"","mail":[]};entry.visible=false
 if not OS.has_feature("web") or game.web_save==null or not game.web_save.ready:return
 refresh_capabilities()
 refresh_mail()
 refresh_stock()

func refresh_stock():
 if game.web_save==null or not game.web_save.ready:return
 _call("stock",[],func(result):
  if bool(result.get("ok",false)) and game.web_save.accept_gift_stock(result):game._update_ui()
 )

func refresh_mail():
 if game.web_save==null or not game.web_save.ready:return
 _call("list",[""],func(result):
  if bool(result.get("ok",false)) and str(result.get("profileId",""))==game.web_save.profile_id and result.get("mail") is Array:
   mail_snapshot={"ok":true,"profileId":result.profileId,"mail":result.mail.slice(0,20),"nextCursor":result.get("nextCursor")}
   mail_error=""
  else:mail_error=str(result.get("error","Mail is unavailable."))
  if compact.inbox!=null:compact.inbox.sync()
 )

func load_more_mail():
 var cursor=mail_snapshot.get("nextCursor")
 if not bool(mail_snapshot.get("ok",false)) or cursor==null or mail_snapshot.mail.size()>=60:return
 _call("list",[str(cursor)],func(result):
  if not bool(result.get("ok",false)) or str(result.get("profileId",""))!=str(mail_snapshot.get("profileId","")) or not result.get("mail") is Array:
   mail_error=str(result.get("error","Older letters are unavailable."));return
  var known={}
  for mail in mail_snapshot.mail:known[str(mail.get("mailId",""))]=true
  for mail in result.mail:
   if not known.has(str(mail.get("mailId",""))) and mail_snapshot.mail.size()<60:
    mail_snapshot.mail.append(mail);known[str(mail.get("mailId",""))]=true
  mail_snapshot.nextCursor=result.get("nextCursor") if mail_snapshot.mail.size()<60 else null
  if compact.inbox!=null:compact.inbox.sync()
 )

func claim_result(ok:bool,reason:String):
 mail_error="" if ok else reason
 if ok:refresh_mail();refresh_stock()

func reset():
 request_generation+=1;entry.visible=false;mail_snapshot={"ok":false,"profileId":"","mail":[]}
 found={};preview_payload={};issue_id="";_callbacks.clear();panel.hide()

func refresh_capabilities():
 if game.web_save==null or not game.web_save.ready:return
 _call("capabilities",[],func(result):entry.visible=bool(result.get("ok",false)) and bool(result.get("canLookup",false)) and bool(result.get("canIssue",false)))
 if compact.inbox!=null:compact.inbox.sync()

func show():
 if not entry.visible:return
 game.settings.hide();compact._popup_at(panel,450);note.text="";panel.show();_invalidate_preview()
 compact._queue_popup_fit()

func _invalidate_preview(reset_issue=true):
 form_generation+=1
 if reset_issue:issue_id=""
 preview_payload={};send_button.disabled=true;preview_summary.text=""

func _lookup():
 _invalidate_preview();found={};lookup_summary.text="Checking exact UID…"
 _call("lookup",[recipient.text.strip_edges()],func(result):
  if not bool(result.get("ok",false)):
   lookup_summary.text=str(result.get("error","Player unavailable."));return
  if str(result.get("uid",""))!=recipient.text.strip_edges():return
  found=result
  lookup_summary.text="UID: %s\nCafé: %s · save revision %s\nSaved: %s (%s) · %s\n%s\nRecent mail (up to 10): %s"%[result.uid,result.profileId,str(result.revision),str(result.savedAt),str(result.timeSource),str(result.device),str(result.evidence),JSON.stringify(result.get("recentMail",[]))]
 )

func _request()->Dictionary:
 if found.is_empty() or str(found.get("uid",""))!=recipient.text.strip_edges():return {}
 var items=[]
 for kind in CATALOG:
  var count=int(quantities[kind].value)
  if count>0:items.append({"catalogId":kind,"quantity":count})
 if issue_id=="":issue_id=str(JavaScriptBridge.eval("crypto.randomUUID()"))
 return {"issueId":issue_id,"recipientUid":recipient.text.strip_edges(),"profileId":str(found.profileId),"caseId":case_id.text.strip_edges(),"subject":subject.text,"body":letter.text,"coins":int(coins.value),"items":items}

func _preview():
 var request=_request()
 if request.is_empty():note.text="Find the exact player UID first.";return
 _invalidate_preview(false);var generation=form_generation;note.text="Checking letter and gifts…"
 _call("preview",[request],func(result):
  if generation!=form_generation:return
  if not bool(result.get("ok",false)):
   note.text=str(result.get("error","Preview unavailable."));return
  if str(result.get("issueId",""))!=issue_id:return
  preview_payload=request.duplicate(true)
  preview_summary.text="Recipient UID: %s\nCafé: %s\nCase: %s\nSubject: %s\n\n%s\n\nCoins: %s · Items: %s"%[result.recipientUid,result.profileId,result.caseId,result.subject,result.body,str(result.coins),JSON.stringify(result.items)]
  note.text="Review the exact recipient and contents before sending."
  send_button.disabled=false
 )

func _send():
 if preview_payload.is_empty():return
 var request=preview_payload.duplicate(true);send_button.disabled=true;note.text="Checking send status…"
 _call("issue",[request],func(result):
  if bool(result.get("ok",false)):
   note.text="Sent, not claimed · mail %s"%str(result.get("mailId",""));issue_id="";preview_payload={};return
  note.text="Send status uncertain · %s. Check the same case before retrying."%str(result.get("error","Please retry with the same issue ID"))
  send_button.disabled=false
 )
