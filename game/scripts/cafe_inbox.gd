extends RefCounted
## Receipt-backed letters only. Never writes a wallet, campaign, save or CFG.
signal unread_changed(unread:bool)
const Money=preload("res://scripts/cafe_money.gd")
const UpdateNotes=preload("res://scripts/cafe_update_notes.gd")
const WIDTH=460.0
const RETENTION_MSEC=14.0*24*60*60*1000
const KNOWN_CAMPAIGN="little-leaf-0.1.5-existing-profile-compensation"
const INK=Color("554631")
const MUTED=Color("75644f")
const GREEN=Color("426b49")
const MONTHS=["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
var compact_ref:WeakRef
var compact:
 get:return compact_ref.get_ref()
var game
var panel:PanelContainer
var body:VBoxContainer
var heading_box:VBoxContainer
var content:VBoxContainer
var footer:VBoxContainer
var scroll:ScrollContainer
var back_button:Button
var storage_note:Label
var letter_paper:PanelContainer
var letter_body:VBoxContainer
var api
var snapshot:Dictionary={"ok":true,"profileId":"","revision":0,"paid":[],"deferred":[]}
var session_read={}
var detail_id=""
var last_unread=false
var last_snapshot=""
var last_source=""
var last_refresh_second=-1
var rows=[]
# Native has no Web authority. This clock also makes synthetic UI tests repeatable.
var clock:Callable=func():return Time.get_unix_time_from_system()*1000.0
var native_high_water=0.0
var native_future_delivery={}

class EnvelopeButton extends Button:
 var unread=false
 func _ready():resized.connect(queue_redraw)
 func _draw():
  var ink=Color("a99170");var p=Vector2(17,size.y/2-13)
  draw_style_box(_envelope_style(),Rect2(p,Vector2(34,26)))
  draw_polyline(PackedVector2Array([p+Vector2(1,2),p+Vector2(17,14),p+Vector2(33,2)]),ink,1.2,true)
  draw_line(p+Vector2(1,25),p+Vector2(12,14),ink,.8,true)
  draw_line(p+Vector2(33,25),p+Vector2(22,14),ink,.8,true)
  if unread:draw_circle(Vector2(size.x-17,18),4,Color("527958"),true,-1,true)
 func _envelope_style()->StyleBoxFlat:
  var style=StyleBoxFlat.new();style.bg_color=Color("f2e7ce");style.border_color=Color("a99170");style.set_border_width_all(1);style.set_corner_radius_all(2);return style

func _init(owner):
 compact_ref=weakref(owner);game=owner.game

func setup():
 if OS.has_feature("web"):api=JavaScriptBridge.get_interface("__littleLeafInbox")
 panel=compact._panel();panel.name="CompensationInbox"
 body=VBoxContainer.new();body.add_theme_constant_override("separation",14);panel.add_child(body)
 compact.hud.theme_panel(panel,true,26)
 heading_box=VBoxContainer.new();heading_box.add_theme_constant_override("separation",6);body.add_child(heading_box)
 scroll=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO;scroll.follow_focus=true;body.add_child(scroll)
 content=VBoxContainer.new();content.add_theme_constant_override("separation",12);content.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(content)
 footer=VBoxContainer.new();footer.add_theme_constant_override("separation",8);body.add_child(footer)
 compact.hud.theme_scroll(scroll);scroll.focus_mode=Control.FOCUS_ALL;scroll.accessibility_name="Inbox letters"
 for node in [heading_box,content,footer]:node.minimum_size_changed.connect(compact._queue_popup_fit)
 panel.visibility_changed.connect(compact._queue_popup_fit);panel.resized.connect(compact._queue_popup_fit)
 _refresh_snapshot(true);_rebuild();panel.hide();sync()

func fit_popup():
 if not is_instance_valid(panel) or not panel.visible:return
 var view=game.get_viewport().get_visible_rect().size;var insets=compact.hud._safe_insets()
 var width=minf(WIDTH,maxf(0,view.x-insets.x-insets.z-24))
 var padding=panel.get_theme_stylebox("panel").get_minimum_size();var bar=scroll.get_v_scroll_bar()
 var gutter=bar.get_minimum_size().x+scroll.get_theme_constant("scrollbar_h_separation") if bar.visible else 0.0
 body.size.x=maxf(0,width-padding.x);content.size.x=maxf(0,width-padding.x-gutter)
 var fixed_height=heading_box.get_combined_minimum_size().y+footer.get_combined_minimum_size().y+28+padding.y
 var available=maxf(44,minf(620,compact.hud.popup_height_budget())-fixed_height)
 scroll.custom_minimum_size=Vector2(0,minf(available,content.get_combined_minimum_size().y))
 panel.size=Vector2(width,0)
 panel.position=Vector2(insets.x+(view.x-insets.x-insets.z-panel.size.x)/2,insets.y+(view.y-insets.y-insets.w-panel.size.y)/2)

func _persist()->bool:
 return not UpdateNotes.review_mode(OS.get_cmdline_user_args()) and not bool(game.save_writes_suppressed) and game.settings_controls!=null and game.settings_controls.persist_enabled

func _refresh_snapshot(force=false)->bool:
 # Only the verified WebSave cache can supply letters, never a wallet balance.
 var source:Dictionary={"ok":true,"profileId":"","revision":0,"paid":[],"deferred":[]}
 if game.web_save!=null:source=game.web_save.inbox_snapshot
 var raw=JSON.stringify(source);var now=float(clock.call());var second=int(now/1000.0)
 if not force and raw==last_source and second==last_refresh_second:return false
 last_source=raw;last_refresh_second=second
 var next:Dictionary
 if api!=null:
  var projected=JSON.parse_string(str(api.visibleSnapshotJson(raw,_persist())))
  next=projected if projected is Dictionary else {"ok":false}
 else:next=_native_projection(source,now)
 # Clock polling must not rebuild controls or steal focus every second.
 next.erase("displayNow")
 var serialized=JSON.stringify(next)
 if serialized==last_snapshot:return false
 last_snapshot=serialized;snapshot=next.duplicate(true)
 return true

func _native_projection(source:Dictionary,now:float)->Dictionary:
 var next=source.duplicate(true);var visible=[]
 native_high_water=maxf(native_high_water,now)
 for receipt in source.get("paid",[]):
  var delivered=float(receipt.get("grantedAt",0))
  var key=str(source.get("profileId",""))+"/"+str(receipt.get("id",""))+"/"+str(receipt.get("revision",0))
  if native_future_delivery.has(key):delivered=float(native_future_delivery[key])
  elif delivered>native_high_water:
   delivered=native_high_water;native_future_delivery[key]=delivered
  if native_high_water-delivered>=RETENTION_MSEC:
   session_read.erase(key);continue
  var letter=receipt.duplicate(true);letter.deliveredAt=delivered;visible.append(letter)
 next.paid=visible;next.retentionDays=14
 return next

func _key(receipt:Dictionary)->String:
 return str(snapshot.get("profileId",""))+"/"+str(receipt.get("id",""))+"/"+str(receipt.get("revision",0))

func _read(receipt:Dictionary)->bool:
 if session_read.has(_key(receipt)):return true
 if api!=null:return bool(api.isRead(str(snapshot.get("profileId","")),str(receipt.id),int(receipt.revision)))
 return false

func has_unread()->bool:
 if not bool(snapshot.get("ok",false)):return false
 for receipt in snapshot.get("paid",[]):
  if not _read(receipt):return true
 return false

func sync():
 var changed=_refresh_snapshot()
 if changed and panel.visible:_rebuild()
 var unread=has_unread()
 if last_unread!=unread:last_unread=unread;unread_changed.emit(unread)
 if is_instance_valid(storage_note):
  storage_note.text=str(api.notice) if api!=null else ""
  storage_note.visible=storage_note.text!=""

func show():
 _refresh_snapshot(true);detail_id="";_rebuild()
 game.settings.hide();compact._popup_at(panel,WIDTH)
 scroll.scroll_vertical=0;scroll.grab_focus.call_deferred();compact._queue_popup_fit();sync()

func _show_detail(id:String):
 _refresh_snapshot(true);detail_id=id
 for receipt in snapshot.get("paid",[]):
  if str(receipt.id)!=id:continue
  session_read[_key(receipt)]=true
  if api!=null:api.markRead(str(snapshot.get("profileId","")),str(receipt.id),int(receipt.revision),_persist())
  break
 _rebuild();scroll.scroll_vertical=0;scroll.grab_focus.call_deferred();compact._queue_popup_fit();sync()

func _back():
 if detail_id!="":show();return
 panel.hide();game.settings.show();compact._fit_themed_popups()
 compact.settings_inbox.grab_focus.call_deferred();compact.sync()

func _rebuild():
 for container in [heading_box,content,footer]:
  for child in container.get_children():container.remove_child(child);child.queue_free()
 rows.clear();letter_paper=null;letter_body=null
 heading_box.add_child(_label("Inbox",24))
 if not bool(snapshot.get("ok",false)):
  content.add_child(_label("Your letters are unavailable. Try reloading your café.",16,MUTED))
 elif detail_id!="":
  var found=false
  for receipt in snapshot.get("paid",[]):
   if str(receipt.id)!=detail_id:continue
   found=true;_detail(receipt);break
  if not found:detail_id="";_list()
 else:_list()
 storage_note=_label("",13,MUTED);footer.add_child(storage_note);storage_note.hide()
 back_button=game.button("Back to Inbox" if detail_id!="" else "Back to Settings",_back)
 back_button.custom_minimum_size=Vector2(0,44);footer.add_child(back_button)
 compact.hud.theme_panel_contents(panel)
 sync()

func _list():
 var paid:Array=snapshot.get("paid",[]);var deferred:Array=snapshot.get("deferred",[])
 heading_box.add_child(_label("Letters are kept for 14 days.",14,MUTED))
 if paid.is_empty():
  var empty=PanelContainer.new();empty.name="EmptyMailbox";empty.add_theme_stylebox_override("panel",_paper_style(24));content.add_child(empty)
  var words=VBoxContainer.new();words.add_theme_constant_override("separation",8);empty.add_child(words)
  words.add_child(_label("No letters for now",18));words.add_child(_label("New letters will arrive here.",15,MUTED))
 for receipt in paid:_entry(receipt)
 # Eligibility isn't delivery: no fabricated receipt, date, unread dot or letter.
 for pending in deferred:
  var note=_label("Compensation pending · "+Money.amount(int(pending.coins))+" Leaf Coins\nYour wallet is full. It will be added after a successful save with enough room.",14,MUTED)
  note.name="PendingCompensation";content.add_child(note)

func _entry(record:Dictionary):
 var unread=not _read(record)
 var entry=EnvelopeButton.new();entry.unread=unread;entry.name="InboxMessage"
 entry.set_meta("soft_panel_button",true);entry.custom_minimum_size=Vector2(0,88);entry.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 entry.pressed.connect(_show_detail.bind(str(record.id)))
 entry.pressed.connect(func():game.settings_controls.play_sfx("click"))
 for state in ["normal","hover","pressed","hover_pressed","disabled"]:
  var style=_paper_style(0);style.bg_color=Color("fff8e9") if state=="normal" else Color("f0e8d3");style.set_corner_radius_all(6)
  entry.add_theme_stylebox_override(state,style)
 var focus=_paper_style(0);focus.bg_color=Color.TRANSPARENT;focus.border_color=GREEN;focus.set_border_width_all(2);focus.set_corner_radius_all(6);entry.add_theme_stylebox_override("focus",focus)
 var inset=MarginContainer.new();inset.name="EnvelopePadding";inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 for side in ["top","bottom"]:inset.add_theme_constant_override("margin_"+side,14)
 inset.add_theme_constant_override("margin_left",64);inset.add_theme_constant_override("margin_right",28);inset.mouse_filter=Control.MOUSE_FILTER_IGNORE;entry.add_child(inset)
 var words=VBoxContainer.new();words.add_theme_constant_override("separation",5);words.mouse_filter=Control.MOUSE_FILTER_IGNORE;inset.add_child(words)
 words.add_child(_label(_title(record),16));words.add_child(_label(_date(record),13,MUTED))
 entry.accessibility_name=_title(record)+", "+_date(record)+(", unread" if unread else ", read")
 content.add_child(entry);rows.append(entry)
 words.minimum_size_changed.connect(func():entry.custom_minimum_size.y=maxf(88,words.get_combined_minimum_size().y+28))

func _detail(record:Dictionary):
 letter_paper=PanelContainer.new();letter_paper.name="LetterPaper";letter_paper.add_theme_stylebox_override("panel",_paper_style(22));content.add_child(letter_paper)
 letter_body=VBoxContainer.new();letter_body.name="LetterContents";letter_body.add_theme_constant_override("separation",16);letter_paper.add_child(letter_body)
 var heading=VBoxContainer.new();heading.add_theme_constant_override("separation",6);letter_body.add_child(heading)
 heading.add_child(_label(_title(record),20));heading.add_child(_label(_date(record),13,MUTED))
 var line=HSeparator.new();var line_style=StyleBoxLine.new();line_style.color=Color("ddceb4");line_style.thickness=1;line.add_theme_stylebox_override("separator",line_style);letter_body.add_child(line)
 letter_body.add_child(_label("Dear café owner,",16))
 letter_body.add_child(_label(_reason(record),16))
 var payment=PanelContainer.new();payment.name="PaidCompensation";var payment_style=_paper_style(14);payment_style.bg_color=Color("edf0df");payment_style.border_color=Color("d4dcc4");payment.add_theme_stylebox_override("panel",payment_style);letter_body.add_child(payment)
 var amount=VBoxContainer.new();amount.add_theme_constant_override("separation",4);payment.add_child(amount)
 amount.add_child(_label(Money.amount(int(record.coins))+" Leaf Coins",22));amount.add_child(_label("Paid · Added to your wallet",14,GREEN))
 letter_body.add_child(_label("Warmly,\nLittle Leaf",16))

func _title(record:Dictionary)->String:
 return "Café update compensation" if str(record.id)==KNOWN_CAMPAIGN else "Café compensation"

func _reason(record:Dictionary)->String:
 return "Compensation for issues in the 0.1.5 update." if str(record.id)==KNOWN_CAMPAIGN else "We've added compensation to your café. The original reason wasn't recorded."

func _date(record:Dictionary)->String:
 var date=Time.get_datetime_dict_from_unix_time(int(float(record.get("deliveredAt",record.get("grantedAt",0)))/1000.0))
 return "%d %s %d"%[date.day,MONTHS[int(date.month)-1],date.year]

func _paper_style(padding:float)->StyleBoxFlat:
 var style=game._style(Color("fffbf0"),Color("d9c9aa"),4)
 for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:style.set_content_margin(side,padding)
 return style

func _label(words:String,size:int,color:Color=INK)->Label:
 var label=game.label(words,size,color);label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;label.mouse_filter=Control.MOUSE_FILTER_IGNORE
 return label

func handle_input(event:InputEvent)->bool:
 if not panel.visible or not event is InputEventKey or not event.pressed or event.keycode!=KEY_TAB:return false
 var controls:Array=[scroll]
 for row in rows:controls.append(row)
 controls.append(back_button)
 var current=game.get_viewport().gui_get_focus_owner();var index=controls.find(current)
 index=posmod(index+(-1 if event.shift_pressed else 1),controls.size())
 controls[index].grab_focus();return true
