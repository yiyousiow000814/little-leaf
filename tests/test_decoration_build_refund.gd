extends SceneTree
const Model=preload("res://scripts/cafe_model.gd")
const Start=preload("res://scripts/minimal_start.gd")
const Walls=preload("res://scripts/cafe_walls.gd")
class TestMain extends "res://scripts/main.gd":
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():return true
var checks=0
var failures=[]
var observations=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func fresh():
 var m=Model.new();Start.apply(m);m.coins=10000;return m
func key(m)->String:return Walls.key_of(m.built_walls[-1])
func _initialize():run.call_deferred()
func run():
 if not "saveguard" in OS.get_user_data_dir():printerr("Use isolated headless profile");quit(2);return
 var baseline="--build-refund-baseline" in OS.get_cmdline_user_args()
 for height in ["half","full"]:
  var m=fresh();m.begin_decoration_session();var wallet=m.coins;var paid=m.wall_price(height)
  check(m.place_wall("x",8,6,height),"buy "+height+" wall: "+m.last_error)
  var id=int(m.built_walls[-1].id)
  check(m.move_wall(key(m),"x",9,6) and int(m.built_walls[-1].id)==id,"wall move preserves identity")
  check(m.paint_wall(key(m),"leaf_print"),"free paint preserves receipt")
  if not baseline:check(m.wall_refund(key(m))==paid,"wall quote full paid cost")
  check(m.remove_wall(key(m)),"sell wall")
  var expected=int(paid/2) if baseline else paid
  check(m.coins==wallet-paid+expected,"wall exact refund")
  observations.append({"category":height+" wall","paid":paid,"refund":m.coins-wallet+paid,"loss":wallet-m.coins})
  wallet=m.coins;check(not m.remove_wall("x:9:6") and m.coins==wallet,"wall duplicate cannot credit")
 for kind in ["door","window"]:
  var m=fresh();m.begin_decoration_session();var wallet=m.coins;var paid=m.attachment_price(kind)
  check(m.place_wall_attachment(kind,"shell:back",2.5),"buy "+kind+": "+m.last_error)
  var id=int(m.wall_attachments[-1].id)
  check(m.move_wall_attachment(id,"shell:back",3.5),"move opening preserves receipt")
  if not baseline:check(m.wall_attachment_refund(id)==paid,"opening quote full paid")
  check(m.remove_wall_attachment(id),"sell opening")
  var expected=int(paid/2) if baseline else paid
  check(m.coins==wallet-paid+expected,"opening exact refund")
  observations.append({"category":kind,"paid":paid,"refund":m.coins-wallet+paid,"loss":wallet-m.coins})
  wallet=m.coins;check(not m.remove_wall_attachment(id) and m.coins==wallet,"opening duplicate cannot credit")
 if baseline:
  print("DECORATION_BUILD_REFUND_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"observations":observations,"baseline":true}));quit(0 if failures.is_empty() else 1);return
 # Older paid objects and free starter opening are never promoted by entry.
 var m=fresh();check(m.place_wall("x",8,6,"half"),"old half wall");var old_key=key(m)
 check(m.place_wall_attachment("window","shell:back",2.5),"old paid window");var old_open=int(m.wall_attachments[-1].id)
 m.begin_decoration_session();check(m.wall_refund(old_key)==17 and m.wall_attachment_refund(old_open)==15 and m.wall_attachment_refund(1)==0,"old wall/window/free door remain normal")
 check(m.place_wall("x",9,6),"new full wall");var new_key=key(m)
 check(m.place_wall_attachment("door","shell:back",3.5),"new paid door");var new_open=int(m.wall_attachments[-1].id)
 check(m.wall_refund(new_key)==55 and m.wall_attachment_refund(new_open)==40,"new saleable build objects full")
 var wallet=m.coins;check(m.save("user://build-refund-interrupted.json"),"mid-session build save")
 check(m.wall_refund(new_key)==55 and m.wall_attachment_refund(new_open)==40,"autosave retains build eligibility")
 var loaded=Model.new();check(loaded.load_save("user://build-refund-interrupted.json"),"interrupted build reload")
 check(loaded.coins==wallet and loaded.decoration_build_purchases.is_empty() and loaded.wall_refund(new_key)==27 and loaded.wall_attachment_refund(new_open)==20,"reload keeps wallet and paid bases; normal resale")
 m.finish_decoration_session();m.begin_decoration_session()
 check(m.wall_refund(new_key)==27 and m.wall_attachment_refund(new_open)==20,"Done/reentry cannot renew build receipts")
 # Host removal must fail before touching either receipt while opening remains.
 m=fresh();m.begin_decoration_session();check(m.place_wall("x",5,4),"new host wall")
 var wall_key=key(m);var host="wall:"+str(int(m.built_walls[-1].id))
 check(m.place_wall_attachment("door",host,.5),"new hosted door")
 var door_id=int(m.wall_attachments[-1].id);wallet=m.coins
 check(not m.remove_wall(wall_key) and m.coins==wallet and m.wall_refund(wall_key)==55 and m.wall_attachment_refund(door_id)==40,"failed host removal keeps both receipts")
 check(m.place("stove",5,3),"stove uses paid doorway");var stove_id=m._next_item_id-1;wallet=m.coins
 check(not m.remove_wall_attachment(door_id) and m.coins==wallet and m.wall_attachment_refund(door_id)==40,"failed door removal preserves receipt")
 check(m.remove(stove_id),"remove blocking stove");wallet=m.coins
 check(m.remove_wall_attachment(door_id) and m.coins==wallet+40,"unblocked door credits once")
 wallet=m.coins;check(m.remove_wall(wall_key) and m.coins==wallet+55 and m.decoration_build_purchases.is_empty(),"unblocked host credits once")
 # Height difference and paid replacement cannot recycle old full receipts.
 m=fresh();m.begin_decoration_session();wallet=m.coins;check(m.place_wall("x",8,6),"height fixture")
 wall_key=key(m);check(m.set_wall_height(wall_key,"half") and m.wall_refund(wall_key)==35 and m.coins==wallet-35,"downgrade adjusts receipt by exact returned20")
 check(m.set_wall_height(wall_key,"full") and m.wall_refund(wall_key)==55 and m.coins==wallet-55,"upgrade cycle preserves paid charge")
 check(m.remove_wall(wall_key) and m.coins==wallet,"height cycle plus sale cannot create money")
 m=fresh();m.begin_decoration_session();wallet=m.coins;check(m.place_wall("x",8,6,"half"),"replacement fixture");wall_key=key(m)
 var bill=m.wall_replacement_quote(wall_key,"full","leaf_print")
 check(bill.valid and bill.refund==17 and bill.new_cost==55 and bill.net==38,"existing replacement half credit unchanged")
 check(m.replace_wall(wall_key,"full","leaf_print") and m.coins==wallet-73 and m.wall_refund(wall_key)==55,"replacement retires old receipt; new product receipt55")
 var ledger=m.decoration_build_purchases.duplicate(true);wallet=m.coins
 check(not m.replace_wall(wall_key,"full","leaf_print") and m.decoration_build_purchases==ledger and m.coins==wallet,"failed replacement cannot refresh receipt")
 check(m.remove_wall(wall_key) and m.coins==wallet+55,"replacement sale credits new product once")
 # Insufficient funds and no-refund removal do not invent refund value.
 m=fresh();m.begin_decoration_session();m.coins=34;var next_id=m._next_wall_id
 check(not m.place_wall("x",8,6,"half") and m.coins==34 and m._next_wall_id==next_id and m.decoration_build_purchases.is_empty(),"poor wall atomic")
 m.coins=29;next_id=m._next_attachment_id
 check(not m.place_wall_attachment("window","shell:back",2.5) and m.coins==29 and m._next_attachment_id==next_id and m.decoration_build_purchases.is_empty(),"poor window atomic")
 m.coins=10000;check(m.place_wall("x",8,6) and m.place_wall_attachment("window","shell:back",2.5),"non-refunding fixtures")
 var opening_id=int(m.wall_attachments[-1].id);wallet=m.coins
 check(m.remove_wall(key(m),false) and m.remove_wall_attachment(opening_id,[],false) and m.coins==wallet and m.decoration_build_purchases.is_empty(),"no-refund removal consumes receipts")
 check(m.place_wall("x",8,6) and not m.decoration_build_purchases.is_empty(),"nonempty build receipt before reset")
 Start.apply(m);check(not m.decoration_session_active and m.decoration_build_purchases.is_empty(),"reset clears build receipts before ID reuse")
 # Actual context labels read authoritative refund quotes in headless UI.
 var game=TestMain.new();root.add_child(game);game.set_process(false);game.paused=true;await process_frame
 game._toggle_edit();game.model.coins=10000;check(game.model.place_wall("x",8,6),"context wall purchase")
 game.compact_ui.selected_wall=key(game.model);game.compact_ui.sync()
 check(game.compact_ui.remove_button.text=="Sell +55","context wall shows full55")
 game._cancel_selection();check(game.model.place_wall_attachment("window","shell:back",2.5),"context window purchase")
 opening_id=int(game.model.wall_attachments[-1].id);game.build_tools.opening_source_id=opening_id;game.compact_ui.sync()
 check(game.compact_ui.remove_button.text=="Sell +30","context opening shows full30")
 game._toggle_edit();game._toggle_edit();game.build_tools.opening_source_id=opening_id;game.compact_ui.sync()
 check(game.compact_ui.remove_button.text=="Sell +15","context reentry shows half15")
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 game.queue_free();await process_frame
 print("DECORATION_BUILD_REFUND_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"observations":observations,"player_save_used":false,"replacement_credits_unchanged":true}))
 quit(0 if failures.is_empty() else 1)
