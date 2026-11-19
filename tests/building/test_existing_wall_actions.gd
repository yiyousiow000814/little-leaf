extends SceneTree
## The three ordinary user flows: restyle an existing wall, add door, add window.
class TestMain extends "res://scripts/main.gd":
 var saves=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():saves+=1;return true
var game
var checks=0
var failures=[]
var operations=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
const Walls=preload("res://scripts/gameplay/cafe_walls.gd")
const WallReachability=preload("res://scripts/gameplay/cafe_wall_reachability.gd")
const OpeningGeometry=preload("res://scripts/gameplay/cafe_wall_openings.gd")
const WallSupportValidation=preload("res://scripts/gameplay/cafe_wall_support_validation.gd")
func opening_validation_input(id:int,supports:Array,offset:float,width:float,kind:String="window")->Dictionary:
 return {"id":id,"kind":kind,"wall_ids":supports,"offset":offset,"width":width}

func check_installed_support_index(model):
 var walls=[]
 for axis in ["x","z"]:
  for row in range(6):
   for offset in range(6):
    var name:="%s:%d:%d"%[axis,row,offset]
    walls.append(Walls.installed(name,Walls.make(axis,offset if axis=="x" else row,row if axis=="x" else offset),0,0))
 var first=opening_validation_input(1,["x:0:0"],.5,.8)
 var beyond=opening_validation_input(2,["x:0:0"],.15,.6)
 var unused=opening_validation_input(3,["x:0:1","x:0:2"],.4,.4)
 var unsupported=opening_validation_input(4,["missing"],.5,.7)
 var intersecting_other_axis=opening_validation_input(5,["z:0:0"],.5,.7)
 var adjacent=opening_validation_input(6,["x:0:1"],.5,1.0)
 var full_first=opening_validation_input(7,["x:0:0"],.5,1.0)
 var overlapping_tail=opening_validation_input(8,["x:0:0","x:0:1"],1.0,1.0,"door")
 var near_left=opening_validation_input(9,["x:0:0"],.25,.50)
 var near_threshold=opening_validation_input(10,["x:0:0"],.749991,.50)
 var above_threshold=opening_validation_input(11,["x:0:0"],.749980,.50)
 var duplicate=first.duplicate();duplicate.width=.7
 var scenarios=[[],[first],[first,intersecting_other_axis],[adjacent,full_first],[first,duplicate],[first,beyond],[beyond,first],
                [unused,first],[unsupported,first],[overlapping_tail,adjacent,first],[near_left,near_threshold],[near_left,above_threshold]]
 check(WallSupportValidation.error(walls,[first,beyond])=="A door or window already occupies this wall interval",
       "An earlier otherwise-valid opening reports its overlap before a later bad width")
 check(WallSupportValidation.error(walls,[beyond,first])=="Opening extends beyond its supporting walls",
       "A malformed opening reports its range error first when installed first")
 for i in range(scenarios.size()):
  var rows:Array=scenarios[i];var snapshot=[walls.duplicate(true),rows.duplicate(true)]
  var reference:=OpeningGeometry.installed_support_error(walls,rows)
  check(WallSupportValidation.error(walls,rows)==reference,"Installed opening priority matches reference case "+str(i))
  check(model._attachment_layout_error(walls,rows)==reference,"Model routes installed opening validation through the index")
  check([walls,rows]==snapshot,"Wall support validation does not mutate placed or proposed rows")
 # Dense no-overlap fixture with realistic ordered wall IDs in both axes;
 # this takes the entire original nested validation path instead of an early exit.
 var dense:Array=[]
 for i in range(walls.size()):
  dense.append(opening_validation_input(i+20,[walls[i].id],.5,.7))
 check(WallSupportValidation.error(walls,dense)==OpeningGeometry.installed_support_error(walls,dense)
       and WallSupportValidation.error(walls,dense)=="","Dense distinct intervals pass both validators")
 # Epsilon-adjacent and noncanonical endpoints can never be collapsed into a different line.
 var unusual=walls.duplicate(true)
 unusual[0].z=.000001
 check(WallSupportValidation.error(unusual,[first,beyond])==OpeningGeometry.installed_support_error(unusual,[first,beyond]),
       "Noncanonical wall coordinates retain exact fallback behavior")

func check_blocked_edge_index(model):
 for axis in ["x","z"]:
  var walls=[]
  for i in range(3):
   walls.append(Walls.installed("wall:%d"%(i+1),Walls.make(axis,2+i if axis=="x" else 2,2 if axis=="x" else 2+i),55,55))
  var cases=[
   [],
   [{"id":1,"kind":"door","wall_ids":["wall:1"],"offset":.5,"width":1.0}],
   [{"id":1,"kind":"door","wall_ids":["wall:1","wall:2"],"offset":.75,"width":1.5}],
   [{"id":1,"kind":"door","wall_ids":["wall:2","wall:1"],"offset":.75,"width":1.5}],
   [{"id":1,"kind":"door","wall_ids":["wall:1","wall:3"],"offset":.75,"width":1.5}],
   [{"id":1,"kind":"window","wall_ids":["wall:1"],"offset":.5,"width":1.0}],
   [{"id":1,"kind":"door","host_id":"span:1,2","offset":.75,"width":1.5}],
   [{"id":1,"kind":"door","wall_ids":["wall:1"],"offset":.5,"width":.460020}],
   [{"id":1,"kind":"door","wall_ids":["wall:1"],"offset":.5,"width":.460040}],
  ]
  for i in range(cases.size()):
   var tested=walls
   if cases[i].size()>0 and cases[i][0].has("host_id"):
    tested=walls.duplicate(true)
    for j in range(tested.size()):tested[j].id=j+1
   var before={}
   for wall in tested:
    var cells=Walls.adjacent_cells(wall)
    if model._built_edge_blocked(cells[0],cells[1],tested,cases[i]):before[Walls.key_of(wall)]=true
   check(WallReachability.blocked_grid_edges(tested,cases[i])==before,"indexed wall clearance matches legacy lookup for %s case %d"%[axis,i])
func check_direct_edge_snapshot(model):
 var walls:Array=[]
 var openings:Array=[]
 for z in range(12):
  for x in range(12):
   for axis in ["x","z"]:
    var id:="wall:%d"%walls.size()
    walls.append(Walls.installed(id,Walls.make(axis,x,z),0,0))
    if (x+z)%4==0:
     var critical=[.46,.46002,.4600201,.5,.7,1.0][(x+2*z)%6]
     openings.append({"id":walls.size(),"kind":"door" if z%2==0 else "window","wall_ids":[id],"offset":.5,"width":critical})
 openings.append({"id":400,"kind":"door","wall_ids":["wall:2","wall:4"],"offset":1.0,"width":1.5})
 var keys=WallReachability.direct_edge_snapshot(walls,openings)
 check(keys is Dictionary,"Regular integer midpoint layout builds an exact direct snapshot")
 var same_answers=true
 for z in range(-1,13):
  for x in range(-1,13):
   var a=Vector2i(x,z)
   for dir in [Vector2i.RIGHT,Vector2i.DOWN,Vector2i(2,0)]:
    same_answers=same_answers and model._built_edge_blocked(a,a+dir,walls,openings)==model._built_edge_blocked(a,a+dir,walls,openings,keys)
 check(same_answers,"Every sampled midpoint, including fractional door widths near clearance, matches the original direct check")
 var legacy=OpeningGeometry.initial_attachments()
 check(WallReachability.direct_edge_snapshot(walls,legacy)==null,"Legacy host reference retains original direct resolver")
 var duplicate=walls.duplicate();duplicate.append(walls[0])
 check(WallReachability.direct_edge_snapshot(duplicate,openings)==null,"Duplicate wall rows retain original first-match oracle")
 var fractional=walls.duplicate(true);fractional[0].x=.25
 check(WallReachability.direct_edge_snapshot(fractional,openings)==null,"Noncanonical candidate coordinates retain original direct resolver")

func _initialize():run.call_deferred()
func settle():
 game._update_ui();game.illustration.queue_redraw()
 for frame in 8:await process_frame
func click(point:Vector2):
 var motion=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;root.push_input(motion,true)
 for pressed in [true,false]:
  var event=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
 await settle()
func aim(x:float)->Vector2:
 var art=game.illustration;var point=art.iso(x,0,70)
 game.interaction._pan_by(art.camera_safe_rect().get_center()-point)
 return art.iso(x,0,70)
func capture(name:String):
 var output=OS.get_environment("OUTPUT")
 if output=="" or DisplayServer.get_name()=="headless":return
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(output+"/"+name+".png")
func run():
 if not "saveguard" in OS.get_user_data_dir():printerr("Use isolated profile");quit(2);return
 root.size=Vector2i(1164,624);game=TestMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false);game.paused=true
 await process_frame;game.model.coins=1600;game._toggle_edit();game._set_catalog_category("Build");game.compact_ui._set_tray_reveal(1);await settle()
 var ui=game.compact_ui;var model=game.model;var tool=game.build_tools
 check_installed_support_index(model)
 check_direct_edge_snapshot(game.model)
 check_blocked_edge_index(model)
 game._cancel_selection();await settle();await click(aim(2.5))
 check(ui.selected_wall=="x:2:0","click existing wall selects exact one-tile host")
 await click(ui.finish_button.get_global_rect().get_center())
 check(ui.shop_ui.build_page=="walls" and not ui.has_open_popup(),"Replace opens existing wall style cards in bottom tray")
 await click(ui.shop_ui.wall_cards["wall:full:cream_stripe"].get_global_rect().get_center());await click(aim(2.5))
 check(ui.wall_review.visible and ui.pending_wall.key=="x:2:0","wall click opens review for same existing host")
 var wallet=model.coins;var saves=game.saves;var dirty_generation=game.platform_dirty_generation
 await click(ui.wall_confirm_button.get_global_rect().get_center())
 var style_ok=model.get_wall("x:2:0").material=="cream_stripe"
 check(style_ok,"existing wall changes to chosen Cream stripes")
 check(model.coins==wallet-55 and game.saves==saves and game.platform_dirty_generation>dirty_generation,"existing wall style pays stated price and marks progress dirty")
 operations.append({"operation":"existing wall style","passed":style_ok,"coins_before":wallet,"coins_after":model.coins})
 await capture("01-existing-wall-style")
 for spec in [["door",3.5],["window",4.5]]:
  var kind=str(spec[0]);game._cancel_selection();await settle()
  if ui.shop_ui.build_page!="products":await click(ui.shop_ui.tiles_back.get_global_rect().get_center())
  await click(tool.tool_buttons[kind].get_global_rect().get_center())
  check(tool.mode==kind,"catalog click selects "+kind)
  wallet=model.coins;saves=game.saves;dirty_generation=game.platform_dirty_generation;var count=model.wall_attachments.size()
  await click(aim(float(spec[1])))
  var installed=model.wall_attachments.size()==count+1 and model.wall_attachments[-1].kind==kind and model.wall_attachments[-1].wall_ids==[model.get_wall("x:%d:0"%int(spec[1])).id] and is_equal_approx(float(model.wall_attachments[-1].offset),.5)
  check(installed,"click existing wall installs "+kind+" at requested host")
  check(model.coins==wallet-model.attachment_price(kind) and game.saves==saves and game.platform_dirty_generation>dirty_generation,kind+" pays listed price and marks progress dirty")
  operations.append({"operation":"existing wall add "+kind,"passed":installed,"coins_before":wallet,"coins_after":model.coins})
  await capture("02-existing-wall-door" if kind=="door" else "03-existing-wall-window")
 print("EXISTING_WALL_ACTIONS_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"operations":operations,"player_save_used":false,"native_render_verified":DisplayServer.get_name()!="headless"}))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
