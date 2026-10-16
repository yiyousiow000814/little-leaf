extends RefCounted
## Owner compose surface and bounded player mail/stock projection. Authority lives in Functions.
const CATALOG=["stove","beverage","sink","counter","bin","plant","lamp","bookshelf","rug","divider"]
const MAX_SUBJECT_UNITS=100
const MAX_LETTER_UNITS=2000
const INK=Color("554631")
const MUTED=Color("79735e")
const GREEN=Color("426b49")
var compact_ref:WeakRef
var compact:
 get:return compact_ref.get_ref()
var game
var bridge
var panel:PanelContainer
var frame:VBoxContainer
var header:HBoxContainer
var scroll:ScrollContainer
var form:VBoxContainer
var gift_grid:GridContainer
var preview_card:PanelContainer
var preview_button:Button
var entry:Button
var note:Label
var recipient:LineEdit
var case_id:LineEdit
var subject:LineEdit
var letter:TextEdit
var message_feedback:Label
var coins:SpinBox
var quantities:Dictionary={}
var lookup_summary:Label
var preview_summary:Label
var send_button:Button
var mail_snapshot:Dictionary={"ok":false,"profileId":"","mail":[]}
var mail_page=0
var mail_fetch_generation=0
var mail_error=""
var found:Dictionary={}
var preview_payload:Dictionary={}
var issue_id=""
var request_generation=0
var form_generation=0
var _callbacks:Dictionary={}
var callback_serial=0
var focus_controls:Array=[]

func _init(owner):compact_ref=weakref(owner);game=owner.game

func setup():
 entry=game.button("Support Mail",show);entry.name="OpenSupportMail";entry.visible=false
 game.settings.get_child(0).add_child(entry)
 compact.hud.theme_button(entry)
 panel=compact._panel();panel.name="SupportMailCompose"
 panel.add_theme_stylebox_override("panel",_surface(Color("fcf6e7"),Color("b9cbb7"),18,18))
 frame=VBoxContainer.new();frame.add_theme_constant_override("separation",10);panel.add_child(frame)
 header=HBoxContainer.new();header.add_theme_constant_override("separation",12);frame.add_child(header)
 var heading=VBoxContainer.new();heading.add_theme_constant_override("separation",1);heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(heading)
 heading.add_child(_label("Support mail",23,INK));heading.add_child(_label("A personal note for one player",13,MUTED))
 var back=game.button("Settings",func():panel.hide();game.settings.show();entry.grab_focus.call_deferred());back.accessibility_name="Back to Settings";back.custom_minimum_size=Vector2(88,44);header.add_child(back)
 scroll=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO;scroll.follow_focus=true;scroll.accessibility_name="Support mail form";frame.add_child(scroll)
 compact.hud.theme_scroll(scroll)
 form=VBoxContainer.new();form.add_theme_constant_override("separation",12);form.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(form)
 var recipient_card=_section("Recipient","Find the café attached to an exact 12-digit Player UID.");form.add_child(recipient_card)
 var recipient_body=recipient_card.get_child(0)
 var lookup_row=HBoxContainer.new();lookup_row.add_theme_constant_override("separation",8);recipient_body.add_child(lookup_row)
 recipient=LineEdit.new();recipient.placeholder_text="12-digit Player UID";recipient.size_flags_horizontal=Control.SIZE_EXPAND_FILL;lookup_row.add_child(recipient)
 var find=game.button("Find player",_lookup);find.custom_minimum_size=Vector2(116,44);lookup_row.add_child(find)
 lookup_summary=_label("No player selected yet.",14,MUTED);lookup_summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;recipient_body.add_child(lookup_summary)
 var message_card=_section("Message","Write the note the player will read in Inbox.");form.add_child(message_card)
 var message_body=message_card.get_child(0)
 message_body.add_child(_label("Support case",13,MUTED));case_id=LineEdit.new();case_id.placeholder_text="Case reference";message_body.add_child(case_id)
 message_body.add_child(_label("Subject",13,MUTED));subject=LineEdit.new();subject.placeholder_text="A short, clear subject";message_body.add_child(subject)
 message_body.add_child(_label("Letter",13,MUTED));letter=TextEdit.new();letter.custom_minimum_size.y=112;letter.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;letter.scroll_fit_content_height=true;letter.scroll_past_end_of_file=false;letter.mouse_filter=Control.MOUSE_FILTER_PASS;letter.placeholder_text="Dear café owner,…";message_body.add_child(letter)
 message_feedback=_label("",12,MUTED);message_body.add_child(message_feedback)
 var gift_card=_section("Attachments","Attachments are delivered only after the player claims them.");form.add_child(gift_card)
 var gift_body=gift_card.get_child(0)
 var coin_row=HBoxContainer.new();coin_row.add_theme_constant_override("separation",10);gift_body.add_child(coin_row)
 var coin_label=_label("Leaf Coins  ·  up to 100,000",14,INK);coin_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;coin_row.add_child(coin_label)
 coins=SpinBox.new();coins.min_value=0;coins.max_value=100000;coins.step=1;coins.custom_minimum_size=Vector2(100,44);coin_row.add_child(coins)
 gift_body.add_child(_label("Unplaced items",13,MUTED))
 gift_grid=GridContainer.new();gift_grid.columns=2;gift_grid.add_theme_constant_override("h_separation",8);gift_grid.add_theme_constant_override("v_separation",8);gift_body.add_child(gift_grid)
 for kind in CATALOG:
  var item=PanelContainer.new();item.mouse_filter=Control.MOUSE_FILTER_PASS;item.add_theme_stylebox_override("panel",_surface(Color("f5f8f1"),Color("e1e9dc"),10,8));item.size_flags_horizontal=Control.SIZE_EXPAND_FILL;gift_grid.add_child(item)
  var item_body=HBoxContainer.new();item_body.add_theme_constant_override("separation",6);item.add_child(item_body)
  item_body.add_child(_label(kind.capitalize(),13,INK))
  var amount=SpinBox.new();amount.min_value=0;amount.max_value=10;amount.step=1;amount.custom_minimum_size=Vector2(72,44);item_body.add_child(amount);quantities[kind]=amount
  amount.value_changed.connect(func(_value):_invalidate_preview())
 preview_card=_section("Review your letter","Confirm the exact recipient, message and gifts.");form.add_child(preview_card);preview_card.hide()
 preview_summary=_label("",14,INK);preview_summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;preview_card.get_child(0).add_child(preview_summary)
 var footer=VBoxContainer.new();footer.add_theme_constant_override("separation",6);frame.add_child(footer)
 var actions=HBoxContainer.new();actions.add_theme_constant_override("separation",8);footer.add_child(actions)
 preview_button=game.button("Review letter",_preview);preview_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;actions.add_child(preview_button)
 send_button=game.button("Send letter",_send);send_button.disabled=true;send_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;actions.add_child(send_button)
 note=_label("",13,MUTED);note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;footer.add_child(note)
 for field in [recipient,case_id]:field.text_changed.connect(func(_value):_invalidate_preview())
 subject.text_changed.connect(func(_value):_invalidate_preview();_refresh_message_feedback())
 letter.caret_changed.connect(func():_reveal_letter_caret.call_deferred())
 letter.text_changed.connect(func():_invalidate_preview();_refresh_message_feedback())
 coins.value_changed.connect(func(_value):_invalidate_preview())
 for field in [recipient,case_id,subject,letter,coins.get_line_edit()]:_theme_input(field)
 for amount in quantities.values():_theme_input(amount.get_line_edit())
 for button in [back,find,preview_button]:_theme_action(button,false)
 _theme_action(send_button,true)
 focus_controls=[back,recipient,find,case_id,subject,letter,coins.get_line_edit()]
 for amount in quantities.values():focus_controls.append(amount.get_line_edit())
 focus_controls.append_array([preview_button,send_button])
 for control in [header,form,footer]:control.minimum_size_changed.connect(compact._queue_popup_fit)
 panel.visibility_changed.connect(compact._queue_popup_fit);panel.resized.connect(compact._queue_popup_fit)
 _refresh_message_feedback()
 panel.hide()

func _surface(fill:Color,border:Color,radius:int,padding:int)->StyleBoxFlat:
 var style=game._style(fill,border,radius)
 for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:style.set_content_margin(side,padding)
 return style

func _label(words:String,size:int,color:Color)->Label:
 var value=game.label(words,size,color);value.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;value.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 if size>=16:value.add_theme_font_override("font",compact.hud.font_bold)
 return value

func _section(title:String,description:String)->PanelContainer:
 var card=PanelContainer.new();card.mouse_filter=Control.MOUSE_FILTER_PASS;card.add_theme_stylebox_override("panel",_surface(Color("ffffff"),Color("e0e9dc"),12,14))
 var body=VBoxContainer.new();body.add_theme_constant_override("separation",6);card.add_child(body)
 body.add_child(_label(title,16,GREEN));body.add_child(_label(description,13,MUTED))
 return card

func _theme_action(button:Button,primary:bool):
 button.mouse_filter=Control.MOUSE_FILTER_PASS;button.action_mode=BaseButton.ACTION_MODE_BUTTON_RELEASE
 button.set_meta("soft_panel_button",true)
 button.add_theme_font_override("font",compact.hud.font_bold)
 var base=Color("416b4d") if primary else Color("eef4eb")
 var border=Color("416b4d") if primary else Color("c8d8c6")
 for state in ["normal","hover","pressed","hover_pressed","disabled"]:
  var style=_surface(base,border,10,8)
  if state=="hover":style.bg_color=Color("517b59") if primary else Color("e2eddf")
  if state in ["pressed","hover_pressed"]:style.bg_color=Color("365a40") if primary else Color("d9e8d5")
  if state=="disabled":style.bg_color=Color("e3e8de");style.border_color=Color("d7dfd3")
  button.add_theme_stylebox_override(state,style)
 var focus=_surface(Color.TRANSPARENT,GREEN,10,0);focus.set_border_width_all(2);button.add_theme_stylebox_override("focus",focus)
 for name in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color"]:button.add_theme_color_override(name,Color("ffffff") if primary else INK)
 button.add_theme_color_override("font_disabled_color",MUTED);button.custom_minimum_size.y=maxf(44,button.custom_minimum_size.y)

func fit_popup():
 if not is_instance_valid(panel) or not panel.visible:return
 var view=game.get_viewport().get_visible_rect().size;var insets=compact.hud._safe_insets()
 var width=minf(540,maxf(0,view.x-insets.x-insets.z-24))
 var padding=panel.get_theme_stylebox("panel").get_minimum_size();var bar=scroll.get_v_scroll_bar()
 var gutter=bar.get_minimum_size().x+scroll.get_theme_constant("scrollbar_h_separation") if bar.visible else 0.0
 gift_grid.columns=1 if width<480 else 2
 frame.size.x=maxf(0,width-padding.x);form.size.x=maxf(0,width-padding.x-gutter)
 var fixed=header.get_combined_minimum_size().y+frame.get_child(2).get_combined_minimum_size().y+20+padding.y
 scroll.custom_minimum_size=Vector2(0,minf(maxf(44,compact.hud.popup_height_budget()-fixed),form.get_combined_minimum_size().y))
 panel.size=Vector2(width,0)
 panel.position=Vector2(insets.x+(view.x-insets.x-insets.z-panel.size.x)/2,insets.y+(view.y-insets.y-insets.w-panel.size.y)/2)

# The form owns scrolling, including caret visibility in an expanding letter.
func _reveal_letter_caret():
 if not letter.has_focus():return
 var caret_y=letter.global_position.y+letter.get_caret_draw_pos().y
 var top=scroll.global_position.y+8
 var bottom=scroll.global_position.y+scroll.size.y-letter.get_line_height()-8
 if caret_y>bottom:scroll.scroll_vertical+=int(ceil(caret_y-bottom))
 elif caret_y<top:scroll.scroll_vertical-=int(ceil(top-caret_y))

func _theme_input(field:Control):
 var normal=game._style(Color("fffdf8"),Color("c8d8c6"),9)
 for side in [SIDE_LEFT,SIDE_RIGHT]:normal.set_content_margin(side,9)
 for side in [SIDE_TOP,SIDE_BOTTOM]:normal.set_content_margin(side,5)
 field.add_theme_stylebox_override("normal",normal)
 var focus=game._style(Color.TRANSPARENT,GREEN,9);focus.set_border_width_all(2)
 field.add_theme_stylebox_override("focus",focus)
 field.add_theme_color_override("font_color",INK)
 field.add_theme_color_override("font_placeholder_color",MUTED)
 field.add_theme_color_override("caret_color",INK)
 if field is LineEdit:field.custom_minimum_size.y=44

func _display_profile(value)->String:
 var id=str(value)
 return id.substr(0,18)+"\n"+id.substr(18) if id.length()>18 else id

# JavaScript String.length counts UTF-16 units; Godot String.length counts code points.
func _utf16_units(value:String)->int:
 var total=0
 for index in value.length():total+=2 if value.unicode_at(index)>0xffff else 1
 return total

func _refresh_message_feedback():
 var subject_units=_utf16_units(subject.text)
 var letter_units=_utf16_units(letter.text)
 message_feedback.text="Subject %d/%d · Letter %d/%d"%[subject_units,MAX_SUBJECT_UNITS,letter_units,MAX_LETTER_UNITS]
 message_feedback.add_theme_color_override("font_color",Color("aa5147") if subject_units>MAX_SUBJECT_UNITS or letter_units>MAX_LETTER_UNITS else MUTED)

func _valid_public_uid(value:String)->bool:
 if value.length()!=12:return false
 for index in value.length():
  var point=value.unicode_at(index)
  if point<48 or point>57 or (index==0 and point==48):return false
 return true

func _valid_case(value:String)->bool:
 if value.length()<3 or value.length()>80:return false
 for index in value.length():
  var point=value.unicode_at(index)
  var alpha=(point>=65 and point<=90) or (point>=97 and point<=122)
  var digit=point>=48 and point<=57
  if not alpha and not digit and (index==0 or (point!=46 and point!=95 and point!=45)):return false
 return true

func _has_forbidden_controls(value:String)->bool:
 for index in value.length():
  var point=value.unicode_at(index)
  if point<=8 or point in [11,12] or (point>=14 and point<=31):return true
 return false

func _field_error()->String:
 var uid=recipient.text.strip_edges()
 if not _valid_public_uid(uid):return "Enter an exact 12-digit Player UID."
 if found.is_empty() or str(found.get("publicUid",""))!=uid:return "Find the exact player UID first."
 if not _valid_case(case_id.text.strip_edges()):return "Use a 3–80 character case reference: ASCII letters, digits, period, underscore or hyphen."
 var subject_units=_utf16_units(subject.text)
 if subject.text.strip_edges().is_empty():return "Add a subject."
 if subject_units>MAX_SUBJECT_UNITS:return "Shorten the subject to 100 characters (emoji count as two)."
 var letter_units=_utf16_units(letter.text)
 if letter.text.strip_edges().is_empty():return "Write a letter."
 if letter_units>MAX_LETTER_UNITS:return "Shorten the letter to 2,000 characters (emoji count as two)."
 if _has_forbidden_controls(subject.text+letter.text):return "Remove unsupported control characters from the message."
 var has_gift=int(coins.value)>0
 for amount in quantities.values():
  if int(amount.value)>0:has_gift=true;break
 if not has_gift:return "Choose Leaf Coins or at least one gift item."
 return ""

func _call(name:String,args:Array,handler:Callable):
 if not OS.has_feature("web") or not JavaScriptBridge.eval("typeof window.LittleLeafSupportMail === 'object' && window.LittleLeafSupportMail !== null"):return
 bridge=JavaScriptBridge.get_interface("LittleLeafSupportMail")
 if bridge==null:return
 if _callbacks.size()>=12:
  note.text="Support is busy. Wait for the current request.";return
 var generation=request_generation
 callback_serial+=1
 var callback_id=callback_serial
 var callback=JavaScriptBridge.create_callback(func(values):
  _callbacks.erase(callback_id)
  if generation!=request_generation or game==null or not game.is_inside_tree():return
  var value=JSON.parse_string(str(values[0])) if values.size()>0 else null
  handler.call(value if value is Dictionary else {"ok":false,"error":"Invalid support response."})
 )
 _callbacks[callback_id]=callback
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
 mail_fetch_generation+=1
 var fetch=mail_fetch_generation
 _call("list",[""],func(result):
  if fetch!=mail_fetch_generation:return
  if bool(result.get("ok",false)) and str(result.get("profileId",""))==game.web_save.profile_id and result.get("mail") is Array:
   mail_snapshot={"ok":true,"profileId":result.profileId,"mail":result.mail.slice(0,20),"nextCursor":result.get("nextCursor")}
   mail_page=0
   mail_error=""
  else:mail_error=str(result.get("error","Mail is unavailable."))
  if compact.inbox!=null:compact.inbox.sync()
 )

func load_more_mail():
 var cursor=mail_snapshot.get("nextCursor")
 if not bool(mail_snapshot.get("ok",false)) or cursor==null:return
 mail_fetch_generation+=1
 var fetch=mail_fetch_generation
 _call("list",[str(cursor)],func(result):
  if fetch!=mail_fetch_generation:return
  if not bool(result.get("ok",false)) or str(result.get("profileId",""))!=str(mail_snapshot.get("profileId","")) or not result.get("mail") is Array:
   mail_error=str(result.get("error","Older letters are unavailable."));return
  # One bounded page at a time; older unclaimed letters remain reachable.
  mail_snapshot.mail=result.mail.slice(0,20)
  mail_snapshot.nextCursor=result.get("nextCursor")
  mail_page+=1;mail_error=""
  if compact.inbox!=null:compact.inbox.sync()
 )

func claim_result(ok:bool,reason:String):
 mail_error="" if ok else reason
 if ok:refresh_mail();refresh_stock()

func reset():
 request_generation+=1;mail_fetch_generation+=1;mail_page=0;entry.visible=false;mail_snapshot={"ok":false,"profileId":"","mail":[]}
 found={};preview_payload={};issue_id="";_callbacks.clear();panel.hide()

func refresh_capabilities():
 if game.web_save==null or not game.web_save.ready:return
 _call("capabilities",[],func(result):entry.visible=bool(result.get("ok",false)) and bool(result.get("canLookup",false)) and bool(result.get("canIssue",false)))
 if compact.inbox!=null:compact.inbox.sync()

func show():
 if not entry.visible:return
 game.settings.hide();compact._popup_at(panel,540);note.text="";panel.show();scroll.scroll_vertical=0;_invalidate_preview()
 compact._queue_popup_fit()

func _invalidate_preview(reset_issue=true):
 form_generation+=1
 if reset_issue:issue_id=""
 preview_payload={};send_button.disabled=true;preview_summary.text="";preview_card.hide()

func _lookup():
 _invalidate_preview();found={}
 if not _valid_public_uid(recipient.text.strip_edges()):
  lookup_summary.text="Enter an exact 12-digit Player UID."
  return
 lookup_summary.text="Checking exact player UID…"
 _call("lookup",[recipient.text.strip_edges()],func(result):
  if not bool(result.get("ok",false)):
   lookup_summary.text=str(result.get("error","Player unavailable."));return
  if str(result.get("publicUid",""))!=recipient.text.strip_edges():return
  found=result
  var saved_at=float(result.get("savedAt",0))
  var saved_label=Time.get_datetime_string_from_unix_time(int(saved_at/1000.0))+" UTC" if saved_at>0 else "Unavailable"
  var recent:Array=result.get("recentMail",[])
  var recent_text="None recorded" if recent.is_empty() else ""
  for mail in recent:
   recent_text+=("\n" if recent_text!="" else "")+str(mail.get("caseId","Case unavailable"))+" · "+str(mail.get("status","Unknown"))
  lookup_summary.text="UID %s  ·  save r%d\nCafé profile %s\nRecorded %s (%s)  ·  %s\n%s\nRecent letters: %s"%[result.publicUid,int(result.revision),_display_profile(result.profileId),saved_label,str(result.timeSource),str(result.device),str(result.evidence),recent_text]
 )

func _request()->Dictionary:
 if found.is_empty() or str(found.get("publicUid",""))!=recipient.text.strip_edges():return {}
 var items=[]
 for kind in CATALOG:
  var count=int(quantities[kind].value)
  if count>0:items.append({"catalogId":kind,"quantity":count})
 if issue_id=="":issue_id=str(JavaScriptBridge.eval("crypto.randomUUID()"))
 return {"issueId":issue_id,"recipientPublicUid":recipient.text.strip_edges(),"profileId":str(found.profileId),"caseId":case_id.text.strip_edges(),"subject":subject.text,"body":letter.text,"coins":int(coins.value),"items":items}

func _preview():
 var error=_field_error()
 if error!="":note.text=error;return
 var request=_request()
 if request.is_empty():note.text="Find the exact player UID first.";return
 _invalidate_preview(false);var generation=form_generation;note.text="Checking letter and gifts…"
 _call("preview",[request],func(result):
  if generation!=form_generation:return
  if not bool(result.get("ok",false)):
   note.text=str(result.get("error","Preview unavailable."));return
  if str(result.get("issueId",""))!=issue_id:return
  preview_payload=request.duplicate(true)
  var gifts="%d Leaf Coins"%int(result.get("coins",0))
  for item in result.get("items",[]):gifts+="\n%s ×%d"%[str(item.get("catalogId","")).capitalize(),int(item.get("quantity",0))]
  preview_summary.text="Player UID: %s\nCafé profile:\n%s\nCase: %s\nSubject: %s\n\n%s\n\nGifts: %s"%[result.recipientPublicUid,_display_profile(result.profileId),result.caseId,result.subject,result.body,gifts]
  preview_card.show();_reveal_review()
  note.text="Review the exact recipient and contents before sending."
  send_button.disabled=false
 )

func _reveal_review():
 # Wait for the newly visible card and status to settle before choosing its offset.
 await game.get_tree().process_frame
 if is_instance_valid(preview_card) and preview_card.visible:scroll.scroll_vertical=int(preview_card.position.y)

func _send():
 if preview_payload.is_empty():return
 var request=preview_payload.duplicate(true);send_button.disabled=true;note.text="Checking send status…"
 _call("issue",[request],func(result):
  if bool(result.get("ok",false)):
   note.text="Sent, not claimed · mail %s"%str(result.get("mailId",""));issue_id="";preview_payload={};return
  note.text="Send status uncertain · %s. Check the same case before retrying."%str(result.get("error","Please retry with the same issue ID"))
  send_button.disabled=false
 )

func handle_input(event:InputEvent)->bool:
 if not panel.visible or not event is InputEventKey or not event.pressed or event.keycode!=KEY_TAB:return false
 var available=focus_controls.filter(func(control):return control.is_visible_in_tree() and not (control is Button and control.disabled))
 var current=game.get_viewport().gui_get_focus_owner()
 var index=posmod(available.find(current)+(-1 if event.shift_pressed else 1),available.size())
 available[index].grab_focus()
 return true
