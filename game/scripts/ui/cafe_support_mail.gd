extends RefCounted
## Owner compose surface and bounded player mail/stock projection. Authority lives in Functions.
const Recipients=preload("res://scripts/ui/cafe_mail_recipients.gd")
const MailFrame=preload("res://scripts/ui/cafe_mail_frame.gd")
const GiftCatalog=preload("res://scripts/ui/cafe_mail_gift_catalog.gd")
const RESULT_PAGE_SIZE=4
const SELECTED_PAGE_SIZE=3
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
var recipient:TextEdit
var recipient_mode="selected"
var selected_button:Button
var all_button:Button
var recipient_input:VBoxContainer
var audience_feedback:Label
var attachment_summary:Label
var item_picker:VBoxContainer
var item_toggle:Button
var subtitle:Label
var footer:VBoxContainer
var gift_catalog=GiftCatalog.new()
var gift_search:LineEdit
var gift_category="All"
var gift_categories:GridContainer
var category_buttons:Dictionary={}
var gift_filters:VBoxContainer
var result_slots:Array=[]
var result_page=0
var result_page_label:Label
var result_previous:Button
var result_next:Button
var result_empty:Label
var selected_box:VBoxContainer
var selected_slots:Array=[]
var selected_page=0
var selected_title:Label
var selected_page_label:Label
var selected_previous:Button
var selected_next:Button
var find_button:Button
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
var lookup_generation=0
var _callbacks:Dictionary={}
var callback_serial=0
var focus_controls:Array=[]
var can_issue_many=false
var can_issue_all=false
var preview_pending=false
var preview_status=""
var preview_expires_at=0.0
var preview_recipient_count=0
var reviewed_text=""
var send_pending=false
var delivery_started=false
var delivery_terminal=false

func _init(owner):compact_ref=weakref(owner);game=owner.game

func setup():
 entry=game.button("Support Mail",show);entry.name="OpenSupportMail";entry.visible=false
 game.settings.get_child(0).add_child(entry)
 compact.hud.theme_button(entry)
 panel=compact._panel();panel.name="SupportMailCompose"
 compact.hud.theme_panel(panel,true,0);MailFrame.apply(panel,640)
 frame=VBoxContainer.new();frame.add_theme_constant_override("separation",10);panel.add_child(frame)
 header=HBoxContainer.new();header.add_theme_constant_override("separation",12);frame.add_child(header)
 var heading=VBoxContainer.new();heading.add_theme_constant_override("separation",1);heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(heading)
 heading.add_child(_label("Little Leaf post",22,INK));subtitle=_label("A note for our café owners",13,MUTED);heading.add_child(subtitle)
 var back=game.button("Settings",func():panel.hide();game.settings.show();entry.grab_focus.call_deferred());back.accessibility_name="Back to Settings";back.custom_minimum_size=Vector2(88,44);header.add_child(back)
 scroll=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO;scroll.follow_focus=true;scroll.accessibility_name="Support mail form";frame.add_child(scroll)
 compact.hud.theme_scroll(scroll)
 form=VBoxContainer.new();form.add_theme_constant_override("separation",12);form.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(form)
 var recipient_card=_section("To our café owners","");form.add_child(recipient_card)
 var recipient_body=recipient_card.get_child(0)
 var modes=HBoxContainer.new();modes.add_theme_constant_override("separation",8);recipient_body.add_child(modes)
 selected_button=game.button("Selected UIDs",func():_set_recipient_mode("selected"));all_button=game.button("All players",func():_set_recipient_mode("all"))
 for mode in [selected_button,all_button]:
  mode.toggle_mode=true;mode.size_flags_horizontal=Control.SIZE_EXPAND_FILL;modes.add_child(mode);_theme_action(mode,false)
 selected_button.set_pressed_no_signal(true)
 all_button.disabled=true
 recipient_input=VBoxContainer.new();recipient_input.add_theme_constant_override("separation",6);recipient_body.add_child(recipient_input)
 recipient=TextEdit.new();recipient.placeholder_text="Paste one or more 12-digit Player UIDs";recipient.custom_minimum_size.y=66;recipient.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;recipient.scroll_fit_content_height=true;recipient.scroll_past_end_of_file=false;recipient.mouse_filter=Control.MOUSE_FILTER_PASS;recipient_input.add_child(recipient)
 recipient.text_changed.connect(func():_invalidate_recipient();_refresh_audience_feedback())
 recipient.caret_changed.connect(func():_reveal_editor_caret.call_deferred(recipient))
 find_button=game.button("Check one UID",_lookup);recipient_input.add_child(find_button)
 audience_feedback=_label("",13,MUTED);recipient_body.add_child(audience_feedback)
 lookup_summary=_label("No player checked yet.",13,MUTED);lookup_summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;recipient_body.add_child(lookup_summary)
 var gift_card=_section("Coins & items","Choose what each player will receive.");form.add_child(gift_card)
 var gift_body=gift_card.get_child(0)
 var coin_row=HBoxContainer.new();coin_row.add_theme_constant_override("separation",10);gift_body.add_child(coin_row)
 var coin_art=compact.hud._picture(coin_row,compact.hud._texture("coin"));coin_art.custom_minimum_size=Vector2(32,32);coin_art.size_flags_vertical=Control.SIZE_SHRINK_CENTER
 var coin_label=_label("Leaf Coins",16,INK);coin_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;coin_row.add_child(coin_label)
 coins=SpinBox.new();coins.min_value=0;coins.max_value=100000;coins.step=1;coins.custom_minimum_size=Vector2(122,44);coin_row.add_child(coins)
 coins.accessibility_name="Leaf Coins per player, from zero to one hundred thousand"
 _setup_gift_picker(gift_body)
 var message_card=_section("Message","Write the note the player will read in Inbox.");form.add_child(message_card)
 var message_body=message_card.get_child(0)
 message_body.add_child(_label("Support case",13,MUTED));case_id=LineEdit.new();case_id.placeholder_text="Case reference";message_body.add_child(case_id)
 message_body.add_child(_label("Subject",13,MUTED));subject=LineEdit.new();subject.placeholder_text="A short, clear subject";message_body.add_child(subject)
 message_body.add_child(_label("Letter",13,MUTED));letter=TextEdit.new();letter.custom_minimum_size.y=112;letter.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;letter.scroll_fit_content_height=true;letter.scroll_past_end_of_file=false;letter.mouse_filter=Control.MOUSE_FILTER_PASS;letter.placeholder_text="Dear café owner,…";message_body.add_child(letter)
 message_feedback=_label("",12,MUTED);message_body.add_child(message_feedback)
 preview_card=_section("Review your letter","");form.add_child(preview_card);preview_card.hide()
 preview_summary=_label("",14,INK);preview_summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;preview_card.get_child(0).add_child(preview_summary)
 footer=VBoxContainer.new();footer.add_theme_constant_override("separation",6);frame.add_child(footer)
 attachment_summary=_label("",13,GREEN);attachment_summary.name="MailAttachmentSummary";footer.add_child(attachment_summary)
 var actions=HBoxContainer.new();actions.add_theme_constant_override("separation",8);footer.add_child(actions)
 preview_button=game.button("Review letter",_preview);preview_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;actions.add_child(preview_button)
 send_button=game.button("Send letter",_send);send_button.disabled=true;send_button.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;send_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;actions.add_child(send_button)
 note=_label("",13,MUTED);note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;note.max_lines_visible=2;note.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;footer.add_child(note)
 case_id.text_changed.connect(func(_value):_invalidate_preview())
 subject.text_changed.connect(func(_value):_invalidate_preview();_refresh_message_feedback())
 letter.caret_changed.connect(func():_reveal_editor_caret.call_deferred(letter))
 letter.text_changed.connect(func():_invalidate_preview();_refresh_message_feedback())
 coins.value_changed.connect(func(_value):_invalidate_preview();_refresh_attachment_summary())
 for field in [recipient,case_id,subject,letter,coins.get_line_edit()]:_theme_input(field)
 for button in [back,find_button,item_toggle,preview_button]:_theme_action(button,false)
 _theme_action(send_button,true)
 focus_controls=[back,selected_button,all_button,recipient,find_button,coins.get_line_edit()]
 for slot in selected_slots:focus_controls.append_array([slot.minus,slot.plus])
 focus_controls.append_array([selected_previous,selected_next,item_toggle,gift_search])
 focus_controls.append_array(category_buttons.values())
 for slot in result_slots:focus_controls.append(slot.add)
 focus_controls.append_array([result_previous,result_next,case_id,subject,letter,preview_button,send_button])
 for control in [header,form,footer]:control.minimum_size_changed.connect(compact._queue_popup_fit)
 panel.visibility_changed.connect(compact._queue_popup_fit);panel.resized.connect(compact._queue_popup_fit)
 _refresh_message_feedback();_refresh_audience_feedback();_refresh_attachment_summary()
 panel.hide()

func _setup_gift_picker(parent:VBoxContainer):
 var rows:Array=[]
 for spec in game.model.catalog:
  if str(spec.kind) in CATALOG:
   rows.append({"id":str(spec.kind),"name":game.model.name_of(str(spec.kind)),"category":game._catalog_group(str(spec.kind))})
 gift_catalog.configure(rows)
 selected_box=VBoxContainer.new();selected_box.add_theme_constant_override("separation",6);parent.add_child(selected_box)
 selected_title=_label("Selected items",14,GREEN);selected_box.add_child(selected_title)
 for index in SELECTED_PAGE_SIZE:
  var card=PanelContainer.new();card.mouse_filter=Control.MOUSE_FILTER_PASS;card.add_theme_stylebox_override("panel",_surface(Color("edf0df"),Color("d4dcc4"),6,6));selected_box.add_child(card)
  var row=HBoxContainer.new();row.add_theme_constant_override("separation",6);card.add_child(row)
  var title=_label("",13,INK);row.add_child(title)
  var minus=game.button("−",_change_selected.bind(index,-1));minus.custom_minimum_size=Vector2(44,44);row.add_child(minus);_theme_action(minus,false)
  var amount=_label("0",14,INK);amount.custom_minimum_size=Vector2(24,44);amount.size_flags_horizontal=Control.SIZE_SHRINK_CENTER;amount.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;amount.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;row.add_child(amount)
  var plus=game.button("+",_change_selected.bind(index,1));plus.custom_minimum_size=Vector2(44,44);row.add_child(plus);_theme_action(plus,false)
  selected_slots.append({"card":card,"title":title,"amount":amount,"minus":minus,"plus":plus,"id":""})
 var selected_nav=HBoxContainer.new();selected_nav.add_theme_constant_override("separation",6);selected_box.add_child(selected_nav)
 selected_previous=game.button("‹",_move_selected_page.bind(-1));selected_previous.custom_minimum_size=Vector2(44,44);selected_nav.add_child(selected_previous);_theme_action(selected_previous,false);selected_previous.accessibility_name="Previous selected items"
 selected_page_label=_label("",12,MUTED);selected_page_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;selected_nav.add_child(selected_page_label)
 selected_next=game.button("›",_move_selected_page.bind(1));selected_next.custom_minimum_size=Vector2(44,44);selected_nav.add_child(selected_next);_theme_action(selected_next,false);selected_next.accessibility_name="Next selected items"
 item_toggle=game.button("Add item attachments",func():item_picker.visible=not item_picker.visible;_refresh_attachment_summary();compact._queue_popup_fit());parent.add_child(item_toggle)
 item_picker=VBoxContainer.new();item_picker.add_theme_constant_override("separation",6);parent.add_child(item_picker);item_picker.hide()
 gift_filters=VBoxContainer.new();gift_filters.add_theme_constant_override("separation",6);item_picker.add_child(gift_filters)
 gift_search=LineEdit.new();gift_search.placeholder_text="Search item names";gift_search.size_flags_horizontal=Control.SIZE_EXPAND_FILL;gift_search.accessibility_name="Search item catalogue";gift_filters.add_child(gift_search);_theme_input(gift_search)
 gift_search.text_changed.connect(func(_value):result_page=0;_refresh_gift_results())
 gift_categories=GridContainer.new();gift_categories.columns=2;gift_categories.add_theme_constant_override("h_separation",6);gift_categories.add_theme_constant_override("v_separation",6);gift_filters.add_child(gift_categories)
 # Inline categories belong to the same clipped form as the results. No native
 # popup can escape the wood face or cover the fixed Review/Send actions.
 for category in gift_catalog.categories():
  var button=game.button(str(category),_select_gift_category.bind(str(category)))
  button.toggle_mode=true;button.button_pressed=category==gift_category;button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
  button.accessibility_name="Item category: "+str(category);gift_categories.add_child(button);_theme_action(button,false);category_buttons[category]=button
 gift_grid=GridContainer.new();gift_grid.columns=2;gift_grid.add_theme_constant_override("h_separation",8);gift_grid.add_theme_constant_override("v_separation",6);item_picker.add_child(gift_grid)
 for index in RESULT_PAGE_SIZE:
  var card=PanelContainer.new();card.mouse_filter=Control.MOUSE_FILTER_PASS;card.add_theme_stylebox_override("panel",_surface(Color("f3ecd8"),Color("d9c9aa"),6,6));card.size_flags_horizontal=Control.SIZE_EXPAND_FILL;gift_grid.add_child(card)
  var row=HBoxContainer.new();row.add_theme_constant_override("separation",6);card.add_child(row)
  var art_slot=Control.new();art_slot.mouse_filter=Control.MOUSE_FILTER_IGNORE;art_slot.custom_minimum_size=Vector2(40,48);row.add_child(art_slot)
  var title=_label("",13,INK);row.add_child(title)
  var add=game.button("+",_add_result.bind(index));add.custom_minimum_size=Vector2(44,44);row.add_child(add);_theme_action(add,false)
  result_slots.append({"card":card,"title":title,"art_slot":art_slot,"add":add,"id":""})
 result_empty=_label("No items match this search.",13,MUTED);item_picker.add_child(result_empty)
 var nav=HBoxContainer.new();nav.add_theme_constant_override("separation",6);item_picker.add_child(nav)
 result_previous=game.button("‹",_move_result_page.bind(-1));result_previous.custom_minimum_size=Vector2(44,44);nav.add_child(result_previous);_theme_action(result_previous,false);result_previous.accessibility_name="Previous item results"
 result_page_label=_label("",12,MUTED);result_page_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;nav.add_child(result_page_label)
 result_next=game.button("›",_move_result_page.bind(1));result_next.custom_minimum_size=Vector2(44,44);nav.add_child(result_next);_theme_action(result_next,false);result_next.accessibility_name="Next item results"
 parent.add_child(_label("Claim → items in Storage, coins in wallet.",12,MUTED))

func _select_gift_category(category:String):
 if not category_buttons.has(category):return
 gift_category=category
 for name in category_buttons:category_buttons[name].button_pressed=name==category
 result_page=0;_refresh_gift_results()

func _refresh_gift_results():
 if gift_grid==null:return
 var page=GiftCatalog.page(gift_catalog.matching(gift_category,gift_search.text),result_page,RESULT_PAGE_SIZE)
 result_page=int(page.page)
 for index in result_slots.size():
  var slot:Dictionary=result_slots[index];slot.card.visible=index<page.rows.size()
  if not slot.card.visible:continue
  var entry:Dictionary=page.rows[index];var id=str(entry.id)
  if slot.id!=id:
   for art in slot.art_slot.get_children():slot.art_slot.remove_child(art);art.queue_free()
   if compact.shop_ui!=null and id in CATALOG:
    var art=compact.shop_ui._illustration(slot.art_slot,id);compact.shop_ui._fit_thumbnail(id,art,Vector2(40,48))
  slot.id=id;slot.title.text=str(entry.name)
  var amount=int(quantities.get(id,0))
  slot.add.disabled=delivery_started or not id in CATALOG or amount>=10
  slot.add.text="+";slot.add.accessibility_name="Add "+str(entry.name)+" to letter";slot.add.tooltip_text="Selected: %d"%amount
 result_empty.visible=page.total==0
 result_page_label.text="%d items · %d / %d"%[page.total,result_page+1,page.pages] if page.total>0 else "0 items"
 result_previous.disabled=result_page==0;result_next.disabled=result_page+1>=page.pages
 compact._queue_popup_fit()

func _refresh_selected_gifts():
 if selected_box==null:return
 var rows=gift_catalog.entries.filter(func(entry):return int(quantities.get(entry.id,0))>0)
 selected_box.visible=not rows.is_empty()
 var page=GiftCatalog.page(rows,selected_page,SELECTED_PAGE_SIZE);selected_page=int(page.page)
 var count=0
 for row in rows:count+=int(quantities.get(row.id,0))
 selected_title.text="Selected items · %d items"%count
 for index in selected_slots.size():
  var slot:Dictionary=selected_slots[index];slot.card.visible=index<page.rows.size()
  if not slot.card.visible:slot.id="";continue
  var entry:Dictionary=page.rows[index];slot.id=str(entry.id);slot.title.text=str(entry.name)
  var amount=int(quantities.get(entry.id,0));slot.amount.text=str(amount);slot.plus.disabled=delivery_started or amount>=10;slot.minus.disabled=delivery_started
  slot.amount.accessibility_name=str(entry.name)+" quantity per player"
  slot.minus.accessibility_name=("Remove " if amount==1 else "One fewer ")+str(entry.name);slot.plus.accessibility_name="One more "+str(entry.name)
 selected_previous.get_parent().visible=page.pages>1
 selected_page_label.text="%d types · %d / %d"%[page.total,selected_page+1,page.pages]
 selected_previous.disabled=selected_page==0;selected_next.disabled=selected_page+1>=page.pages

func _set_gift_quantity(id:String,amount:int):
 if delivery_started:return
 if not id in CATALOG:return
 if amount<=0:quantities.erase(id)
 else:quantities[id]=mini(10,amount)
 _invalidate_preview();_refresh_attachment_summary();compact._queue_popup_fit()

func _add_result(index:int):
 var id=str(result_slots[index].id);_set_gift_quantity(id,int(quantities.get(id,0))+1)
func _change_selected(index:int,change:int):
 var id=str(selected_slots[index].id);_set_gift_quantity(id,int(quantities.get(id,0))+change)
func _remove_selected(index:int):_set_gift_quantity(str(selected_slots[index].id),0)
func _move_result_page(direction:int):result_page+=direction;_refresh_gift_results();_reveal_picker_navigation.call_deferred()
func _reveal_picker_navigation():
 await game.get_tree().process_frame
 if is_instance_valid(item_picker) and item_picker.is_visible_in_tree():scroll.ensure_control_visible(result_next)
func _move_selected_page(direction:int):selected_page+=direction;_refresh_selected_gifts();compact._queue_popup_fit()

func _surface(fill:Color,border:Color,radius:int,padding:int)->StyleBoxFlat:
 var style=game._style(fill,border,radius)
 for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:style.set_content_margin(side,padding)
 return style

func _label(words:String,size:int,color:Color)->Label:
 var value=game.label(words,size,color);value.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;value.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 if size>=16:value.add_theme_font_override("font",compact.hud.font_bold)
 return value

func _section(title:String,description:String)->PanelContainer:
 var card=PanelContainer.new();card.mouse_filter=Control.MOUSE_FILTER_PASS;card.add_theme_stylebox_override("panel",_surface(Color("fffbf0"),Color("d9c9aa"),6,12))
 var body=VBoxContainer.new();body.add_theme_constant_override("separation",6);card.add_child(body)
 body.add_child(_label(title,17,GREEN))
 if description!="":body.add_child(_label(description,13,MUTED))
 return card

func _theme_action(button:Button,primary:bool):
 button.mouse_filter=Control.MOUSE_FILTER_PASS;button.action_mode=BaseButton.ACTION_MODE_BUTTON_RELEASE
 compact.hud.theme_button(button,primary)

func _set_recipient_mode(mode:String):
 if delivery_started or (mode=="all" and not can_issue_all):return
 recipient_mode=mode;_invalidate_recipient()
 selected_button.set_pressed_no_signal(mode=="selected");all_button.set_pressed_no_signal(mode=="all")
 recipient_input.visible=mode=="selected"
 lookup_summary.text="No player checked yet." if mode=="selected" else "Review freezes the cloud cafés found by the server."
 _refresh_audience_feedback();compact._queue_popup_fit()

func _invalidate_recipient():
 lookup_generation+=1;found={};_invalidate_preview()
 lookup_summary.text="No player checked yet."

func _refresh_audience_feedback():
 if recipient_mode=="all":
  audience_feedback.text="All players · recipient count confirmed in Review."
  audience_feedback.add_theme_color_override("font_color",MUTED)
  return
 var parsed=Recipients.parse(recipient.text)
 if not parsed.invalid.is_empty():
  var invalid_preview:Array=[]
  for token in parsed.invalid.slice(0,3):invalid_preview.append(str(token).substr(0,24)+("…" if str(token).length()>24 else ""))
  audience_feedback.text="Fix invalid UID entries: "+", ".join(invalid_preview)+("…" if parsed.invalid.size()>3 else "")
 elif parsed.too_many:audience_feedback.text="Use at most %d unique UIDs per batch."%Recipients.MAX_RECIPIENTS
 elif parsed.uids.is_empty():audience_feedback.text="Separate UIDs with a new line, comma or space."
 else:
  audience_feedback.text="%d unique UID%s"%[parsed.uids.size(),"" if parsed.uids.size()==1 else "s"]
  if parsed.duplicates>0:audience_feedback.text+=" · %d duplicate%s removed"%[parsed.duplicates,"" if parsed.duplicates==1 else "s"]
  if parsed.uids.size()>1 and not can_issue_many:audience_feedback.text+=" · batch permission required"
 find_button.disabled=delivery_started or parsed.uids.size()!=1 or not parsed.invalid.is_empty() or parsed.too_many
 audience_feedback.add_theme_color_override("font_color",Color("aa5147") if not parsed.invalid.is_empty() or parsed.too_many else MUTED)

func _refresh_attachment_summary():
 if attachment_summary==null:return
 var count=0
 for amount in quantities.values():count+=int(amount)
 attachment_summary.text="Each player: %d Leaf Coins · %d item%s"%[int(coins.value),count,"" if count==1 else "s"]
 item_toggle.text="Close item catalogue" if item_picker.visible else "Add item attachments"
 _refresh_selected_gifts()
 _refresh_gift_results()

func _selected_uid()->String:
 var parsed=Recipients.parse(recipient.text)
 return str(parsed.uids[0]) if parsed.invalid.is_empty() and parsed.uids.size()==1 else ""

func _recipient_error()->String:
 if recipient_mode=="all":return "" if can_issue_all else "All-player mail is not enabled for this account."
 var parsed=Recipients.parse(recipient.text)
 if parsed.uids.is_empty() or not parsed.invalid.is_empty():return "Enter exact 12-digit Player UIDs and fix invalid entries."
 if parsed.too_many:return "Use at most %d unique UIDs per batch."%Recipients.MAX_RECIPIENTS
 if parsed.uids.size()>1 and not can_issue_many:return "Multiple-UID mail is not enabled for this account."
 return ""

func fit_popup():
 if not is_instance_valid(panel) or not panel.visible:return
 var view=game.get_viewport().get_visible_rect().size;var insets=compact.hud._safe_insets()
 var width=minf(640,maxf(0,view.x-insets.x-insets.z-24))
 MailFrame.apply(panel,width)
 subtitle.visible=width>=520 and view.y>=500
 var padding=panel.get_theme_stylebox("panel").get_minimum_size();var bar=scroll.get_v_scroll_bar()
 var gutter=bar.get_minimum_size().x+scroll.get_theme_constant("scrollbar_h_separation") if bar.visible else 0.0
 var inner_width=maxf(0,width-padding.x)
 gift_grid.columns=2 if inner_width-gutter>=500 else 1
 gift_categories.columns=3 if inner_width-gutter>=480 else 2
 frame.size.x=inner_width;form.size.x=maxf(0,inner_width-gutter)
 var fixed=header.get_combined_minimum_size().y+footer.get_combined_minimum_size().y+2*frame.get_theme_constant("separation")+padding.y
 var budget=MailFrame.height_budget(view,insets,compact.hud.popup_height_budget())
 scroll.custom_minimum_size=Vector2(0,minf(maxf(0,budget-fixed),form.get_combined_minimum_size().y))
 panel.size=Vector2(width,0)
 panel.position=Vector2(insets.x+(view.x-insets.x-insets.z-panel.size.x)/2,insets.y+(view.y-insets.y-insets.w-panel.size.y)/2)

# The form owns scrolling, including caret visibility in an expanding letter.
func _reveal_editor_caret(editor:TextEdit):
 if not editor.has_focus():return
 var caret_y=editor.global_position.y+editor.get_caret_draw_pos().y
 var top=scroll.global_position.y+8
 var bottom=scroll.global_position.y+scroll.size.y-editor.get_line_height()-8
 if caret_y>bottom:scroll.scroll_vertical+=int(ceil(caret_y-bottom))
 elif caret_y<top:scroll.scroll_vertical-=int(ceil(top-caret_y))

func _theme_input(field:Control):
 var normal=game._style(Color("fffdf8"),Color("c8b590"),9)
 for side in [SIDE_LEFT,SIDE_RIGHT]:normal.set_content_margin(side,9)
 for side in [SIDE_TOP,SIDE_BOTTOM]:normal.set_content_margin(side,5)
 field.add_theme_stylebox_override("normal",normal)
 var focus=game._style(Color.TRANSPARENT,GREEN,9);focus.set_border_width_all(2)
 field.add_theme_stylebox_override("focus",focus)
 field.add_theme_color_override("font_color",INK)
 field.add_theme_color_override("font_placeholder_color",MUTED)
 field.add_theme_color_override("caret_color",INK)
 if field is LineEdit:field.custom_minimum_size.y=44

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
 return Recipients.valid_uid(value)

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
 var recipient_error=_recipient_error()
 if recipient_error!="":return recipient_error
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
  if int(amount)>0:has_gift=true;break
 if not has_gift:return "Choose Leaf Coins or at least one item."
 return ""

func _call(name:String,args:Array,handler:Callable):
 if not OS.has_feature("web") or not JavaScriptBridge.eval("typeof window.LittleLeafSupportMail === 'object' && window.LittleLeafSupportMail !== null"):
  handler.call({"ok":false,"error":"Mail service is unavailable."});return
 bridge=JavaScriptBridge.get_interface("LittleLeafSupportMail")
 if bridge==null:handler.call({"ok":false,"error":"Mail service is unavailable."});return
 if _callbacks.size()>=12:
  handler.call({"ok":false,"error":"Support is busy. Wait for the current request."});return
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

func refresh():
 request_generation+=1;found={};_reset_delivery()
 mail_snapshot={"ok":false,"profileId":"","mail":[]};entry.visible=false
 if not OS.has_feature("web") or game.web_save==null or not game.web_save.ready:return
 refresh_capabilities()
 refresh_mail()


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
 if ok:refresh_mail()
 if compact.inbox!=null:compact.inbox.sync()

func reset():
 request_generation+=1;mail_fetch_generation+=1;mail_page=0;entry.visible=false;mail_snapshot={"ok":false,"profileId":"","mail":[]}
 found={};_reset_delivery();_callbacks.clear();panel.hide()

func refresh_capabilities():
 if game.web_save==null or not game.web_save.ready:return
 _call("capabilities",[],func(result):
  entry.visible=bool(result.get("ok",false)) and bool(result.get("canIssue",false))
  can_issue_many=entry.visible and bool(result.get("canIssueMany",false))
  can_issue_all=entry.visible and bool(result.get("canIssueAll",false))
  all_button.disabled=not can_issue_all or delivery_started
  _refresh_audience_feedback()
 )
 if compact.inbox!=null:compact.inbox.sync()

func show():
 if not entry.visible:return
 # Closing a window is not cancellation of an uncertain or partial dispatch.
 game.settings.hide();compact._popup_at(panel,640);panel.show()
 compact._queue_popup_fit()

func _invalidate_preview(reset_issue=true):
 if delivery_started:return
 form_generation+=1
 if reset_issue:issue_id=""
 preview_payload={};preview_pending=false;preview_status="";preview_expires_at=0.0;preview_recipient_count=0;reviewed_text=""
 send_button.disabled=true;preview_button.disabled=false;preview_button.text="Review letter";preview_summary.text="";preview_card.hide()
 send_button.text="Send letter"

func _lookup():
 if delivery_started:return
 found={};lookup_generation+=1
 if recipient_mode!="selected" or _selected_uid()=="":
  lookup_summary.text="Check one UID at a time. Review checks the whole audience."
  return
 var generation=lookup_generation;var lookup_mode=recipient_mode;var lookup_uid=_selected_uid()
 lookup_summary.text="Checking exact player UID…"
 _call("lookup",[lookup_uid],func(result):
  # Recipient edits and mode switches fence both success and failure responses.
  if generation!=lookup_generation or lookup_mode!=recipient_mode or lookup_uid!=_selected_uid():return
  if not bool(result.get("ok",false)):
   lookup_summary.text=str(result.get("error","Player unavailable."));return
  if str(result.get("publicUid",""))!=lookup_uid:return
  found=result
  var saved_at=float(result.get("savedAt",0))
  var saved_label=Time.get_datetime_string_from_unix_time(int(saved_at/1000.0))+" UTC" if saved_at>0 else "Unavailable"
  var recent:Array=result.get("recentMail",[])
  var recent_text="None recorded" if recent.is_empty() else ""
  for mail in recent:
   recent_text+=("\n" if recent_text!="" else "")+str(mail.get("caseId","Case unavailable"))+" · "+str(mail.get("status","Unknown"))
  lookup_summary.text="UID %s · save r%d\nSaved %s\nRecent letters: %s"%[result.publicUid,int(result.get("revision",0)),saved_label,recent_text]
 )

func _request()->Dictionary:
 if _recipient_error()!="":return {}
 var items=[]
 for kind in CATALOG:
  var count=int(quantities.get(kind,0))
  if count>0:items.append({"catalogId":kind,"quantity":count,"catalogRevision":1})
 # Match normalizeLetter before comparing the server's exact reviewed fields.
 items.sort_custom(func(a,b):return a.catalogId<b.catalogId)
 if issue_id=="":issue_id=_new_issue_id()
 var audience={"mode":"all"} if recipient_mode=="all" else {"mode":"selected","publicUids":Recipients.parse(recipient.text).uids}
 return {"issueId":issue_id,"audience":audience,"caseId":case_id.text.strip_edges(),"subject":subject.text.strip_edges(),"body":letter.text.strip_edges(),"coins":int(coins.value),"items":items}

func _new_issue_id()->String:
 # Also works in a synthetic native fixture, without a live browser/account.
 if OS.has_feature("web"):return str(JavaScriptBridge.eval("crypto.randomUUID()"))
 var bytes=Crypto.new().generate_random_bytes(16)
 bytes[6]=(bytes[6]&15)|64;bytes[8]=(bytes[8]&63)|128
 var value=bytes.hex_encode()
 return "%s-%s-%s-%s-%s"%[value.substr(0,8),value.substr(8,4),value.substr(12,4),value.substr(16,4),value.substr(20,12)]

func _preview():
 if preview_pending or send_pending:return
 if delivery_terminal:_reset_delivery();note.text="Ready for a new letter.";return
 if delivery_started:return
 var error=_field_error()
 if error!="":note.text=error;return
 if preview_expires_at>0 and preview_expires_at<=Time.get_unix_time_from_system()*1000.0:_invalidate_preview()
 var request=_request()
 if request.is_empty():note.text="Check the audience first.";return
 var generation=form_generation
 preview_payload={};preview_status="";preview_recipient_count=0
 preview_pending=true;preview_button.disabled=true;send_button.disabled=true
 note.text="Preparing audience and checking attachments…"
 _call("preview",[request],func(result):
  if generation!=form_generation:return
  preview_pending=false;preview_button.disabled=false
  if not bool(result.get("ok",false)):
   if str(result.get("code",""))=="PREVIEW_EXPIRED":_invalidate_preview()
   note.text=str(result.get("error","Review unavailable. Continue Review to retry."));return
  if not _matching_review(result,request):
   note.text="Review did not match this letter. Nothing has been sent.";return
  preview_status=str(result.get("status",""))
  preview_expires_at=float(result.get("expiresAt",0))
  if preview_status=="preparing":
   preview_payload={};preview_button.text="Continue review"
   preview_summary.text="All players\n%d cloud cafés prepared. Continue Review to finish the audience."%int(result.get("preparedCount",0))
   note.text="Preparing audience · nothing sent."
  else:
   preview_recipient_count=int(result.recipientCount)
   preview_payload=request.duplicate(true);preview_payload.previewHash=str(result.previewHash)
   _render_review(result)
   send_button.text="Send to %d players"%preview_recipient_count if result.audience.mode=="all" else "Send letter"
   preview_button.text="Review again"
   note.text="Confirm recipients and contents, then Send."
   send_button.disabled=int(result.recipientCount)<=0 or preview_expires_at<=Time.get_unix_time_from_system()*1000.0
   if int(result.recipientCount)<=0:note.text="No recipients found. Nothing to send."
  preview_card.show();_reveal_review()
 )

func _matching_review(result:Dictionary,request:Dictionary)->bool:
 for key in ["issueId","audience","caseId","subject","body","coins","items"]:
  if not result.has(key) or result[key]!=request[key]:return false
 var status=str(result.get("status",""))
 if not status in ["preparing","ready"] or not _whole_count(result.get("preparedCount")):return false
 if not _whole_count(result.get("expiresAt")):return false
 if status=="preparing":return request.audience.mode=="all" and result.get("recipientCount")==null and result.get("totals")==null and result.get("previewHash")==null
 if not _whole_count(result.get("recipientCount")) or int(result.preparedCount)!=int(result.recipientCount) or not result.get("previewHash") is String or str(result.previewHash).is_empty():return false
 if not _whole_count(result.get("captureStartedAt")) or not _whole_count(result.get("captureCompletedAt")) or float(result.captureCompletedAt)<float(result.captureStartedAt) or float(result.captureCompletedAt)>float(result.expiresAt):return false
 var totals=result.get("totals")
 if not totals is Dictionary or not _whole_count(totals.get("coins")) or not totals.get("items") is Array:return false
 if int(totals.coins)!=int(request.coins)*int(result.recipientCount) or totals.items.size()!=request.items.size():return false
 for index in request.items.size():
  var total=totals.items[index];var item=request.items[index]
  if not total is Dictionary or total.get("catalogId")!=item.catalogId or not _whole_count(total.get("quantity")) or int(total.quantity)!=int(item.quantity)*int(result.recipientCount):return false
 return true

func _whole_count(value)->bool:
 return (value is int or value is float) and is_finite(float(value)) and float(value)>=0 and float(value)==floor(float(value))

func _render_review(result:Dictionary):
 var audience="All players" if result.audience.mode=="all" else "Selected UIDs: "+", ".join(result.audience.publicUids)
 var attachments="%d Leaf Coins"%int(result.get("coins",0))
 for item in result.get("items",[]):
  attachments+="\n%s ×%d"%[GiftCatalog.item_name(game.model,str(item.get("catalogId",""))),int(item.get("quantity",0))]
 var totals="%d Leaf Coins"%int(result.totals.coins)
 for item in result.totals.items:
  totals+="\n%s ×%d"%[GiftCatalog.item_name(game.model,str(item.get("catalogId",""))),int(item.get("quantity",0))]
 var captured="Captured %s to %s"%[_capture_time(float(result.captureStartedAt)),_capture_time(float(result.captureCompletedAt))]
 preview_summary.text="%s\n%d recipients · %s\n%s\n\nCase: %s\nSubject: %s\n\n%s\n\nEach player receives:\n%s\n\nTotal for this audience:\n%s"%[audience,int(result.get("recipientCount",0)),str(result.get("scope","Server-confirmed audience")),captured,result.caseId,result.subject,result.body,attachments,totals]
 reviewed_text=preview_summary.text

func _capture_time(milliseconds:float)->String:
 return Time.get_datetime_string_from_unix_time(int(milliseconds/1000.0)).replace("T"," ")+".%03d UTC"%(int(milliseconds)%1000)

func _reveal_review():
 # Wait for the newly visible card and status to settle before choosing its offset.
 await game.get_tree().process_frame
 if is_instance_valid(preview_card) and preview_card.visible:scroll.scroll_vertical=int(preview_card.position.y)

func _set_composition_locked(locked:bool):
 for field in [recipient,case_id,subject,letter,coins.get_line_edit()]:field.editable=not locked
 coins.editable=not locked
 selected_button.disabled=locked;all_button.disabled=locked or not can_issue_all
 item_toggle.disabled=locked
 for slot in selected_slots:
  slot.minus.disabled=locked;slot.plus.disabled=locked or int(quantities.get(slot.id,0))>=10
 for slot in result_slots:slot.add.disabled=locked or not slot.id in CATALOG or int(quantities.get(slot.id,0))>=10
 _refresh_audience_feedback()

func _reset_delivery():
 delivery_started=false;delivery_terminal=false;send_pending=false
 _invalidate_preview();_set_composition_locked(false)
 send_button.text="Send letter"

func _send():
 if send_pending or preview_pending or delivery_terminal or preview_payload.is_empty() or preview_status!="ready" or preview_recipient_count<=0:return
 if not delivery_started and preview_expires_at<=Time.get_unix_time_from_system()*1000.0:
  _invalidate_preview();note.text="Review expired. Review again before sending.";return
 var request=preview_payload.duplicate(true);var generation=form_generation
 delivery_started=true;send_pending=true;_set_composition_locked(true)
 send_button.disabled=true;preview_button.disabled=true;note.text="Checking delivery status…"
 _call("issue",[request],func(result):
  if generation!=form_generation:return
  send_pending=false
  # The audience service reserves this code for the exact frozen request with
  # zero sent/failed recipients. Other errors never release an uncertain send.
  if not bool(result.get("ok",false)) and str(result.get("code",""))=="PREVIEW_EXPIRED":
   _reset_delivery();note.text="Review expired before delivery. Review again; nothing was sent.";return
  if not bool(result.get("ok",false)) or not _matching_delivery(result,request):
   note.text="Delivery unconfirmed. Resume the same send. "+str(result.get("error","No confirmed result."))
   send_button.text="Resume send";send_button.disabled=false;return
  var sent=int(result.sentCount);var failed=int(result.failedCount);var pending=int(result.pendingCount)
  note.text="%d / %d sent · %d failed · %d pending"%[sent,int(result.total),failed,pending]
  delivery_terminal=str(result.status)!="sending"
  if not delivery_terminal:
   send_button.text="Continue send";send_button.disabled=false
  else:
   send_button.text="Sent" if failed==0 else "Some failed"
   send_button.disabled=true;preview_button.text="New letter";preview_button.disabled=false
  var failures:Array=result.get("failures",[]) if result.get("failures") is Array else []
  preview_summary.text=reviewed_text
  if not failures.is_empty():
   var details=[]
   for failure in failures.slice(0,5):details.append((str(failure.publicUid) if failure.get("publicUid")!=null else "Cloud café")+": "+str(failure.get("code","Delivery failed")))
   preview_summary.text+="\n\nDelivery failures:\n"+"\n".join(details)
 )

func _matching_delivery(result:Dictionary,request:Dictionary)->bool:
 if str(result.get("issueId",""))!=str(request.issueId):return false
 for key in ["total","sentCount","failedCount","pendingCount"]:
  if not _whole_count(result.get(key)):return false
 if int(result.total)!=preview_recipient_count:return false
 if int(result.total)!=int(result.sentCount)+int(result.failedCount)+int(result.pendingCount):return false
 var status=str(result.get("status",""))
 if status=="sending":return int(result.pendingCount)>0
 if status=="sent":return int(result.pendingCount)==0 and int(result.failedCount)==0
 return status=="completed_with_failures" and int(result.pendingCount)==0 and int(result.failedCount)>0

func handle_input(event:InputEvent)->bool:
 if not panel.visible or not event is InputEventKey or not event.pressed or event.keycode!=KEY_TAB:return false
 var available=focus_controls.filter(func(control):return control.is_visible_in_tree() and not (control is Button and control.disabled))
 var current=game.get_viewport().gui_get_focus_owner()
 var index=posmod(available.find(current)+(-1 if event.shift_pressed else 1),available.size())
 available[index].grab_focus()
 return true
