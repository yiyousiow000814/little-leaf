extends SceneTree
## Synthetic UI state and Dummy audio only; no player profile, hearing or pixels.
const Catalog=preload("res://scripts/ui/cafe_music_catalog.gd")
class TestMain extends "res://scripts/main.gd":
 var saves=0
 var seeks=0
 var observed_audio:Array[WeakRef]=[]
 func _ensure_music_player(id:String)->bool:
  var existed=audio_players.has(id);var available=super._ensure_music_player(id)
  if available and not existed:
   observed_audio.append(weakref(audio_players[id]));observed_audio.append(weakref(audio_players[id].stream))
  return available
 func seek_music_transport(seconds:float)->bool:
  seeks+=1;return super.seek_music_transport(seconds)
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():saves+=1;return true
 func _music_playback_supported()->bool:return true
var game
var checks=0
var failures=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func check_selected_song_markers(music,tag:String):
 var selected=str(game.settings_controls.music_track)
 var selected_id=Catalog.family_id(str(music.snapshot.effective_id) if selected==Catalog.AUTOMATIC else selected)
 check(music.family_cards.has(selected_id),"Shown selected family exists "+tag)
 var title_offset=-1.0
 for id in music.family_cards:
  var card=music.family_cards[id];var is_selected=id==selected_id
  check(card.selected_leaf.visible==is_selected and card.chevron.visible==is_selected,"Leaf and chevron preserve selection "+tag+" "+id)
  check(card.title.get_theme_font("font")== (game.compact_ui.hud.font_bold if is_selected else card.normal_font),"Only selected song is bold "+tag+" "+id)
  check(not card.status.visible,"No unrelated audible glyph crowds the selection chevron "+tag+" "+id)
  check(card.selected_leaf.texture.resource_path.ends_with("selected_song_leaves_r25.svg"),"Selected leaf uses editable detailed paired source "+tag+" "+id)
  check(card.selected_leaf.mouse_filter==Control.MOUSE_FILTER_IGNORE and card.chevron.mouse_filter==Control.MOUSE_FILTER_IGNORE,"Selection marks do not intercept clicks "+tag+" "+id)
  check(card.marker_slot.visible and card.marker_slot.size.x>=24 and card.marker_slot.mouse_filter==Control.MOUSE_FILTER_IGNORE,"Every row retains its noninteractive leaf gutter "+tag+" "+id)
  var offset=card.title.global_position.x-card.button.global_position.x
  if title_offset<0:title_offset=offset
  check(is_equal_approx(offset,title_offset),"Selected and ordinary titles stay aligned "+tag+" "+id)
func _initialize():run.call_deferred()
func settle():
 game._update_ui()
 for frame in 8:await process_frame
func click(button:Control):
 var music=game.compact_ui.music_panel
 if music.scroll.is_ancestor_of(button):music.scroll.ensure_control_visible(button)
 await settle()
 var point=button.get_global_rect().get_center()
 var motion=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;root.push_input(motion,true)
 for pressed in [true,false]:
  var event=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
  await process_frame
 await settle()
func key(code:Key,shift=false):
 for pressed in [true,false]:
  var event=InputEventKey.new();event.keycode=code;event.shift_pressed=shift;event.pressed=pressed;root.push_input(event,true)
 await settle()
func painted_style_rect(style:StyleBox,bounds:Rect2)->Rect2:
 if not (style is StyleBoxFlat or style is StyleBoxTexture):return bounds
 var ink=bounds.grow_individual(style.get_expand_margin(SIDE_LEFT),style.get_expand_margin(SIDE_TOP),style.get_expand_margin(SIDE_RIGHT),style.get_expand_margin(SIDE_BOTTOM))
 if style is StyleBoxFlat and style.shadow_size>0:
  var shadow=ink.grow(style.shadow_size);shadow.position+=style.shadow_offset;ink=ink.merge(shadow)
 return ink

func tween_running(tween:Tween)->bool:
 return tween!=null and tween.is_valid() and tween.is_running()

func artwork_nodes(music)->Array[Node]:
 # Frame is a board descendant, so visiting the board includes it exactly once.
 var nodes:Array[Node]=[music.record_mark,music.premium_feedback,music.board_material]
 var index=0
 while index<nodes.size():
  nodes.append_array(nodes[index].get_children());index+=1
 return nodes

func artwork_resources(music)->Dictionary:
 # Only subtree-owned resources. Source PNGs and shaders are intentionally
 # shared preloads. The ordinary material is also owned by the shared HUD cache;
 # scene teardown must not pretend those are per-panel owned-resource leaks.
 var resources={"board.original":music.board_material.original,"board.wood_material":music.board_material.wood_material,"library.ordinary_style":music.ordinary_library_skin.style,"feedback.rim.style":music.premium_feedback.rim.style}
 for node in artwork_nodes(music):
  if node is MeshInstance2D:
   resources[str(node.get_path())+".mesh"]=node.mesh
   resources[str(node.get_path())+".material"]=node.material
 return resources

func artwork_resource_ids(music)->Array:
 var ids=[]
 for resource in artwork_resources(music).values():
  if resource!=null and not ids.has(resource.get_instance_id()):ids.append(resource.get_instance_id())
 ids.sort()
 return ids

func observe_artwork(music)->Array[Dictionary]:
 # Keep all strong resource temporaries inside this synchronous helper. A local
 # iteration array in the awaiting teardown coroutine can itself retain Tweens.
 var observations:Array[Dictionary]=[]
 for node in artwork_nodes(music):
  observations.append({"owner":str(node.get_path()),"class":node.get_class(),"id":node.get_instance_id(),"ref":weakref(node)})
 var resources=artwork_resources(music)
 resources.merge({"record.transition":music.record_mark._transition,"board.transition":music.board_material._transition,"feedback.pulse":music.premium_feedback.pulse})
 var seen=[]
 for owner in resources:
  var resource=resources[owner]
  if resource==null or seen.has(resource.get_instance_id()):continue
  seen.append(resource.get_instance_id())
  observations.append({"owner":owner,"class":resource.get_class(),"id":resource.get_instance_id(),"ref":weakref(resource)})
 return observations

func retained_artwork(observations:Array[Dictionary])->Array[Dictionary]:
 var retained:Array[Dictionary]=[]
 for observation in observations:
  var object=observation.ref.get_ref()
  if object==null:continue
  var detail={"owner":observation.owner,"class":observation["class"],"id":observation.id}
  if object is Tween:detail["valid"]=object.is_valid();detail["running"]=object.is_running()
  retained.append(detail)
 return retained

func audio_inventory()->Dictionary:
 var inventory={}
 for id in game.audio_players:
  var player=game.audio_players[id]
  inventory[id]={"node":player.get_instance_id(),"stream":player.stream.get_instance_id() if player.stream!=null else 0}
 return inventory

func expected_content_insets()->Vector4:
 # Independent synthetic-viewport contract. Do not derive the expected safe
 # rectangle from the panel, material or frame implementation under test.
 var view=Vector2(root.size)
 var screen_insets:Vector4=game.get_meta("hud_safe_insets",Vector4.ZERO)
 var usable=Vector2(maxf(0,view.x-screen_insets.x-screen_insets.z),maxf(0,view.y-screen_insets.y-screen_insets.w))
 var short_view=usable.y<650
 var portrait=usable.x<500 or (not short_view and usable.x<760)
 if not portrait and usable.x>=1000 and usable.y>=720:return Vector4(28,34,28,18)*minf(usable.x/1528.0,usable.y/1029.0)
 if not portrait and usable.y>=650:return Vector4(84,60,84,54)
 # r25 intentional phone redesign: fixed phone-safe margins, independently
 # specified here. Desktop reference contract and all ink/input gates remain.
 if portrait:return Vector4(22,20,22,22)
 return Vector4(20,16,20,16) if usable.x<700 else Vector4(24,18,24,18)

func expected_inner_board(music)->Rect2:
 var insets=expected_content_insets()
 return music.panel.get_global_rect().grow_individual(-insets.x,-insets.y,-insets.z,-insets.w)

func check_decorative_ink(music,tag:String):
 check_board_blend(music,tag)
 # Generic Control bounds miss transformed meshes and custom drawing. Inspect
 # complete reported ink without clipping away a possible allocation overrun.
 var panel_bounds=music.panel.get_global_rect()
 var safe=expected_inner_board(music)
 var other_controls:Array[Node]=[music.body]
 var index=0
 while index<other_controls.size():
  other_controls.append_array(other_controls[index].get_children());index+=1
 for artwork in [music.record_mark,music.premium_feedback]:
  if not artwork.is_visible_in_tree():continue
  var allocation=artwork.get_global_rect()
  var owner=artwork.get_parent() if artwork==music.premium_feedback else artwork
  var ink_rects=artwork.ink_rects()
  check(not ink_rects.is_empty(),"Decorative audit observes explicit painted ink "+str(artwork.name)+" "+tag)
  for ink in ink_rects:
   check(safe.grow(.1).encloses(ink),"Transformed decorative ink stays inside the board interior "+str(artwork.name)+" "+tag)
   check(allocation.grow(.1).encloses(ink),"Transformed decorative ink stays inside its allocated artwork rectangle "+str(artwork.name)+" "+tag)
   var overlaps=[]
   for control in other_controls:
    if not (control is Label or control is BaseButton or control is Range) or not control.is_visible_in_tree():continue
    if control==owner or owner.is_ancestor_of(control):continue
    var forbidden=control.get_global_rect()
    if music.scroll.is_ancestor_of(control):forbidden=forbidden.intersection(music.scroll.get_global_rect())
    if forbidden.has_area() and ink.intersection(forbidden).has_area():overlaps.append(str(control.name))
   check(overlaps.is_empty(),"Decorative ink avoids other controls and labels "+str(artwork.name)+" "+str(overlaps)+" "+tag)

 if music.header_skin.is_visible_in_tree():
  for target in [music.automatic_button,music.close_button]:check(music.header_skin.get_global_rect().encloses(target.get_global_rect()),"Header backing covers current control "+str(target.name)+" "+tag)
 if music.botanical_frame.is_visible_in_tree():
  for ink in music.botanical_frame.ink_rects():
   check(panel_bounds.encloses(ink),"Reference botanical ink stays within board "+tag)
   for control in other_controls:
    if not (control is Label or control is BaseButton or control is Range) or not control.is_visible_in_tree():continue
    var forbidden=control.get_global_rect()
    if control is Label and control.get_line_count()==1:
     var text_width=minf(forbidden.size.x,control.get_theme_font("font").get_string_size(control.text,HORIZONTAL_ALIGNMENT_LEFT,-1,control.get_theme_font_size("font_size")).x)
     if control.horizontal_alignment==HORIZONTAL_ALIGNMENT_CENTER:forbidden.position.x+=(forbidden.size.x-text_width)*.5
     elif control.horizontal_alignment==HORIZONTAL_ALIGNMENT_RIGHT:forbidden.position.x+=forbidden.size.x-text_width
     forbidden.size.x=text_width
    if music.scroll.is_ancestor_of(control):forbidden=forbidden.intersection(music.scroll.get_global_rect())
    check(not ink.intersection(forbidden).has_area(),"Reference botanical ink avoids control "+str(control.name)+" "+tag)

func step_artwork(music,seconds:float):
 for tween in [music.record_mark._transition,music.board_material._transition,music.premium_feedback.pulse]:
  if tween_running(tween):tween.custom_step(seconds)
 # Explicit stepping is deterministic and still honors each component's
 # processing gate. Inactive artwork must never receive a fabricated phase tick.
 for artwork in [music.record_mark]:
  if artwork.is_processing():artwork._process(seconds)

func tip_bends(materials:Array)->Array:
 var result=[]
 for material in materials:
  var value=material.get_shader_parameter("tip_bend")
  result.append(0.0 if value==null else float(value))
 return result

func artwork_phase(music)->Dictionary:
 var label_uniform=music.record_mark._record_material.get_shader_parameter("label_angle")
 return {"label_uniform":0.0 if label_uniform==null else float(label_uniform),"label":music.record_mark._label_angle,"leaf_phase":music.record_mark._leaf_phase,"leaf_bends":tip_bends(music.record_mark._leaf_materials),"tonearm_motion":music.record_mark._arm_motion}

func planted_transforms(music)->Array:
 var result=[]
 for stem in music.record_mark._leaves:result.append(stem.transform)
 return result

func check_artwork_rest(music,tag:String,immediate=false):
 var mark=music.record_mark
 check(not mark.is_processing(),"Inactive playback stops record and foliage phase updates "+tag)
 if not immediate:
  step_artwork(music,0.6)
 var frozen=artwork_phase(music)
 if not immediate:step_artwork(music,2.0)
 check(artwork_phase(music)==frozen,"Inactive artwork preserves its exact label angle and leaf-tip bends "+tag)
 for artwork in [mark,music.board_material]:
  check(artwork.active_tweens()==0,"No finite artwork transition remains after rest "+str(artwork.name)+" "+tag)
  check(is_equal_approx(artwork.reveal,1.0 if artwork._premium else 0.0),"Inactive presentation retains the selected settled edition "+str(artwork.name)+" "+tag)
 check(is_zero_approx(mark._record.rotation),"Paused projection never rotates the whole ellipse "+tag)
 if immediate:
  check(not music.premium_feedback.visible and not tween_running(music.premium_feedback.pulse),"Hidden/reduced presentation cancels selection feedback immediately "+tag)

func check_artwork_playing(music,tag:String):
 var mark=music.record_mark
 step_artwork(music,.02)
 check(bool(music.snapshot.playing) and not bool(music.snapshot.muted) and mark._playing_requested,"Artwork follows audible effective backend playback "+tag)
 check(mark._premium and mark.is_processing()==mark.is_visible_in_tree(),"Visible Premium record advances its retained shader phase "+tag)
 for artwork in [mark,music.board_material]:
  check(artwork.active_tweens()<=1,"Each artwork owner has at most one replaceable finite transition "+str(artwork.name)+" "+tag)
 check(is_zero_approx(mark._record.rotation),"Playing projection keeps a fixed ellipse orientation "+tag)

func check_motion_lifecycle(music,ui,controls,premium_id:String):
 var old_view=root.size
 var old_volume=controls.bgm_volume
 var old_selection=controls.music_track
 var master=AudioServer.get_bus_index("Master")
 var master_was_muted=AudioServer.is_bus_mute(master)
 AudioServer.set_bus_mute(master,false)
 root.size=Vector2i(1360,880);await settle()
 controls.set_audio_enabled("BGM",true);game.set_music_transport_paused(false)
 music._select("service");await settle();music._poll_playback()
 var mark=music.record_mark
 check(is_equal_approx(mark.TRANSITION_SECONDS,.5) and is_equal_approx(music.board_material.TRANSITION_SECONDS,.5),"Hero and board share the approved half-second timeline")
 step_artwork(music,2.0)
 check(not mark._premium and is_zero_approx(mark.reveal) and not mark._support.visible and not mark._base.visible and not mark._sprigs.visible and mark._bud_blades.all(func(bud):return not bud.visible) and mark._petals.all(func(petal):return not petal.visible) and mark._leaves.all(func(leaf):return not leaf.visible),"Default edition keeps the simple record without a cabinet or floral layers")
 check(is_zero_approx(music.board_material.reveal),"Default keeps its original board")
 check_board_motion(music)
 var focus_before={}
 for button in [music.automatic_button,music.close_button,music.play_button,music.previous_button,music.next_button,music.mute_button]+music.track_buttons.values():focus_before[button]=button.get_theme_stylebox("focus")
 music._select(premium_id);await settle();music._select("service");await settle()
 for button in focus_before:check(button.get_theme_stylebox("focus")==focus_before[button],"Default restores its exact focus resource after Premium "+str(button.name))
 var original_nodes=artwork_nodes(music).map(func(node):return node.get_instance_id())
 var original_resources=artwork_resource_ids(music)
 check(not mark._petal_blades.is_empty() and not mark._leaf_blades.is_empty(),"Layered artwork retains painted petals and player leaves")
 check(mark.find_child("IvoryPetalSupport",true,false)==null,"Cabinet feet have no duplicate horizontal petal support")
 check(mark._support.name=="SculptedIvorySupport" and mark._support.z_index<mark._base.z_index,"One authored support stays behind the cabinet")
 var front=mark._base.get_node("BaseFrontFascia");var back=mark._base.get_node("BaseTopRecess")
 check(front.material.shader==back.material.shader and front.material.get_shader_parameter("front_layer")==1.0 and back.material.get_shader_parameter("front_layer")==0.0,"Cabinet front and back use complementary curved source masks")
 var petal_meshes={}
 for blade in mark._petal_blades:petal_meshes[blade.mesh.get_instance_id()]=true
 check(petal_meshes.size()==mark._petal_blades.size() and mark._leaf_blades.all(func(blade):return blade.mesh==mark._leaf_blades[0].mesh),"Player petals retain distinct authored profiles and leaves reuse one immutable mesh")
 music._select(premium_id);await settle();music._poll_playback()
 check_artwork_playing(music,"selected Premium")
 step_artwork(music,2.0)
 var phase_before=artwork_phase(music)
 var roots_before=planted_transforms(music)
 var projection_before=mark._record.transform
 step_artwork(music,.2)
 var advanced=artwork_phase(music)
 check(not is_equal_approx(advanced.label,phase_before.label) and not is_equal_approx(advanced.label_uniform,phase_before.label_uniform) and is_equal_approx(advanced.label,advanced.label_uniform),"Playing advances the circular label shader angle and its material uniform")
 check(advanced.leaf_bends!=phase_before.leaf_bends,"Playing deforms the retained record artwork leaf tips")
 check(planted_transforms(music)==roots_before,"Leaf-tip motion leaves all planted stems and lower-root transforms fixed")
 check(mark._record.transform.is_equal_approx(projection_before),"Label rotation never rotates or reprojects the settled record ellipse")
 check(mark._sprigs.bake_count==1 and mark._sprigs.paths.size()==3,"Hero sprig curves are baked once and rooted inside the cabinet")
 check(mark._bud_blades.size()==3 and mark._bud_blades.all(func(bud):return bud.mesh==mark._bud_blades[0].mesh),"Hero buds reuse one immutable source-bound atlas mesh")
 for index in mark._bud_blades.size():
  check((mark._bud_blades[index].get_global_transform()*Vector2.ZERO).is_equal_approx(mark._canvas.get_global_transform()*mark.BUD_ROOTS[index]),"Bud growth keeps its stem attachment planted "+str(index))
 check(absf(rad_to_deg(mark._arm_motion))<=mark.ARM_MUSIC_DEGREES,"Music-driven tonearm compliance stays below its sub-degree limit")
 check((mark._arm.get_global_transform()*mark.ARM_PIVOT).is_equal_approx(mark._canvas.get_global_transform()*(mark.ARM_PIVOT+Vector2(0,-18))),"Tonearm motion preserves the exact planted pivot")
 var needle=mark._arm.transform*Vector2(291,213)
 var projected=(needle-mark._record.position)/(mark._record.scale*.5)
 check(projected.length_squared()<.9,"Moving stylus remains safely inside the record projection")
 check(artwork_resource_ids(music)==original_resources,"Animation allocates no replacement meshes, materials or board styles")
 music._select("service");step_artwork(music,2.0)
 music._select(premium_id);music._poll_playback();step_artwork(music,.08)
 check(mark.reveal>0 and mark.reveal<1,"Rapid interruption fixture catches the floral reveal between Default and Premium")
 var interrupted:Array[WeakRef]=[]
 for artwork in [mark,music.board_material]:
  if artwork._transition!=null:interrupted.append(weakref(artwork._transition))
 music._select("service");music._select(premium_id);music._poll_playback()
 for artwork in [mark,music.board_material]:check(artwork.active_tweens()<=1,"Rapid edition toggles replace the owner's finite transition "+str(artwork.name))
 game.set_music_transport_paused(true);music._poll_playback();check_artwork_rest(music,"paused during floral reveal")
 game.set_music_transport_paused(false);music._poll_playback()
 check_artwork_playing(music,"rapid pause/resume after edition interruption")
 await settle()
 check(interrupted.all(func(ref):return ref.get_ref()==null),"Interrupted edition transitions release their replaced Tween resources")
 for view in [Vector2i(1528,1029),Vector2i(1360,880),Vector2i(390,844),Vector2i(844,390)]:
  root.size=view;await settle();music._poll_playback()
  var stationary_controls=[music.panel,music.header,music.player,music.record_mark,music.library,music.scroll,music.dock,music.controls_row,music.transport,music.progress_slider,music.footer,music.heading,music.now_playing,music.edition_host]
  var premium_rects=stationary_controls.map(func(control):return control.get_global_rect())
  music._select(str(Catalog.family_for_track(premium_id).default_id));await settle();music._poll_playback()
  for index in stationary_controls.size():check(stationary_controls[index].get_global_rect().is_equal_approx(premium_rects[index]),"Default and Premium share stationary control geometry "+str(stationary_controls[index].name)+" "+str(view))
  music._select(premium_id);await settle();music._poll_playback()
  for index in stationary_controls.size():check(stationary_controls[index].get_global_rect().is_equal_approx(premium_rects[index]),"Returning to Premium preserves the same control geometry "+str(stationary_controls[index].name)+" "+str(view))
  if view.x>=1000:
   var axis=music.play_button.get_global_rect().get_center().y
   check(absf(axis-music.transport_skin.get_global_rect().get_center().y)<=1.0,"Whole transport group is centered within the actual tray "+str(view))
   for control in [music.previous_button,music.next_button,music.mute_button,music.progress_slider,music.volume_slider,music.elapsed_label,music.duration_label,music.volume_value]:
    check(absf(control.get_global_rect().get_center().y-axis)<=1.0,"Transport controls share the same optical center axis "+str(control.name)+" "+str(view))
   for button in [music.previous_button,music.next_button,music.mute_button]:
    check(absf(button.size.x-button.size.y)<=.1,"Desktop side buttons remain circular rather than stretched "+str(button.name)+" "+str(view))
  # Sample reveal and shader phases without relying on wall-clock timing. This
  # covers Default, every transition layer, fixed projection and bend envelopes.
  music.premium_feedback.play_on(music.track_buttons[premium_id],false)
  var fixed_controls=[music.close_button.get_global_rect(),music.transport.get_global_rect(),music.progress_slider.get_global_rect(),music.footer.get_global_rect()]
  for phase in 41:
   for artwork in [mark,music.board_material]:artwork.set_reveal(float(phase)/40.0)
   check_decorative_ink(music,str(view)+" phase "+str(phase))
   step_artwork(music,.1)
   check([music.close_button.get_global_rect(),music.transport.get_global_rect(),music.progress_slider.get_global_rect(),music.footer.get_global_rect()]==fixed_controls,"Material/floral transition never moves interactive controls "+str(view)+" phase "+str(phase))
  check(not music.premium_feedback.visible and not tween_running(music.premium_feedback.pulse),"Selection click feedback finishes within its finite timeline "+str(view))
  mark.set_state(true,true,false,"bounds "+str(view));music.board_material.set_state(true,false)
  check(mark.active_tweens()==0 and music.board_material.active_tweens()==0,"Unchanged Premium state does not restart settled material/floral transitions "+str(view))
  check(artwork_resource_ids(music)==original_resources,"Resize and sampled phases reuse the same retained resources "+str(view))
 root.size=Vector2i(1360,880);await settle();music._poll_playback()
 var feedback_button=music.track_buttons[premium_id];var feedback_button_size=feedback_button.size
 feedback_button.size=feedback_button_size+Vector2(24,0)
 music.premium_feedback.play_on(feedback_button,false);step_artwork(music,.08)
 check(music.premium_feedback.visible and tween_running(music.premium_feedback.pulse),"Resize interruption fixture catches an active selection pulse")
 feedback_button.size=feedback_button_size
 check(music.premium_feedback.size.is_equal_approx(feedback_button_size) and not music.premium_feedback.visible and not tween_running(music.premium_feedback.pulse),"Narrowing the button mid-pulse cancels stale rim and glint geometry immediately")
 game.set_music_transport_paused(true);music._poll_playback();check_artwork_rest(music,"paused")
 game.set_music_transport_paused(false);await settle();music._poll_playback();check_artwork_playing(music,"resumed")
 controls.set_audio_enabled("BGM",false);music.sync();music._poll_playback();check_artwork_rest(music,"BGM muted")
 controls.set_audio_enabled("BGM",true);await settle();music._poll_playback();check_artwork_playing(music,"BGM unmuted")
 controls.set_audio_volume("BGM",0);music.sync();music._poll_playback();check_artwork_rest(music,"zero volume")
 controls.set_audio_volume("BGM",old_volume);music.sync();music._poll_playback();check_artwork_playing(music,"volume restored")
 AudioServer.set_bus_mute(master,true);music._poll_playback();check_artwork_rest(music,"Master muted")
 AudioServer.set_bus_mute(master,false);music._poll_playback();check_artwork_playing(music,"Master restored")
 game.browser_suspended=true;music.sync();music._poll_playback();check_artwork_rest(music,"browser suspended")
 game.browser_suspended=false;music.sync();music._poll_playback();check_artwork_playing(music,"browser resumed")
 # Exercise a genuinely missing effective decoder through the normal retirement
 # path, rather than fabricating a UI snapshot or reading an original profile.
 game._stop_music_at_current_position();game._retire_music_player(premium_id);music._poll_playback()
 check(not music.snapshot.available and not music.snapshot.playing and not music.snapshot.can_play and not music.snapshot.seekable,"Missing effective audio exposes genuinely unavailable playback")
 check(music.play_button.disabled and not music.progress_slider.editable and not music.context_label.text.is_empty(),"Unavailable audio disables transport and explains its state")
 check_artwork_rest(music,"audio unavailable")
 game._switch_music(premium_id);await settle();music._poll_playback();check_artwork_playing(music,"audio restored")
 game._toggle_edit();music.show();await settle();music._poll_playback()
 check(mark._premium and controls.music_track==premium_id and music.snapshot.effective_id==Catalog.DECORATE,"Decorate preserves the Premium selection while playing its effective Quiet Table recording")
 check_artwork_rest(music,"Decorate effective mismatch")
 var queued_id=""
 for entry in Catalog.TRACKS:
  if entry.group==Catalog.PREMIUM and entry.id!=premium_id:queued_id=entry.id;break
 music._select(queued_id);music._poll_playback();check_artwork_rest(music,"different queued Premium")
 music._select(premium_id);game._toggle_edit();music.show();await settle();music._poll_playback();check_artwork_playing(music,"Decorate exited")
 game.set_meta("hud_reduce_motion",true);music._poll_playback()
 check(mark._reduced,"Artwork reads the existing HUD reduced-motion preference")
 check_artwork_rest(music,"reduced motion",true)
 music._select(queued_id);music._poll_playback();check_artwork_rest(music,"reduced-motion Premium activation",true)
 game.set_meta("hud_reduce_motion",false);music._select(premium_id);await settle();music._poll_playback();check_artwork_playing(music,"reduced motion cleared")
 music.premium_feedback.play_on(music.track_buttons[premium_id],false)
 game.ui.hide();check_artwork_rest(music,"hidden ancestor",true)
 game.ui.show();await settle();music._poll_playback();check_artwork_playing(music,"ancestor revealed")
 var seeks_before=game.seeks;var saves_before=game.saves
 var audio_before=audio_inventory();var observed_before=game.observed_audio.size()
 var retired_feedback:Array[WeakRef]=[]
 step_artwork(music,2.0)
 var tween_inventory=get_processed_tweens().size()
 # Repeated identical activations and close/reopen cycles must reuse the same
 # owned nodes. Keep only weak observations of replaced feedback tweens.
 for cycle in 12:
  if music.premium_feedback.pulse!=null:retired_feedback.append(weakref(music.premium_feedback.pulse))
  await click(music.track_buttons[premium_id]);music._poll_playback()
  check(mark.active_tweens()==0 and music.board_material.active_tweens()==0,"Same-track activation does not restart settled edition transitions "+str(cycle))
  check(artwork_resource_ids(music)==original_resources,"Same-track activation reuses painted meshes, materials and board styles "+str(cycle))
  check(artwork_nodes(music).map(func(node):return node.get_instance_id())==original_nodes,"Repeated Premium activation reuses every artwork node "+str(cycle))
  check(mark.active_tweens()<=1 and music.board_material.active_tweens()<=1 and (not music.premium_feedback.visible or tween_running(music.premium_feedback.pulse)),"Repeated Premium activation owns bounded transitions and one feedback pulse "+str(cycle))
  music.dismiss();check_artwork_rest(music,"closed cycle "+str(cycle),true)
  await settle();music.show(ui.music_access);await settle();music._poll_playback()
  check_artwork_playing(music,"reopened cycle "+str(cycle))
  check(get_processed_tweens().size()<=tween_inventory+1,"Repeated open/close does not accumulate orphaned SceneTree tweens "+str(cycle))
 check(retired_feedback.all(func(ref):return ref.get_ref()==null),"Replaced Premium feedback tweens are released rather than retained")
 check(game.seeks==seeks_before and game.saves==saves_before,"Repeated same-track activation and reopening cause no seeks or restaurant saves")
 var audio_after=audio_inventory();var unexpected_audio=[]
 for id in audio_after:
  if not audio_before.has(id) or audio_before[id]!=audio_after[id]:unexpected_audio.append(id)
 # An outgoing decoder may retire during its existing 1.2-second crossfade.
 # Allocation observations never shrink, and every survivor must keep identity.
 print("MUSIC_MOTION_AUDIO ",JSON.stringify({"before":audio_before,"after":audio_after,"observations_before":observed_before,"observations_after":game.observed_audio.size(),"new_or_replaced":unexpected_audio}))
 check(unexpected_audio.is_empty() and game.observed_audio.size()==observed_before,"Repeated same-track activation and reopening allocate no audio nodes or streams")
 check(artwork_nodes(music).map(func(node):return node.get_instance_id())==original_nodes,"Close/reopen retains exactly the original artwork node inventory")
 AudioServer.set_bus_mute(master,master_was_muted)
 music._select(old_selection);root.size=old_view;await settle()

func check_inner_board(music,tag:String):
 # Independent responsive content envelope; both board materials must use it.
 var expected=expected_content_insets()
 var safe=expected_inner_board(music)
 check(safe.is_equal_approx(music.inner_board_rect()),"Independent responsive interior contract "+tag)
 var panel_style=music.panel.get_theme_stylebox("panel")
 var actual=Vector4(panel_style.get_content_margin(SIDE_LEFT),panel_style.get_content_margin(SIDE_TOP),panel_style.get_content_margin(SIDE_RIGHT),panel_style.get_content_margin(SIDE_BOTTOM))
 check(actual.is_equal_approx(expected),"Layout margins match the independent usable-viewport fixture "+tag)
 check(music.board_material.get_global_rect().is_equal_approx(safe),"Material transition occupies the same responsive content allocation "+tag)
 var pending:Array[Node]=[music.body,music.scroll.get_v_scroll_bar()]
 var seen=0
 while not pending.is_empty():
  var node=pending.pop_back()
  pending.append_array(node.get_children())
  if not node is Control or not node.is_visible_in_tree():continue
  if not (node is Label or node is BaseButton or node is Range or node is PanelContainer or node==music.record_mark or node==music.speaker_mark or node in music.control_marks):continue
  var ink=node.get_global_rect()
  if node is BaseButton:
   for state in ["normal","hover","pressed","hover_pressed","disabled","focus"]:
    ink=ink.merge(painted_style_rect(node.get_theme_stylebox(state),node.get_global_rect()))
  elif node is PanelContainer:ink=ink.merge(painted_style_rect(node.get_theme_stylebox("panel"),ink))
  if music.scroll.is_ancestor_of(node):ink=ink.intersection(music.scroll.get_global_rect())
  if not ink.has_area():continue
  seen+=1
  check(safe.grow(.1).encloses(ink),"Painted content stays within wooden interior: "+str(node.name)+" "+tag)
 check(seen>=16,"Inner-board audit observes real control and label ink "+tag)
 check_decorative_ink(music,tag)
 for slider in [music.progress_slider,music.volume_slider]:
  var thumb=slider.get_theme_icon("grabber")
  check(slider.size.x>=thumb.get_width() and slider.size.y>=thumb.get_height(),"Slider thumb fits its inner-board target "+str(slider.name)+" "+tag)
 print("MUSIC_INNER_BOARD ",JSON.stringify({"case":tag,"panel":str(music.panel.get_global_rect()),"inner":str(safe),"library_surface":str(music.library.get_global_rect()),"player_surface":str(music.player.get_global_rect()),"dock":str(music.dock.get_global_rect()),"observed_ink_controls":seen}))

func check_board_geometry(music):
 # Synchronous by design: temporary styles/materials must be released before
 # lifecycle teardown records weak references to scene-owned resources.
 var board=music.board_material
 var frame=board.original
 check(frame is StyleBoxTexture and frame.texture.get_size()==Vector2(512,158),"Board uses the actual original512x158 painted wood texture")
 check([SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM].all(func(side):return frame.get_texture_margin(side)==64),"Default and Premium retain the same64px nine-patch corner geometry")
 check(board.ordinary.style==frame and board.ordinary.material==music.compact.hud._art_material(0),"Default draws the exact original wood style and shared HUD material")
 check(board.ordinary.show_behind_parent and board._corner_canvas.get_index()<board.ordinary.get_index(),"Original corner meshes retract behind the continuously retained wood body")
 check(board.material==null and not board.use_parent_material,"Board material treatment remains isolated from live controls")
 check(board.wood_material is ShaderMaterial and board.corner_leaves.size()==4 and board.corner_materials.size()==4,"Board owns one wood treatment and four retained original corner pieces")
 check(board.corner_leaves.all(func(leaf):return leaf.texture==frame.texture and leaf.mesh==board.corner_leaves[0].mesh),"All original corner pieces share the unchanged source texture and one immutable mesh")
 var mesh=board.corner_leaves[0].mesh
 check(mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()==323 and mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size()==1728,"Source-derived corner deformation retains one bounded323-vertex grid")
 var corner_data=board.corner_motion_data()
 check(corner_data[1].source_region.position==Vector2(440,0) and corner_data[1].source_region.size==Vector2(72,64),"Top-right foliage includes the source443px leaf inside the stretched center strip")
 check(music.record_mark._canvas.z_as_relative and music.record_mark._canvas.z_index>=4,"Local art canvas keeps negative-Z cabinet and petals above the board material")

func check_board_blend(music,tag:String):
 var board=music.board_material
 var state=board.material_state()
 check(state.body_rect.is_equal_approx(music.panel.get_global_rect()),"The same original paint geometry covers the actual board at every material phase "+tag)
 check(state.body_visible and state.same_original_style,"Original wood body never disappears or swaps silhouettes "+tag)
 check(is_equal_approx(state.body_alpha,1.0) and is_equal_approx(board.ordinary.self_modulate.a,1.0) and is_equal_approx(board.original.modulate_color.a,1.0),"Body alpha remains continuously opaque instead of exposing the cafe "+tag)
 check(state.original_material_active==(board.reveal==0.0),"Zero reveal returns to the actual original HUD material "+tag)
 if board.reveal>0:
  check(board.ordinary.material==board.wood_material,"Premium stain is applied on the original retained board surface "+tag)
 check(board._corner_canvas.visible==(board.reveal>0.0),"Original corner split is used only while the wood material morphs "+tag)
 var corners=board.corner_motion_data()
 check(corners.all(func(corner):return is_equal_approx(corner.alpha,1.0)),"Original corner leaves retain full alpha in both editions "+tag)
 check(board.corner_materials.all(func(paint):return is_equal_approx(float(paint.get_shader_parameter("retraction")),state.corner_retraction)),"All corner shaders use the inspected geometric retraction phase "+tag)

func check_board_motion(music):
 var board=music.board_material
 board.set_state(false,true,true)
 var original_rect=board.ordinary.get_global_rect()
 var original_data=board.corner_motion_data()
 var original_resources=artwork_resource_ids(music)
 var forward=[0.0,.001,.159,.16,.32,.639,.64,.641,.959,.96,1.0]
 var phases=forward.duplicate();var reverse=forward.duplicate();reverse.reverse();phases.append_array(reverse)
 for phase in phases:
  board.set_reveal(phase)
  check_board_blend(music,"forward/reverse boundary "+str(phase))
  var data=board.corner_motion_data()
  check(board.ordinary.get_global_rect()==original_rect,"Material boundary never shifts the board rectangle "+str(phase))
  for index in 4:
   check(data[index].root==original_data[index].root,"Corner root remains planted through the complete forward/reverse curl "+str(index)+" "+str(phase))
   check(data[index].tip==original_data[index].tip,"Both editions retain the exact original corner tip "+str(index)+" "+str(phase))
  check(artwork_resource_ids(music)==original_resources,"Material boundary retains all source styles, meshes and materials "+str(phase))
 board.set_state(false,true,true)
 board.set_state(true,false,true)
 check(board.active_tweens()==1,"An audible edition change creates exactly one finite wood/corner transition")
 if tween_running(board._transition):board._transition.custom_step(.48)
 var interrupted_reveal=board.reveal
 check(interrupted_reveal>0 and interrupted_reveal<1,"Board interruption fixture observes actual intermediate geometry")
 board.set_state(false,false,true)
 check(board.reveal==interrupted_reveal and board.active_tweens()==1,"Reversing a partial board transition continues from the exact current geometry")
 if tween_running(board._transition):board._transition.custom_step(.1)
 interrupted_reveal=board.reveal
 board.set_state(true,false,true)
 check(board.reveal==interrupted_reveal and board.active_tweens()==1,"Repeated reversal replaces one tween without an endpoint jump")
 board.set_state(true,false,false)
 check(board.reveal==interrupted_reveal and board.active_tweens()==1,"Pausing playback preserves the current pose of the bounded material transition")
 if tween_running(board._transition):board._transition.custom_step(.5)
 check(board.reveal==1 and board.active_tweens()==0,"Paused material transition finishes within the half-second envelope")
 board.set_state(false,true,true)
 check(board.reveal==0 and board.active_tweens()==0 and board.ordinary.material==music.compact.hud._art_material(0),"Reduced motion restores Default through the exact original draw path")
 check(artwork_resource_ids(music)==original_resources,"Interrupted board transitions never replace retained artwork resources")

func check_touch_waves(music):
 var ripple=music.air_ripple
 check(ripple.mouse_filter==Control.MOUSE_FILTER_IGNORE,"Air waves never consume control input")
 check(ripple.clip_contents and ripple._waves.size()==4,"Air wave capacity and board clip are bounded")
 ripple.clear();ripple.reduced=false
 for index in 12:ripple.emit_at(ripple.size*.5)
 check(ripple.active_count()==4,"Repeated touches reuse four retained quads")
 ripple._process(1.0)
 check(ripple.active_count()==0 and not ripple.is_processing(),"Air waves retire all work after decay")
 ripple.reduced=true;ripple.emit_at(ripple.size*.5)
 check(ripple.active_count()==0,"Reduced motion suppresses touch waves")
 ripple.reduced=false;ripple.emit_at(ripple.size*.5);ripple.hide()
 check(ripple.active_count()==0 and not ripple.is_processing(),"Hidden touch waves clear immediately")
 ripple.show()

func run():
 game=TestMain.new();root.add_child(game);game.set_process(false);game.paused=true
 game.set_meta("hud_reduce_motion",false)
 if game.cafe_intro!=null:game.cafe_intro.finish()
 await process_frame
 var ui=game.compact_ui;var music=ui.music_panel;var controls=game.settings_controls
 check(music.automatic_button.text=="Auto" and music.automatic_button.accessibility_name.contains("Automatic"),"Visible Auto keeps its full accessible meaning")
 check(music.close_button.text.is_empty() and music.close_mark.glyph=="close","Close uses a native drawn X, not a font character")
 check(music.previous_button.text.is_empty() and music.next_button.text.is_empty() and music.previous_mark.glyph=="previous" and music.next_mark.glyph=="next","Previous and next use proper native track icons")
 check(not music.panel.visible and not game.settings.visible,"Music setup never opens a popup")
 check(music.poll_timer.is_stopped() and is_equal_approx(music.poll_timer.wait_time,.25),"Progress timer is bounded to 4Hz and starts stopped")
 check_board_geometry(music)
 check(music.track_buttons.size()==23 and music.family_cards.size()==9,"All 23 recordings occur in 9 configured song families")
 check(Catalog.selectable_tracks().size()==23,"All 23 retained recordings remain available")
 check(music.library_heading.text=="SONGS  /  "+str(Catalog.families().size()),"Shelf heading count derives from configured song families")
 var sunshine_default="sunshine-skip-176-new-theme";var sunshine_premium="sunshine-skip-150-r6-2nd"
 var sunshine_card=music.family_cards[Catalog.family_id(sunshine_default)]
 check(Catalog.family_id(sunshine_default)==Catalog.family_id(sunshine_premium) and sunshine_card.tracks.size()==2 and music.track_buttons[sunshine_default].get_parent()==sunshine_card.versions and music.track_buttons[sunshine_premium].get_parent()==sunshine_card.versions and music.track_buttons[sunshine_default].text=="Default" and music.track_buttons[sunshine_premium].text=="Premium B","Both original Sunshine Skip IDs share one card with Default and Premium B controls")
 check(music.group_note.visible and music.group_note.accessibility_description==Catalog.PREMIUM_TOOLTIP,"Premium terms visible without hover")
 var counts={Catalog.DEFAULT:0,Catalog.PREMIUM:0}
 for entry in Catalog.TRACKS:
  var row=music.rows[entry.id];counts[entry.group]+=1
  check(row.button.get_meta("music_track_id")==entry.id and Catalog.display_title(entry.id) in row.button.accessibility_name,"Stable ID and full accessible title preserved "+entry.id)
  check(row.button.disabled==not entry.get("selectable",true),"Recording availability follows the catalog "+entry.id)
  check(row.button.get_parent()==music.track_buttons[Catalog.family_for_track(entry.id).variants[0].id].get_parent(),"Related editions share the same card "+entry.id)
 var draft_markers=RegEx.new();draft_markers.compile("(?i)(study|fix|\\bR[0-9]+\\b|[0-9]+\\s*bpm|\\b(150|176)\\b|1nd|2nd)")
 for entry in Catalog.TRACKS:
  var button=music.track_buttons[entry.id]
  check(Catalog.display_title(entry.id)==Catalog.song_title(entry.id),"Song title never appends an edition label "+entry.id)
  check(draft_markers.search(Catalog.song_title(entry.id)+Catalog.display_title(entry.id)+button.text+button.tooltip_text+button.accessibility_name)==null,"Player-facing recording labels contain only clean names and edition metadata "+entry.id)
 for family in Catalog.families():
  check(draft_markers.search(family.title)==null,"Song shelf omits draft production markers "+family.id)
 check(counts[Catalog.DEFAULT]==10 and counts[Catalog.PREMIUM]==13,"All Default and Premium recordings retained")
 check(music.family_cards["harmony-study"].tracks.size()==2 and music.track_buttons["harmony-study-A"].text=="Version 1" and music.track_buttons["harmony-study-B"].text=="Version 2","Harmony studies share one family with two visible choices")
 for id in music.track_buttons:
  var button=music.track_buttons[id]
  check(not "1nd" in button.text+button.tooltip_text+button.accessibility_name and not "2nd" in button.text+button.tooltip_text+button.accessibility_name,"Legacy recording suffixes never leak into visible edition UI "+id)
 for view in [Vector2i(1360,880),Vector2i(390,844),Vector2i(844,390),Vector2i(566,360)]:
  root.size=view;await settle();await click(ui.music_access)
  check(music.panel.visible and not game.settings.visible,"HUD opens independent Music "+str(view))
  check(ui.has_open_popup() and not ui.shop_ui.root.visible,"Music uses existing popup world-input policy "+str(view))
  check(not music.poll_timer.is_stopped(),"Live position updates only while open "+str(view))
  var bounds=music.panel.get_global_rect();var close=music.close_button.get_global_rect();var footer=music.footer.get_global_rect()
  print("MUSIC_PANEL_GEOMETRY ",JSON.stringify({"viewport":str(view),"panel":str(bounds),"minimum":str(music.panel.get_combined_minimum_size()),"library":str(music.scroll.get_global_rect()),"player":str(music.player.get_global_rect())}))
  check(Rect2(Vector2.ZERO,Vector2(view)).encloses(bounds),"Panel bounded to viewport "+str(view))
  var expected_center=Vector2(view)/2+Vector2(0,8*minf(view.x/1528.0,view.y/1029.0) if view.x>=1000 else 0)
  check(bounds.get_center().distance_to(expected_center)<1,"Player keeps the shared edition anchor "+str(view))
  if view.x>=1000:check(absf(bounds.size.x/view.x-.934)<.01 and absf(bounds.size.y/view.y-.906)<.01,"Both desktop editions retain the approved reference allocation "+str(view))
  if view==Vector2i(844,390):
   check(bounds.size.is_equal_approx(Vector2(820,370)),"Phone landscape uses its independent full-height composition")
   check(music.edition_host.get_parent()==music.player_body,"Landscape editions have independent full-width row")
   for button in music.track_buttons.values():
    if button.is_visible_in_tree():check(button.size.x>=80 and not button.text.contains("\n"),"Landscape edition captions stay single-line with spacing")
  check(bounds.encloses(close) and close.size.x>=44 and close.size.y>=44,"44px X remains reachable "+str(view))
  check_inner_board(music,str(view))
  for target in [music.previous_button,music.play_button,music.next_button,music.mute_button,music.volume_slider,music.progress_slider,music.automatic_button]:
   check(target.size.x>=44 and target.size.y>=44,"Inner-board layout preserves44px interaction target "+str(target.name)+" "+str(view))
  check(not music.transport.get_global_rect().intersects(music.footer.get_global_rect()),"Playback and volume hit areas never overlap "+str(view))
  check(bounds.encloses(footer) and music.volume_slider.size.y>=44,"BGM controls remain reachable "+str(view))
  check(bounds.encloses(music.transport.get_global_rect()) and bounds.encloses(music.progress_slider.get_global_rect()),"Transport and timeline are fixed and reachable "+str(view))
  check(music.stacked_layout==(view.x<500),"Only portrait stacks the compact playback controls "+str(view))
  check(not music.scroll.is_ancestor_of(music.player) and not music.scroll.is_ancestor_of(music.dock),"Selected recording and transport stay outside the song shelf "+str(view))
  check(music.player.get_global_rect().encloses(music.now_playing.get_global_rect()) and (not music.selection_label.visible or music.player.get_global_rect().encloses(music.selection_label.get_global_rect())),"Current song identity never sits in a scrolling pane "+str(view))
  if view==Vector2i(566,360):
   music._select("petal-promenade-clarinet-main-r3-2nd");await settle()
   check(music.now_playing.text=="Petal Promenade","Small landscape retains full long song title")
   check(music.player.get_global_rect().encloses(music.now_playing.get_global_rect()) and (not music.selection_label.visible or music.player.get_global_rect().encloses(music.selection_label.get_global_rect())),"Small landscape shows title and edition in its fixed dock")
  var full_cards=0
  music.scroll.scroll_vertical=0;await settle()
  for card in music.family_cards.values():
   if music.scroll.get_global_rect().grow(1).encloses(card.panel.get_global_rect()):full_cards+=1
  check(full_cards>=(3 if view.x>=1000 else 2),"Shelf shows multiple complete songs inside the wood "+str(view))
  for entry in Catalog.TRACKS:
   var button=music.track_buttons[entry.id]
   if button.is_visible_in_tree():check(button.size.x>=44 and button.size.y>=44,"Visible recording retains 44px target "+entry.id+" "+str(view))
  var last_button=music.family_cards[Catalog.family_id("sunshine-skip-176-new-theme")].button
  music.scroll.ensure_control_visible(last_button);await settle()
  check(music.scroll.get_global_rect().grow(1).encloses(last_button.get_global_rect()),"Last catalog choice fully reachable "+str(view))
  check(music.close_button.get_global_rect().is_equal_approx(close) and music.footer.get_global_rect().is_equal_approx(footer),"Close and transport do not scroll with library "+str(view))
  music.close_button.grab_focus();await key(KEY_TAB,true)
  var last_focus=music.volume_slider
  check(root.gui_get_focus_owner()==last_focus,"Shift+Tab traps focus inside player "+str(view))
  await key(KEY_TAB)
  check(root.gui_get_focus_owner()==music.close_button,"Tab wraps to Music X "+str(view))
  await click(music.close_button)
  check(not music.panel.visible and root.gui_get_focus_owner()==ui.music_access,"X restores Music entry focus "+str(view))
  check(music.poll_timer.is_stopped(),"Closing stops progress timer "+str(view))
  await click(ui.music_access);await key(KEY_ESCAPE)
  check(not music.panel.visible and not ui.has_open_popup() and root.gui_get_focus_owner()==ui.music_access,"Escape dismisses and restores focus "+str(view))
 root.size=Vector2i(390,844);await settle();await click(ui.music_access)
 music.close_button.grab_focus();await key(KEY_TAB);await key(KEY_TAB)
 var shelf_start=root.gui_get_focus_owner();var saved_before_browse=controls.music_track
 check(music.scroll.is_ancestor_of(shelf_start),"Shelf is one keyboard stop after Automatic")
 await key(KEY_DOWN)
 check(music.scroll.is_ancestor_of(root.gui_get_focus_owner()) and root.gui_get_focus_owner()!=shelf_start and controls.music_track==saved_before_browse,"Arrow browsing keeps playback unchanged until activation")
 await key(KEY_ENTER);await key(KEY_TAB)
 check(music.edition_host.is_ancestor_of(root.gui_get_focus_owner()),"Tab moves directly from the song shelf to its editions")
 var premium_id="cloverlight-phrasefix-r3-1nd"
 await click(music.family_cards[Catalog.family_id(premium_id)].button)
 await click(music.track_buttons[premium_id])
 check(controls.music_track==premium_id and music.track_buttons[premium_id].button_pressed,"Premium edition selects by stable ID without entitlement")
 check_selected_song_markers(music,"playing")
 await click(music.track_buttons[premium_id])
 check(music.track_buttons[premium_id].button_pressed,"Repeated selected-edition click preserves selection")
 var selected_family=music.family_cards[Catalog.family_id(premium_id)].button
 await click(selected_family)
 check(selected_family.button_pressed and controls.music_track==premium_id,"Repeated selected-song click retains selection and current edition")
 await click(music.family_cards[Catalog.family_id("service")].button)
 await click(selected_family)
 check(controls.music_track==premium_id,"Returning to a family remembers its selected edition")
 check(music.now_playing.text=="Cloverlight" and music.selection_label.text=="Premium A","Now Playing identifies song and edition separately")
 check(music.group_note.visible and "planned" in music.group_note.text,"Free Premium and future charging stay visible")
 for entry in Catalog.TRACKS:
  if not entry.get("selectable",true):continue
  await click(music.family_cards[Catalog.family_id(entry.id)].button)
  await click(music.track_buttons[entry.id])
  check(controls.music_track==entry.id,"Every selectable recording is reachable from its family "+entry.id)
  var live=game.music_transport_snapshot()
  check(draft_markers.search(live.title+live.context_reason)==null,"Playback status omits production markers "+entry.id)
  var visible_choosers=0
  for card in music.family_cards.values():
   if card.versions.is_visible_in_tree():visible_choosers+=1
  check(visible_choosers==1,"One edition chooser avoids repeated control clutter "+entry.id)
 music._select(premium_id);await settle()
 var sfx_enabled=controls.sfx_enabled;var sfx_volume=controls.sfx_volume
 await click(music.mute_button)
 check(not controls.bgm_enabled and not game.music_enabled and music.status_label.text=="MUTED","Mute uses existing BGM owner and visible state")
 check_selected_song_markers(music,"muted")
 music.volume_slider.value=23;await settle()
 check(controls.bgm_volume==23 and music.volume_value.text=="23%","Volume uses existing Settings setter")
 check(controls.sfx_enabled==sfx_enabled and controls.sfx_volume==sfx_volume,"BGM controls leave SFX independent")
 await click(music.mute_button)
 check(controls.bgm_enabled and game.music_enabled,"Unmute keeps existing BGM owner")
 music._poll_playback()
 check(music.progress_slider.editable and music.snapshot.duration>0,"Timeline uses available loaded-stream duration")
 await click(music.play_button)
 check(game.music_transport_paused and music.play_mark.glyph=="play","Pause action reflects actual backend pause")
 check_selected_song_markers(music,"paused")
 music.progress_slider.value=17;await settle();music._poll_playback()
 check(absf(float(music.snapshot.position)-17)<.3 and music.elapsed_label.text=="0:17","Seek display reads actual backend position")
 var seeks_before_refresh=game.seeks
 music.progress_slider.max_value=1000;music.progress_slider.set_value_no_signal(900);music._poll_playback()
 check(game.seeks==seeks_before_refresh and absf(float(music.snapshot.position)-17)<.3,"A shorter duration clamps display without accidentally seeking playback")
 var stable_position=float(music.snapshot.position)
 await create_timer(.55).timeout;music._poll_playback()
 check(absf(float(music.snapshot.position)-stable_position)<.1,"Paused timeline never fabricates elapsed progress")
 await click(music.play_button)
 check(not game.music_transport_paused and music.play_mark.glyph=="pause","Resume uses existing playback controller")
 var before=str(controls.music_track);await click(music.next_button)
 check(controls.music_track==Catalog.sibling_family_track(before,1),"Next follows family navigation rather than edition IDs")
 check_selected_song_markers(music,"next family")
 await click(music.automatic_button)
 check(controls.music_track==Catalog.AUTOMATIC and music.automatic_button.button_pressed,"Automatic restores context-driven music")
 check_selected_song_markers(music,"automatic")
 await click(music.automatic_button)
 check(music.automatic_button.button_pressed,"Repeated Automatic click preserves selection")
 var automatic_effective=str(music.snapshot.effective_id)
 music.track_buttons[automatic_effective].grab_focus()
 var next_automatic="busy" if automatic_effective!="busy" else "service"
 music._sync_cards(next_automatic,next_automatic)
 check(root.gui_get_focus_owner()==music.track_buttons[next_automatic] and music.track_buttons[next_automatic].is_visible_in_tree(),"Automatic family change preserves focus on the visible edition")
 music.last_playback.clear();music._poll_playback()
 game._toggle_edit();await settle();music._poll_playback()
 check(draft_markers.search(music.context_label.text)==null,"Decorate explanation uses the clean song title")
 check("Decorate" in music.context_label.text and game.music_state==Catalog.DECORATE,"Decorate status explains effective Quiet Table override")
 check(music.previous_button.disabled and music.next_button.disabled,"Decorate disables song stepping with a visible reason")
 await click(music.family_cards[Catalog.family_id(premium_id)].button)
 await click(music.track_buttons[premium_id])
 check(controls.music_track==premium_id and game.music_state==Catalog.DECORATE,"Selecting inside Decorate preserves effective Quiet Table")
 game._toggle_edit();await settle()
 check(game.music_state==premium_id,"Selected edition resumes after Decorate")
 music.seeking=true
 var seeks_before_suspend=game.seeks
 game.browser_suspended=true;music.sync();music._poll_playback()
 music._seek_finished(true)
 check(not music.seeking and game.seeks==seeks_before_suspend,"Suspension cancels a seek without committing a stale pointer release")
 check(music.play_button.disabled and not music.progress_slider.editable and "hidden" in music.context_label.text,"Browser suspension exposes unavailable playback and seek")
 game.browser_suspended=false;music.sync()
 var saves=game.saves
 game.ui.hide();await settle()
 check(music.panel.visible and not music.panel.is_visible_in_tree() and music.poll_timer.is_stopped(),"Ancestor hiding stops the visible-only progress timer")
 var hidden_tab=InputEventKey.new();hidden_tab.keycode=KEY_TAB;hidden_tab.pressed=true
 check(not music.handle_input(hidden_tab),"Hidden Music never consumes keyboard focus")
 game.ui.show();await settle()
 check(music.panel.is_visible_in_tree() and not music.poll_timer.is_stopped(),"Ancestor reveal resumes the same progress timer")
 for cycle in 4:
  music.dismiss();await settle();music.show(ui.music_access);await settle()
 check(music.track_buttons.size()==23 and music.rows.size()==23 and music.family_cards.size()==9,"Repeated opening retains bounded cards")
 check(music.panel.find_children("VisibleMusicProgress","Timer",false,false).size()==1,"Repeated opening retains one panel-owned timer")
 check(game.saves==saves and game.save_writes_suppressed,"Player changes never save restaurant progress")
 game.set_meta("hud_safe_insets",Vector4(18,16,18,20));root.size=Vector2i(390,844);await settle()
 var safe=Rect2(Vector2(18,16),Vector2(354,808))
 check(safe.encloses(music.panel.get_global_rect()),"Player respects portrait safe areas")
 check(safe.get_center().distance_to(music.panel.get_global_rect().get_center())<1,"Player centers within safe areas")
 for view in [Vector2i(360,600),Vector2i(360,680)]:
  game.set_meta("hud_safe_insets",Vector4(8,20,8,16));root.size=view;await settle();music._select("petal-promenade-clarinet-main-r3-2nd");await settle()
  var portrait_safe=Rect2(Vector2(8,20),Vector2(view)-Vector2(16,36))
  var portrait_bounds=music.panel.get_global_rect()
  check(portrait_safe.encloses(portrait_bounds) and portrait_safe.get_center().distance_to(portrait_bounds.get_center())<1,"Short portrait stays centered inside safe viewport "+str(view))
  check(music.stacked_layout and music.group_note.visible,"Short portrait uses bounded compact composition "+str(view))
  check(music.player.get_global_rect().encloses(music.now_playing.get_global_rect()) and (not music.selection_label.visible or music.player.get_global_rect().encloses(music.selection_label.get_global_rect())),"Short portrait shows full current title and edition "+str(view))
  for target in [music.previous_button,music.play_button,music.next_button,music.mute_button,music.volume_slider,music.progress_slider]:
   check(portrait_bounds.encloses(target.get_global_rect()) and target.size.x>=44 and target.size.y>=44,"Short portrait keeps full44px control "+target.name+" "+str(view))
  check(music.play_button.text.is_empty() and music.play_mark.get_global_rect()==music.play_button.get_global_rect(),"Narrow playback icon stays centered without a text caption "+str(view))
  music.scroll.scroll_vertical=0;await settle()
  var first_card=music.track_body.get_child(0)
  check(music.scroll.get_global_rect().grow(1).encloses(first_card.get_global_rect()),"Short portrait initially shows a complete family card "+str(view))
  var selected_card=music.family_cards[music.rows["petal-promenade-clarinet-main-r3-2nd"].family_id].panel
  music.scroll.ensure_control_visible(selected_card);await settle()
  check(music.scroll.get_global_rect().grow(1).encloses(selected_card.get_global_rect()),"Short portrait selected family fully reachable "+str(view))
  check(music.group_note.visible and portrait_bounds.encloses(music.group_note.get_global_rect()) and "planned" in music.group_note.text,"Short portrait Premium disclosure remains fixed and visible "+str(view))
  check_inner_board(music,"safe "+str(view))
  print("MUSIC_PANEL_SAFE_PORTRAIT ",JSON.stringify({"viewport":str(view),"panel":str(portrait_bounds),"library":str(music.scroll.get_global_rect()),"player":str(music.player.get_global_rect())}))
 game.set_meta("hud_safe_insets",Vector4.ZERO)
 for view in [Vector2i(566,360),Vector2i(844,390)]:
  root.size=view;await settle();game._toggle_edit();await settle();music.show();await settle()
  check(Rect2(Vector2.ZERO,Vector2(view)).encloses(music.panel.get_global_rect()),"Decorate explanation remains bounded in landscape "+str(view))
  check(music.context_label.visible and music.panel.get_global_rect().encloses(music.context_label.get_global_rect()),"Decorate explanation is readable in landscape "+str(view))
  check_inner_board(music,"Decorate "+str(view))
  game._toggle_edit();await settle();game.browser_suspended=true;music.sync();await settle()
  check(Rect2(Vector2.ZERO,Vector2(view)).encloses(music.panel.get_global_rect()),"Suspended playback explanation remains bounded in landscape "+str(view))
  check_inner_board(music,"Suspended "+str(view))
  game.browser_suspended=false;music.sync();await settle()
 for view in [Vector2i(499,600),Vector2i(500,600),Vector2i(649,550),Vector2i(650,550),Vector2i(759,600),Vector2i(760,600),Vector2i(899,550),Vector2i(900,550)]:
  root.size=view;await settle()
  check(Rect2(Vector2.ZERO,Vector2(view)).encloses(music.panel.get_global_rect()),"Resize breakpoint keeps the full board visible "+str(view))
  check_inner_board(music,"resize "+str(view))
 check_touch_waves(music)
 await check_motion_lifecycle(music,ui,controls,premium_id)
 music.dismiss();game.settings.show();ui.settings_inbox.grab_focus();await settle()
 check(root.gui_get_focus_owner()==ui.settings_inbox,"Focus return never steals from replacement popup")
 var timer_ref=weakref(music.poll_timer);var audio_refs=game.observed_audio
 var artwork_refs=observe_artwork(music)
 game.queue_free();await process_frame;await process_frame
 # Audio-thread retirement can finish after deferred scene deletion. Observe all
 # played resources, rather than quit before their actual release is established.
 var deadline=Time.get_ticks_msec()+1000
 while (audio_refs.any(func(ref):return ref.get_ref()!=null) or artwork_refs.any(func(observation):return observation.ref.get_ref()!=null)) and Time.get_ticks_msec()<deadline:
  await create_timer(.05).timeout
 check(not audio_refs.any(func(ref):return ref.get_ref()!=null),"All exercised audio nodes and streams release after scene teardown")
 check(timer_ref.get_ref()==null,"Panel timer is released with its owning scene")
 var retained=retained_artwork(artwork_refs)
 print("MUSIC_ARTWORK_RELEASE ",JSON.stringify({"observed":artwork_refs.size(),"retained":retained}))
 check(retained.is_empty(),"All artwork nodes, owned meshes/materials/styles and transition tweens release with their owning scene")
 print("MUSIC_PANEL_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 quit(0 if failures.is_empty() else 1)
