extends SceneTree
## Offline notes, real Help controls and disposable synthetic preferences only.
const Notes=preload("res://scripts/cafe_update_notes.gd")
const FIXTURE="user://synthetic_update_notes.json"
class TestMain extends "res://scripts/main.gd":
 var saves=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():saves+=1;return true
var game
var checks=0
var failures=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func settle():
 game._update_ui()
 for frame in 6:await process_frame
func words(node:Node)->Array:
 var result=[]
 if node is Label:result.append(node.text)
 for child in node.get_children():result.append_array(words(child))
 return result
func fixture(status:String)->Dictionary:
 return {"schema_version":1,"status":status,"version":"9.8.7","date":"2026-01-01","label":"Synthetic release label","new":["Synthetic shipped change"],"fixed":[],"review_pending":["Internal review gap"]}
func load_fixture(document:Variant):
 var file=FileAccess.open(FIXTURE,FileAccess.WRITE)
 file.store_string(JSON.stringify(document));file.close()
 var ui=game.compact_ui;var notes=ui.update_notes
 # Rebuild only the test panel; existing Help callbacks keep their controller.
 for record in ui.themed_popups.duplicate():
  if record.panel==notes.panel:ui.themed_popups.erase(record)
 notes.panel.free();notes.panel=null;notes.session_seen_version=""
 notes.setup(FIXTURE)
 await settle()
func run():
 var checked=Notes.validate_document(JSON.parse_string(FileAccess.get_file_as_string(Notes.DATA_PATH)))
 check(checked.valid,"checked-in release notes are accepted by runtime")
 check(checked.status=="released" and checked.version=="0.1.10","published preview notes expose the current version")
 check(checked.label=="Developer preview" and checked.date=="2026-10-09","published preview keeps its label and publication date")
 for status in ["pending","draft"]:
  var input=fixture(status);var original=input.duplicate(true)
  var normalized=Notes.validate_document(input)
  check(normalized.valid and normalized.status==status,status+" is a valid unpublished state")
  for field in ["version","date","label"]:check(normalized[field]=="",status+" suppresses "+field)
  check(normalized.new.is_empty() and normalized.fixed.is_empty(),status+" suppresses candidate bullets")
  check(not normalized.has("review_pending"),status+" suppresses internal review gaps")
  check(input==original,status+" validation does not mutate the source")
 var released=fixture("released");released.erase("review_pending")
 check(Notes.validate_document(released).valid,"released fixture still validates")
 for change in [{"status":"unknown"},{"schema_version":2},{"version":"tbd"},{"date":"2026-02-30"},{"new":[" "]},{"new":[],"fixed":[]}]:
  var input=released.duplicate(true);input.merge(change,true)
  check(not Notes.validate_document(input).valid,"malformed release remains invalid "+str(change))
 check(not Notes.validate_document(null).valid,"missing document remains invalid")
 game=TestMain.new();root.add_child(game);game.set_process(false);game.paused=true
 await process_frame
 var ui=game.compact_ui;var notes=ui.update_notes;var preferences=game.settings_controls
 var shipped_text=words(notes.body)
 check("Developer preview" in shipped_text and "Version 0.1.10 · 2026-10-09" in shipped_text,"actual checked-in preview header is rendered")
 check(not "Release details are being prepared." in shipped_text,"published preview does not fall back to preparation copy")
 for section in ["new","fixed"]:
  for item in checked[section]:check(item in shipped_text,"every published "+section+" bullet is rendered")
 check(str(checked.new[-1]).begins_with("Preview limits:"),"acceptance limits are in visible notes rather than ignored review metadata")
 preferences.last_seen_update_version="8.0.0"
 var original_config_exists=FileAccess.file_exists(preferences.config_path)
 for status in ["pending","draft"]:
  await load_fixture(fixture(status))
  check(notes.data_error=="",status+" does not become unavailable")
  check(not notes.panel.visible,status+" setup never opens a panel")
  check(notes.current_version()=="" and not notes.has_unread(),status+" has no released version or unread state")
  var text=words(notes.body)
  check("Release details are being prepared." in text,status+" shows preparation copy")
  check(text.size()==2,status+" shows only title and preparation copy")
  for entry in notes.menu_entries:
   check(not entry.badge.visible and entry.button.accessibility_name=="Update Notes",status+" menu has no unread badge or announcement")
  for entry in ui.update_badges:
   if entry.button!=ui.settings_button and entry.button!=ui.settings_inbox:
    check(not entry.badge.visible,status+" Help has no update badge")
  for view in [Vector2i(960,540),Vector2i(390,844),Vector2i(566,360)]:
   root.size=view;ui.show_help();await settle()
   ui.help_notes.pressed.emit();await settle()
   check(notes.panel.visible and not ui.help_panel.visible,status+" opens through Help at "+str(view))
   check(Rect2(Vector2.ZERO,Vector2(view)).encloses(notes.panel.get_global_rect()),status+" preparation panel fits "+str(view))
   notes.show();await settle()
   check(notes.panel.visible and notes.session_seen_version=="",status+" repeated open never marks draft seen")
   notes.back_button.pressed.emit();await settle()
   check(ui.help_panel.visible and not notes.panel.visible,status+" Back returns to Help")
  check(preferences.last_seen_update_version=="8.0.0",status+" preserves previously seen version")
 await load_fixture(released)
 check(notes.current_version()=="9.8.7" and notes.has_unread(),"released notes retain version and unread behavior")
 check("Version 9.8.7 · 2026-01-01" in words(notes.body),"released panel retains version and date")
 check("Synthetic shipped change" in words(notes.body),"released panel retains shipped changes")
 check(not notes.panel.visible and notes.session_seen_version=="","released setup does not mark seen")
 for entry in notes.menu_entries:check(entry.badge.visible,"released notes show unread badge")
 ui.help_notes.pressed.emit();await settle()
 check(notes.session_seen_version=="9.8.7" and not notes.has_unread(),"reading released notes clears session unread state")
 check(preferences.last_seen_update_version=="8.0.0","review session never persists seen release")
 notes._back_to_help();await settle();ui.help_notes.pressed.emit();await settle()
 check(not notes.has_unread(),"reopening released notes does not restore unread badge")
 await load_fixture({"schema_version":1,"status":"broken"})
 check(notes.data_error!="" and notes.current_version()=="" and not notes.has_unread(),"malformed notes remain unavailable without badge")
 check("Update notes are unavailable in this build." in words(notes.body),"malformed notes retain unavailable copy")
 check(preferences.last_seen_update_version=="8.0.0","all notes flows preserve saved seen version")
 check(FileAccess.file_exists(preferences.config_path)==original_config_exists,"notes flows do not create preferences")
 check(game.saves==0,"notes flows never write gameplay saves")
 DirAccess.remove_absolute(FIXTURE)
 print("UPDATE_NOTES_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 for player in game.audio_players.values():player.stop();player.stream=null
 preferences.sfx_player.stop();preferences.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
