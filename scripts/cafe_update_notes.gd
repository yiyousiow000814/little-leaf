extends RefCounted
## Offline, opt-in release notes. Settings owns all preference persistence.
signal unread_changed(unread:bool)

const DATA_PATH="res://data/release_notes.json"
const PANEL_WIDTH=396.0
const INK=Color("554631")
const MUTED=Color("75644f")
const REVIEW_FLAGS=["--visual-qa","--fresh-review","--review-checkpoint"]

var game
var compact_ref:WeakRef
var compact:
 get:return compact_ref.get_ref()
var panel:PanelContainer
var body:VBoxContainer
var back_button:Button
var menu_entries=[]
var release:Dictionary={}
var data_error=""
var session_seen_version=""
var last_unread=false

func _init(owner):
 compact_ref=weakref(owner)
 game=owner.game

func setup(data_path:String=DATA_PATH):
 if is_instance_valid(panel):return
 assert(compact.hud!=null,"Update Notes setup requires the shared HUD theme")
 var document:Variant=null
 if FileAccess.file_exists(data_path):
  document=JSON.parse_string(FileAccess.get_file_as_string(data_path))
 release=validate_document(document)
 data_error=str(release.get("error",""))
 panel=compact._panel()
 panel.name="UpdateNotesPanel"
 body=VBoxContainer.new()
 body.add_theme_constant_override("separation",10)
 panel.add_child(body)
 body.add_child(_label("Update Notes",22))
 if current_version()!="":
  if str(release.get("label",""))!="":body.add_child(_label(release.label,14,MUTED))
  body.add_child(_label("Version %s · %s"%[current_version(),release.date],13,MUTED))
  _add_section("New",release.new)
  if not release.fixed.is_empty():_add_section("Fixed",release.fixed)
 else:
  var message="Release details are being prepared."
  if data_error!="":message="Update notes are unavailable in this build."
  body.add_child(_label(message,14,MUTED))
 back_button=game.button("Back to Help",_back_to_help)
 back_button.custom_minimum_size=Vector2(0,44)
 back_button.accessibility_name="Back to Quick Help"
 body.add_child(back_button)
 compact.hud.theme_panel(panel,true,26)
 compact.hud.theme_panel_contents(panel)
 compact._wrap_themed_popup(panel,PANEL_WIDTH)
 var scroll=panel.get_child(0) as ScrollContainer
 scroll.focus_mode=Control.FOCUS_ALL
 scroll.accessibility_name="Update Notes"
 # Setup must never open a dialog or consume the unread state.
 panel.hide()
 sync()

func make_menu_entry()->Button:
 var button=game.button("Update Notes",show)
 button.name="UpdateNotesEntry"
 button.custom_minimum_size=Vector2(180,44)
 button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 compact.hud.theme_button(button)
 var badge=Panel.new()
 badge.name="UnreadDot"
 badge.mouse_filter=Control.MOUSE_FILTER_IGNORE
 badge.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
 badge.offset_left=-19
 badge.offset_right=-12
 badge.offset_top=-3.5
 badge.offset_bottom=3.5
 var dot=StyleBoxFlat.new()
 dot.bg_color=Color("526a4e")
 dot.set_corner_radius_all(4)
 badge.add_theme_stylebox_override("panel",dot)
 button.add_child(badge)
 menu_entries.append({"button":button,"badge":badge})
 sync()
 return button

func current_version()->String:
 if not bool(release.get("valid",false)) or release.get("status","")!="released":return ""
 return str(release.get("version",""))

func has_unread()->bool:
 var version=current_version()
 if version=="" or session_seen_version==version:return false
 if game.settings_controls==null:return true
 return str(game.settings_controls.last_seen_update_version)!=version

func sync():
 var unread=has_unread()
 for entry in menu_entries:
  if not is_instance_valid(entry.button):continue
  entry.badge.visible=unread
  entry.button.accessibility_name="Update Notes, unread" if unread else "Update Notes"
  entry.button.tooltip_text="Read the latest update notes"+(" · unread" if unread else "")
 if last_unread!=unread:
  last_unread=unread
  unread_changed.emit(unread)

func show():
 if not is_instance_valid(panel):return
 game.settings.hide()
 compact._popup_at(panel,PANEL_WIDTH)
 # Reopening starts at the release header, including after a viewport change.
 var scroll=panel.get_child(0) as ScrollContainer
 scroll.scroll_vertical=0
 compact._queue_popup_fit()
 _mark_seen()
 # Focusing a footer button would make follow_focus jump past the notes.
 scroll.grab_focus.call_deferred()

func hide():
 if is_instance_valid(panel):panel.hide()
 compact.sync()

func _back_to_help():
 if is_instance_valid(panel):panel.hide()
 compact.return_to_help()

func _mark_seen():
 var version=current_version()
 if version=="" or session_seen_version==version:return
 session_seen_version=version
 var preferences=game.settings_controls
 # Review sessions can read notes and clear their in-memory dot, but must
 # never mutate the user's preferences or progression files.
 if preferences!=null and not review_mode(OS.get_cmdline_user_args()):
  if preferences.persist_enabled and not bool(game.save_writes_suppressed):
   preferences.mark_update_notes_seen(version)
 sync()

func _label(words:String,font_size:int,color:Color=INK)->Label:
 var label=game.label(words,font_size,color)
 label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
 label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 return label

func _add_section(heading:String,items:Array):
 body.add_child(_label(heading,18))
 if items.is_empty():
  body.add_child(_label("No changes in this section.",14,MUTED))
  return
 for item in items:
  var row=HBoxContainer.new()
  row.add_theme_constant_override("separation",7)
  row.size_flags_horizontal=Control.SIZE_EXPAND_FILL
  var bullet=game.label("•",14,INK)
  bullet.mouse_filter=Control.MOUSE_FILTER_IGNORE
  bullet.vertical_alignment=VERTICAL_ALIGNMENT_TOP
  bullet.size_flags_vertical=Control.SIZE_SHRINK_BEGIN
  row.add_child(bullet)
  row.add_child(_label(str(item),14))
  body.add_child(row)

static func review_mode(args:PackedStringArray)->bool:
 for flag in REVIEW_FLAGS:
  if flag in args:return true
 return false

static func validate_document(document:Variant)->Dictionary:
 if not document is Dictionary:return _invalid("Expected a JSON object")
 if document.get("schema_version",0)!=1:return _invalid("Unsupported release-notes schema")
 var status=document.get("status","")
 if status=="pending":
  # Draft strings never become visible release claims or unread badges.
  return {"valid":true,"status":"pending","version":"","date":"","label":"","new":[],"fixed":[]}
 if status!="released":return _invalid("Expected pending or released status")
 var version=document.get("version",null)
 if not version is String or version.strip_edges()=="":return _invalid("Released notes need a version")
 version=version.strip_edges()
 if version.to_lower() in ["pending","tbd","unknown"] or "\n" in version or "\r" in version:
  return _invalid("Released version cannot be a placeholder")
 var date=document.get("date",null)
 if not date is String or not _valid_date(date):return _invalid("Released notes need a real YYYY-MM-DD date")
 var label=document.get("label","")
 if not label is String:return _invalid("Release label must be text")
 var normalized={"valid":true,"status":"released","version":version,"date":date,"label":label.strip_edges(),"new":[],"fixed":[]}
 for section in ["new","fixed"]:
  var items=document.get(section,null)
  if not items is Array:return _invalid("Release sections must be arrays")
  for item in items:
   if not item is String or item.strip_edges()=="":return _invalid("Release bullets must contain text")
   normalized[section].append(item.strip_edges())
 if normalized.new.is_empty() and normalized.fixed.is_empty():return _invalid("Released notes need at least one shipped change")
 return normalized

static func _invalid(reason:String)->Dictionary:
 return {"valid":false,"status":"unavailable","version":"","date":"","label":"","new":[],"fixed":[],"error":reason}

static func _valid_date(value:String)->bool:
 if value.length()!=10 or value.substr(4,1)!="-" or value.substr(7,1)!="-":return false
 var digits=value.substr(0,4)+value.substr(5,2)+value.substr(8,2)
 for index in range(digits.length()):
  if digits.unicode_at(index)<48 or digits.unicode_at(index)>57:return false
 var year=int(value.substr(0,4))
 var month=int(value.substr(5,2))
 var day=int(value.substr(8,2))
 if year<1 or month<1 or month>12:return false
 var days=[31,28,31,30,31,30,31,31,30,31,30,31]
 if year%400==0 or (year%4==0 and year%100!=0):days[1]=29
 return day>=1 and day<=days[month-1]
