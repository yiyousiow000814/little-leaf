extends SceneTree
const AudioDrain=preload("res://tests/fixtures/audio_mixer_drain.gd")
class Fixture extends "res://scripts/main.gd":
 var saves=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():saves+=1;return true
 func _interaction_over_ui(_screen:Vector2)->bool:return false
var game
var checks=0
var failures=[]
var kinds=[]
var rows=[]
var capture_dir=OS.get_environment("LL_CAPTURE_OUTPUT")
func _initialize():run.call_deferred()
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func refresh():game._update_ui();game.compact_ui.update_pointer()
func session_controls(label:String):
 var hud=game.compact_ui.hud
 check(game.editing and game.model.decoration_session_active and hud.edit_cancel.visible and not hud.edit_cancel.disabled and hud.done_face.visible,label+" keeps session Apply/Cancel")
func capture(label:String):
 if capture_dir=="":return
 refresh();game.illustration.queue_redraw()
 for frame in 5:await process_frame
 await RenderingServer.frame_post_draw
 check(root.get_texture().get_image().save_png(capture_dir.path_join(label+".png"))==OK,"captured "+label)
 rows.append({"label":label,"selected_id":game.selected_id,"selected_kind":game.selected_kind,"context_visible":game.compact_ui.context.visible,"context_title":game.compact_ui.context_label.text,"session_cancel_visible":game.compact_ui.hud.edit_cancel.visible,"session_apply_visible":game.compact_ui.hud.done_face.visible})
func run():
 root.size=Vector2i(1360,880)
 game=Fixture.new();root.add_child(game);game.set_process(false);game.paused=true
 await process_frame
 game._toggle_edit();game.compact_ui.set_tray_open(true)
 game.illustration.zoom=1.0;game.illustration.pan_offset=Vector2.ZERO;game.illustration.update_projection()
 var included_register=game.model.checkout_register().duplicate(true)
 for staff in game.staff_states:staff.pos=Vector2(1.5,7.5)
 for kind in game.catalog_cards:
  game._cancel_selection()
  var m=game.model;m.items.clear();m.dining_sets.clear();m.customers.clear();m.checkout_staff_claims.clear();m.wall_actor_positions.clear();m.coins=100000;m._notify()
  game._set_catalog_category(game._catalog_group(kind));game.catalog_cards[kind].pressed.emit();refresh()
  check(game.compact_ui.context.visible and game.compact_ui.rotate_button.visible,kind+" new selection has item actions")
  session_controls(kind+" selected")
  if kind=="register":
   m.items.append(included_register.duplicate(true));m._notify()
   check(m.move(int(included_register.id),5,4,0),"included register fixture retains its original identity")
  else:check(m.place(kind,5,4),kind+" generated existing item")
  if m.items.is_empty():continue
  var item=m.items[0];game._rebuild_furniture();game.interaction._select_item(item);refresh()
  check(game.compact_ui.context.visible and game.compact_ui.remove_button.visible,kind+" existing selection keeps normal actions")
  game._rotate();refresh()
  check(game.compact_ui.context.visible and game.selected_id>=0,kind+" rotation retains selection actions")
  if kind=="plant" or kinds.is_empty():await capture("selected-"+kind)
  var point=game.illustration.iso(item.x+.5,item.z+.5)
  game.interaction._begin_left(point);game.interaction._move_left(point+Vector2(18,0))
  point=game.illustration.iso(7.5,5.5);game.interaction.refresh(point)
  check(game.interaction.drag_active and game.interaction.drag_valid,kind+" real move preview")
  game.interaction._release_left(point);refresh()
  check(game.selected_id<0 and game.selected_kind=="",kind+" successful move ends item selection")
  check(not game.compact_ui.context.visible and not game.compact_ui.cancel_button.visible,kind+" successful move leaves no orphan item Cancel")
  session_controls(kind+" moved")
  if kind=="plant" or kinds.is_empty():await capture("moved-"+kind)
  game.catalog_cards[kind].pressed.emit();game.interaction.cancel();refresh()
  check(not game.compact_ui.context.visible,kind+" preview cancellation clears item actions")
  session_controls(kind+" cancelled")
  kinds.append(kind)
 game._set_catalog_category("Build");refresh()
 check(not game.compact_ui.context.visible,"Build browsing has no empty item action board")
 session_controls("Build browse")
 for mode in ["half","full","floor","door","window"]:
  game.build_tools.choose(mode);refresh()
  check(game.compact_ui.context.visible,mode+" actual Build tool keeps its item board")
  session_controls(mode+" tool")
 game.build_tools.cancel();refresh()
 check(not game.compact_ui.context.visible,"cancelled Build tool leaves no item Cancel")
 await capture("build-browse")
 game.compact_ui.hud.cancel_edit_action();refresh()
 check(not game.editing and not game.model.decoration_session_active,"top session Cancel still cancels the full session")
 check(game.saves==0,"no original or synthetic save writes")
 var report={"checks":checks,"failures":failures,"catalogue_kinds":kinds,"captures":rows,"save_calls":game.saves,"original_player_save_used":false}
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;await process_frame
 report.audio_teardown=await AudioDrain.wait_for_mixer_cycles(self)
 if capture_dir!="":FileAccess.open(capture_dir.path_join("action-observations.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
 print("ITEM_ACTION_BOARD_RESULT ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
