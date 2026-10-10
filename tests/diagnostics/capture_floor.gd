extends SceneTree
class TestMain extends "res://scripts/main.gd":
 var saves=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():saves+=1;return true
 func _interaction_over_ui(_screen:Vector2)->bool:return false
var game
var summaries=[]
func _initialize():run.call_deferred()
func refresh():
 game.interaction.refresh(Vector2.ZERO)
 if game.interaction.has_method("refresh_floor_feedback"):
  while not game.model.placement_field.pending.is_empty():game.interaction.refresh_floor_feedback()
 game.interaction.preview_active=false
func capture(label):
 game.illustration.queue_redraw()
 for frame in 5:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(OS.get_environment("OUTPUT")+"/"+OS.get_environment("PHASE")+"-"+label+"-1360x880.png")
 var counts={"green":0,"red":0}
 if "floor_availability" in game.interaction:
  for result in game.interaction.floor_availability.refresh(game.model).values():counts.red+=int(result.blocked);counts.green+=int(not result.blocked)
 var i=game.interaction
 summaries.append({"label":label,"kind":game.selected_kind,"rotation":game.rotation_step,"cursor":str(i.drag_cell),"cursor_valid":i.drag_valid,"reason":i.drag_reason,"background":counts,"hint_visible":game.compact_ui.hint.visible,"hint":game.compact_ui.hint_text.text,"pointer":str(game.get_viewport().get_mouse_position()),"saves":game.saves})
func hover(cell):
 var point=game.illustration.iso(cell.x+.5,cell.y+.5)
 var event=InputEventMouseMotion.new();event.position=point;event.global_position=point
 Input.use_accumulated_input=false;Input.parse_input_event(event)
 game.interaction.refresh(point)
 if game.interaction.has_method("refresh_floor_feedback"):
  while not game.model.placement_field.pending.is_empty():game.interaction.refresh_floor_feedback()
 game.compact_ui.update_pointer()
func run():
 root.size=Vector2i(1360,880)
 game=TestMain.new();root.add_child(game);game.set_process(false)
 await process_frame
 game._toggle_edit();game.model.coins=100000;game._update_ui()
 game.illustration.zoom=1.0;game.illustration.pan_offset=Vector2.ZERO;game.illustration.update_projection()
 game._cancel_selection();refresh();await capture("no-selection")
 game._choose("table_set");game.rotation_step=0;refresh();await capture("table-selected")
 hover(Vector2i(5,8));await capture("edge-chair-outside")
 game.rotation_step=2;hover(Vector2i(5,8));await capture("edge-chair-inside")
 FileAccess.open(OS.get_environment("OUTPUT")+"/"+OS.get_environment("PHASE")+"-capture.json",FileAccess.WRITE).store_string(JSON.stringify(summaries,"  "))
 print("ACTUAL_FLOOR_CAPTURE ",JSON.stringify(summaries))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;await create_timer(.1).timeout;quit()
