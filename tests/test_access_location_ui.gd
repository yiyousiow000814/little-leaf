extends SceneTree
const Main=preload("res://scripts/main.gd")
class FixtureMain extends Main:
 var save_calls=0
 func _save():save_calls+=1;return true
var game
var checks=0
var failures=[]
var rows=[]
func _init():call_deferred("run")
func check(ok:bool,what:String):
 checks+=1
 if not ok:failures.append(what);printerr("FAIL ",what)
func frames(n=4):
 for unused in range(n):await process_frame
func state():return JSON.stringify([game.model.items,game.model.customers,game.model.coins,game.model.revision,game.model.served,game.service_guests,game.staff_states,game.save_calls,game.model._next_item_id,game.model._next_customer_id,game.model._next_wall_id,game.model._next_attachment_id,game.model.next_checkout_ticket])
func mouse(point:Vector2,down:bool):
 var e=InputEventMouseButton.new();e.position=point;e.global_position=point;e.button_index=MOUSE_BUTTON_LEFT;e.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0;e.pressed=down;Input.parse_input_event(e);await frames(1)
func motion(point:Vector2):
 var e=InputEventMouseMotion.new();e.position=point;e.global_position=point;Input.parse_input_event(e);await frames(1)
func click(point:Vector2):await motion(point);await mouse(point,true);await mouse(point,false);await frames()
func sync():game.compact_ui.sync();game.workface_guidance._refresh_access();game.compact_ui.status_notice.sync_position()
func safe_focus(tag:String):
 var ui=game.compact_ui;var issue=game.workface_guidance.current_access_issue();var art=game.illustration
 check(not issue.is_empty(),"focused descriptor remains "+tag)
 if issue.is_empty():return
 var safe=art.camera_safe_rect().grow(-16.0);var panel=ui.status_notice.panel
 var notice=panel.get_global_rect() if panel.is_visible_in_tree() else Rect2()
 var cell:Vector2i=issue.cell;var station:Vector2i=issue.station_cell
 for p in [art.iso(cell.x+.04,cell.y+.04),art.iso(cell.x+.96,cell.y+.04),art.iso(cell.x+.96,cell.y+.96),art.iso(cell.x+.04,cell.y+.96)]:check(safe.grow(-2.5).has_point(p) and (not notice.has_area() or not notice.grow(18.5).has_point(p)),"access corner visible after clamp "+tag+str(p)+str(safe))
 var marker=art.iso(station.x+.5,station.y+.5,68)
 check(safe.grow(-12).has_point(marker) and (not notice.has_area() or not notice.grow(28).has_point(marker)),"station marker visible after clamp "+tag)
 check(art.screen_to_cell(art.iso(cell.x+.5,cell.y+.5))==cell,"same-grid inverse pick preserved "+tag)
func setup_preview(kind:String,cell:Vector2i,id=-1,rot=0):
 game.selected_kind=kind if id<0 else "";game.selected_id=id;game.rotation_step=rot
 var i=game.interaction;i.drag_item_id=id;i.drag_kind=kind;i.drag_rotation=rot;i.drag_cell=cell;i.preview_active=true;i.drag_active=id>=0
 var point=game.illustration.iso(cell.x+.5,cell.y+.5);i.last_pointer=point
 if i.has_method("refresh_floor_feedback"):i.refresh_floor_feedback()
 i._update_validity(point);sync()
func run():
 if not "--fresh-review" in OS.get_cmdline_user_args():quit(2);return
 Input.use_accumulated_input=false;root.size=Vector2i(1360,880);game=FixtureMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false)
 var ui=game.compact_ui;var guide=game.workface_guidance;var notice=ui.status_notice;await frames();game._toggle_edit();await create_timer(.25).timeout;await frames()
 for index in range(game.staff_states.size()):game.staff_states[index].pos=Vector2(1.5,7.5+index*.03)
 var stove={}
 for item in game.model.items:
  if item.kind=="stove":stove=item;break
 var cell=game.model.workface_cell(stove);check(game.model.layout_access_issues().is_empty(),"fresh café has no static access errors")
 var before=state();setup_preview("plant",cell);await frames();sync()
 check(game.interaction.drag_valid,"optional stove obstruction is allowed with guidance")
 var issue=guide.current_access_issue();check(int(issue.get("item_id",-1))==int(stove.id) and issue.get("cell")==cell,"preview descriptor names actual affected stove/cell")
 check(guide.access_source=="preview" and notice.issue_label.text.begins_with("Would block"),"preview wording distinguishes uncommitted obstruction")
 check(notice.show_button.visible and notice.panel.mouse_filter==Control.MOUSE_FILTER_STOP,"whole issue notice is an actionable UI region")
 check(state()==before,"preview does not mutate gameplay or save")
 var text_point=notice.issue_label.get_global_rect().get_center();print("UI_BEFORE_TEXT ",JSON.stringify({"point":str(text_point),"panel":str(notice.panel.get_global_rect()),"label":str(notice.issue_label.get_global_rect()),"over":game.interaction._over_ui(text_point),"visible":notice.panel.is_visible_in_tree(),"filter":notice.panel.mouse_filter,"context":str(guide.preview_context),"latched":guide.preview_latched}));await motion(text_point);print("UI_AFTER_MOTION ",JSON.stringify({"last_pointer":str(game.interaction.last_pointer),"point":str(text_point),"panel":str(notice.panel.get_global_rect()),"over":game.interaction._over_ui(text_point),"context":str(guide.preview_context),"live_context":str([game.model.revision,game.selected_id,game.selected_kind]),"latched":guide.preview_latched,"cached":str(guide.preview_issues),"active":str(guide.access_issues),"reason":game.interaction.drag_reason}));await frames();sync();check(not guide.current_access_issue().is_empty(),"crossing message text preserves diagnostic")
 await click(text_point);check(state()==before,"message-body click cannot place behind notice")
 var selected_before=[game.selected_id,game.selected_kind];await click(notice.show_button.get_global_rect().get_center());check([game.selected_id,game.selected_kind]==selected_before,"mouse Show preserves selected tool identity");check(state()==before,"Show does not mutate gameplay/save");safe_focus("mouse Show")
 # A different invalid cause at the same cell cannot reuse a workface warning.
 guide.focus_hold=false;game.interaction.preview_active=true;game.interaction.drag_active=false;game.interaction.last_pointer=game.illustration.iso(cell.x+.5,cell.y+.5);game.interaction.drag_reason="A staff member is using part of this space";game.interaction.drag_valid=false;guide._refresh_access();notice.sync_position();check(guide.current_access_issue().is_empty(),"same-cell different invalid reason clears stale access issue")
 # Keyboard focus retains the rejected location under a stationary world cursor.
 setup_preview("plant",cell);await frames();sync();var cursor=game.interaction.last_pointer;selected_before=[game.selected_id,game.selected_kind];guide.show_access_issue();check([game.selected_id,game.selected_kind]==selected_before,"keyboard Show preserves selected tool identity");await frames();game.interaction.refresh(cursor);sync();check(guide.focus_hold and not guide.current_access_issue().is_empty(),"keyboard Show survives camera-induced preview cell changes");safe_focus("keyboard Show");check(state()==before,"keyboard navigation preserves gameplay")
 game._cancel_selection();sync();check(guide.current_access_issue().is_empty(),"Cancel clears uncommitted preview diagnostic")
 # A held rotated furniture draft cancels safely before camera navigation.
 var movable={"id":game.model._next_item_id,"kind":"plant","x":4,"z":6,"rot":0};game.model._next_item_id+=1;game.model.items.append(movable);game.model.revision+=1;game._rebuild_furniture();before=state()
 setup_preview("plant",cell,int(movable.id),1);await frames();sync();check(not guide.current_access_issue().is_empty(),"rotated existing draft has authoritative access failure")
 game.interaction._left_down=true;game.interaction._gesture="drag";game.interaction._pointer_device=0
 selected_before=[game.selected_id,game.selected_kind];notice.show_button.pressed.emit();await frames()
 check([game.selected_id,game.selected_kind]==selected_before,"rotated-draft Show preserves selection identity");check(game.rotation_step==0 and not game.interaction._left_down,"Show cancels draft rotation and pointer capture")
 await mouse(game.illustration.iso(5.5,6.5),false);await frames();check(state()==before,"late release after Show cannot move or save furniture")
 game._cancel_selection();game.model.items.erase(movable);game.model.revision+=1;game._rebuild_furniture();sync()
 # Legacy bad layout is a disposable fixture; the UI must navigate and help repair it.
 var blocker={"id":game.model._next_item_id,"kind":"plant","x":cell.x,"z":cell.y,"rot":0};game.model._next_item_id+=1;game.model.items.append(blocker);game.model.revision+=1;game._rebuild_furniture();sync();await frames();check(not guide.current_access_issue().is_empty() and guide.access_source=="current","legacy obstruction has persistent current issue")
 before=state()
 for view in [Vector2i(344,500),Vector2i(390,844),Vector2i(960,540),Vector2i(1360,880),Vector2i(390,844)]:
  root.size=view;await frames(8);sync();game.illustration.pan_offset=Vector2(-1000,700);game.illustration.update_projection()
  var guarded_pan=game.illustration.pan_offset;guide.show_access_issue();await frames();sync()
  if ui.viewport_too_small:check(game.illustration.pan_offset==guarded_pan,"size guard leaves focus inert "+str(view))
  else:safe_focus(str(view))
  check(state()==before,"focus/resize preserves gameplay "+str(view));rows.append({"view":str(view),"guarded":ui.viewport_too_small,"issue":str(guide.current_access_issue()),"panel":str(notice.panel.get_global_rect()),"pan":str(game.illustration.pan_offset)})
 # Existing issues are not falsely described as a new unrelated placement failure.
 root.size=Vector2i(1360,880);await frames(8);game.illustration.focus_fresh_start();setup_preview("plant",Vector2i(4,6));await frames();sync();check(game.interaction.drag_valid,"unrelated preview remains valid");check(guide.access_source=="current" and not notice.issue_label.text.begins_with("Would block"),"unrelated valid preview keeps honest current-issue wording")
 # A repair preview removes the issue before it is committed, with no state loss.
 setup_preview("plant",Vector2i(4,6),int(blocker.id),0);await frames();sync();check(game.interaction.drag_valid,"legacy blocker can preview a repair");check(guide.current_access_issue().is_empty(),"repair preview clears the access issue before commit");check(state()==before,"repair preview remains non-mutating")
 # Show must be inert if its control became hidden by a dialog/size guard.
 game.interaction.on_focus_lost();game.selected_id=-1;sync();var pan=game.illustration.pan_offset;game.settings.show();sync();guide.show_access_issue();check(game.illustration.pan_offset==pan,"hidden modal Show is inert");game.settings.hide();sync();ui.viewport_too_small=true;guide.show_access_issue();check(game.illustration.pan_offset==pan,"size-guarded Show is inert");ui.viewport_too_small=false
 check(state()==before,"all navigation leaves committed state intact")
 var result={"checks":checks,"failures":failures,"rows":rows};FileAccess.open(OS.get_environment("LL_UI_RESULT"),FileAccess.WRITE).store_string(JSON.stringify(result,"  "));print("ACCESS_LOCATION ",JSON.stringify({"checks":checks,"failures":failures}))
 for tween in get_processed_tweens():tween.kill()
 game.settings_controls.sfx_player.stop()
 for player in game.audio_players.values():player.stop()
 await frames();game.queue_free();await frames();quit(0 if failures.is_empty() else 1)
